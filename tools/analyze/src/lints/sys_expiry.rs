//! Original registration/incremental adapter; the unchanged four global folds remain here.
use std::{collections::BTreeSet,sync::OnceLock};
use crate::{dm::sys::{register_module,SysModule},incr,lint::Registry,pat::Pat,tree::{SourceFile,Tree}};
use crate::expiry_policy::{Writes,pass_compares,pass_writes,pass_at_writes};
use crate::allow_registry_fields::sys_expiry::RULES;
fn files_scan(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    // The declared-name index is gone with the old declaration macro: a raw compare against a cooldown var is the cooldown lint's.
    let names: BTreeSet<String> = BTreeSet::new();
    let stamp: OnceLock<Option<Pat>> = OnceLock::new();
    let p1: Vec<Vec<u32>> = incr::keyed("sys-expiry-compares", incr::ctx_key(&names), files, |f| {
        let stamp = stamp
            .get_or_init(|| {
                if names.is_empty() {
                    None
                } else {
                    Some(Pat::new(&format!(r"(?<![\w])(?:{})\b", names.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("|"))))
                }
            })
            .as_ref();
        pass_compares(f, stamp).into_iter().map(|l| l as u32).collect()
    });
    let p2: Vec<Writes> = incr::facts("sys-expiry-writes", files, pass_writes);
    let p3: Vec<Vec<u32>> = incr::facts("sys-expiry-at", files, |f| pass_at_writes(f).into_iter().map(|l| l as u32).collect());
    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    for (f, lines) in files.iter().zip(&p1) {
        for &l in lines {
            out.push(("world_time_expiry", f.rel.clone(), l as usize));
        }
    }
    let mut declared: BTreeSet<&str> = BTreeSet::new();
    for w in &p2 {
        for d in &w.declared {
            declared.insert(d.as_str());
        }
    }
    for (f, w) in files.iter().zip(&p2) {
        for &l in &w.writes {
            out.push(("world_time_write", f.rel.clone(), l));
        }
    }
    for (f, w) in files.iter().zip(&p2) {
        for (l, name) in &w.uses {
            if !declared.contains(name.as_str()) {
                out.push(("expiry_undeclared", f.rel.clone(), *l));
            }
        }
    }
    for (f, lines) in files.iter().zip(&p3) {
        for &l in lines {
            out.push(("world_time_write", f.rel.clone(), l as usize));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_expiry::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(files_scan), ..SysModule::DEFAULT });
}
