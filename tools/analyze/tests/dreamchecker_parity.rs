//! `analyze dreamchecker` against the standalone suite-1.11 binary (`~/SpacemanDMM/dreamchecker.exe` or `DREAMCHECKER_EXE`) on the
//! seeded fixture under `fixtures/dreamchecker/`: stdout, stderr and exit code identical, serial and parallel. Skipped (with a note)
//! where the standalone binary is not installed.

use std::path::PathBuf;
use std::process::Command;

fn standalone() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("DREAMCHECKER_EXE") {
        return Some(PathBuf::from(p));
    }
    let home = std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME"))?;
    let p = PathBuf::from(home).join("SpacemanDMM").join(if cfg!(windows) { "dreamchecker.exe" } else { "dreamchecker" });
    p.exists().then_some(p)
}

fn run(exe: &std::path::Path, args: &[&str], dir: &std::path::Path, threads: &str) -> (i32, String, String) {
    let out = Command::new(exe).args(args).current_dir(dir).env("DQ_DREAMCHECKER_THREADS", threads).output().expect("run checker");
    let text = |b: &[u8]| String::from_utf8_lossy(b).replace("\r\n", "\n");
    (out.status.code().unwrap_or(-1), text(&out.stdout), text(&out.stderr))
}

#[test]
fn seeded_fixture_matches_standalone() {
    let Some(reference) = standalone() else {
        eprintln!("dreamchecker_parity: no standalone dreamchecker; skipped");
        return;
    };
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures/dreamchecker/seeded");
    let expected = run(&reference, &["-e", "seeded.dme"], &dir, "1");
    assert_eq!(expected.0, 1, "the seeded fixture must fail the reference checker");
    for threads in ["1", "4"] {
        let got = run(std::path::Path::new(env!("CARGO_BIN_EXE_analyze")), &["dreamchecker", "-e", "seeded.dme"], &dir, threads);
        assert_eq!(got, expected, "analyze dreamchecker ({threads} thread(s)) differs from the standalone checker");
    }
}
