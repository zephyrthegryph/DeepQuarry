//! `analyze base-vars-dead`: vars on the base types that nothing reads (doc/rewrite/proposals/base_vars.md, "Dead").
//!
//! For every instance var declared on a base type (the `base_vars` lint's list) the report counts the occurrences of its
//! name in every `.dm` file under `code/` and every map under `maps/`, outside its own declaration line:
//!
//! * a **write** is an assignment to the name (`x = v`, `x += v`, `x[i] = v`, `x++`, a type-body override, a map edit);
//! * a declaration of the same name (`var/x`, `var/type/x`, a proc argument) is neither;
//! * anything else is a **read**: an expression use, a string holding the name (`vars["x"]`, `call(src, "x")`), `nameof(x)`.
//!
//! The match is by name, not by type, so a read of a same-named var on an unrelated type keeps a base var alive: the report
//! over-approximates reads and never lists a var that is read. Rows: `dead` (no occurrence at all) and `write_only` (written,
//! never read); `--few` adds `few_reads` (one or two reads by name) for a hand review. `--tsv` prints `kind TAB owner TAB var TAB file:line TAB writes`.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;
use std::process::ExitCode;

use dreammaker::ast::VarTypeFlags;

use crate::lints::base_vars::BASE_TYPES;
use crate::sem::decls::strip_comments_keep_strings;
use crate::sem::Sem;

struct BaseVar {
    owner: String,
    name: String,
    rel: String,
    line: u32,
}

#[derive(Default, Clone, Copy)]
struct Uses {
    reads: u32,
    writes: u32,
}

fn is_ident(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Classify the occurrence at `[s, e)` of a name in `t` (comments stripped, strings kept).
fn classify(t: &[u8], s: usize, e: usize, in_string: bool) -> Option<bool> {
    if in_string {
        return Some(false);
    }
    // A declaration: preceded by `var/` or `var/<type path>/`, or by `/` inside a typed proc argument (`obj/item/x`).
    let mut i = s;
    if i > 0 && t[i - 1] == b'/' {
        // walk back over the path to see whether it starts with `var`, or is a proc argument type (`/obj/item/x,`).
        let mut j = i - 1;
        while j > 0 && (is_ident(t[j - 1]) || t[j - 1] == b'/') {
            j -= 1;
        }
        let path = &t[j..s];
        if path.starts_with(b"var/") || path.windows(5).any(|w| w == b"/var/") {
            return None;
        }
        // `/obj/item/x` (an absolute path: a typed argument or a type): not a use. `a/x` (a division) is a read.
        if t[j] == b'/' {
            return None;
        }
    }
    // `.x` is a field access on something: still a use of the name.
    i = e;
    while i < t.len() && (t[i] == b' ' || t[i] == b'\t') {
        i += 1;
    }
    // skip an index `x[...]`
    if i < t.len() && t[i] == b'[' {
        let mut depth = 0i32;
        while i < t.len() {
            match t[i] {
                b'[' => depth += 1,
                b']' => {
                    depth -= 1;
                    if depth == 0 {
                        i += 1;
                        break;
                    }
                }
                b'\n' => break,
                _ => {}
            }
            i += 1;
        }
        while i < t.len() && (t[i] == b' ' || t[i] == b'\t') {
            i += 1;
        }
    }
    let rest = &t[i..t.len().min(i + 3)];
    let write = match rest {
        [b'=', b'=', ..] => false,
        [b'=', ..] => true,
        [b'+' | b'-' | b'*' | b'/' | b'|' | b'&' | b'^' | b'%', b'=', ..] => true,
        [b'<', b'<', b'='] | [b'>', b'>', b'='] => true,
        _ => false,
    };
    if write {
        return Some(true);
    }
    // `x++`, `++x` and `x--` are reads and writes at once (the value is often used): counted as reads.
    Some(false)
}

/// Every occurrence of a watched name in `text` (comments stripped, strings kept): (name, line, is_write).
fn scan(text: &str, names: &HashSet<&str>, mut f: impl FnMut(&str, u32, bool)) {
    let t = text.as_bytes();
    let n = t.len();
    let mut line = 1u32;
    let mut in_string = false;
    let mut i = 0;
    while i < n {
        let c = t[i];
        if c == b'\n' {
            line += 1;
            i += 1;
            continue;
        }
        if c == b'"' && (i == 0 || t[i - 1] != b'\\') {
            in_string = !in_string;
            i += 1;
            continue;
        }
        if is_ident(c) && (i == 0 || !is_ident(t[i - 1])) {
            let s = i;
            while i < n && is_ident(t[i]) {
                i += 1;
            }
            let w = &text[s..i];
            if names.contains(w) {
                if let Some(wr) = classify(t, s, i, in_string) {
                    f(w, line, wr);
                }
            }
            continue;
        }
        i += 1;
    }
}

fn walk(dir: &Path, ext: &str, out: &mut Vec<std::path::PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() {
            walk(&p, ext, out);
        } else if p.extension().map(|x| x == ext).unwrap_or(false) {
            out.push(p);
        }
    }
}

