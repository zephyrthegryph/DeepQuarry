//! Profile finalization shared by command-line and retained request hosts.
//! Process counter certification remains serialized by the profiler.

pub fn finish(
    profile: dm_profile::ProfileGuard,
    build_succeeded: bool,
) -> Result<dm_profile::Report, String> {
    let sequential_stages: &[&str] = if build_succeeded
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
    match std::env::var("DMB_PROFILE_STAGE_MAP_JSON") {
        Ok(json) => serde_json::from_str::<dm_profile::StageMap>(&json)
            .map_err(|error| format!("invalid profile stage map JSON: {error}"))
            .and_then(|map| profile.finish_with_stage_map(&present, &map)),
        Err(std::env::VarError::NotPresent) => profile.finish(&present),
        Err(error) => Err(format!("invalid profile stage map environment: {error}")),
    }
}
