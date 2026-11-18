//! Existing registration/selftest adapter, one unique old appearance writer policy.
use crate::{dm::sys::{register_module,SysModule},lint::Registry,tree::{SourceFile,Tree}};
use crate::allow_registry_fields::sys_dx_look_side_effects::RULES;
const FIXTURE: &str = "
/obj/machinery/vent/appearance_overlays()
\tvar/list/parts = list()
\tparts += \"on\"
\ticon_state = \"vent\"
\tif(welded)
\t\tplaysound(src, 'sound/weld.ogg', 50)
\tlast_state = \"on\"
\treturn parts

/obj/machinery/quiet/appearance_overlays()
\tvar/list/parts = list()
\tparts += \"idle\"
\treturn parts

DECLARE_APPEARANCE_PROC(/obj/machinery/custom, TYPE_PROC_REF(/obj/machinery/custom, custom_look), list())

/obj/machinery/custom/proc/custom_look()
\ticon_state = \"custom\"
\ton = TRUE
\treturn list()
";

fn selftest()->Result<String,String>{crate::sys_selftest_policy::run(crate::sys_selftest_policy::Kind::Look,&mut crate::derived_selftest_policy::LegacyAssertions,&mut crate::derived_selftest_policy::LegacyAssertions).map_err(|failure|match failure{crate::derived_selftest_policy::Failure::Assertion(text)=>text,crate::derived_selftest_policy::Failure::Operational(actual)=>actual.to_string()})}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_look_side_effects::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(crate::sys_look_effects_policy::scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
