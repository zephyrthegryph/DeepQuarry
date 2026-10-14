//! Procs and calls located on the typed tree, for the ratchet lints that used to find them by header text.
//!
//! * [`proc_defs`]: every definition (base or override) of the named procs, with the file and header line the tree gives,
//!   whatever the syntax (`/obj/x/Initialize()`, a nested `obj/x` block, a macro that writes the proc).
//! * [`call_sites`]: every call of the named procs in any proc body, at the line of the call itself (a call on the third line
//!   of a multi-line statement is on that line).
//!
//! A text rule that still reads lines (a pattern that is a macro the parser expands away) applies itself to
//! [`body_lines`]: the header's body, bounded by indentation as the text rule bounded it.

use std::collections::BTreeSet;

use dreammaker::ast::{Block, Expression, Statement, Term};

use super::ast::{stmt_blocks, stmt_exprs, walk_expr};
use super::Sem;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ProcDef {
    pub rel: String,
    /// The line of the definition's header.
    pub header: u32,
    /// The type the definition is on (`/` for a global proc).
    pub owner: String,
    pub name: String,
}

/// Every definition with a body of the procs in `names`, sorted by file and line.
pub fn proc_defs(sem: &Sem, names: &[&str]) -> Vec<ProcDef> {
    let mut out = Vec::new();
    for ty in sem.objtree.iter_types() {
        let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
        for name in names {
            let Some(tp) = ty.get().procs.get(*name) else { continue };
            for v in tp.value.iter() {
                if v.code.is_none() {
                    continue;
                }
                let Some(rel) = sem.file_of(v.location) else { continue };
                out.push(ProcDef { rel: rel.to_string(), header: engine_line(&sem.root, rel, v.location.line), owner: owner.clone(), name: name.to_string() });
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

fn walk_calls<'a>(b: &'a Block, f: &mut dyn FnMut(&'a Expression)) {
    for st in b.iter() {
        if let Statement::If { arms, .. } = &st.elem {
            for (c, _) in arms.iter() {
                walk_expr(&c.elem, f);
            }
        } else {
            for e in stmt_exprs(&st.elem) {
                walk_expr(e, f);
            }
        }
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                for e in stmt_exprs(s) {
                    walk_expr(e, f);
                }
            }
        }
        for nb in stmt_blocks(&st.elem) {
            walk_calls(nb, f);
        }
    }
}

/// Every unscoped call `name(...)` (and `global.name(...)`) of a proc in `names`, in any proc body: `(file, line, name)`,
/// sorted and unique.
pub fn call_sites(sem: &Sem, names: &[&str]) -> Vec<(String, u32, String)> {
    let mut out: BTreeSet<(String, u32, String)> = BTreeSet::new();
    for ty in sem.objtree.iter_types() {
        for (_, tp) in ty.get().procs.iter() {
            for v in tp.value.iter() {
                let Some(code) = v.code.as_ref() else { continue };
                walk_calls(code, &mut |e| {
                    if let Expression::Base { term, .. } = e {
                        let n = match &term.elem {
                            Term::Call(n, _) | Term::GlobalCall(n, _) => n.as_str(),
                            _ => return,
                        };
                        if names.contains(&n) {
                            if let Some(rel) = sem.file_of(term.location) {
                                out.insert((rel.to_string(), engine_line(&sem.root, rel, term.location.line), n.to_string()));
                            }
                        }
                    }
                });
            }
        }
    }
    out.into_iter().collect()
}

/// The line the lint engine numbers `model_line` of `rel` as. The engine reads files with universal newlines (a lone carriage
/// return ends a line, as in Python); the parser does not, so after a lone carriage return the two count differently. Read once per file.
pub fn engine_line(root: &std::path::Path, rel: &str, model_line: u32) -> u32 {
    use std::collections::HashMap;
    use std::sync::Mutex;
    static LONE_CR: Mutex<Option<HashMap<String, Vec<u32>>>> = Mutex::new(None);
    let mut guard = LONE_CR.lock().unwrap();
    let map = guard.get_or_insert_with(HashMap::new);
    let lines = map.entry(rel.to_string()).or_insert_with(|| {
        let Ok(bytes) = std::fs::read(root.join(rel)) else { return Vec::new() };
        let mut out = Vec::new();
        let mut line = 1u32;
        for (i, b) in bytes.iter().enumerate() {
            match b {
                b'\n' => line += 1,
                b'\r' if bytes.get(i + 1) != Some(&b'\n') => out.push(line),
                _ => {}
            }
        }
        out
    });
    model_line + lines.iter().filter(|l| **l < model_line).count() as u32
}

fn indent(line: &str) -> Option<usize> {
    let line = line.trim_end_matches('\r');
    let t = line.trim_start_matches([' ', '\t']);
    if t.is_empty() || t.starts_with("//") {
        return None;
    }
    Some(line.len() - t.len())
}

/// The 1-based body lines of the definition whose header is line `header` of `lines`: every following line until the first
/// non-blank, non-comment line indented no deeper than the header (the next definition, or the end of the block).
pub fn body_lines(lines: &[&str], header: u32) -> std::ops::Range<usize> {
    let h = header as usize;
    if h == 0 || h > lines.len() {
        return h..h;
    }
    let base = indent(lines[h - 1]).unwrap_or(0);
    let mut end = h + 1;
    while end <= lines.len() {
        if let Some(i) = indent(lines[end - 1]) {
            if i <= base {
                break;
            }
        }
        end += 1;
    }
    (h + 1)..end
}

#[cfg(test)]
mod tests {
    use super::{body_lines, engine_line};

    #[test]
    fn a_lone_carriage_return_shifts_the_engine_line() {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(root.path().join("probe.dm"), "a\r\nb\rc\nd\n").unwrap();
        assert_eq!(engine_line(root.path(), "probe.dm", 1), 1);
        assert_eq!(engine_line(root.path(), "probe.dm", 2), 2);
        assert_eq!(engine_line(root.path(), "probe.dm", 3), 4);
    }

    #[test]
    fn a_body_ends_at_the_next_line_as_shallow_as_its_header() {
        let lines = ["/obj/a/Initialize()", "\t. = ..()", "", "\t// note", "\tx = 1", "/obj/b", "\tInitialize()", "\t\ty = 2", "\tvar/z"];
        assert_eq!(body_lines(&lines, 1), 2..6);
        assert_eq!(body_lines(&lines, 7), 8..9);
    }
}
