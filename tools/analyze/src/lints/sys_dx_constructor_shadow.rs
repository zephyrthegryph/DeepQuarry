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

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let preset_rel = format!("{}s.dm", PRESET_FILES);
    let lib_rel = format!("{}library/apc.dm", CAPS_DIR);
    let tree = Tree::from_files(vec![
        SourceFile::from_text("x.dm", FIXTURE),
        SourceFile::from_text(&preset_rel, PRESETS_FIXTURE),
        SourceFile::from_text(&lib_rel, LIBRARY_FIXTURE),
    ]);
    let files: Vec<&SourceFile> = ["x.dm", preset_rel.as_str(), lib_rel.as_str()].iter().map(|r| tree.get(r).unwrap()).collect();
    let idx = DxIndex::get(&tree, &files);
    let mut got: Vec<usize> = crate::sys_constructor_shadow_policy::scan_procs(&tree, &idx.procs).into_iter().filter(|(_, r, _)| r == "x.dm").map(|(_, _, n)| n).collect();
    got.sort();
    let at = |snippet: &str| -> usize { lines.iter().position(|l| l.contains(snippet)).map(|k| k + 1).unwrap_or(0) };
    let mut want = vec![at("airlock/proc/cap_lock()"), at("airlock/cap_has(bits)"), at("console/proc/wall_console()"), at("apc/proc/power_channels()")];
    want.sort();
    if got != want {
        return Err(format!("dx_constructor_shadow selftest: got {:?}, want {:?}", got, want));
    }
    // part_constructor_shadow: a capability datum's own `cooldown` proc captures the engine's constructor; an unrelated type's does not, nor does a
    // legacy capability datum's.
    let part_src = "CAPABILITY_TYPE(widget, CAP_WIDGET, /datum/e0_cap/widget, key = NONE)\n/datum/e0_cap/widget/proc/cooldown()\n\treturn 1\n/datum/capability/other/proc/cooldown()\n\treturn 2\n/obj/item/telecube/proc/cooldown()\n\treturn 3\n/datum/e0_cap/widget/sub/proc/cooldown()\n\treturn 4\n";
    let part_tree = Tree::from_files(vec![
        SourceFile::from_text("code/engine/parts/part.dm", "/proc/cooldown(t)\n\treturn t\n"),
        SourceFile::from_text("code/x.dm", part_src),
    ]);
    let part_files: Vec<&SourceFile> = ["code/engine/parts/part.dm", "code/x.dm"].iter().map(|r| part_tree.get(r).unwrap()).collect();
    let part_idx = DxIndex::get(&part_tree, &part_files);
    let part_got: Vec<usize> = crate::sys_constructor_shadow_policy::scan_part_shadows(&part_tree, &part_idx.procs).into_iter().map(|(_, _, n)| n).collect();
    if part_got != vec![2, 8] {
        return Err(format!("part_constructor_shadow selftest: got {:?}, want [2, 8]", part_got));
    }
    Ok("dx_constructor_shadow".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_constructor_shadow::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(crate::sys_constructor_shadow_policy::scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
