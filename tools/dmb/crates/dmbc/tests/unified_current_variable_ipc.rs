//! Explicit retained-source checker observation through real production IPC.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;

use std::{path::Path, process::Command};

fn slash(path: impl AsRef<Path>) -> String {
    path.as_ref().to_string_lossy().replace('\\', "/")
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn original_current_variable_ipc_parent_switch() {
    run_smoke("parent-switch");
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn original_ordered_checker_ipc_has_nonempty_phases_in_producer_order() {
    run_smoke("ordered");
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn original_ordered_checker_ipc_preserves_root_increment_spelling() {
    run_smoke("root-increment");
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn original_ordered_checker_ipc_carries_implicit_new_hints_through_logical_or() {
    run_smoke("implicit-new-or-hint");
}

#[test]
#[ignore = "requires current private dmbc and the pinned DreamMaker library example"]
fn original_ordered_checker_ipc_matches_pinned_sealed_parent_reader() {
    run_smoke("sealed-parent");
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn original_checker_ipc_captures_nested_raw_only_source() {
    run_smoke("nested-source");
}

fn run_smoke(case: &str) {
    let scratch = test_scratch::dir("unified-current-variable-ipc");
    let crate_root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let repository = crate_root.join("../../../..");
    let bash = std::env::var_os("DQ_BASH").unwrap_or_else(|| "bash".into());
    let python = std::env::var_os("DQ_PYTHON").unwrap_or_else(|| "python".into());
    let output = Command::new(bash)
        .arg(slash(repository.join("tools/dq_machine_slots.sh")))
        .args(["run", "dm_compile", "--label", "unified-current-variable-ipc", "--"])
        .arg(slash(Path::new(&python)))
        .arg(slash(crate_root.join("../../scripts/unified_current_variable_ipc_smoke.py")))
        .args(["--case", case])
        .arg("--binary")
        .arg(slash(env!("CARGO_BIN_EXE_dmbc")))
        .arg("--scratch-root")
        .arg(slash(scratch))
        .arg("--repository")
        .arg(slash(repository))
        .env("DQ_PRIORITY", "low")
        .env("PYTHONDONTWRITEBYTECODE", "1")
        .output()
        .expect("start bounded Original current-variable IPC smoke");
    assert!(
        output.status.success(),
        "Original current-variable IPC failed\nstdout:{}\nstderr:{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    print!("{}", String::from_utf8_lossy(&output.stdout));
}
