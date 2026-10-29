//! Explicit opt-in smoke of the freshly built private binary's real IPC path.
//! No benchmark/full suite; the Python coordinator bounds requests and retires
//! only its own random namespace. Its fixtures/cache live in the shared guard.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;

#[test]
#[ignore = "starts one private namespace; run explicitly after the private dmbc build"]
fn unified_daemon_ipc_edit_and_retraction() {
    let scratch = test_scratch::dir("unified-daemon-ipc");
    let crate_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let script = crate_root.join("../../scripts/unified_daemon_smoke.py");
    let repository = crate_root.join("../../../..");
    let python = std::env::var_os("DQ_PYTHON").unwrap_or_else(|| "python".into());
    // Slot queueing is outside the Python coordinator's bounded request clock.
    // Run this built test executable after releasing any outer cargo slot: a
    // compiler lane may itself need cargo before releasing dm_compile.
    let slot_script = repository
        .join("tools/dq_machine_slots.sh")
        .to_string_lossy()
        .replace('\\', "/");
    // Windows CreateProcess may prefer System32's WSL launcher over Git Bash.
    // The harness can select its configured MSYS shell without invoking WSL.
    let bash = std::env::var_os("DQ_BASH").unwrap_or_else(|| "bash".into());
    let output = std::process::Command::new(bash)
        .arg(slot_script)
        .args(["run", "dm_compile", "--label", "unified-analysis-ipc", "--"])
        .arg(python)
        .arg(script)
        .arg("--binary")
        .arg(env!("CARGO_BIN_EXE_dmbc"))
        .arg("--scratch-root")
        .arg(&scratch)
        .arg("--repository")
        .arg(repository)
        .output()
        .expect("start bounded private-daemon smoke");
    assert!(
        output.status.success(),
        "daemon smoke failed\nstdout:{}\nstderr:{}\nscratch:{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
        scratch.display()
    );
    print!("{}", String::from_utf8_lossy(&output.stdout));
}
