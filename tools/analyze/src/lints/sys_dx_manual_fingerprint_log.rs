//! Existing registration/selftest adapter for the unique manual-log producer.
use crate::{dm::sys::{register_module,SysModule},lint::Registry,tree::{SourceFile,Tree}};
use crate::allow_registry_fields::sys_dx_manual_fingerprint_log::RULES;
const FIXTURE: &str = include_str!("../../fixtures/sys__dx_manual_fingerprint_log/code/modules/x/selftest.dm");

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let tree = Tree::from_files(vec![SourceFile::from_text("x.dm", FIXTURE)]);
    let files = vec![tree.get("x.dm").unwrap()];
    let mut got: Vec<usize> = crate::manual_log_policy::scan(&tree, &files).into_iter().map(|(_, _, n)| n).collect();
    got.sort();
    let at = |snippet: &str| -> usize { lines.iter().position(|l| l.contains(snippet)).map(|k| k + 1).unwrap_or(0) };
    let mut want = vec![at("\tadd_fingerprint(user)"), at("log_game(\"[user] toggled"), at("message_admins("), at("log_admin(\"unbolted\")")];
    want.sort();
    if got != want {
        return Err(format!("dx_manual_fingerprint_log selftest: got {:?}, want {:?}", got, want));
    }
    Ok("dx_manual_fingerprint_log".to_string())
}

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
