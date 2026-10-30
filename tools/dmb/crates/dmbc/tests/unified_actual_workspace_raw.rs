//! Run the actual repository proof from this built ignored test, outside Cargo.
//! No build/publication or fixture substitution is performed by the script.
//! Use --release: the unchanged cold-main request deadline is not a debug-build
//! performance allowance. Small IPC/ownership proofs remain usable in debug.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;
fn slash(path: impl AsRef<std::path::Path>) -> String {
    path.as_ref().to_string_lossy().replace('\\', "/")
}
#[test]
#[ignore = "requires --release current private dmbc and independently built old workspace oracle"]
fn actual_workspace_raw_pages_match_independent_old_engine() {
    assert!(
        !cfg!(debug_assertions),
        "run this cold-main proof with --release; use the small workspace IPC test for debug builds"
    );
    let oracle = std::path::PathBuf::from(
        std::env::var_os("DQ_LEGACY_WORKSPACE_RAW_ORACLE").expect("build old oracle separately"),
    );
    let crate_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let repository = std::env::var_os("DQ_ACTUAL_WORKSPACE_ROOT")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| crate_root.join("../../../.."));
    let scratch = test_scratch::dir("unified-actual-workspace-raw");
    let bash = std::env::var_os("DQ_BASH").unwrap_or_else(|| "bash".into());
    let python = std::env::var_os("DQ_PYTHON").unwrap_or_else(|| "python".into());
    let mut command = std::process::Command::new(bash);
    command
        .arg(slash(repository.join("tools/dq_machine_slots.sh")))
        .args([
            "run",
            "dm_compile",
            "--label",
            "unified-actual-workspace-raw",
            "--",
        ])
        .arg(slash(std::path::Path::new(&python)))
        .arg(slash(
            repository.join("tools/dmb/scripts/unified_actual_workspace_raw.py"),
        ))
        .arg("--binary")
        .arg(slash(env!("CARGO_BIN_EXE_dmbc")))
        .arg("--oracle")
        .arg(slash(oracle))
        .arg("--scratch-root")
        .arg(slash(&scratch))
        .arg("--repository")
        .arg(slash(&repository));
    if let Some(output) = std::env::var_os("DQ_ACTUAL_WORKSPACE_EVIDENCE") {
        command
            .arg("--evidence-out")
            .arg(slash(std::path::Path::new(&output)));
    }
    command.env("DQ_PRIORITY", "low");
    let result = command
        .output()
        .expect("run bounded actual-workspace coordinator");
    assert!(
        result.status.success(),
        "actual workspace proof failed\nstdout:{}\nstderr:{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
    print!("{}", String::from_utf8_lossy(&result.stdout));
}
