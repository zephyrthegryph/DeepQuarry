//! Explicit Derived resident transport IPC proof. Build first, release the cargo slot, then
//! invoke this ignored test from its built executable. It never starts Cargo,
//! publishes a compiler, chooses an arbitrary scratch root, or retires peers.
#[path = "../../../shared/test_scratch.rs"]
mod test_scratch;
#[path = "../../../../analyze/fixtures/report_configuration.rs"]
mod report_configuration;
#[path = "../../../fixtures/unified_original_generation/source.rs"]
mod generation_source;

// Native Windows canonicalize produces verbatim backslash paths. These
// arguments cross the Git Bash slot wrapper before Python/CreateProcess; keep
// every path in slash form so that boundary cannot consume its separators.
fn bash_path(path: impl AsRef<std::path::Path>) -> String {
    path.as_ref().to_string_lossy().replace('\\', "/")
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn actual_derived_resident_transport_cold_warm_modified_raw_notice_and_fragmented_report() {
    run_resident_transport(
        "unified-derived-resident-transport-ipc",
        "unified_derived_resident_transport_smoke.py",
        &[],
    );
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn actual_image_dir_resident_transport_uses_a_distinct_report_role() {
    run_resident_transport_with_tool(
        "unified-image-dir-resident-ipc",
        "unified_image_dir_resident_smoke.py",
        &[],
        false,
    );
}

#[test]
#[ignore = "requires current private dmbc and analyze-native; run outside cargo slot"]
fn actual_semantic_read_cohort_matches_independent_reports_on_one_daemon() {
    let configuration = test_scratch::dir("unified-semantic-read-configuration").join("lint_scopes.toml");
    std::fs::write(
        &configuration,
        report_configuration::with_overlay("[lint.auto_tracked.lists]\ninclude=[\"/datum/setter_probe::charge\"]\n"),
    )
    .unwrap();
    run_resident_transport(
        "unified-semantic-read-resident-ipc",
        "unified_semantic_read_cohort_smoke.py",
        &["--configuration".into(), bash_path(configuration)],
    );
}

#[test]
#[ignore = "requires current private dmbc and analyze-native; run outside cargo slot"]
fn actual_original_generation_settles_and_reuses_resident_daemon() {
    use std::fs;

    let fixtures = test_scratch::dir("original-generation-resident-inputs");
    let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../../tools/analyze/fixtures/native-cold-generation/basic");
    let manifest = fs::read(source.join("deepquarry.dme")).unwrap();
    let probe = fs::read_to_string(source.join("code/probe.dm")).unwrap();
    let only = fs::read(source.join("code/tests/only.dm")).unwrap();
    for case in generation_source::CASES {
        let root = fixtures.join(case);
        fs::create_dir_all(root.join("code/tests")).unwrap();
        fs::write(root.join("code/probe.dm"), generation_source::guarded_probe(&probe)).unwrap();
        fs::write(root.join("code/tests/only.dm"), &only).unwrap();
        if case != "real" {
            fs::create_dir(root.join("code/__defines")).unwrap();
            fs::write(
                root.join("code/__defines/original_generation.dm"),
                generation_source::synthetic_support(&manifest),
            ).unwrap();
        }
        if let Some(bytes) = generation_source::manifest(case, manifest.clone()) {
            fs::write(root.join("deepquarry.dme"), bytes).unwrap();
        }
    }
    let mut extra = vec!["--fixtures".into(), bash_path(fixtures)];
    if let Some(log) = std::env::var_os("DQ_UNIFIED_GENERATION_ORIGINAL") {
        extra.extend(["--original".into(), bash_path(std::path::Path::new(&log))]);
    }
    if let Ok(case) = std::env::var("DQ_UNIFIED_GENERATION_CASE") {
        extra.extend(["--case".into(), case]);
    }
    run_resident_transport(
        "unified-original-generation-resident-ipc",
        "unified_original_generation_resident_smoke.py",
        &extra,
    );
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn actual_declare_overlay_fixed_dme_check_write_and_warm_generation() {
    run_resident_transport_with_tool(
        "unified-declare-overlay-resident-ipc",
        "unified_declare_overlay_resident_smoke.py",
        &[],
        false,
    );
}

#[test]
#[ignore = "requires current private dmbc; run outside cargo slot"]
fn actual_selected_exclusions_cold_warm_and_edit_on_one_resident_daemon() {
    use dq_analyze::captured_allow_annotations::{full_unused, Operation};
    use dq_analyze::captured_generator_budget::Budget;

    let controls = test_scratch::dir("unified-selected-exclusions-controls");
    let configuration = controls.join("lint_scopes.toml");
    std::fs::write(&configuration, report_configuration::with_overlay("")).unwrap();
    let registry = controls.join("registry.json");
    let budget = Budget::new(1 << 20).unwrap();
    let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
    let selected = full_unused::registered_full_selection(&[], &mut work).unwrap();
    std::fs::write(&registry, serde_json::to_vec(selected.names()).unwrap()).unwrap();
    run_resident_transport_with_tool(
        "unified-selected-exclusions-resident",
        "unified_selected_exclusions_resident_smoke.py",
        &["--configuration".into(), bash_path(configuration), "--registry".into(), bash_path(registry)],
        true,
    );
}

fn run_resident_transport(label: &str, script: &str, extra: &[String]) {
    run_resident_transport_with_tool(label, script, extra, true);
}

fn run_resident_transport_with_tool(
    label: &str,
    script: &str,
    extra: &[String],
    needs_analyze: bool,
) {
    // The official shared owner creates and removes this fresh child. Python
    // validates its run-<pid>-<time> parent and emptiness before using it.
    let scratch = test_scratch::dir(label);
    let crate_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let repository = crate_root.join("../../../..");
    let slot_script = repository
        .join("tools/dq_machine_slots.sh")
        .to_string_lossy()
        .replace('\\', "/");
    let bash = std::env::var_os("DQ_BASH").unwrap_or_else(|| "bash".into());
    let python = std::env::var_os("DQ_PYTHON").unwrap_or_else(|| "python".into());
    let mut command = std::process::Command::new(bash);
    command.arg(slot_script)
        .args([
            "run",
            "dm_compile",
            "--label",
            label,
            "--",
        ])
        .arg(bash_path(std::path::Path::new(&python)))
        .arg(bash_path(
            crate_root.join("../../scripts").join(script),
        ))
        .arg("--binary")
        // Bound at test compilation, not an arbitrary published/foreign binary.
        .arg(bash_path(env!("CARGO_BIN_EXE_dmbc")));
    if needs_analyze {
        let binary = std::env::var_os("DQ_UNIFIED_ANALYZE_NATIVE")
            .expect("independently build current analyze-native, then run this explicit IPC proof");
        command.arg("--analyze").arg(bash_path(std::path::PathBuf::from(binary)));
    }
    let output = command.arg("--scratch-root")
        .arg(bash_path(&scratch))
        .arg("--repository")
        .arg(bash_path(&repository))
        .args(extra)
        .env("DQ_PRIORITY", "low")
        .output()
        .expect("start bounded owned resident transport IPC coordinator");
    assert!(
        output.status.success(),
        "Resident transport IPC failed for {label}\nstdout:{}\nstderr:{}\nscratch:{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
        scratch.display()
    );
    print!("{}", String::from_utf8_lossy(&output.stdout));
}
