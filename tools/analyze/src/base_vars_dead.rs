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

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::process::ExitCode;

use dreammaker::ast::VarTypeFlags;

use crate::lints::base_vars::BASE_TYPES;
use crate::sem::decls::strip_comments_keep_strings;
use crate::sem::Sem;

use crate::base_vars_dead_policy::{BaseVar,Uses,scan};

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

    let result=crate::base_vars_dead_policy::report(&vars,&uses,tsv,few,&mut crate::key_policy_control::Compatibility,|channel,args|{match channel{crate::base_vars_dead_policy::Channel::Stdout=>println!("{}",args),crate::base_vars_dead_policy::Channel::Stderr=>eprintln!("{}",args)}Ok(())});
    match result{Ok(())=>(),Err(never)=>match never{}}
    ExitCode::SUCCESS
}
