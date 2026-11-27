//! `analyze dreamchecker`: SpacemanDMM's DreamChecker (vendored, `vendor/dreamchecker`), its checks run on the compiler front end's
//! own tree (`dreamchecker::native`, its input built by the compiler: `dmbc/src/dreamchecker_input.rs`), with the standalone
//! `dreamchecker -e <dme>` output: progress on stdout, every diagnostic at info severity or above on stderr as it is registered, the
//! closing count, `--json` totals and exit 1 on any. Its oracle is the corpus (`vendor/dreamchecker/tests/corpus`), recorded from
//! the checker on dreammaker's parse before that checker was removed.

use std::path::{Path, PathBuf};

/// Arguments: the standalone's own `[-e DME] [-c CONFIG] [--json] [--parse-only]`, plus `--threads N`.
pub fn cli(argv: &[String], root: &Path) -> i32 {
    let mut dme: Option<PathBuf> = None;
    let mut config: Option<PathBuf> = None;
    let mut json = false;
    let mut parse_only = false;
    let mut threads = default_threads();
    let mut it = argv.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "-e" => dme = it.next().map(PathBuf::from),
            "-c" => config = it.next().map(PathBuf::from),
            "--json" => json = true,
            "--parse-only" => parse_only = true,
            "--threads" => match it.next().and_then(|n| n.parse().ok()) {
                Some(n) => threads = n,
                None => {
                    eprintln!("--threads takes a number");
                    return 2;
                }
            },
            other => {
                eprintln!("unknown argument: {other}");
                return 2;
            }
        }
    }
    // Shown as given and read from the working directory, as the standalone does (the repository root when none can be read).
    let root = dq_hostio::current_dir().unwrap_or_else(|_| root.to_path_buf());
    let shown = dme.unwrap_or_else(|| PathBuf::from("deepquarry.dme"));
    let dme = if shown.is_absolute() { shown.clone() } else { root.join(&shown) };
    run(&dme, &shown, config.as_deref(), json, parse_only, threads)
}

/// Half the cores (the machine is also a desktop), at most 8; `DQ_DREAMCHECKER_THREADS` overrides, 1 is the serial upstream pass.
fn default_threads() -> usize {
    if let Some(n) = dq_hostio::var("DQ_DREAMCHECKER_THREADS").ok().and_then(|v| v.parse().ok()) {
        return n;
    }
    std::thread::available_parallelism().map(|n| (n.get() / 2).clamp(1, 8)).unwrap_or(1)
}

/// The native checker (`dreamchecker::native` on the compiler front end's own tree): registers the front end's files and diagnostics
/// into the context, then (with `checks`) runs the checks. The compiler registers it (`dmbc::dreamchecker_input`).
pub type NativeChecker = fn(dme: &Path, context: &dreammaker::Context, checks: bool, cli: bool, threads: usize) -> Result<(), String>;

static NATIVE: std::sync::OnceLock<NativeChecker> = std::sync::OnceLock::new();

/// Registers the native checker. The first registration wins.
pub fn register_native(checker: NativeChecker) {
    let _ = NATIVE.set(checker);
}

/// The checker's context: its config from the given file or the `.dme`'s directory, printing as the standalone does under `cli`.
pub fn context_for(dme: &Path, config: Option<&Path>, cli: bool) -> dreammaker::Context {
    let mut context = dreammaker::Context::default();
    if cli {
        context.set_print_severity(Some(dreammaker::Severity::Info));
    }
    match config {
        Some(c) => context.force_config(c),
        None => context.autodetect_config(dme),
    }
    context
}

pub fn run(dme: &Path, shown: &Path, config: Option<&Path>, json: bool, parse_only: bool, threads: usize) -> i32 {
    println!("============================================================");
    println!("Parsing {}...\n", shown.display());
    let Some(native) = NATIVE.get().copied() else {
        eprintln!("analyze dreamchecker: the checker reads the compiler's front end; run it as `dmbc analyze dreamchecker` (the analyze alias)");
        return 2;
    };
    // The per-proc results live in the analysis query database (`crate::incr`), under the same stamp `check` uses, so the two
    // commands share one session in the daemon.
    let root = dme.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let scopes = crate::scopes::Scopes::load(&root.join("tools").join("ci").join("lint_scopes.toml")).map(|s| s.hash).unwrap_or_else(|_| "dreamchecker".into());
    let _cache = crate::cache::Cache::open(root, &scopes, true);
    let context = context_for(dme, config, true);
    if let Err(e) = native(dme, &context, !parse_only, true, threads) {
        eprintln!("analyze dreamchecker: {e}");
        return 2;
    }
    println!("============================================================");
    // `DQ_DREAMCHECKER_LIST=1`: every counted diagnostic, one per line, on stderr (comparing two parses' outputs).
    if dq_hostio::var_os("DQ_DREAMCHECKER_LIST").is_some() {
        for e in context.errors().iter().filter(|e| e.severity() <= dreammaker::Severity::Info) {
            let l = e.location();
            eprintln!("diag {}:{}:{} {:?} {}", context.file_path(l.file).display(), l.line, l.column, e.severity(), e.description());
        }
    }
    let errors = context.errors().iter().filter(|e| e.severity() <= dreammaker::Severity::Info).count();
    println!("Found {errors} diagnostics");
    if json {
        let count = |s| context.errors().iter().filter(|e| e.severity() == s).count();
        print!(
            "{}",
            serde_json::json!({
                "hint": count(dreammaker::Severity::Hint),
                "info": count(dreammaker::Severity::Info),
                "warning": count(dreammaker::Severity::Warning),
                "error": count(dreammaker::Severity::Error),
            })
        );
    }
    if errors > 0 { 1 } else { 0 }
}

/// Every diagnostic the context holds, every severity, in registration order, as the standalone prints one (`file, line L, column C:`,
/// `severity: description`, its notes) with its error type: the form the corpus (`vendor/dreamchecker/tests/corpus`) records.
pub fn render(context: &dreammaker::Context) -> String {
    use std::fmt::Write as _;
    let mut out = String::new();
    for e in context.errors().iter() {
        let l = e.location();
        let _ = writeln!(out, "{}, line {}, column {}:", context.file_path(l.file).display().to_string().replace('\\', "/"), l.line, l.column);
        let _ = writeln!(out, "{}: {}{}", e.severity(), e.description(), e.errortype().map(|t| format!(" [{t}]")).unwrap_or_default());
        for note in e.notes().iter() {
            let n = note.location();
            if n == l {
                let _ = writeln!(out, "- {}", note.description());
            } else if n.file == l.file {
                let _ = writeln!(out, "- {}:{}: {}", n.line, n.column, note.description());
            } else {
                let _ = writeln!(out, "- {}:{}:{}: {}", context.file_path(n.file).display().to_string().replace('\\', "/"), n.line, n.column, note.description());
            }
        }
    }
    out
}
