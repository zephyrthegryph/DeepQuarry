//! Original base/list policy over a borrowed single-variable projection.
//! No type model or filesystem reads. Raw annotation questions are only line
//! identities emitted by the existing source-policy callback scanner.
use crate::{base_var_hot_policy::homes_in, pat, tree::SourceFile};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
pub const SINGLETON_ROOTS: &[&str] = &["/datum/world_service", "/datum/controller"];
pub fn is_singleton(type_path: &str, globals: &HashSet<String>) -> bool {
    globals.contains(type_path)
        || SINGLETON_ROOTS.iter().any(|r| {
            type_path == *r
                || (type_path.starts_with(r) && type_path.as_bytes().get(r.len()) == Some(&b'/'))
        })
}
pub struct VarView<'a> {
    pub rel: &'a str,
    pub line: u32,
    pub owner: &'a str,
    pub name: &'a str,
    pub vtype: &'a str,
    pub base: bool,
    pub list_init: bool,
}
pub struct Classification {
    pub base: bool,
    pub list: bool,
}
#[allow(clippy::too_many_arguments)]
pub(crate) fn classify(
    v: VarView<'_>,
    file: &SourceFile,
    singletons: &HashSet<String>,
    exempt_prefixes: &[String],
    exempt_files: &[String],
    homes: &HashSet<(String, String)>,
    hot: &BTreeMap<String, String>,
    home_types: &[String],
) -> Option<Classification> {
    if crate::dm::sys::kept_recorded(file, v.line as usize, "base_vars") {
        return None;
    }
    let housed = homes.contains(&(v.owner.to_string(), v.name.to_string()))
        || hot.contains_key(&format!("{}/{}", v.owner, v.name))
        || home_types
            .iter()
            .any(|h| v.vtype == *h || v.vtype.starts_with(&format!("{}/", h)));
    let base = v.base && !housed;
    let mut list = false;
    if v.list_init {
        let exempt = exempt_prefixes
            .iter()
            .any(|p| v.rel.starts_with(p.as_str()))
            || exempt_files.iter().any(|e| e == v.rel);
        let empty = HashSet::new();
        if !exempt
            && !is_singleton(v.owner, &empty)
            && !singletons.contains(v.owner)
            && !crate::dm::sys::kept_recorded(file, v.line as usize, "instance_list")
        {
            list = true;
        }
    }
    Some(Classification { base, list })
}
/// Exactly the questions facts_of asks, including raw noncompiled declarations.
/// The compact ledger retains owner-order and line only, never a variable tree,
/// declared type model, initializer AST or duplicate source text.
pub(crate) fn raw_allow_lines(file: &SourceFile) -> Vec<usize> {
    if file.hidden {
        return Vec::new();
    }
    let mut owners: HashMap<String, (usize, usize)> = HashMap::new();
    let mut rows = Vec::new();
    crate::raw_declaration_policy::visit_file(
        &file.rel,
        file.code(),
        |owner, (_, mods, _, _), _, line| {
            let next = owners.len();
            let (_, first) = *owners.entry(owner.to_string()).or_insert((next, line));
            if mods
                .iter()
                .any(|m| ["const", "static", "global"].contains(&m.as_str()))
            {
                return;
            }
            rows.push((first, rows.len(), line));
        },
        |_, _| {},
    );
    rows.sort_by_key(|(first, ordinal, _)| (*first, *ordinal));
    rows.into_iter().map(|(_, _, line)| line).collect()
}
#[derive(Default)]
pub(crate) struct RawFacts {
    pub homes: Vec<(String, String)>,
    pub singles: Vec<String>,
}
// file_facts is appended mechanically from the original facts_of prefix by
// prepare.py; its regex policy is not independently reimplemented here.

pub(crate) fn file_facts(f:&SourceFile,macros:&[String],relations:&[String])->RawFacts{
let mut out=RawFacts::default();
    if f.rel.starts_with("code/") {
        let text = f.raw().text.as_str();
        out.homes = homes_in(f.code().text.as_str(), macros, relations);
        if text.contains("GLOBAL_DATUM_INIT") {
            // The trailing `\x08` is the Python's literal backspace (see dm/singletons.rs).
            let mut set: BTreeSet<String> = BTreeSet::new();
            for m in pat!(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new\x08").captures_iter(text) {
                set.insert(m.s(1).to_string());
            }
            out.singles = set.into_iter().collect();
        }
        if text.contains("SYSTEM_DEF(") {
            // SYSTEM_DEF(x) declares the one instance of /datum/system/x.
            let mut set: BTreeSet<String> = out.singles.iter().cloned().collect();
            for m in pat!(r"(?m)^SYSTEM_DEF\((\w+)\)").captures_iter(text) {
                set.insert(format!("/datum/system/{}", m.s(1)));
            }
            out.singles = set.into_iter().collect();
        }
    }
out
}
