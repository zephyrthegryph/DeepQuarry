//! Explicit diagnostic-declaration-profile IPC proof. Build first, release the cargo slot, then
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
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn diagnostic_declaration_profile_uses_original_error_owner_without_runtime_admission() {
    // The official shared owner creates and removes this fresh child. Python
    // validates its run-<pid>-<time> parent and emptiness before using it.
    let scratch = test_scratch::dir("unified-diagnostic-declaration-ipc");
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
            "unified-diagnostic-declaration-ipc",
            "--",
        ])
        .arg(bash_path(std::path::Path::new(&python)))
        .arg(bash_path(crate_root.join(
            "../../scripts/unified_diagnostic_declarations_smoke.py",
        )))
        .arg("--binary")
        // Bound at test compilation, not an arbitrary published/foreign binary.
        .arg(bash_path(env!("CARGO_BIN_EXE_dmbc")))
        .arg("--scratch-root")
        .arg(bash_path(&scratch))
        .arg("--repository")
        .arg(bash_path(&repository))
        .env("DQ_PRIORITY", "low")
        .output()
        .expect("start bounded owned diagnostic-declaration-profile IPC coordinator");
    assert!(
        output.status.success(),
        "diagnostic-declaration-profile IPC failed\nstdout:{}\nstderr:{}\nscratch:{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
        scratch.display()
    );
    print!("{}", String::from_utf8_lossy(&output.stdout));
}
