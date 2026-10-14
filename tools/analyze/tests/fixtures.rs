//! Fixture tests: for every lint with `fixtures/<lint>/expected.txt`, the engine run over that
//! fixture tree must produce exactly the recorded findings (recorded by `analyze parity --bless`
//! from the legacy script, which is what makes this a parity test that outlives the script).

use std::path::PathBuf;

use dq_analyze::parity::{engine_on_fixture, fixture_dir, format_expected, read_expected};

fn repo_root() -> PathBuf {
    // tools/analyze -> repo root
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

#[test]
fn every_fixture_matches_its_expected_findings() {
    let root = repo_root();
    let reg = dq_analyze::run::registry();
    let mut checked = 0;
    let mut failures = Vec::new();
    for lint in &reg.lints {
        let name = lint.meta().name;
        let dir = fixture_dir(&root, name);
        let Some(expected) = read_expected(&dir.join("expected.txt")) else { continue };
        let got = match engine_on_fixture(&dir, Some(&root), name) {
            Ok(g) => g,
            Err(e) => {
                failures.push(format!("{}: engine error: {}", name, e));
                continue;
            }
        };
        checked += 1;
        if got != expected {
            failures.push(format!(
                "{}: fixture findings differ\n--- expected\n{}--- got\n{}",
                name,
                format_expected(&expected),
                format_expected(&got)
            ));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
    eprintln!("{} lint fixture sets checked", checked);
}

#[test]
fn every_lint_selftest_passes() {
    let reg = dq_analyze::run::registry();
    let mut failures = Vec::new();
    for lint in &reg.lints {
        if let Err(e) = lint.selftest() {
            failures.push(format!("{}: {}", lint.meta().name, e));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn every_lint_declares_consistent_metadata() {
    let reg = dq_analyze::run::registry();
    let mut names = std::collections::HashSet::new();
    for lint in &reg.lints {
        let m = lint.meta();
        assert!(names.insert(m.name), "duplicate lint name {}", m.name);
        assert!(!m.rules.is_empty(), "{} declares no rules", m.name);
        let mut rules = std::collections::HashSet::new();
        for r in m.rules {
            assert!(rules.insert(r.name), "{}: duplicate rule {}", m.name, r.name);
        }
    }
}

#[test]
fn runtime_capability_payload_keeps_holder_identity() {
    let root = repo_root();
    let dir = fixture_dir(&root, "sys/dx_reactive");
    let findings = engine_on_fixture(&dir, Some(&root), "sys/dx_reactive").expect("fixture engine");
    let runtime: Vec<_> = findings.iter().filter(|finding| finding.rel.ends_with("runtime_data.dm")).collect();
    assert_eq!(runtime.len(), 1, "only the foreign holder's payload is an untracked read");
    assert_eq!(runtime[0].line, 9);
}
