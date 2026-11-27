//! Native compilation over captured inputs, with disposable validated disk memos.
use std::path::PathBuf;

#[cfg(feature = "allocation-counting")]
#[global_allocator]
static ALLOCATOR: dm_profile::CountingAllocator = dm_profile::CountingAllocator;

// Revision 6 acceptance uses mimalloc without allocation-counting overhead.
// The separate counting build supplies allocation diagnostics only.
#[cfg(not(feature = "allocation-counting"))]
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

fn main() {
    dmbc::cache_maintenance::install_write_accounting();
    if std::panic::catch_unwind(main_inner).is_err() {
        eprintln!("internal compiler panic");
        std::process::exit(70);
    }
    dmbc::cache_maintenance::finish_process();
}
/// `analyze` is this executable under another name (the build links `tools/analyze/target/<profile>/analyze` to the compiler), so
/// every caller of the analyze binary runs `dmbc analyze`. A link beside its `<name>.target` file (the compiler's own path, written
/// by the build) hands the run to that compiler, which is the published one whose daemon every worktree shares.
fn analyze_alias() -> bool {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.file_stem().map(|s| s.to_string_lossy().eq_ignore_ascii_case("analyze")))
        .unwrap_or(false)
}

fn run_analyze_alias() -> ! {
    if let Ok(exe) = std::env::current_exe() {
        let target_file = exe.with_extension(if cfg!(windows) { "exe.target" } else { "target" });
        if let Ok(target) = std::fs::read_to_string(&target_file) {
            let target = std::path::PathBuf::from(target.trim());
            if target.is_file() {
                match std::process::Command::new(&target).arg("analyze").args(std::env::args_os().skip(1)).status() {
                    Ok(status) => std::process::exit(status.code().unwrap_or(1)),
                    Err(error) => eprintln!("analyze: could not run the compiler {}: {error}; running this copy", target.display()),
                }
            }
        }
    }
    dmbc::priority::apply_from_env();
    let code = dq_analyze::cli::main_args(std::env::args().collect(), Vec::new());
    std::process::exit(exit_code(code));
}

fn exit_code(code: std::process::ExitCode) -> i32 {
    if code == std::process::ExitCode::SUCCESS {
        0
    } else {
        (0..=255u8).find(|n| std::process::ExitCode::from(*n) == code).map(i32::from).unwrap_or(1)
    }
}

