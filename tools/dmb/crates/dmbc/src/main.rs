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
    if std::panic::catch_unwind(main_inner).is_err() {
        eprintln!("internal compiler panic");
        std::process::exit(70);
    }
}
fn main_inner() {
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
                    eprintln!("{error}");
                    std::process::exit(dmbc::request_failure::exit_code(error.as_ref()));
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
        eprintln!("{error}");
        std::process::exit(dmbc::request_failure::exit_code(error.as_ref()));
    }
}
