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

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let tree = Tree::from_files(vec![SourceFile::from_text("x.dm", FIXTURE)]);
    let files = vec![tree.get("x.dm").unwrap()];
    let found = analyse(&tree, &files);
    let by = |rule: &str| -> Vec<usize> {
        let mut v: Vec<usize> = found.iter().filter(|(r, _, _)| *r == rule).map(|(_, _, n)| *n).collect();
        v.sort();
        v
    };
    let at = |snippet: &str| -> usize { lines.iter().position(|l| l.contains(snippet)).map(|k| k + 1).unwrap_or(0) };
    let want = |snippets: &[&str]| -> Vec<usize> {
        let mut v: Vec<usize> = snippets.iter().map(|s| at(s)).collect();
        v.sort();
        v
    };
    let checks: Vec<(&str, Vec<usize>, Vec<usize>)> = vec![
        (
            "dx_untracked_read",
            by("dx_untracked_read"),
            want(&["when = cell.rigged", "when = cell.label_text", "return cell?.maxcharge", "return cell.rigged", "when = C.rigged"]),
        ),
        (
            "dx_reactive_write",
            by("dx_reactive_write"),
            want(&[
                "holder.last_ui = world.time",
                "last_holder = holder",
                "changed(holder)",
                "holder.verbs.Remove",
                "holder.set_dir(NORTH)",
                "\tlevel++",
                "src.cell.set_charge(5)",
            ]),
        ),
        (
            "dx_caps_instance_read",
            by("dx_caps_instance_read"),
            want(&[". += cap_gauge(level = level)", "cap_lock(access = src.req_access)"]),
        ),
        ("dx_timed_write", by("dx_timed_write"), want(&["\temp_disabled = FALSE", "M.emp_disabled = TRUE"])),
    ];
    for (rule, got, want) in checks {
        if got != want {
            return Err(format!("dx_reactive selftest {}: got {:?}, want {:?}", rule, got, want));
        }
    }
    Ok("dx_reactive".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_reactive::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
