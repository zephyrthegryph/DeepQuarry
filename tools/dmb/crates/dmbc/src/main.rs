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
    let arguments: Vec<String> = std::env::args().skip(1).collect();
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
                if let Err(error) = dmbc::daemon::route(*request) {
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
    let result = command.and_then(dmbc::request_runner::run);
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
