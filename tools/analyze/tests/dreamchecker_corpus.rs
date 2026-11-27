//! DreamChecker's oracle: every case under `vendor/dreamchecker/tests/corpus/cases` (the vendored crate's old test snippets and seeded
//! cases that make each diagnostic kind fire) is checked as `analyze dreamchecker` checks a `.dme`, and its every diagnostic (every
//! severity, line and column, error type and notes; `dreamchecker::render`) must be the case's `expected/<case>.txt`, recorded from the
//! checker on dreammaker's parse before it was removed, or, where the compiler's front end differs on purpose, `<case>.dmbc.txt` (the
//! reasons are in `corpus/README.md`). The checker runs serially and on three threads, which must agree.
//!
//! `DQ_DC_CORPUS_BLESS_NATIVE=1` writes a differing output as the case's intended difference (give its reason in the README);
//! `DQ_DC_CORPUS_ONLY=<substring>` runs the cases whose name contains it.

use std::path::{Path, PathBuf};

fn corpus() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("vendor/dreamchecker/tests/corpus")
}

/// A scratch project holding one case: `test.dme` including `fixture.dm`.
fn project(name: &str, source: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("dq-dc-corpus-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("fixture.dm"), source).unwrap();
    std::fs::write(dir.join("test.dme"), "#include \"fixture.dm\"\n").unwrap();
    dir
}

/// The native checker (the compiler front end's own tree, `dmbc::dreamchecker_input`) on `dme`.
fn native(dme: &Path, threads: usize) -> String {
    let context = dq_analyze::dreamchecker::context_for(dme, None, false);
    let out = match dmbc::dreamchecker_input::check(dme, &context, true, false, threads) {
        Ok(()) => dq_analyze::dreamchecker::render(&context),
        Err(e) => format!("parse refused: {e}\n"),
    };
    let dir = format!("{}/", dme.parent().unwrap().display().to_string().replace('\\', "/"));
    out.replace(&dir, "")
}

fn diff(expected: &str, found: &str) -> String {
    let (e, f): (Vec<&str>, Vec<&str>) = (expected.lines().collect(), found.lines().collect());
    let mut out = String::new();
    for i in 0..e.len().max(f.len()) {
        match (e.get(i), f.get(i)) {
            (Some(a), Some(b)) if a == b => {}
            (a, b) => out.push_str(&format!("  line {}: expected {:?}\n           found    {:?}\n", i + 1, a.unwrap_or(&""), b.unwrap_or(&""))),
        }
    }
    out
}

#[test]
fn corpus_cases_give_their_expected_diagnostics() {
    let only = std::env::var("DQ_DC_CORPUS_ONLY").ok();
    let mut cases: Vec<PathBuf> = std::fs::read_dir(corpus().join("cases"))
        .expect("corpus cases")
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|x| x == "dm"))
        .filter(|p| only.as_deref().is_none_or(|o| p.file_stem().unwrap().to_string_lossy().contains(o)))
        .collect();
    cases.sort();
    assert!(only.is_some() || cases.len() >= 60, "the corpus has its cases");
    let expected_dir = corpus().join("expected");
    let mut failures = Vec::new();
    for case in &cases {
        let name = case.file_stem().unwrap().to_string_lossy().into_owned();
        let source = std::fs::read_to_string(case).unwrap().replace("\r\n", "\n");
        let dir = project(&name, &source);
        let dme = dir.join("test.dme");
        let expected_path = expected_dir.join(format!("{name}.txt"));
        let expected = std::fs::read_to_string(&expected_path).unwrap_or_else(|_| panic!("{name}: no expected output"));
        let intended = std::fs::read_to_string(expected_dir.join(format!("{name}.dmbc.txt"))).ok();
        let want = intended.as_deref().unwrap_or(&expected);
        let serial = native(&dme, 1);
        assert_eq!(serial, native(&dme, 3), "{name} (native): the parallel pass must give the serial diagnostics");
        if serial != want && std::env::var_os("DQ_DC_CORPUS_BLESS_NATIVE").is_some() {
            std::fs::write(expected_dir.join(format!("{name}.dmbc.txt")), &serial).unwrap();
        } else if serial != want {
            failures.push(format!("{name} (native):\n{}", diff(want, &serial)));
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
    assert!(failures.is_empty(), "{} of {} cases differ:\n{}", failures.len(), cases.len(), failures.join("\n"));
}
