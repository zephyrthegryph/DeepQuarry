//! Tiny compile-only compatibility gates. These never start DreamDaemon.
use serde_json::Value;
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(0);

struct Fixture {
    root: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!(
            "dm-integration-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("project.dme"), "#include \"source.dm\"\n").unwrap();
        fs::write(root.join("source.dm"), "/proc/probe()\n    return 7\n").unwrap();
        Self { root }
    }
    fn command(&self) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_dm-compile"));
        command
            .current_dir(&self.root)
            .env_remove("DQ_NATIVE_DAEMON")
            .env_remove("DQ_COMPILER")
            .env_remove("DQ_NATIVE_TARGET")
            .env_remove("DQ_COMPILER_STRICT")
            .env("DM_COMPILER_CACHE_ROOT", self.root.join("cache"))
            .env("DM_MEMORY_LIMIT_MB", "512");
        command
    }
    fn build(&self, extra: &[&str]) -> Output {
        self.command()
            .args([
                "integrated-build",
                "project.dme",
                "--mode",
                "native",
                "--builtins",
            ])
            .arg(builtins())
            .args(extra)
            .output()
            .unwrap()
    }
    fn report(&self) -> Value {
        serde_json::from_slice(
            &fs::read(self.root.join(".dm-native/project.dme/integration.json")).unwrap(),
        )
        .unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}
fn builtins() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/native_template.bin")
}
fn assert_success(output: Output) {
    assert!(
        output.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn native_edit_and_revert_restore_canonical_generation_and_detached_outputs() {
    let fixture = Fixture::new();
    assert_success(fixture.build(&["--strict"]));
    let first = fixture.report();
    assert_eq!(first["producing_compiler"], "native");
    assert_eq!(first["native_gate_passed"], true);
    assert!(first["fallback"].is_null());
    let original = fs::read(fixture.root.join("project.dmb")).unwrap();
    assert_success(fixture.build(&["--strict"]));
    assert_eq!(fixture.report()["conventional"]["unchanged"], true);
    fs::write(
        fixture.root.join("source.dm"),
        "/proc/probe()\n    return 8\n",
    )
    .unwrap();
    assert_success(fixture.build(&["--strict"]));
    assert_ne!(
        fs::read(fixture.root.join("project.dmb")).unwrap(),
        original
    );
    assert_eq!(fixture.report()["conventional"]["reused_archive"], true);
    fs::write(
        fixture.root.join("source.dm"),
        "/proc/probe()\n    return 7\n",
    )
    .unwrap();
    assert_success(fixture.build(&["--strict"]));
    assert_eq!(
        fixture.report()["build"]["generation"],
        first["build"]["generation"]
    );
    assert_eq!(
        fs::read(fixture.root.join("project.dmb")).unwrap(),
        original
    );
    let immutable = PathBuf::from(fixture.report()["build"]["dmb"].as_str().unwrap());
    fs::write(
        fixture.root.join("project.dmb"),
        b"mutable conventional copy",
    )
    .unwrap();
    assert_eq!(fs::read(immutable).unwrap(), original);
    assert_success(fixture.build(&["--strict"]));
    assert_eq!(
        fs::read(fixture.root.join("project.dmb")).unwrap(),
        original
    );
}

#[test]
fn source_errors_never_fallback_and_preserve_previous_output() {
    let fixture = Fixture::new();
    assert_success(fixture.build(&["--strict"]));
    let original = fs::read(fixture.root.join("project.dmb")).unwrap();
    fs::write(
        fixture.root.join("source.dm"),
        "#error integration-source-error\n",
    )
    .unwrap();
    let output = fixture.build(&["--byond", "missing-byond-executable"]);
    assert!(!output.status.success());
    let report = fixture.report();
    assert!(report["fallback"].is_null());
    assert_eq!(report["failure"]["kind"], "source");
    assert_eq!(report["native_gate_passed"], false);
    assert!(String::from_utf8_lossy(&output.stderr).contains(":error:"));
    assert_eq!(
        fs::read(fixture.root.join("project.dmb")).unwrap(),
        original
    );
}

#[test]
fn strict_internal_failure_cannot_be_reported_as_native_pass() {
    let fixture = Fixture::new();
    // Reserve and close a unique loopback port so the transport failure is real.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap().to_string();
    drop(listener);
    let output = fixture.build(&[
        "--strict",
        "--daemon",
        &address,
        "--byond",
        "missing-byond-executable",
    ]);
    assert!(!output.status.success());
    let report = fixture.report();
    assert!(report["fallback"].is_null());
    assert_eq!(report["failure"]["kind"], "internal");
    assert!(report["producing_compiler"].is_null());
    assert_eq!(report["native_gate_passed"], false);
}

#[test]
fn automatic_internal_fallback_is_visible_and_never_claims_native_pass() {
    let fixture = Fixture::new();
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap().to_string();
    drop(listener);
    let output = fixture.build(&["--daemon", &address, "--byond", "missing-byond-executable"]);
    assert!(!output.status.success()); // The fixture has no BYOND executable.
    let report = fixture.report();
    assert_eq!(report["fallback"]["kind"], "internal");
    assert_eq!(report["selected_backend"], "byond");
    assert_eq!(report["native_gate_passed"], false);
    assert!(String::from_utf8_lossy(&output.stderr)
        .contains(":warning: native compiler infrastructure failure; using BYOND:"));
}

#[test]
fn ungated_native_targets_are_configuration_errors() {
    let fixture = Fixture::new();
    assert!(!fixture.build(&["--target", "516.9999"]).status.success());
    let report = fixture.report();
    assert_eq!(report["failure"]["kind"], "configuration");
    assert!(report["fallback"].is_null());
    assert!(!fixture.root.join("project.dmb").exists());
}

#[test]
fn jsonl_exports_authored_facts_without_claiming_resolved_references() {
    let fixture = Fixture::new();
    let output = fixture
        .command()
        .args(["analysis-jsonl", "project.dme"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let facts = String::from_utf8(output.stdout)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str::<Value>(line).unwrap())
        .collect::<Vec<_>>();
    assert_eq!(facts[0]["record"], "snapshot");
    assert_eq!(facts[0]["coverage"]["references"], "unavailable");
    assert!(facts.iter().any(|fact| fact["record"] == "signature"
        && fact["header"]
            .as_str()
            .is_some_and(|header| header.contains("probe()"))));
}
