//! Explicit pool-policy IPC proof. Build first, release the cargo slot, then
//! invoke this ignored test from its built executable. It never starts Cargo,
//! publishes a compiler, chooses an arbitrary scratch root, or retires peers.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;

// Native Windows canonicalize produces verbatim backslash paths. These
// arguments cross the Git Bash slot wrapper before Python/CreateProcess; keep
// every path in slash form so that boundary cannot consume its separators.
fn bash_path(path: impl AsRef<std::path::Path>) -> String {
    path.as_ref().to_string_lossy().replace('\\', "/")
}

#[test]
#[ignore = "requires current private dmbc and separately built old Engine.scan oracle; run outside cargo slot"]
fn bounded_pool_policy_ipc_matches_independent_frozen_engine() {
    let oracle = std::env::var_os("DQ_LEGACY_POOL_ORACLE")
        .expect("set DQ_LEGACY_POOL_ORACLE to the separately built unified_pool executable");
    let oracle = std::path::PathBuf::from(oracle)
        .canonicalize()
        .expect("the independent old-engine executable must already exist");
    // The official shared owner creates and removes this fresh child. Python
    // validates its run-<pid>-<time> parent and emptiness before using it.
    let scratch = test_scratch::dir("unified-pool-policy-ipc");
    let crate_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let repository = crate_root.join("../../../..");
    let slot_script = repository
        .join("tools/dq_machine_slots.sh")
        .to_string_lossy()
        .replace('\\', "/");
    let bash = std::env::var_os("DQ_BASH").unwrap_or_else(|| "bash".into());
    let python = std::env::var_os("DQ_PYTHON").unwrap_or_else(|| "python".into());
    let output = std::process::Command::new(bash)
        .arg(slot_script)
        .args([
            "run",
            "dm_compile",
            "--label",
            "unified-pool-policy-ipc",
            "--",
        ])
        .arg(bash_path(std::path::Path::new(&python)))
        .arg(bash_path(
            crate_root.join("../../scripts/unified_pool_policy_smoke.py"),
        ))
        .arg("--binary")
        // Bound at test compilation, not an arbitrary published/foreign binary.
        .arg(bash_path(env!("CARGO_BIN_EXE_dmbc")))
        .arg("--oracle")
        .arg(bash_path(std::path::Path::new(&oracle)))
        .arg("--scratch-root")
        .arg(bash_path(&scratch))
        .arg("--repository")
        .arg(bash_path(&repository))
        .env("DQ_PRIORITY", "low")
        .output()
        .expect("start bounded owned pool-policy IPC coordinator");
    assert!(
        output.status.success(),
        "extended typed-policy IPC failed\nstdout:{}\nstderr:{}\nscratch:{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
        scratch.display()
    );
    print!("{}", String::from_utf8_lossy(&output.stdout));
}
