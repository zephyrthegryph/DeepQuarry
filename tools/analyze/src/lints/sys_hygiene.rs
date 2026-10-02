//! Port of `tools/ci/sys_rules/hygiene.py` (doc/rewrite/systems.md, "Hygiene"): placeholder ALLOW
//! reasons (`annotation_boilerplate`), hand-maintained `cached_*` instance vars (`cached_var`) and
//! world.time polling of stored deadlines in periodic bodies (`deadline_poll`).
//!
//! The deadline scan is `tools/ci/check_deadline_polling.py`'s (`scan_lines`, `strip_comment`,
//! `DEADLINE`), which hygiene.py imports; it is ported here as private helpers.

use std::collections::{BTreeSet, HashMap, HashSet};

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{is_py_space, py_strip};
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "annotation_boilerplate",
        hint: "write the real reason for this site, or fix the site (doc/rewrite/systems.md, Hygiene)",
    },
    RuleMeta {
        name: "cached_var",
        hint: "om_derived()/DERIVE(), declared_cache_vars() + changed(), a shared cache, or a name for what it holds (Hygiene)",
    },
    RuleMeta {
        name: "deadline_poll",
        hint: "om_after()/om_deadline() at the moment the deadline is set, not a world.time check in periodic work (Hygiene)",
    },
];

const PLACEHOLDERS: &[&str] = &["baseline when ci was wired", "convert or give a real reason", "mobs at boot", "see audit"];

/// Vendored upstream code kept verbatim (the tgstation-server DMAPI).
const VENDORED: &[&str] = &["code/modules/tgs/"];

fn kind_path(kind: &str) -> &'static str {
    match kind {
        "mob" => "/mob",
        "obj" => "/obj",
        "item" => "/obj/item",
        "machine" => "/obj/machinery",
        "turf" => "/turf",
        _ => "/area",
    }
}

// ---- check_deadline_polling.py ---------------------------------------------------------------

/// Drop `//` comments outside strings (`check_deadline_polling.strip_comment`).
fn strip_comment(line: &str) -> &str {
    let b = line.as_bytes();
    let mut in_str = false;
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c == b'"' && (i == 0 || b[i - 1] != b'\\') {
            in_str = !in_str;
        }
        if !in_str && b[i..].starts_with(b"//") {
            return &line[..i];
        }
        i += 1;
    }
    line
}

fn deadline_re() -> &'static Pat {
    pat!(
        r"(?<![\w.])(?:world\.time|REALTIMEOFDAY)\s*(?:>=|<=|>|<)\s*(?!\d)([A-Za-z_][\w.\[\]?]*)|(?<![\w.])([A-Za-z_][\w.\[\]?]*)\s*(?:>=|<=|>|<)\s*(?:world\.time|REALTIMEOFDAY)(?![\w])"
    )
}

fn is_periodic(type_path: &str, name: &str) -> bool {
    name != "tick" || type_path.starts_with("/datum/om/behaviour")
}

fn indent_of(line: &str) -> usize {
    line.bytes().take_while(|b| *b == b'\t').count()
}

/// `scan_lines`: line numbers of every deadline comparison in a periodic body.
fn deadline_hits(lines: &[&str]) -> Vec<usize> {
    let mut out = Vec::new();
    let mut current_type: Option<String> = None;
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        let mut body_indent = 0usize;
        let mut found = false;
        if let Some(m) = pat_match!(r"^(/[\w/]+?)/(?:proc/)?(process|periodic_step|machine_step|service_step|tick)\(").captures(line) {
            if is_periodic(m.s(1), m.s(2)) {
                found = true;
                body_indent = 1;
            }
        }
        if !found {
            if let Some(tb) = pat_match!(r"^(/[\w/]+)\s*(?://.*)?$").captures(line) {
                current_type = Some(tb.s(1).to_string());
            } else if !line.is_empty() && !(line.starts_with('\t') || line.starts_with(' ') || line.starts_with('#') || line.starts_with("//")) {
                current_type = None;
            }
            if let Some(ct) = &current_type {
                if let Some(n) = pat_match!(r"^\t(?:proc/)?(process|periodic_step|machine_step|service_step|tick)\(").captures(line) {
                    if is_periodic(ct, n.s(1)) {
                        found = true;
                        body_indent = 2;
                    }
                }
            }
        }
        if !found {
            i += 1;
            continue;
        }
        let mut j = i + 1;
        while j < lines.len() {
            let body = lines[j];
            if !py_strip(body).is_empty() && indent_of(body) < body_indent {
                break;
            }
            if deadline_re().is_match(strip_comment(body)) {
                out.push(j + 1);
            }
            j += 1;
        }
        i = j;
    }
    out
}

// ---- hygiene.py ------------------------------------------------------------------------------

/// The type path the line at 0-based `index` belongs to (nearest column-0 path above it).
fn owner_type(lines: &[&str], index: usize) -> String {
    for j in (0..=index).rev() {
        if let Some(m) = pat_match!(r"^(/(?!/)[\w/]+)").captures(lines[j]) {
            let mut path = m.s(1).to_string();
            if path.contains("/proc/") || path.contains("/verb/") {
                path = path.split("/proc/").next().unwrap_or("").split("/verb/").next().unwrap_or("").to_string();
            }
            return path;
        }
    }
    String::new()
}

