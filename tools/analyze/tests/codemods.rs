//! The 2.5 gates, held per codemod by `cargo test`: every fixture rewrites to its expected output, an
//! already converted input is a no-op, a second run changes nothing (idempotent), two runs are byte-identical
//! (deterministic), CRLF files keep their line endings, every edit has an exact inverse, the negative inputs
//! are listed as residue with the expected reason, and every reason code a codemod declares has a fixture.
//!
//! Fixtures: `tools/analyze/codemods/<name>/fixtures/`
//!   `_stubs.dm`          the definitions the cases call (legacy and new forms), compiled with every case
//!   `<case>.in.dm`       the input
//!   `<case>.out.dm`      the expected output (identical to the input for a no-op)
//!   `<case>.residue`     the reason codes of the residue sites in file order, one per line (absent: none)

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use dq_analyze::codemod::{self, Codemod, RunOpts, RunResult};

fn fixture_dir(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("codemods").join(name).join("fixtures")
}

struct Case {
    name: String,
    input: String,
    output: String,
    residue: Vec<String>,
}

fn cases(name: &str) -> (String, Vec<Case>) {
    let dir = fixture_dir(name);
    let stubs = std::fs::read_to_string(dir.join("_stubs.dm")).unwrap_or_else(|e| panic!("{}: _stubs.dm: {}", name, e));
    let mut names: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().to_string_lossy().strip_suffix(".in.dm").map(|s| s.to_string()))
        .collect();
    names.sort();
    assert!(!names.is_empty(), "{} has no fixtures", name);
    let norm = |s: String| s.replace("\r\n", "\n");
    let out = names
        .into_iter()
        .map(|n| {
            let input = norm(std::fs::read_to_string(dir.join(format!("{}.in.dm", n))).unwrap());
            let output = norm(std::fs::read_to_string(dir.join(format!("{}.out.dm", n))).unwrap_or_else(|_| panic!("{}: {}.out.dm missing", name, n)));
            let residue = std::fs::read_to_string(dir.join(format!("{}.residue", n))).map(|t| t.lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect()).unwrap_or_default();
            Case { name: n, input, output, residue }
        })
        .collect();
    (norm(stubs), out)
}

/// A scratch tree holding the stubs and one case file.
fn scratch(stubs: &str, case: &str) -> tempfile::TempDir {
    let d = tempfile::tempdir().unwrap();
    let code = d.path().join("code");
    std::fs::create_dir_all(&code).unwrap();
    std::fs::write(code.join("a_stubs.dm"), stubs).unwrap();
    std::fs::write(code.join("case.dm"), case).unwrap();
    d
}

fn run_case(cm: &dyn Codemod, stubs: &str, input: &str) -> (RunResult, String) {
    let d = scratch(stubs, input);
    let res = codemod::run(d.path(), cm, &RunOpts { apply: true, paths: vec![] }).expect("run");
    let after = res.changes.iter().find(|c| c.rel == "code/case.dm").map(|c| c.after.clone()).unwrap_or_else(|| input.to_string());
    for c in &res.changes {
        assert_eq!(c.rel, "code/case.dm", "a codemod may only change the case file, not the stubs");
    }
    (res, after)
}

fn reasons(res: &RunResult) -> Vec<String> {
    res.residue.iter().map(|r| r.reason.clone()).collect()
}

fn check(name: &str) {
    let cm = codemod::find(name).unwrap_or_else(|| panic!("no codemod {}", name));
    let (stubs, cases) = cases(name);
    let mut seen: BTreeSet<String> = BTreeSet::new();
    let mut rewrote_something = false;
    for c in &cases {
        let (res, after) = run_case(cm.as_ref(), &stubs, &c.input);
        assert_eq!(after, c.output, "{}/{}: output differs from {}.out.dm", name, c.name, c.name);
        assert_eq!(reasons(&res), c.residue, "{}/{}: residue reasons (in file order)", name, c.name);
        seen.extend(reasons(&res));
        rewrote_something |= res.rewrites > 0;

        // Idempotent: the output is a fixed point.
        let (again, after2) = run_case(cm.as_ref(), &stubs, &after);
        assert_eq!(after2, after, "{}/{}: a second run changed the output", name, c.name);
        assert_eq!(again.rewrites, 0, "{}/{}: a second run rewrote {} sites", name, c.name, again.rewrites);
        assert!(again.changes.is_empty());

        // Deterministic: two runs on the same input agree on every byte and every residue site.
        let (res2, after_b) = run_case(cm.as_ref(), &stubs, &c.input);
        assert_eq!(after_b, after, "{}/{}: two runs differ", name, c.name);
        assert_eq!(res2.residue, res.residue, "{}/{}: two runs report different residue", name, c.name);
        assert_eq!(res2.keys, res.keys);

        // Local and reversible: every edit has an exact inverse, and no line is added or removed (a codemod that declares what its sites need adds those lines).
        for ch in &res.changes {
            assert_eq!(codemod::revert_edits(&ch.after, &ch.inverse), ch.before, "{}/{}: the inverse edits do not restore the input", name, c.name);
            if !cm.declares() {
                assert_eq!(ch.before.matches('\n').count(), ch.after.matches('\n').count(), "{}/{}: the codemod changed the line count", name, c.name);
            }
        }

        // CRLF in, CRLF out: line endings are outside the rewritten spans.
        let crlf_in = c.input.replace('\n', "\r\n");
        let (res3, after_crlf) = run_case(cm.as_ref(), &stubs, &crlf_in);
        assert_eq!(after_crlf, c.output.replace('\n', "\r\n"), "{}/{}: CRLF input", name, c.name);
        assert_eq!(reasons(&res3), c.residue);
    }
    assert!(cases.iter().any(|c| c.name == "already_converted" && c.input == c.output && c.residue.is_empty()), "{}: needs an already_converted case that is a no-op", name);
    assert!(rewrote_something, "{}: no fixture rewrites anything", name);
    let declared: BTreeSet<String> = cm.reasons().iter().map(|(c, _)| c.to_string()).collect();
    let missing: Vec<&String> = declared.iter().filter(|r| !seen.contains(*r)).collect();
    assert!(missing.is_empty(), "{}: reason codes with no negative fixture: {:?}", name, missing);
    let undeclared: Vec<&String> = seen.iter().filter(|r| !declared.contains(*r) && !codemod::FRAMEWORK_REASONS.iter().any(|(c, _)| c == r)).collect();
    assert!(undeclared.is_empty(), "{}: residue reasons the codemod does not declare: {:?}", name, undeclared);
}

