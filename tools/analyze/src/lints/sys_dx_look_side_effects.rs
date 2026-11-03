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

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let tree = Tree::from_files(vec![SourceFile::from_text("code/fixture.dm", FIXTURE)]);
    let files = vec![tree.get("code/fixture.dm").unwrap()];
    let mut got: Vec<usize> = crate::sys_look_effects_policy::scan(&tree, &files).into_iter().map(|(_, _, n)| n).collect();
    got.sort();
    let bad = ["\t\tplaysound(src, 'sound/weld.ogg', 50)", "\tlast_state = \"on\"", "\ton = TRUE"];
    let mut want: Vec<usize> = bad.iter().map(|t| lines.iter().position(|l| l == t).map(|k| k + 1).unwrap_or(0)).collect();
    want.sort();
    if got != want {
        return Err(format!("dx_look_side_effects selftest: got {:?}, want {:?}", got, want));
    }
    Ok("true".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_look_side_effects::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(crate::sys_look_effects_policy::scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
