//! Port of `tools/ci/sys_rules/fields.py` (doc/rewrite/systems.md section 2): core machine state
//! as declared fields.
//!
//! Rules: `stat_bits` (raw `stat` bit use in machinery/vehicle procs, or `thing.stat` used with a bit
//! operator or typed as a machine), `stat_owned` (NOPOWER/BROKEN written outside their owner),
//! `stat_helper` (the old `inoperable()`/`is_operational()` readers) and `field_write` (a direct write
//! to a core field outside its setter, resolved by `dm::field_write`).

use crate::dm::field_write::{is_var_decl, local_or_member, norm, proc_def, typed_names, FwlIndex, Locals};
use crate::dm::sys::{register_module, SysModule};
use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{is_py_space, under};

use crate::allow_registry_fields::sys_fields::RULES;


fn files_scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let index = FwlIndex::get(tree);
    let fields = index.fields_named(crate::sys_fields_policy::CORE);
    let key = index.ctx_key(Some(crate::sys_fields_policy::CORE));
    let per: Vec<Vec<(u8, u32)>> = incr::keyed("sys-fields-judge", key, files, |f| {
        crate::sys_fields_policy::scan_one(&index, &fields, f)
            .into_iter()
            .map(|(rule, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32))
            .collect()
    });
    let mut out = Vec::new();
    for (f, sites) in files.iter().zip(per) {
        for (rule, line) in sites {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_fields::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(files_scan), ..SysModule::DEFAULT });
}
