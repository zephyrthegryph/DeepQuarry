//! The `analyze` command line: `analyze --help`. Shared by the `analyze` binary and `dmbc analyze`.

use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Instant;

use crate::baseline::Mode;
use crate::run::{self, Engine, Options};

/// Whether a full `analyze check` also runs the unused-ALLOW check on its own (every lint is in the
/// engine now, so every annotation's usage is visible to it).
const NATIVE_UNUSED_DEFAULT: bool = true;

const HELP: &str = "analyze: DeepQuarry's lint/analysis engine

USAGE
  analyze check [--lint NAME...] [--changed-only] [--no-cache] [--rehash] [--raw] [--ci] [--root DIR]
      Run lints (default: all). Exit 1 if any fails. --raw ignores baselines (every site is new);
      --changed-only judges only files changed against origin/master and the working tree.
  analyze baseline --update|--seed|--migrate [--lint NAME...]
      Rewrite ratchet baselines: --update only ever drops fixed sites; --seed records every site;
      --migrate rewrites line-text rows as identity rows (@owner::...) without adding or dropping one.
  analyze parity [NAME... | --all] [--bless] [--fixtures-only]
      Run the legacy Python lint and the engine port on this tree (and on tools/analyze/fixtures/)
      and diff the findings. --bless writes expected.txt from a clean fixture comparison.
  analyze timing [--lint NAME...] [--no-cache]
      A full check with a per-lint timing table.
  analyze selftest [--lint NAME...]     Run each lint's fixture tests.
  analyze dreamchecker [-e DME] [-c TOML] [--json] [--parse-only]
      DreamChecker on this process's own parse; same output and exit code as the standalone binary.
  analyze list                          The registered lints.
  analyze frontend-diff                 Compare the text scanner with the dreammaker parser.
  analyze gen [--check] [NAME...]       Write (or check) the generated DM under code/engine/_generated/.
  analyze codemod list | NAME [--check|--apply|--revert] [--path PREFIX...] [--write-residue]
      AST-aware rewriters (phase 2.5); `analyze codemod help`.
  analyze base-vars-dead [--tsv] [--few]
      Base-type vars nothing reads (dead or write-only), by name over code/ and maps/.
  analyze sem reads /type proc | oracle [--all]
                                        Semantic queries: a handler's reads; the reads spike oracle.

