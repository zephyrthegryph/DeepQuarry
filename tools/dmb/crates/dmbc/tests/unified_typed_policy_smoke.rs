//! Explicit independent-policy IPC proof with one owned private namespace.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;

#[test]
#[ignore = "requires a freshly built private dmbc and separate old-engine oracle"]
fn native_typed_policy_ipc_matches_independent_legacy_engine() {
    let oracle = std::env::var_os("DQ_LEGACY_TYPED_ORACLE")
        .expect("build unified_legacy_typed_policies separately and set DQ_LEGACY_TYPED_ORACLE");
    let scratch = test_scratch::dir("unified-typed-policy-ipc");
    let crate_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let repository = crate_root.join("../../../..");
    let bash = std::env::var_os("DQ_BASH").unwrap_or_else(|| "bash".into());
    let python = std::env::var_os("DQ_PYTHON").unwrap_or_else(|| "python".into());
    let output = std::process::Command::new(bash)
        .arg(repository.join("tools/dq_machine_slots.sh"))
        .args([
            "run",
            "dm_compile",
            "--label",
            "unified-typed-policy-ipc",
            "--",
        ])
        .arg(python)
        .arg(crate_root.join("../../scripts/unified_typed_policy_smoke.py"))
        .arg("--binary")
        .arg(env!("CARGO_BIN_EXE_dmbc"))
        .arg("--oracle")
        .arg(oracle)
        .arg("--scratch-root")
        .arg(&scratch)
        .arg("--repository")
        .arg(repository)
        .output()
        .expect("start bounded owned typed-policy coordinator");
    assert!(
        output.status.success(),
        "typed IPC proof failed\n{}\n{}\nscratch:{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
        scratch.display()
    );
    print!("{}", String::from_utf8_lossy(&output.stdout));
}
