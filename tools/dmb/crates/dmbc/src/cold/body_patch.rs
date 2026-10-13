//! Body-edit fast path (see `crate::body_patch`): lower only the selected
//! bodies, with the same startup, ABI policy, static resolver and completion
//! as the full path, and stop before initializers, required-type admission,
//! linking and composition.
use super::*;

/// Contributions of the selected bodies plus the query owners a full build
/// would have captured for the analysis API.
pub(crate) struct PatchLowering {
    pub contributions: Vec<crate::symbolic::PreparedContribution>,
    pub query: (
        std::sync::Arc<crate::driver_facts::PreparedAbiUnits>,
        std::sync::Arc<crate::startup::StartupFacts>,
    ),
}

/// Mirrors `prepare_captured_classified_with_pinned_abi_memo_revision` up to
/// procedure lowering, restricted to `selected`. Any diagnostic or completion
/// error is returned as an error so the caller falls back to the full path,
/// which reports it exactly as before.
/// The engine and link facts lowering reads (no link inventory is consumed).
pub(crate) struct LinkFacts<'a> {
    pub engine_bytes: &'a [u8],
    pub engine: &'a crate::engine::EngineSnapshot,
    pub references: &'a ReferenceBindings,
    pub spellings: &'a Vec<(dm_ir::SymbolId, std::sync::Arc<[u8]>)>,
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn lower_selected<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    links: LinkFacts<'_>,
    resource_search_context: Option<u128>,
    config: LoweringConfig,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    revision: Option<&dm_tree::frontend::FrontendRevision>,
    executor: &dm_exec::BuildExecutor,
    selected: &[&dm_tree::frontend::BodyOccurrence],
) -> Result<PatchLowering, String> {
    let roster = crate::lowering::PreparedBodyRoster::issue(frontend)
        .map_err(|diagnostics| format!("body roster: {} diagnostics", diagnostics.len()))?;
    let bodies = dm_tree::frontend::BodyArena::new_typed(
        frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let startup = crate::startup::capture_with_prepared_bodies(
        frontend,
        revision,
        links.spellings,
        executor,
        &bodies,
        memo.and_then(|memo| memo.startup.as_deref()),
        &roster,
    )
    .map_err(|error| format!("startup capture: {error:?}"))?;
    dm_profile::request_mark("patch.startup_captured");
    let prepared =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            frontend,
            links.engine,
            resolver,
            &startup,
            resource_search_context,
            executor,
            memo.and_then(|memo| memo.abi.as_deref()),
        )
        .map_err(|error| format!("ABI preparation: {error}"))?;
    if !prepared.prepared.diagnostics.is_empty() {
        return Err("ABI preparation reported diagnostics".into());
    }
    let policy = crate::driver_facts::FrozenPreparedPolicy::new_with_units(
        frontend,
        &prepared.prepared,
        std::sync::Arc::clone(startup.unit_members()),
    )
    .map_err(|error| format!("ABI policy: {error}"))?;
    dm_profile::request_mark("patch.abi_prepared");
    startup.validate_for(frontend)?;
    let captured = frontend.engine.as_ref().ok_or("engine model absent")?;
    if captured.identity != links.engine.identity()
        || !links
            .engine
            .matches_template(links.engine_bytes, links.engine.interpretation_schema())
    {
        return Err("engine differs from captured frontend".into());
    }
    let static_resolver = startup.resolver(frontend, resolver)?;
    let plan = startup.plan();
    let source_bindings = roster
        .source_bindings(frontend)
        .ok_or("current prepared symbolic namespace absent")?;
    let complete = |unit: crate::lowering::CompletedInput| {
        unit.prepare(plan.symbols.as_ref(), source_bindings, links.references, false)
    };
    let batch = crate::lowering::lower_frontend_completed_input_on_execution(
        frontend,
        &static_resolver,
        &policy,
        config,
        Some(&startup),
        None,
        crate::lowering::LoweringExecution::new(executor, &bodies)
            .with_prepared_roster(&roster)
            .with_selected_bodies(selected),
        true,
        &complete,
    );
    dm_profile::request_mark("patch.lowered");
    if !batch.diagnostics.is_empty() {
        return Err(format!(
            "lowering reported {} diagnostics (first: {})",
            batch.diagnostics.len(),
            batch.diagnostics[0].message
        ));
    }
    if let Some((body, error)) = batch.completion_errors.into_iter().next() {
        return Err(format!(
            "completion error at {}:{}: {error:?}",
            body.source.semantic_path, body.source.line
        ));
    }
    if batch.units.len() != selected.len() {
        return Err(format!(
            "lowered {} units for {} selected bodies",
            batch.units.len(),
            selected.len()
        ));
    }
    Ok(PatchLowering {
        contributions: batch.units.into_iter().map(|unit| unit.value).collect(),
        query: (
            std::sync::Arc::clone(prepared.prepared.units_owner()),
            startup.facts(),
        ),
    })
}
