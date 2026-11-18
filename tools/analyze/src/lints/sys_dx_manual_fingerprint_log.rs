//! Existing registration/selftest adapter for the unique manual-log producer.
use crate::{dm::sys::{register_module,SysModule},lint::Registry,tree::{SourceFile,Tree}};
use crate::allow_registry_fields::sys_dx_manual_fingerprint_log::RULES;
const FIXTURE: &str = include_str!("../../fixtures/sys__dx_manual_fingerprint_log/code/modules/x/selftest.dm");

fn selftest()->Result<String,String>{crate::sys_selftest_policy::run(crate::sys_selftest_policy::Kind::ManualLog,&mut crate::derived_selftest_policy::LegacyAssertions,&mut crate::derived_selftest_policy::LegacyAssertions).map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(actual)=>actual.to_string()})}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule {
            name: crate::allow_registry_fields::sys_dx_manual_fingerprint_log::SCOPE_MODULE_NAME,
            rules: RULES,
            files_scan: Some(crate::manual_log_policy::scan),
            selftest: Some(selftest),
            py_selftest: true,
            ..SysModule::DEFAULT
        },
    );
}
