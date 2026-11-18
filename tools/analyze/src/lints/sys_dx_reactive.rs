//! Port of `tools/ci/sys_rules/dx_reactive.py`: the reactive-proc rules of the DX framework
//! (design review H4, H5, M3, M5). The analysis lives in [`crate::dm::dx_reactive`] because
//! `sys/dx_look_side_effects` reuses it.

use crate::dm::dx_reactive::analyse;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::tree::{SourceFile, Tree};

use crate::allow_registry_fields::sys_dx_reactive::RULES;

fn scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    analyse(tree, files)
}

/// The Python `FIXTURE` of dx_reactive.py, verbatim.
const FIXTURE: &str = include_str!("../../fixtures/sys__dx_reactive/code/selftest.dm");

fn selftest()->Result<String,String>{
 let tree=Tree::from_files(vec![SourceFile::from_text("x.dm",FIXTURE)]);let files=vec![tree.get("x.dm").unwrap()];let found=analyse(&tree,&files);
 crate::sys_reactive_selftest_policy::assert_rows(found.iter().map(|(rule,_,line)|(*rule,*line)),&mut crate::derived_selftest_policy::LegacyAssertions).map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(error)=>error.to_string()})
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_reactive::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