A lint is selected by its name or its group (`sys` selects every sys/* lint).";

struct Args {
    cmd: String,
    lints: Vec<String>,
    flags: Vec<String>,
    root: Option<PathBuf>,
}

fn parse(argv: Vec<String>) -> Args {
    let mut it = argv.into_iter().skip(1);
    let cmd = it.next().unwrap_or_else(|| "help".to_string());
    let mut lints = Vec::new();
    let mut flags = Vec::new();
    let mut root = None;
    let mut taking_lints = false;
    let mut rest: Vec<String> = it.collect();
    let mut i = 0;
    while i < rest.len() {
        let a = std::mem::take(&mut rest[i]);
        i += 1;
        match a.as_str() {
            "--lint" => taking_lints = true,
            "--root" => {
                root = rest.get(i).map(PathBuf::from);
                i += 1;
                taking_lints = false;
            }
            s if s.starts_with("--") => {
                flags.push(s.to_string());
                taking_lints = false;
            }
            _ => {
                if taking_lints || cmd == "parity" {
                    for n in a.split(',') {
                        if !n.is_empty() {
                            lints.push(n.to_string());
                        }
                    }
                } else {
                    flags.push(a);
                }
            }
        }
    }
    Args { cmd, lints, flags, root }
}

fn find_root(explicit: Option<PathBuf>) -> PathBuf {
    if let Some(r) = explicit {
        return r;
    }
    let mut dir = dq_hostio::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    loop {
        if dir.join("deepquarry.dme").exists() {
            return dir;
        }
        if !dir.pop() {
            return dq_hostio::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        }
    }
}

/// An unused-ALLOW verdict that came out of warm caches is confirmed by one cold run (an empty private cache, no shared seed, no gen
/// store): the verdict must depend on the tree alone, and a cached lint result that lost an annotation's use would otherwise fail a gate
/// the cold audit passes. When the cold run finds none, the warm caches are wrong: say so, delete this worktree's cache files (the next
/// run rebuilds them) and return no problems. When it finds problems they are real. Not repeated inside the cold child.
fn recheck_unused_cold(root: &Path, problems: Vec<String>) -> Vec<String> {
    if dq_hostio::var_os("DQ_ANALYZE_UNUSED_RECHECK").is_some() {
        return problems;
    }
    let Some(cache) = crate::incr::dir() else { return problems };
    let Ok(exe) = std::env::current_exe() else { return problems };
    let scratch = std::env::temp_dir().join(format!("analyze-cold-{}", std::process::id()));
    let _ = std::fs::create_dir_all(&scratch);
    eprintln!("analyze: {} unused ALLOW annotation(s) under warm caches; confirming with a cold run", problems.len());
    let mut args: Vec<String> = RUN_ARGV.get().cloned().unwrap_or_else(|| std::env::args().collect()).into_iter().skip(1).collect();
    if !args.iter().any(|a| a == "--root") {
        args.push("--root".to_string());
        args.push(root.to_string_lossy().to_string());
    }
    let out = self_command(&exe)
        .args(&args)
        .env("DQ_ANALYZE_CACHE", &scratch)
        .env("DQ_ANALYZE_SHARED_CACHE", "off")
        .env("DQ_GEN_STORE", "off")
        .env("DQ_ANALYZE_UNUSED_RECHECK", "1")
        .output();
    let _ = std::fs::remove_dir_all(&scratch);
    let Ok(out) = out else { return problems };
    if cold_finds_no_unused(&String::from_utf8_lossy(&out.stdout)) != Some(true) {
        return problems;
    }
    eprintln!("analyze: WARNING warm and cold disagree: the cold run finds no unused ALLOW; these came from stale cached results:");
    for p in &problems {
        eprintln!("analyze:   {}", p);
    }
    if let Ok(rd) = std::fs::read_dir(&cache) {
        for e in rd.flatten() {
            if e.path().extension().map(|x| x == "bin").unwrap_or(false) {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
    Vec::new()
}

/// `Some(true)` when a cold run's output reports the unused-ALLOW check with no problem, `Some(false)` with some, `None` when the check did not run.
/// The check's own summary line decides (`allow annotations: N unused`): a problem can read "is unused: no longer triggers ..." or
/// "... but no lint run used any ...", and matching one wording took a real unused annotation for stale caches, which then deleted
/// the caches on every run.
fn cold_finds_no_unused(text: &str) -> Option<bool> {
    let count = text.lines().rev().find_map(|l| l.strip_prefix("allow annotations: ")?.strip_suffix(" unused")?.trim().parse::<usize>().ok())?;
    Some(count == 0)
}

#[cfg(test)]
mod tests {
    use super::cold_finds_no_unused;

    #[test]
    fn cold_verdict_is_read_from_the_check_output() {
        assert_eq!(cold_finds_no_unused("x\nallow annotations: 0 unused\n"), Some(true));
        assert_eq!(cold_finds_no_unused("a.dm:3: ALLOW(handlers) is unused: no longer triggers the handlers lint; delete\nallow annotations: 1 unused\n"), Some(false));
        assert_eq!(
            cold_finds_no_unused("ALLOW(sys_x): 1 annotation, but no lint run used any: the sys_x lint is not run\nallow annotations: 1 unused\n"),
            Some(false)
        );
        assert_eq!(cold_finds_no_unused("crashed before the check\n"), None);
    }
}

fn options(args: &Args, root: &Path) -> Options {
    let has = |f: &str| args.flags.iter().any(|x| x == f);
    Options {
        root: root.to_path_buf(),
        lints: args.lints.clone(),
        changed_only: has("--changed-only"),
        no_cache: has("--no-cache"),
        rehash: has("--rehash"),
        raw: has("--raw"),
        ci: has("--ci"),
        scopes_from: None,
    }
}

/// The arguments that select analyze in the running executable: none for the `analyze` binary, `analyze` for `dmbc analyze`.
static LAUNCH_PREFIX: std::sync::OnceLock<Vec<String>> = std::sync::OnceLock::new();

/// A command that runs analyze again in this executable (the warm worker, the cold unused-ALLOW recheck).
pub fn self_command(exe: &Path) -> std::process::Command {
    let mut cmd = dq_hostio::command(exe);
    cmd.args(LAUNCH_PREFIX.get().map(|v| v.as_slice()).unwrap_or(&[]));
    cmd
}

/// Sets the arguments that select analyze in this executable when it is not entered through [`main_args`] (a daemon hosting
/// requests: `dmbc` needs `analyze`).
pub fn set_launch_prefix(prefix: Vec<String>) {
    let _ = LAUNCH_PREFIX.set(prefix);
}

/// The `analyze` binary's entry point.
pub fn main() -> ExitCode {
    main_args(std::env::args().collect(), Vec::new())
}

/// The command line `argv` (`argv[0]` is the program name), run in an executable that selects analyze with `prefix`
/// (`dmbc analyze ...` passes `["analyze"]`).
pub fn main_args(argv: Vec<String>, prefix: Vec<String>) -> ExitCode {
    let _ = LAUNCH_PREFIX.set(prefix);
    ExitCode::from(run_all(argv))
}

/// The commands a hosted request may run (`run_hosted`): they read the tree under the given root and write only inside it, take no
/// argument a relative path in the client's working directory would change, and run nothing interactive.
pub fn hostable(argv: &[String]) -> bool {
    match argv.get(1).map(|a| a.as_str()) {
        Some("check" | "timing" | "baseline" | "gen") => true,
        // `-e` is read against the working directory the request carries; a `-c` must be absolute.
        Some("dreamchecker") => !argv.windows(2).any(|w| w[0] == "-c" && !Path::new(&w[1]).is_absolute()),
        _ => false,
    }
}

/// This worktree's root as a run of `argv` would find it (for the client: which root a request is for).
pub fn root_of(argv: &[String]) -> PathBuf {
    find_root(parse(argv.to_vec()).root)
}

/// One request inside a long-lived host process (the dmbc daemon): `argv` as the client gave it, its environment and working
/// directory, its output to `sink`. Returns the exit code the same command returns standalone.
///
/// Requests run one at a time. Each runs on threads of its own (a fresh thread and its own worker pool, so no thread-local state
/// carries over), inside a `dq_hostio` scope; afterwards the run state is reset (`crate::host`), so the next request starts as a
/// fresh process would.
pub fn run_hosted(argv: Vec<String>, env: std::collections::HashMap<String, String>, cwd: PathBuf, sink: std::sync::Arc<dq_hostio::Sink>) -> u8 {
    let _one = HOSTED.lock().unwrap_or_else(|e| e.into_inner());
    take_pending_reset();
    let scope = dq_hostio::Scope { env, cwd, sink };
    let worker = std::thread::Builder::new().name("analyze-request".into()).stack_size(64 << 20).spawn(move || {
        dq_hostio::with_scope(scope, || {
            // What was read ahead belongs to one root: a request for another starts from nothing.
            let root = find_root(parse(argv.clone()).root);
            let mut held = HOSTED_ROOT.lock().unwrap_or_else(|e| e.into_inner());
            if held.as_deref() != Some(root.as_path()) {
                if held.is_some() {
                    crate::host::reset_run_state();
                    crate::sem::model_store::shed();
                }
                *held = None;
            }
            drop(held);
            let pool = match rayon::ThreadPoolBuilder::new().thread_name(|i| format!("analyze-{i}")).stack_size(16 << 20).build() {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("analyze: could not start the request's worker pool: {e}");
                    return 70;
                }
            };
            let code = pool.install(|| std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run_all(argv))));
            drop(pool);
            match code {
                Ok(c) => c,
                Err(_) => {
                    eprintln!("analyze: internal panic in a hosted request");
                    70
                }
            }
        })
    });
    let code = match worker {
        Ok(h) => h.join().unwrap_or(70),
        Err(_) => 70,
    };
    // The request is answered now; freeing what it built (seconds for a whole-tree model, which a process that exits never pays)
    // is the start of the next request's turn, done by [`finish_hosted`] after the reply.
    *HOSTED_ROOT.lock().unwrap_or_else(|e| e.into_inner()) = None;
    *PENDING_RESET.lock().unwrap_or_else(|e| e.into_inner()) = true;
    code
}

/// A finished request whose run state is not yet reset.
static PENDING_RESET: std::sync::Mutex<bool> = std::sync::Mutex::new(false);

/// Resets what the last hosted request left (call after its reply is sent; the next request does it itself if this did not run).
pub fn finish_hosted() {
    let _one = HOSTED.lock().unwrap_or_else(|e| e.into_inner());
    take_pending_reset();
}

fn take_pending_reset() {
    let mut p = PENDING_RESET.lock().unwrap_or_else(|e| e.into_inner());
    if std::mem::take(&mut *p) {
        crate::host::reset_run_state();
    }
}

/// Serializes hosted requests and the read-ahead between them.
static HOSTED: std::sync::Mutex<()> = std::sync::Mutex::new(());
/// The root whose stored model and walks are read ahead (decoded in memory for its next request), if any.
static HOSTED_ROOT: std::sync::Mutex<Option<PathBuf>> = std::sync::Mutex::new(None);

/// Reads ahead for the next request of the root `argv` ran in (what a warm process reads first: the stored model with every body
/// decoded, and the walk store), in the request's environment. Runs after the request has answered; holds about 1-2 GB until
/// the next request uses it or [`shed_hosted`] drops it.
pub fn prewarm_hosted(argv: &[String], env: std::collections::HashMap<String, String>, cwd: PathBuf) {
    let _one = HOSTED.lock().unwrap_or_else(|e| e.into_inner());
    take_pending_reset();
    let argv = argv.to_vec();
    let scope = dq_hostio::Scope { env, cwd, sink: std::sync::Arc::new(|_, _| {}) };
    let done = std::thread::Builder::new().name("analyze-prewarm".into()).stack_size(64 << 20).spawn(move || {
        dq_hostio::with_scope(scope, || {
            let root = find_root(parse(argv).root);
            let pool = rayon::ThreadPoolBuilder::new().thread_name(|i| format!("analyze-prewarm-{i}")).stack_size(16 << 20).build();
            let Ok(pool) = pool else { return None };
            pool.install(|| crate::prewarm(&root));
            Some(root)
        })
    });
    let root = done.ok().and_then(|h| h.join().ok()).flatten();
    *HOSTED_ROOT.lock().unwrap_or_else(|e| e.into_inner()) = root;
}

/// Drops what was read ahead (idle, or the machine is short of memory). False when a request is running (nothing to drop then).
pub fn shed_hosted() -> bool {
    let Ok(_one) = HOSTED.try_lock() else { return false };
    take_pending_reset();
    let mut held = HOSTED_ROOT.lock().unwrap_or_else(|e| e.into_inner());
    if held.is_none() {
        return true;
    }
    crate::host::reset_run_state();
    crate::sem::model_store::shed();
    *held = None;
    true
}

/// Whether anything is read ahead.
pub fn hosted_resident() -> bool {
    HOSTED_ROOT.lock().unwrap_or_else(|e| e.into_inner()).is_some()
}

/// One run of `argv`, with the end-of-run work.
fn run_all(argv: Vec<String>) -> u8 {
    let code = real_main(argv);
    // Hand the cache files this run rewrote to the other worktrees (src/shared.rs).
    crate::shared::publish();
    crate::sem::model_store::finish();
    crate::sem::walk_cache::finish();
    crate::util::cpu_account_report();
    if dq_hostio::var_os("DQ_ANALYZE_TRACE").is_some() {
        eprintln!("analyze: {} stored proc bodies decoded", dreammaker::objtree::decoded_count());
        for (k, n) in dreammaker::objtree::decode_probes() {
            eprintln!("BODY {} {}", n, k);
        }
    }
    for (k, n) in crate::tree::TEXT_PROBE.lock().unwrap().iter() {
        eprintln!("TEXT {} {}", n, k);
    }
    exit_byte(code)
}

/// The byte an `ExitCode` carries (the ones this binary returns: SUCCESS, FAILURE and `from(n)`).
fn exit_byte(code: ExitCode) -> u8 {
    if code == ExitCode::SUCCESS {
        0
    } else if code == ExitCode::FAILURE {
        1
    } else {
        (0..=255u8).find(|n| ExitCode::from(*n) == code).unwrap_or(1)
    }
}

/// The command line of this run: the process's own, or the request a warm worker serves (`crate::warm`).
static RUN_ARGV: crate::host::RunCell<Vec<String>> = crate::host::RunCell::new();

fn real_main(argv: Vec<String>) -> ExitCode {
    let _ = RUN_ARGV.set(argv.clone());
    if dq_hostio::var_os("DQ_BODY_PROBE").is_some() {
        dreammaker::objtree::PROBE.store(true, std::sync::atomic::Ordering::Relaxed);
    }
    crate::tree::start_watchdog();
    let args = parse(argv);
    let root = find_root(args.root.clone());
    let has = |f: &str| args.flags.iter().any(|x| x == f);
    match args.cmd.as_str() {
        "help" | "--help" | "-h" => {
            println!("{}", HELP);
            ExitCode::SUCCESS
        }
        "list" => {
            let reg = run::registry();
            for l in &reg.lints {
                let m = l.meta();
                println!("{:<28} group={:<8} scan={:?} legacy={}", m.name, m.group, m.scan, m.legacy);
            }
            println!("{} lints", reg.lints.len());
            ExitCode::SUCCESS
        }
        "check" | "report" => {
            let mut o = options(&args, &root);
            if args.cmd == "report" {
                o.raw = true;
            }
            let t0 = Instant::now();
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let problems = engine.validate_scopes();
            if !problems.is_empty() {
                for p in &problems {
                    eprintln!("analyze: {}", p);
                }
                return ExitCode::from(2);
            }
            // Fixture selftests first: a lint whose own fixtures fail can't be trusted to ratchet.
            let mut failed: Vec<String> = Vec::new();
            let t_self = Instant::now();
            if args.cmd == "check" && !has("--no-selftest") {
                // A selftest is a function of the engine build alone: once every selected lint's passed for
                // this build (and none was skipped), a marker in the cache says so.
                let names: Vec<String> = run::selected(&engine.reg, &engine.opts.lints).iter().map(|l| l.meta().name.to_string()).collect();
                let marker = crate::incr::dir().map(|d| d.join("selftest.ok"));
                let stamp = format!("{}|{}", crate::cache::ENGINE_HASH, names.join(","));
                let known = marker.as_ref().and_then(|m| std::fs::read_to_string(m).ok()).map(|t| t == stamp).unwrap_or(false);
                if !known {
                    crate::incr::suspend(true);
                    for lint in run::selected(&engine.reg, &engine.opts.lints) {
                        if let Err(e) = lint.selftest() {
                            println!("selftest FAILED: {}: {}", lint.meta().name, e);
                            failed.push(format!("{} --selftest", lint.meta().name));
                        }
                    }
                    crate::incr::suspend(false);
                    if failed.is_empty() {
                        if let Some(m) = &marker {
                            let _ = std::fs::create_dir_all(m.parent().unwrap());
                            let _ = std::fs::write(m, &stamp);
                        }
                    }
                }
            }
            let t_run = Instant::now();
            let outcomes = engine.run_all();
            if dq_hostio::var("DQ_ANALYZE_TRACE").is_ok() {
                eprintln!("analyze: startup {:.0?}, selftests {:.0?}, lints {:.0?}, files loaded {}", t_self.duration_since(t0), t_run.duration_since(t_self), t_run.elapsed(), engine.tree.fresh_count());
            }
            let (text, lint_failed) = run::render(&outcomes, engine.opts.ci);
            failed.extend(lint_failed);
            print!("{}", text);
            write_allow_usage(&engine, &outcomes);
            // The unused-ALLOW check needs every lint's usage: a full run only. While legacy Python
            // lints remain, check_ratchets.sh keeps doing it (they record into DQ_ALLOW_USAGE).
            let full_run = engine.opts.lints.iter().all(|n| n.starts_with('-'));
            if args.cmd == "check" && full_run && (has("--unused") || NATIVE_UNUSED_DEFAULT) && !has("--no-unused") && dq_hostio::var("DQ_ALLOW_USAGE").is_err() {
                use crate::lints::allow_annotations;
                let used: Vec<crate::lint::AllowUse> = outcomes.iter().flat_map(|o| o.allow_used.iter().cloned()).collect();
                let mut problems = allow_annotations::unused(&engine.tree, &used, &[], &|_| String::new());
                if !problems.is_empty() {
                    problems = recheck_unused_cold(&root, problems);
                }
                for p in &problems {
                    println!("{}", p);
                }
                println!("allow annotations: {} unused", problems.len());
                if !problems.is_empty() {
                    failed.push("allow_annotations --unused".to_string());
                }
            }
            if has("--timing") {
                print_timing(&engine, &outcomes, t0.elapsed());
            }
            if failed.is_empty() {
                println!("All ratchet lints passed.");
                ExitCode::SUCCESS
            } else {
                println!("Ratchet lints failed: {}", failed.join(" "));
                ExitCode::FAILURE
            }
        }
        "timing" => {
            let o = options(&args, &root);
            let t0 = Instant::now();
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let outcomes = engine.run_all();
            print_timing(&engine, &outcomes, t0.elapsed());
            ExitCode::SUCCESS
        }
        "baseline" => {
            let mode = if has("--seed") {
                Mode::Seed
            } else if has("--update") {
                Mode::Update
            } else if has("--migrate") {
                Mode::Migrate
            } else {
                eprintln!("analyze baseline: pass --update, --seed or --migrate");
                return ExitCode::from(2);
            };
            // The reads the read lints judge come from the generated files, so a baseline rewrite judges the tree the check will:
            // generate first, as `check_ratchets.sh` does (a no-op when nothing changed).
            if dq_hostio::var("DQ_BASELINE_NO_GEN").is_err() {
                let rc = crate::sem::cli::gen(&[], &root);
                if format!("{rc:?}") != format!("{:?}", ExitCode::SUCCESS) {
                    eprintln!("analyze baseline: `analyze gen` failed; fix it first (the baseline must be written from the generated tree)");
                    return rc;
                }
            }
            let o = options(&args, &root);
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let mut code = ExitCode::SUCCESS;
            for lint in run::selected(&engine.reg, &engine.opts.lints) {
                match engine.update_baseline(lint, mode) {
                    Ok(s) => {
                        if !s.is_empty() {
                            println!("{}", s)
                        }
                    }
                    Err(e) => {
                        eprintln!("{}: {}", lint.meta().name, e);
                        code = ExitCode::FAILURE;
                    }
                }
            }
            code
        }
        "parity" => {
            let mut o = options(&args, &root);
            o.no_cache = true;
            let names = if has("--all") { Vec::new() } else { args.lints.clone() };
            if names.is_empty() && !has("--all") {
                eprintln!("analyze parity: name a lint or pass --all");
                return ExitCode::from(2);
            }
            ExitCode::from(crate::parity::run(&o, &names, has("--bless"), has("--fixtures-only")) as u8)
        }
        "selftest" => {
            let o = options(&args, &root);
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let mut failed = false;
            for lint in run::selected(&engine.reg, &engine.opts.lints) {
                match lint.selftest() {
                    Ok(s) => println!("selftest ok: {} {}", lint.meta().name, s),
                    Err(e) => {
                        println!("selftest FAILED: {}: {}", lint.meta().name, e);
                        failed = true;
                    }
                }
            }
            if failed {
                ExitCode::FAILURE
            } else {
                ExitCode::SUCCESS
            }
        }
        "dreamchecker" => {
            let rest: Vec<String> = RUN_ARGV.get().cloned().unwrap_or_default().into_iter().skip(2).collect();
            return ExitCode::from(crate::dreamchecker::cli(&rest, &root) as u8);
        }
        "sem" => crate::sem::cli::run(&args.flags, &root),
        "base-vars-dead" => crate::base_vars_dead::run(&args.flags, &root),
        "gen" => crate::sem::cli::gen(&args.flags, &root),
        "codemod" => crate::codemod::cli(&args.flags, &root),
        "fix" if args.flags.iter().any(|a| a == "--propose-schema") => crate::lints::untyped_refs::propose_cli(&root),
        "fix" => crate::lints::tracked::fix_cli(&args.flags, &root),
        "fixture" => crate::sem::cli::fixture(&args.flags, &root),
        "frontend-diff" => {
            use crate::frontend::{self, Frontend};
            let mut o = options(&args, &root);
            o.lints = vec![];
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let t = Instant::now();
            let text = frontend::TextFrontend.analyze(&root, &engine.tree);
            println!("text frontend: {:?}", t.elapsed());
            let t = Instant::now();
            let dm = frontend::DreamMakerFrontend::default().analyze(&root, &engine.tree);
            println!("dreammaker frontend: {:?}", t.elapsed());
            match (text, dm) {
                (Ok(a), Ok(b)) => {
                    println!("text: {} types, {} procs, {} vars", a.types.len(), a.proc_count(), a.var_count());
                    println!("dreammaker: {} types, {} procs, {} vars, {} parse errors", b.types.len(), b.proc_count(), b.var_count(), b.diagnostics.len());
                    for l in frontend::diff(&a, &b, 60) {
                        println!("{}", l);
                    }
                    ExitCode::SUCCESS
                }
                (a, b) => {
                    eprintln!("frontend error: {:?} / {:?}", a.err(), b.err());
                    ExitCode::FAILURE
                }
            }
        }
        other => {
            eprintln!("analyze: unknown command {:?}\n\n{}", other, HELP);
            ExitCode::from(2)
        }
    }
}

fn print_timing(engine: &Engine, outcomes: &[run::Outcome], total: std::time::Duration) {
    println!("\n-- timing (tree load {:.0?}, {} files in tree, meta cache {} entries) --", engine.load_time, engine.files_read, engine.meta_len());
    let mut rows: Vec<&run::Outcome> = outcomes.iter().collect();
    rows.sort_by(|a, b| b.timing.total.cmp(&a.timing.total));
    println!("{:<30} {:>9} {:>7} {:>9} {:>6}", "lint", "time", "files", "rescanned", "memo");
    for o in rows {
        println!(
            "{:<30} {:>9.1?} {:>7} {:>9} {:>6}",
            o.name,
            o.timing.total,
            o.timing.files,
            o.timing.rescanned,
            if o.timing.tree_memo_hit { "hit" } else { "-" }
        );
    }
    println!("total wall time: {:.2?}", total);
}

/// With `DQ_ALLOW_USAGE=<file>` set (check_ratchets.sh), appends one `lint<TAB>file digest<TAB>line`
/// row per ALLOW annotation that kept a site: the format `allow_annotations.py --unused` reads, so
/// annotations used by engine lints count as used. The digest is sha1 of the file text without
/// trailing newlines (what the Python's `digest_of` computes).
fn write_allow_usage(engine: &Engine, outcomes: &[run::Outcome]) {
    use sha1::{Digest, Sha1};
    use std::io::Write;
    let Ok(path) = dq_hostio::var("DQ_ALLOW_USAGE") else { return };
    if path.is_empty() {
        return;
    }
    let mut rows: std::collections::BTreeSet<(String, String, u32)> = std::collections::BTreeSet::new();
    let mut digests: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    for o in outcomes {
        for u in &o.allow_used {
            let digest = digests.entry(u.rel.clone()).or_insert_with(|| match engine.tree.get(&u.rel) {
                Some(f) => {
                    let mut h = Sha1::new();
                    h.update(f.text().trim_end_matches('\n').as_bytes());
                    h.finalize().iter().map(|b| format!("{:02x}", b)).collect()
                }
                None => String::new(),
            });
            rows.insert((u.name.clone(), digest.clone(), u.line));
        }
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        for (name, digest, line) in rows {
            let _ = writeln!(f, "{}\t{}\t{}", name, digest, line);
        }
    }
}

/// Run state for `crate::host::reset_run_state`.
pub(crate) fn reset() {
    crate::host::clear(&RUN_ARGV);
}
