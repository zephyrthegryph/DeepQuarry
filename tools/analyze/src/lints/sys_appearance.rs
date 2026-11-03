//! Same cached legacy appearance adapter; unique lexical/schema policy lives in sys_appearance_policy.
use std::collections::{BTreeSet,HashSet};
use crate::{sys_appearance_policy as shared,dm::{field_write::FwlIndex,sys::{register_module,SysModule}},incr,lint::Registry,tree::{Tree,SourceFile}};
use crate::allow_registry_fields::sys_appearance::RULES;
fn files_scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let index = FwlIndex::get(tree);
    let regs = incr::facts("sys-appearance-regs", files, shared::registrations_of);
    let events = incr::facts("sys-appearance-watches", files, shared::watch_events_of);
    let cx = shared::schema(&index, &regs, &events);
    // What pass 1 can read: every registration and declaration, the typed members and globals.
    let key1 = incr::mix(&[incr::ctx_key(&(&regs, &events)), index.ctx_key(Some(&[]))]);

    // Pass 1 per file, reduced to the owning pairs each file contributes.
    let owning_per: Vec<Vec<(String, String)>> = incr::keyed("sys-appearance-owning", key1, files, |f| shared::owning_file(&cx, f));
    let owning: HashSet<(String, String)> = owning_per.into_iter().flatten().collect();
    let key2 = incr::mix(&[key1, incr::ctx_key(&owning.iter().collect::<BTreeSet<_>>())]);
    let results = incr::keyed("sys-appearance-judge", key2, files, |f| {
        shared::judge_file(&cx, &owning, f)
            .into_iter()
            .map(|(rule, _, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32))
            .collect::<Vec<(u8, u32)>>()
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
    register_module(
        reg,
        SysModule {
            name: crate::allow_registry_fields::sys_appearance::SCOPE_MODULE_NAME,
            rules: RULES,
            allow_extra: crate::allow_registry_fields::sys_appearance::ALLOW_EXTRA,
            allow_extra_rules: &["update_icon_override"],
            files_scan: Some(files_scan),
            ..SysModule::DEFAULT
        },
    );
}
