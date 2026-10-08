//! Native compilation over captured inputs, with disposable validated disk memos.
use std::path::PathBuf;

#[cfg(feature = "allocation-counting")]
#[global_allocator]
static ALLOCATOR: dm_profile::CountingAllocator = dm_profile::CountingAllocator;

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
    let result = dmbc::cli::parse(&arguments).and_then(dmbc::request_runner::run);
    if let Some(profile) = profile {
        let sequential_stages: &[&str] = if result.is_ok()
            && profile.has_stage("session_validation")
            && !profile.has_stage("engine_capture")
        {
            &["engine_input", "session_validation"]
        } else {
            &[
                "engine_input",
                "engine_capture",
                "session_validation",
                "input_scan",
                "frontend.directive_planning",
                "frontend.expansion",
                "frontend.source_indexing",
                "frontend.declaration_parsing",
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
            ]
        };
        if let Err(error) = profile.finish(sequential_stages) {
            eprintln!("native profile finalization failed: {error}");
            std::process::exit(1);
        }
    }
    if let Err(error) = result {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
