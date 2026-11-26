//! `analyze dreamchecker` against the standalone suite-1.11 binary (`~/SpacemanDMM/dreamchecker.exe` or `DREAMCHECKER_EXE`) on the
//! seeded fixture under `fixtures/dreamchecker/`: stdout and exit code identical, the same diagnostics, serial and parallel. The
//! standalone prints the call-tree diagnostics in a hash order seeded per process (two runs can differ), so diagnostics compare as a
//! multiset; `analyze dreamchecker` prints them in source order and must give the same text on every run. Skipped (with a note) where
//! the standalone binary is not installed.

mod common;

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex};

fn standalone() -> Option<PathBuf> {
    if let Some(p) = std::env::var_os("DREAMCHECKER_EXE") {
        return Some(PathBuf::from(p));
    }
    let home = std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME"))?;
    let p = PathBuf::from(home).join("SpacemanDMM").join(if cfg!(windows) { "dreamchecker.exe" } else { "dreamchecker" });
    p.exists().then_some(p)
}

/// A diagnostic as (file, line, severity, first line of the message). The column is left out: the compiler's front end keeps lines only, and
/// a parenthesized condition (`if(1)`) is reported at its first operand there (column 5), not at its parenthesis (column 4), from the standalone's printed form (ANSI stripped:
/// `file, line N, column M:` then `severity: message`).
fn standalone_diagnostics(stderr: &str) -> Vec<String> {
    let mut plain = String::new();
    let mut chars = stderr.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' && chars.peek() == Some(&'[') {
            for n in chars.by_ref() {
                if n.is_ascii_alphabetic() {
                    break;
                }
            }
        } else {
            plain.push(c);
        }
    }
    let mut out = Vec::new();
    let mut lines = plain.lines().peekable();
    while let Some(line) = lines.next() {
        let Some((file, rest)) = line.split_once(", line ") else { continue };
        let Some((n, col)) = rest.strip_suffix(':').and_then(|r| r.split_once(", column ")) else { continue };
        let Some(msg) = lines.next() else { continue };
        let Some((sev, text)) = msg.split_once(": ") else { continue };
        let _ = col;
        out.push(format!("{file}:{n} {} {text}", sev.to_ascii_lowercase()));
    }
    out.sort();
    out
}

/// The same from `DQ_DREAMCHECKER_LIST` (`diag file:line:col Severity message`): `analyze dreamchecker` writes its diagnostics through
/// the vendored context's own stderr stream, which an in-process run cannot capture, and lists them there instead.
fn listed_diagnostics(stderr: &str) -> Vec<String> {
    let mut out: Vec<String> = stderr
        .lines()
        .filter_map(|l| l.strip_prefix("diag "))
        .filter_map(|l| {
            let (place, rest) = l.split_once(' ')?;
            let place = place.rsplit_once(':').map_or(place, |(file_line, _column)| file_line);
            let (sev, text) = rest.split_once(' ')?;
            Some(format!("{place} {} {}", sev.to_ascii_lowercase(), text.lines().next().unwrap_or("")))
        })
        .collect();
    out.sort();
    out
}

fn run(exe: &std::path::Path, args: &[&str], dir: &std::path::Path, threads: &str) -> (i32, String, String) {
    let out = Command::new(exe).args(args).current_dir(dir).env("DQ_DREAMCHECKER_THREADS", threads).output().expect("run checker");
    let text = |b: &[u8]| String::from_utf8_lossy(b).replace("\r\n", "\n");
    (out.status.code().unwrap_or(-1), text(&out.stdout), text(&out.stderr))
}

/// `analyze dreamchecker -e seeded.dme` in this process on the compiler's parse: the request's output is captured as the daemon
/// captures it for a client (one request at a time; this file's one test is the only one in the process).
fn run_in_process(args: &[&str], dir: &std::path::Path, threads: &str) -> (i32, String, String) {
    let mut env: HashMap<String, String> = std::env::vars().collect();
    env.insert("DQ_DREAMCHECKER_THREADS".into(), threads.into());
    env.insert("DQ_DREAMCHECKER_LIST".into(), "1".into());
    let captured: Arc<Mutex<(String, String)>> = Arc::new(Mutex::new((String::new(), String::new())));
    let sink = captured.clone();
    let argv: Vec<String> = args.iter().map(|a| a.to_string()).collect();
    let scope = dq_hostio::Scope {
        env,
        cwd: dir.to_path_buf(),
        sink: Arc::new(move |stdout, bytes| {
            let mut c = sink.lock().unwrap();
            let text = String::from_utf8_lossy(bytes).replace("\r\n", "\n");
            if stdout { c.0.push_str(&text) } else { c.1.push_str(&text) }
        }),
    };
    let code = dq_hostio::with_scope(scope, || dq_analyze::dreamchecker::cli(&argv, dir));
    let c = captured.lock().unwrap();
    (code, c.0.clone(), c.1.clone())
}

#[test]
fn seeded_fixture_matches_standalone() {
    common::dmbc_parse();
    let Some(reference) = standalone() else {
        eprintln!("dreamchecker_parity: no standalone dreamchecker; skipped");
        return;
    };
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures/dreamchecker/seeded");
    let expected = run(&reference, &["-e", "seeded.dme"], &dir, "1");
    assert_eq!(expected.0, 1, "the seeded fixture must fail the reference checker");
    let mut first: Option<(i32, String, String)> = None;
    for threads in ["1", "4", "4"] {
        let got = run_in_process(&["-e", "seeded.dme"], &dir, threads);
        assert_eq!((got.0, &got.1), (expected.0, &expected.1), "analyze dreamchecker ({threads} thread(s)): exit code or stdout differs");
        assert_eq!(listed_diagnostics(&got.2), standalone_diagnostics(&expected.2), "analyze dreamchecker ({threads} thread(s)): diagnostics differ");
        match &first {
            Some(f) => assert_eq!(&got, f, "analyze dreamchecker must print the same text on every run"),
            None => first = Some(got),
        }
    }
}
