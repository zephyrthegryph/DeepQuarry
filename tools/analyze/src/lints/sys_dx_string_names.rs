//! Existing registration/selftest delegates the unique lexical accessor policy.
use crate::{dm::{dx::DxIndex,sys::{register_module,SysModule}},lint::Registry,tree::{SourceFile,Tree}};
use crate::allow_registry_fields::sys_dx_string_names::RULES;
fn selftest()->Result<String,String>{crate::sys_selftest_policy::run(crate::sys_selftest_policy::Kind::StringNames,&mut crate::derived_selftest_policy::LegacyAssertions,&mut crate::derived_selftest_policy::LegacyAssertions).map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(actual)=>actual.to_string()})}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_string_names::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(crate::sys_string_names_policy::scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
