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

use super::Sem;
use crate::model::expr::{Form, Root};
use crate::model::procs::Proc;
use crate::model::walk::walk_block;

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
    for ty in sem.m().types() {
        let owner = ty.path().to_string();
        for name in names {
            for v in ty.proc_definitions(name) {
                if v.body().is_none() {
                    continue;
                }
                let Some(rel) = sem.file_of(v.site()) else { continue };
                let header = engine_line(&sem.root, &rel, sem.line(v.site()));
                out.push(ProcDef { rel, header, owner: owner.clone(), name: name.to_string() });
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

/// Every unscoped call `name(...)` of a proc in `names`, in any proc body: `(file, line, name)`,
/// sorted and unique.
pub fn call_sites(sem: &Sem, names: &[&str]) -> Vec<(String, u32, String)> {
    let store = format!("call-sites-{}", names.join("-"));
    let per_file: Vec<Vec<(String, u32, String)>> = per_file(sem, &store, |_rel, defs| {
        let mut out: Vec<(String, u32, String)> = Vec::new();
        for (_, v) in defs {
            let Some(code) = v.body() else { continue };
            walk_block(code, &mut |visit, _| {
                let Form::Chain(c) = &visit.form else { return };
                let Root::Call { name: n, .. } = &c.root else { return };
                if names.contains(n) {
                    let site = c.root_site();
                    if let Some(rel) = sem.file_of(Some(site)) {
                        let line = engine_line(&sem.root, &rel, sem.line(Some(site)));
                        out.push((rel, line, n.to_string()));
                    }
                }
            });
        }
        out
    });
    let out: BTreeSet<(String, u32, String)> = per_file.into_iter().flatten().collect();
    out.into_iter().collect()
}

/// `f(rel, definitions)` over every file's proc definitions, each with its type's path (a definition belongs to the file of its location), cached per file in
/// the `incr` store `name` by the file's content in the macro environment (`Sem::site_key`): after an edit `f` runs for the edited
/// files only, and the other files' bodies are not even decoded. A model that is not the full one (a fixture, a partial model) computes
/// everything. Results come in path order.
pub fn per_file<R>(sem: &Sem, name: &str, f: impl Fn(&str, &[(String, Proc<'_>)]) -> R + Sync) -> Vec<R>
where
    R: serde::Serialize + serde::de::DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    per_file_in(sem, name, 0, f)
}

/// [`per_file`] for a judgement that also reads what `ctx` names (a digest of everything outside the file it consults: the model's
/// structure, an index built from every file): a file's result is kept while its content and `ctx` are unchanged.
pub fn per_file_in<R>(sem: &Sem, name: &str, ctx: u128, f: impl Fn(&str, &[(String, Proc<'_>)]) -> R + Sync) -> Vec<R>
where
    R: serde::Serialize + serde::de::DeserializeOwned + Default + PartialEq + Clone + Send + Sync + 'static,
{
    use std::collections::BTreeMap;
    let mut by_file: BTreeMap<String, (u128, Vec<(String, Proc<'_>)>)> = BTreeMap::new();
    for ty in sem.m().types() {
        let path = ty.path().to_string();
        for pname in ty.proc_names() {
            for v in ty.proc_definitions(pname) {
                if v.body().is_none() {
                    continue;
                }
                if let Some(rel) = sem.file_of(v.site()) {
                    by_file.entry(rel).or_insert_with(|| (sem.site_key(v.site()), Vec::new())).1.push((path.clone(), v));
                }
            }
        }
    }
    let groups: Vec<(&String, &(u128, Vec<(String, Proc<'_>)>))> = by_file.iter().collect();
    if !sem.cacheable() {
        return groups.iter().map(|(rel, (_, defs))| f(rel, defs)).collect();
    }
    let keys: Vec<u128> = groups.iter().map(|(_, (k, _))| *k).collect();
    crate::incr::keyed_by(name, ctx, &keys, |i| f(groups[i].0, &groups[i].1 .1))
}

/// A digest of every `set SpacemanDMM_return_type = /type` a proc body declares (the return type `image_dir_after_build::return_type`
/// reads from a body), kept per file: with [`Sem::structure_digest`] (which holds the `as /type` declarations) it names every return
/// type a judgement can look up.
pub fn return_settings_digest(sem: &Sem) -> u128 {
    let per: Vec<Vec<(String, String)>> = per_file(sem, "procs-return-settings", |_rel, defs| {
        let mut out = Vec::new();
        for (owner, v) in defs {
            let Some(code) = v.body() else { continue };
            for st in crate::model::walk::stmts(code) {
                if let crate::model::walk::Stmt::Setting { name, value, .. } = &st.stmt {
                    if *name == "SpacemanDMM_return_type" {
                        out.push((owner.clone(), format!("{:?}", value.kind)));
                    }
                }
            }
        }
        out
    });
    crate::incr::ctx_key(&per)
}

/// The line the lint engine numbers `model_line` of `rel` as. The engine reads files with universal newlines (a lone carriage
/// return ends a line, as in Python); the parser does not, so after a lone carriage return the two count differently. Read once per file.
pub fn engine_line(root: &std::path::Path, rel: &str, model_line: u32) -> u32 {
    use std::collections::HashMap;
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

/// Each file's lone carriage returns, read once per run (`engine_line`).
static LONE_CR: std::sync::Mutex<Option<std::collections::HashMap<String, Vec<u32>>>> = std::sync::Mutex::new(None);

/// Run state for `crate::host::reset_run_state`.
pub(crate) fn reset() {
    *LONE_CR.lock().unwrap_or_else(|e| e.into_inner()) = None;
}
