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
    let arguments: Vec<String> = std::env::args().skip(1).collect();
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
        let sequential_stages: &[&str] = if result.is_ok()
            && profile.has_stage("session_validation")
            && !profile.has_stage("engine_capture")
        {
            &[
                "profile.setup",
                "cli.parse",
                "exclusive:build",
                "exclusive:request.prepare",
                "exclusive:request.input_context",
                "engine_input",
                "session_validation",
                "profile.finalization",
            ]
        } else {
            &[
                "profile.setup",
                "cli.parse",
                "exclusive:build",
                "exclusive:request.prepare",
                "exclusive:request.input_context",
                "exclusive:request.frontend_context",
                "exclusive:request.source_context",
                "exclusive:request.frontend_handoff",
                "exclusive:request.nontext_context",
                "exclusive:request.compilation",
                "exclusive:request.finalization",
                "exclusive:frontend",
                "engine_input",
                "engine_capture",
                "session_validation",
                "input_scan",
                "frontend.directive_planning",
                "frontend.expansion",
                "frontend.source_indexing",
                "frontend.grammar_scan",
                "exclusive:frontend.declaration_parsing",
                "frontend.ordered_declaration_merge",
                "frontend.declaration_origins",
                "frontend.tree_resolution",
                "frontend.body_indexing",
                "captured_facts",
                "resources_maps",
                "linking_inputs",
                "cold.startup_capture",
                "cold.abi_preparation",
                "cold.initializers",
                "cold.procedure_lowering",
                "cold.required_type_admission",
                "cold.symbolic_linking",
                "cold.composition",
                "cache_flush",
                "publication",
                "profile.finalization",
            ]
        };
        let present: Vec<_> = sequential_stages
            .iter()
            .copied()
            .filter(|name| {
                *name == "profile.finalization"
                    || profile.has_stage(name.strip_prefix("exclusive:").unwrap_or(name))
            })
            .collect();
        if let Err(error) = profile.finish(&present) {
            eprintln!("native profile finalization failed: {error}");
            std::process::exit(1);
        }
    }
    if let Err(error) = result {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