fn scan_boilerplate(rel: &str, lines: &[&str], out: &mut Vec<(&'static str, String, usize)>) {
    for (idx, line) in lines.iter().enumerate() {
        let number = idx + 1;
        let Some(m) = pat!(r"(?://+|/\*)\s*ALLOW\(\s*([\w\s,]*?)\s*\)\s*:\s*(.*?)\s*(?:\*/.*)?$").captures(line) else { continue };
        let reason = py_strip(m.s(2)).to_lowercase();
        if PLACEHOLDERS.iter().any(|p| reason.contains(p)) {
            out.push(("annotation_boilerplate", rel.to_string(), number));
            continue;
        }
        if let Some(kind) = pat_match!(r"^(mob|obj|item|machine|turf|area)s?:").captures(&reason) {
            let owner = owner_type(lines, idx);
            if !owner.is_empty() && !owner.starts_with(kind_path(kind.s(1))) {
                out.push(("annotation_boilerplate", rel.to_string(), number));
            }
        }
    }
}

/// `[(0-based index, name)]` of cached_* instance var declarations.
fn cached_decls(lines: &[&str]) -> Vec<(usize, String)> {
    let mut found = Vec::new();
    let mut in_type = false;
    let mut in_nested_proc = false;
    for (i, line) in lines.iter().enumerate() {
        if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) {
            in_type = pat_match!(r"^(/(?!/)[\w/]+)\s*(?://.*)?$").is_match(line) || pat_match!(r"^[A-Z][A-Z0-9_]*_DEF\(").is_match(line);
            in_nested_proc = false;
            if let Some(m) = pat_match!(r"^/(?!/)[\w/]*?/var/((?:\w+/)*?)(cached_\w+)\b").captures(line) {
                if !pat!(r"(?:^|/)(static|global|const)/").is_match(m.s(1)) {
                    found.push((i, m.s(2).to_string()));
                }
            }
            continue;
        }
        if !in_type {
            continue;
        }
        if pat_match!(r"^\t(?:proc/|verb/)?\w+\(").is_match(line) {
            in_nested_proc = true;
            continue;
        }
        if line.starts_with('\t') && !line.starts_with("\t\t") && !py_strip(line).is_empty() {
            in_nested_proc = false;
        }
        if let Some(m) = pat_match!(r"^\tvar/((?:\w+/)*?)(cached_\w+)\b").captures(line) {
            if !in_nested_proc && !pat!(r"(?:^|/)(static|global|const)/").is_match(m.s(1)) {
                found.push((i, m.s(2).to_string()));
            }
        }
    }
    found
}

fn scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    let mut declared: HashSet<String> = HashSet::new();
    // (file position in `files`, index, name), grouped by file in first-seen order
    let mut by_file: Vec<(usize, Vec<(usize, String)>)> = Vec::new();
    for (fi, f) in files.iter().enumerate() {
        let rel = f.rel.as_str();
        let lines = f.raw().lines_vec();
        scan_boilerplate(rel, &lines, &mut out);
        for line in &lines {
            if line.contains("CACHE_ON_") {
                for m in pat!(r#"\[\s*"(cached_\w+)"\s*\]\s*=\s*CACHE_ON_"#).captures_iter(line) {
                    declared.insert(m.s(1).to_string());
                }
            }
        }
        if VENDORED.iter().any(|p| rel.starts_with(p)) {
            continue;
        }
        let decls = cached_decls(&lines);
        if !decls.is_empty() {
            by_file.push((fi, decls));
        }
    }
    // cached_var: undeclared caches (declaration and every write), and manual invalidation of
    // declared ones. Writes are looked for in the declaring file (these vars are type-private).
    for (fi, entries) in &by_file {
        let f = files[*fi];
        let rel = f.rel.as_str();
        let lines = f.raw().lines_vec();
        for (index, name) in entries {
            let write = Pat::cached(&format!(r"(?<![\w.])(?:src\.)?{}\s*(?:=(?!=)|\+=|-=|\|=)\s*(.*)$", regex::escape(name)));
            if !declared.contains(name) {
                out.push(("cached_var", rel.to_string(), index + 1));
            }
            for (idx, line) in lines.iter().enumerate() {
                let number = idx + 1;
                if number == index + 1 {
                    continue;
                }
                if !line.contains(name.as_str()) {
                    continue;
                }
                let Some(m) = write.captures(strip_comment(line)) else { continue };
                if !declared.contains(name) || py_strip(m.s(1)) == "null" {
                    out.push(("cached_var", rel.to_string(), number));
                }
            }
        }
    }
    // deadline_poll: the poll, and the writes that store its deadline.
    for f in files {
        let rel = f.rel.as_str();
        let lines = f.raw().lines_vec();
        let hits = deadline_hits(&lines);
        if hits.is_empty() {
            continue;
        }
        let mut idents: BTreeSet<String> = BTreeSet::new();
        for number in hits {
            if crate::allow::kept(f, number, "sys_deadline_poll").is_some() {
                continue;
            }
            out.push(("deadline_poll", rel.to_string(), number));
            for m in deadline_re().captures_iter(strip_comment(lines[number - 1])) {
                let ident = if m.matched(1) && !m.s(1).is_empty() { m.s(1) } else { m.s(2) };
                if !ident.is_empty() {
                    let last = ident.rsplit('.').next().unwrap_or("");
                    idents.insert(last.split('[').next().unwrap_or("").to_string());
                }
            }
        }
        let mut cache: HashMap<&str, &Pat> = HashMap::new();
        for ident in &idents {
            let store = cache.entry(ident.as_str()).or_insert_with(|| {
                Pat::cached(&format!(r"(?<![\w]){}\s*(?:=(?!=)|\+=)[^=]*world\.time", regex::escape(ident)))
            });
            for (idx, line) in lines.iter().enumerate() {
                if store.is_match(strip_comment(line)) {
                    out.push(("deadline_poll", rel.to_string(), idx + 1));
                }
            }
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "hygiene", rules: RULES, files_scan: Some(scan), ..SysModule::DEFAULT });
}
