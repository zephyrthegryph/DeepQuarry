//! Runs the repository's established lint checks through one entry point.
use serde::Serialize;
use std::path::Path;
use std::process::Command;
use std::time::Instant;

#[derive(Serialize)]
struct CheckResult {
    name: String,
    passed: bool,
    exit_code: Option<i32>,
    duration_ms: u128,
}

const CHECKS: &[(&str, &str)] = &[
    ("DM health bridge", "dotnet build tools/dm-health/opendream-bridge/OpenDreamBridge.csproj -c Release -p:OpenDreamDir=\"$PWD/DMCompiler_linux-x64\" && mkdir -p tools/dm-health/target && dotnet tools/dm-health/opendream-bridge/bin/Release/net10.0/OpenDreamBridge.dll deepquarry.dme tools/dm-health/target/deepquarry.ast.jsonl \"$PWD/DMCompiler_linux-x64\" --reuse-if-current"),
    ("DM health tests", "cargo test --manifest-path tools/dm-health/Cargo.toml"),
    ("DM health fmt", "cargo fmt --manifest-path tools/dm-health/Cargo.toml --check"),
    ("DM health clippy", "cargo clippy --manifest-path tools/dm-health/Cargo.toml --all-targets -- -D warnings"),
    ("DM health analysis", "tools/dm-health/target/release/dm-health --root . --ast tools/dm-health/target/deepquarry.ast.jsonl --baseline tools/dm-health/baseline.json --fail-on-new --summary --report tools/dm-health/target/latest-report.json --history-dir tools/dm-health/target/history --cache-dir tools/dm-health/target/analysis-cache"),
    ("genesis", "bash tools/ci/check_genesis.sh"),
    ("grep", "bash tools/ci/check_grep.sh"),
    ("verdigris bindings", "bash tools/ci/check_verdigris_bindings.sh"),
    ("defines", "tools/bootstrap/python -m define_sanity.check"),
    ("DreamChecker", "set -o pipefail; ~/dreamchecker 2>&1 | bash tools/ci/annotate_dm.sh"),
    ("OpenDream compiler", "set -o pipefail; ./DMCompiler_linux-x64/DMCompiler deepquarry.dme --suppress-unimplemented --define=CIBUILDING | bash tools/ci/annotate_od.sh"),
    ("maps", "tools/bootstrap/python -m mapmerge2.dmm_test && tools/bootstrap/python -m tools.maplint.source"),
    ("DMI", "tools/bootstrap/python -m dmi.test"),
    ("changelogs", "bash tools/ci/check_changelogs.sh"),
    ("miscellaneous", "bash tools/ci/check_misc.sh"),
    ("signals", "bash tools/ci/check_signals.sh"),
    ("state schema", "python3 tools/ci/state_schema_lint.py"),
    ("containment", "python3 tools/ci/containment_lint.py"),
    ("latent walks", "python3 tools/ci/latent_lint.py"),
    ("lifecycle", "python3 tools/ci/lifecycle_lint.py"),
    ("instance lists", "python3 tools/ci/instance_list_lint.py"),
    ("deadlines", "python3 tools/ci/check_deadline_polling.py"),
    ("breakpoints", "python3 tools/ci/breakpoint_lint.py"),
    ("registries", "python3 tools/ci/registry_lint.py"),
    ("actor forwarding", "python3 tools/ci/actor_forwarding_lint.py"),
    ("generated object model bindings", "python tools/object_model/ui_bindings.py --check && python tools/object_model/stat_definitions.py --check && python tools/object_model/declaration_census.py && python -m unittest discover -s tools/object_model -p 'test_*.py'"),
    ("Rust core consolidation", "python3 tools/ci/check_rust_core_consolidation.py"),
    ("TGUI", "tools/build/build.sh --ci lint tgui-test"),
    ("Verdigris fmt", "cd verdigris && cargo fmt --all --check"),
    // The host-buildable crates exclude vendored vg-gas and the byondapi-only vg-ffi.
    ("Verdigris clippy", "cd verdigris && cargo clippy --package verdigris --package vg-core --package vg-layout --package vg-heat --package vg-power --all-targets -- -D warnings"),
    ("Verdigris tests", "cd verdigris && cargo test"),
    ("Nanomap", "tools/github-actions/nanomap-renderer-invoker.sh --testing"),
];

pub fn run(root: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let mut failed = Vec::new();
    let mut results = Vec::new();
    for (name, command) in CHECKS {
        println!("::group::{name}");
        let started = Instant::now();
        let status = Command::new("bash")
            .arg("-lc")
            .arg(command)
            .current_dir(root)
            .status()?;
        println!("::endgroup::");
        results.push(CheckResult {
            name: (*name).into(),
            passed: status.success(),
            exit_code: status.code(),
            duration_ms: started.elapsed().as_millis(),
        });
        if !status.success() {
            eprintln!("dm-health: {name} failed ({status})");
            failed.push(*name);
        }
    }
    let check_path = root.join("tools/dm-health/target/ci-checks.json");
    if let Some(parent) = check_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&check_path, serde_json::to_vec_pretty(&results)?)?;
    let report_path = root.join("tools/dm-health/target/latest-report.json");
    if report_path.exists() {
        let mut report: serde_json::Value = serde_json::from_slice(&std::fs::read(&report_path)?)?;
        report["ci_checks"] = serde_json::to_value(&results)?;
        std::fs::write(&report_path, serde_json::to_vec_pretty(&report)?)?;
    }
    if failed.is_empty() {
        Ok(())
    } else {
        Err(format!("{} CI checks failed: {}", failed.len(), failed.join(", ")).into())
    }
}