#[test]
fn om_after_fixtures_and_gates() {
    check("om_after");
}

#[test]
fn own_set_fixtures_and_gates() {
    check("own_set");
}

#[test]
fn own_add_fixtures_and_gates() {
    check("own_add");
}

#[test]
fn every_registered_codemod_has_a_test_and_a_directory() {
    let names: Vec<&str> = vec!["om_after", "own_add", "own_set"];
    let reg: Vec<String> = codemod::registry().iter().map(|c| c.name().to_string()).collect();
    assert_eq!(reg, names, "a new codemod needs a #[test] in tests/codemods.rs that calls check(name)");
    for n in &reg {
        assert!(fixture_dir(n).join("_stubs.dm").exists(), "{} has no fixtures", n);
    }
}

#[test]
fn excluded_paths_are_counted_and_never_rewritten() {
    let cm = codemod::find("own_set").unwrap();
    let (stubs, _) = cases("own_set");
    let d = tempfile::tempdir().unwrap();
    let write = |rel: &str, text: &str| {
        let p = d.path().join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, text).unwrap();
    };
    write("code/a_stubs.dm", &stubs);
    write("code/modules/unit_tests/t.dm", "/datum/proc/t()\n\town_set(src, \"cell\", null)\n");
    write("code/engine/e.dm", "/datum/proc/e()\n\town_set(src, \"cell\", null)\n");
    write("code/modules/real/r.dm", "/datum/real_holder\n\tvar/datum/cell\n\n/datum/real_holder/proc/r()\n\town_set(src, \"cell\", null)\n");
    let res = codemod::run(d.path(), cm.as_ref(), &RunOpts { apply: true, paths: vec![] }).unwrap();
    assert_eq!(res.rewrites, 1);
    assert_eq!(res.excluded, 2);
    assert_eq!(res.changes.len(), 1);
    assert_eq!(res.changes[0].rel, "code/modules/real/r.dm");
}

#[test]
fn a_path_filter_withholds_edits_but_still_reports_the_whole_tree() {
    let cm = codemod::find("own_set").unwrap();
    let (stubs, _) = cases("own_set");
    let d = tempfile::tempdir().unwrap();
    let write = |rel: &str, text: &str| {
        let p = d.path().join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, text).unwrap();
    };
    write("code/a_stubs.dm", &stubs);
    write("code/modules/a/x.dm", "/datum/holder_a\n\tvar/datum/cell\n\n/datum/holder_a/proc/x()\n\town_set(src, \"cell\", null)\n");
    write("code/modules/b/y.dm", "/datum/proc/y()\n\town_set(src, \"cell\", null, user = null)\n");
    let res = codemod::run(d.path(), cm.as_ref(), &RunOpts { apply: true, paths: vec!["code/modules/a/".into()] }).unwrap();
    assert_eq!(res.rewrites, 1);
    assert_eq!(res.changes.len(), 1);
    assert_eq!(res.residue.len(), 1, "residue outside the filter is still reported");
    assert!(res.outside_filter >= 1);
}

#[test]
fn write_then_revert_restores_every_byte() {
    let cm = codemod::find("om_after").unwrap();
    let (stubs, cases) = cases("om_after");
    let d = scratch(&stubs, &cases.iter().find(|c| c.name == "basic").unwrap().input);
    let before = std::fs::read(d.path().join("code/case.dm")).unwrap();
    let res = codemod::run(d.path(), cm.as_ref(), &RunOpts { apply: true, paths: vec![] }).unwrap();
    codemod::write_changes(d.path(), &res).unwrap();
    assert_ne!(std::fs::read(d.path().join("code/case.dm")).unwrap(), before);
    assert_eq!(codemod::revert(d.path(), "om_after").unwrap(), 1);
    assert_eq!(std::fs::read(d.path().join("code/case.dm")).unwrap(), before);
    // A file edited since the codemod wrote it is refused, never overwritten.
    let res = codemod::run(d.path(), cm.as_ref(), &RunOpts { apply: true, paths: vec![] }).unwrap();
    codemod::write_changes(d.path(), &res).unwrap();
    let p: &Path = &d.path().join("code/case.dm");
    let mut t = std::fs::read_to_string(p).unwrap();
    t.push_str("// edited\n");
    std::fs::write(p, &t).unwrap();
    assert!(codemod::revert(d.path(), "om_after").is_err());
    assert_eq!(std::fs::read_to_string(p).unwrap(), t);
}
