//! Sys Loot delegates to one unique roots/rule policy.
use std::collections::{BTreeSet,HashSet};
use crate::{dm::sys::{register_module,SysModule},incr,lint::Registry,tree::{SourceFile,Tree}};
use crate::sys_loot_policy::{roots_of,judge,RULES};
fn scan_files(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-loot-facts", files, roots_of);
    let mut roots: BTreeSet<String> = BTreeSet::new();
    roots.insert("/obj/random".to_string());
    for r in fs.into_iter().flatten() {
        roots.insert(r);
    }
    let key = incr::ctx_key(&roots);
    let roots: HashSet<String> = roots.into_iter().collect();
    let results = incr::keyed("sys-loot-judge", key, files, |f| {
        let mut v: Vec<(&'static str, usize)> = Vec::new();
        judge(f, &roots, &mut v);
        v.into_iter().map(|(rule, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32)).collect::<Vec<(u8, u32)>>()
    });
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        for (rule, line) in v {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}
pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_loot::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(scan_files), ..SysModule::DEFAULT });
}