pub fn run(args: &[String], root: &Path) -> ExitCode {
    let tsv = args.iter().any(|a| a == "--tsv");
    // `--few`: also list vars with one or two reads anywhere (by name), for a hand review.
    let few = args.iter().any(|a| a == "--few");
    let o = crate::run::Options { root: root.to_path_buf(), lints: vec!["base_vars".to_string()], ..Default::default() };
    let engine = match crate::run::Engine::new(crate::run::registry(), o) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("analyze: {}", e);
            return ExitCode::from(2);
        }
    };
    let sem = match Sem::build(root, &engine.tree) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("analyze base-vars-dead: the semantic model could not be built: {}", e);
            return ExitCode::from(2);
        }
    };
    let mut vars: Vec<BaseVar> = Vec::new();
    for ty in sem.objtree.iter_types() {
        let owner = ty.get().path.clone();
        if !BASE_TYPES.contains(&owner.as_str()) {
            continue;
        }
        for (name, tv) in ty.get().vars.iter() {
            let Some(decl) = &tv.declaration else { continue };
            if decl.var_type.flags.intersects(VarTypeFlags::STATIC | VarTypeFlags::CONST) {
                continue;
            }
            let Some(rel) = sem.file_of(decl.location) else { continue };
            let line = crate::sem::procs::engine_line(&sem.root, rel, decl.location.line);
            vars.push(BaseVar { owner: owner.clone(), name: name.to_string(), rel: rel.to_string(), line });
        }
    }
    let names: HashSet<&str> = vars.iter().map(|v| v.name.as_str()).collect();
    let decl_at: HashSet<(&str, u32)> = vars.iter().map(|v| (v.rel.as_str(), v.line)).collect();
    let mut uses: HashMap<String, Uses> = HashMap::new();

    let mut files = Vec::new();
    walk(&root.join("code"), "dm", &mut files);
    walk(&root.join("maps"), "dmm", &mut files);
    for p in &files {
        let Ok(raw) = std::fs::read(p) else { continue };
        let raw = String::from_utf8_lossy(&raw).replace("\r\n", "\n");
        let rel = p.strip_prefix(root).unwrap_or(p).to_string_lossy().replace('\\', "/");
        let is_map = rel.ends_with(".dmm");
        let text = if is_map { raw } else { strip_comments_keep_strings(&raw) };
        scan(&text, &names, |w, line, write| {
            if decl_at.contains(&(rel.as_str(), line)) {
                return;
            }
            let u = uses.entry(w.to_string()).or_default();
            // In a map every occurrence of `x = ` is an edit; a name inside a map string is text, not a use.
            if is_map {
                if write {
                    u.writes += 1;
                }
                return;
            }
            if write {
                u.writes += 1;
            } else {
                u.reads += 1;
            }
        });
    }

    let mut rows: BTreeMap<(String, String), (&'static str, String, u32)> = BTreeMap::new();
    for v in &vars {
        let u = uses.get(&v.name).copied().unwrap_or_default();
        let kind = if u.reads == 0 && u.writes == 0 {
            "dead"
        } else if u.reads == 0 {
            "write_only"
        } else if few && u.reads <= 2 {
            "few_reads"
        } else {
            continue;
        };
        rows.insert((v.owner.clone(), v.name.clone()), (kind, format!("{}:{}", v.rel, v.line), u.writes));
    }
    let (mut dead, mut wo) = (0, 0);
    for ((owner, name), (kind, at, writes)) in &rows {
        match *kind {
            "dead" => dead += 1,
            "write_only" => wo += 1,
            _ => {}
        }
        if tsv {
            println!("{}\t{}\t{}\t{}\t{}", kind, owner, name, at, writes);
        } else {
            println!("{:<10} {}/var/{}  ({}, {} writes)", kind, owner, name, at, writes);
        }
    }
    eprintln!("analyze base-vars-dead: {} base vars, {} dead, {} write-only", vars.len(), dead, wo);
    ExitCode::SUCCESS
}
