//! Original registration/selftests delegate one constructor-name policy.
use crate::{dm::{dx::DxIndex,sys::{register_module,SysModule}},lint::Registry,tree::{SourceFile,Tree}};
use crate::allow_registry_fields::sys_dx_constructor_shadow::RULES;
use crate::sys_constructor_shadow_policy::{PRESET_FILES,CAPS_DIR};
const FIXTURE: &str = include_str!("../../fixtures/sys__dx_constructor_shadow/code/modules/x/selftest.dm");
const PRESETS_FIXTURE: &str = "
/proc/wall_console(board)
\treturn list()
";
const LIBRARY_FIXTURE: &str = "
/proc/power_channels(list/channels)
\treturn list(new /datum/capability/power_channels)
/proc/wires_of(atom/A)
\treturn cap_of(A, /datum/capability/wires)
/proc/cap_of(atom/A, key)
\treturn null
";

fn selftest()->Result<String,String>{crate::sys_selftest_policy::run(crate::sys_selftest_policy::Kind::Constructor,&mut crate::derived_selftest_policy::LegacyAssertions,&mut crate::derived_selftest_policy::LegacyAssertions).map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(actual)=>actual.to_string()})}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_constructor_shadow::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(crate::sys_constructor_shadow_policy::scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