fn main_inner() {
    // Analysis inside the compiler may take its model from this front end (`DQ_ANALYZE_PARSE=dmbc`).
    dmbc::analysis_tree::register_analysis_provider();
    // `analyze dreamchecker` checks this front end's own tree (dreamchecker::native).
    dmbc::dreamchecker_input::register_native_checker();
    if analyze_alias() && std::env::args().nth(1).as_deref() != Some("--serve-daemon") {
        run_analyze_alias();
    }
    // One latest compiler: an executable of a superseded published version hands the whole invocation to the current one (same
    // arguments, same standard streams and exit status), so a process that resolved an older version still reaches the one
    // daemon. A daemon never forwards (it retires itself), and the forwarded process is never forwarded again.
    if std::env::var_os("DMB_FORWARDED").is_none() && std::env::args().nth(1).as_deref() != Some("--serve-daemon") {
        if let Some(target) = dmbc::daemon::resident::forward_target() {
            match std::process::Command::new(&target).args(std::env::args_os().skip(1)).env("DMB_FORWARDED", "1").status() {
                Ok(status) => std::process::exit(status.code().unwrap_or(1)),
                Err(error) => eprintln!("dmbc: could not forward to the current compiler {}: {error}; running this version", target.display()),
            }
        }
    }
    // A development build gets a private daemon namespace before any endpoint is computed (never touches the published daemon).
    if std::env::var_os("DMB_DAEMON_NAMESPACE").is_none() && dmbc::daemon::resident::provenance_of_self() == dmbc::daemon::resident::Provenance::Development {
        if let Ok(identity) = dmbc::daemon::compiler_identity() {
            dmbc::daemon::resident::isolate_development_build(identity);
        }
    }
    if std::env::args().nth(1).as_deref() == Some("syntax-coverage") {
        let dme = std::env::args().nth(2).unwrap_or_else(|| "deepquarry.dme".into());
        if let Err(e) = dmbc::syntax_coverage::run(std::path::Path::new(&dme)) {
            eprintln!("syntax-coverage: {e}");
            std::process::exit(1);
        }
        std::process::exit(0);
    }
    if std::env::args().nth(1).as_deref() == Some("analysis-parity") {
        let rest: Vec<String> = std::env::args().skip(2).collect();
        let tree = rest.iter().any(|a| a == "--tree");
        let dme = rest.iter().find(|a| !a.starts_with("--")).cloned().unwrap_or_else(|| "deepquarry.dme".into());
        let result = if tree {
            dmbc::analysis_parity::run_tree(std::path::Path::new(&dme))
        } else {
            dmbc::analysis_parity::run(std::path::Path::new(&dme))
        };
        if let Err(e) = result {
            eprintln!("analysis-parity: {e}");
            std::process::exit(1);
        }
        std::process::exit(0);
    }
    // `dmbc analyze ...`: the lint and analysis engine (tools/analyze), the same command line as the `analyze` binary.
    if std::env::args().nth(1).as_deref() == Some("analyze") {
        dmbc::priority::apply_from_env();
        let mut argv: Vec<String> = std::env::args().collect();
        argv.remove(1);
        // The daemon serves it when it can (one resident program for compile and analysis); otherwise it runs here.
        if let Some(code) = dmbc::daemon::analyze_client(&argv) {
            std::process::exit(i32::from(code));
        }
        let code = dq_analyze::cli::main_args(argv, vec!["analyze".to_string()]);
        let _ = std::io::Write::flush(&mut std::io::stdout());
        std::process::exit(exit_code(code));
    }
    // Below normal priority before any worker thread or daemon exists (DMB_PRIORITY=normal opts out).
    dmbc::priority::apply_from_env();
    let mut arguments: Vec<String> = std::env::args().skip(1).collect();
    let compile_result = match dmbc::output_cli::extract_compile_result(&mut arguments) {
        Ok(path) => path,
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(2);
        }
    };
    if arguments.first().map(String::as_str) == Some("--daemon-endpoint-json") {
        if arguments.len() != 1 || compile_result.is_some() {
            eprintln!("--daemon-endpoint-json accepts no other arguments");
            std::process::exit(2);
        }
        if let Err(error) =
            dmbc::daemon::endpoint_descriptor::write_current(&mut std::io::stdout().lock())
        {
            eprintln!("native daemon endpoint: {error}");
            std::process::exit(1);
        }
        return;
    }
    if arguments.first().map(String::as_str) == Some("--daemon-stats") {
        if compile_result.is_some() {
            eprintln!("--daemon-stats accepts no compile result");
            std::process::exit(2);
        }
        // --daemon-stats [--since-hours H]: what the daemon recorded per compile (hit rate, paths, wall time, memory).
        let mut since_ms = 0u64;
        let mut rest = arguments.iter().skip(1);
        while let Some(argument) = rest.next() {
            match (argument.as_str(), rest.next().and_then(|value| value.parse::<f64>().ok())) {
                ("--since-hours", Some(hours)) if hours >= 0.0 => {
                    let now = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map_or(0, |d| d.as_millis() as u64);
                    since_ms = now.saturating_sub((hours * 3_600_000.0) as u64);
                }
                _ => {
                    eprintln!("usage: dmbc --daemon-stats [--since-hours H]");
                    std::process::exit(2);
                }
            }
        }
        let directory = dmbc::daemon::resident::state_dir();
        let records = dmbc::compile_stats::load(&directory);
        println!("compile statistics from {}", dmbc::compile_stats::stats_path(&directory).display());
        print!("{}", dmbc::compile_stats::summary(&records, since_ms));
        return;
    }
    if arguments.first().map(String::as_str) == Some("--cache-gc") {
        // One pass of the shared per-file cache's size and age caps (tools/dq_cache_prune.sh); a running daemon runs the same pass.
        println!("{}", dmbc::daemon::cache_gc_once());
        return;
    }
    if arguments.first().map(String::as_str) == Some("--daemon-retire") {
        if arguments.len() != 1 || compile_result.is_some() {
            eprintln!("--daemon-retire accepts no other arguments");
            std::process::exit(2);
        }
        if std::env::var_os("DMB_DAEMON_NAMESPACE").is_none() {
            eprintln!("--daemon-retire requires DMB_DAEMON_NAMESPACE; it never retires the shared default daemon");
            std::process::exit(2);
        }
        match dmbc::daemon::retire_namespace() {
            Ok(true) => println!("retiring"),
            Ok(false) => println!("absent"),
            Err(error) => {
                eprintln!("native daemon retire: {error}");
                std::process::exit(1);
            }
        }
        return;
    }
    if arguments.first().map(String::as_str) == Some("acquire") {
        if let Err(error) = dmbc::output_cli::acquire(&arguments) {
            eprintln!("{error}");
            std::process::exit(1);
        }
        return;
    }
    if arguments.first().map(String::as_str) == Some("query") {
        let result = dmbc::cli::parse(&arguments).and_then(|command| match command {
            dmbc::request::Command::Query { request, jsonl } => {
                dmbc::daemon::query::run_file(&request, jsonl)
            }
            dmbc::request::Command::QueryExport { request, limits } => {
                dmbc::daemon::query::semantic_client::run_export_file(&request, limits)
            }
            _ => Err("invalid query command".into()),
        });
        if let Err(error) = result {
            eprintln!("{error}");
            std::process::exit(dmbc::request_failure::exit_code(error.as_ref()));
        }
        return;
    }
    if arguments == ["--serve-daemon"] {
        if let Err(error) = dmbc::daemon::serve() {
            eprintln!("native daemon: {error}");
            std::process::exit(1);
        }
        return;
    }
    // Remote builds precede local profiler setup: process counters belong to the
    // process doing the compilation, not this waiting client.
    if !arguments.iter().any(|argument| argument == "--trace") {
        if let Ok(dmbc::request::Command::Build(request)) = dmbc::cli::parse(&arguments) {
            if !request.no_daemon {
                let result = dmbc::daemon::route(*request).and_then(|outcome| {
                    dmbc::output_cli::finish_command(
                        compile_result.as_deref(),
                        dmbc::request::CommandOutcome::Build(outcome),
                    )
                });
                if let Err(error) = result {
                    report_failure(error.as_ref());
                }
                return;
            }
        }
    }

    if arguments.iter().any(|arg| arg == "--verify") {
        if let Err(error) = dmbc::verification::run_cli(&arguments) {
            eprintln!("{error}");
            std::process::exit(1);
        }
        return;
    }
    let trace_path = arguments
        .windows(2)
        .find(|pair| pair[0] == "--trace")
        .map(|pair| PathBuf::from(&pair[1]));
    let profile = match trace_path
        .as_deref()
        .map(dm_profile::initialize)
        .transpose()
    {
        Ok(profile) => profile,
        Err(error) => {
            eprintln!("native profile initialization failed: {error}");
            std::process::exit(1);
        }
    };
    let parse_profile = dm_profile::stage("cli.parse");
    let command = dmbc::cli::parse(&arguments);
    drop(parse_profile);
    let result = command
        .and_then(dmbc::request_runner::run)
        .and_then(|outcome| dmbc::output_cli::finish_command(compile_result.as_deref(), outcome));
    if let Some(profile) = profile {
        let finished = dmbc::profile_host::finish(profile, result.is_ok());
        if let Err(error) = finished {
            eprintln!("native profile finalization failed: {error}");
            std::process::exit(1);
        }
    }
    if let Err(error) = result {
        report_failure(error.as_ref());
    }
}
/// A source failure whose diagnostics and summary were already printed carries
/// an empty message; print only what the user has not seen yet.
fn report_failure(error: &(dyn std::error::Error + 'static)) -> ! {
    let message = error.to_string();
    if !message.is_empty() {
        eprintln!("{message}");
    }
    dmbc::cache_maintenance::finish_process();
    std::process::exit(dmbc::request_failure::exit_code(error));
}
