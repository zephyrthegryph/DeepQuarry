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

// The ratcheted rewrite lints (tools/ci/check_ratchets.sh), the Rust core
// consolidation check and the Verdigris fmt/clippy/tests run as their own
// workflow steps (.github/workflows/run_linters.yml), so they are not repeated here.
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
    ("TGUI", "tools/build/build.sh --ci lint tgui-test"),
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
