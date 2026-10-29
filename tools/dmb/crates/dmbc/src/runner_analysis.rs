//! Explicit analysis and retained body queries share actual issued preparation owners.
use super::*;
#[allow(clippy::too_many_arguments)]
pub(super) fn finish(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine_capture: Option<&Arc<crate::runner_host::RetainedEngine>>,
    host_facts: Option<&runner_facts::RetainedHostFacts>,
    executor: &dm_exec::BuildExecutor,
    procedure_memo: Option<&crate::lowering_memo::ProcedureMemo>,
    memo_policy: u128,
    command: BuildCommand,
    query_attempt: &mut crate::runner_host::query_snapshot::QueryAttempt,
    total: Instant,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    let mut output = io::BufWriter::new(crate::daemon::stdout_writer());
    crate::daemon::control::checkpoint()?;
    let counts = dm_analysis::tree_export::write_jsonl(&frontend, &mut output)?;
    if command == BuildCommand::AnalyzeResolved {
        let retained_engine = engine_capture.ok_or("resolved analysis requires pinned engine")?;
        let (resolver, _scalar) =
            runner_facts::prepare_retained(&frontend, retained_engine, host_facts)?;
        crate::daemon::control::checkpoint()?;
        let links = retained_engine.link_overlay()?;
        let fallback_memo = crate::lowering_memo::ProcedureMemo::new(memo_policy);
        let memo = procedure_memo.unwrap_or(&fallback_memo);
        let mut owners = None;
        let procedures = crate::analysis_export::write_resolved_selected_with_owners(
            &frontend,
            &retained_engine.snapshot,
            &resolver,
            &links.inventory.spellings,
            executor,
            memo,
            &mut output,
            None,
            |procedure| query_attempt.capture_selected(&frontend, procedure),
            |abi, startup| {
                owners = Some((Arc::clone(abi), startup));
                Ok(())
            },
        )?;
        if let Some((abi, startup)) = owners {
            query_attempt.capture_analysis_host(frontend, resolver, abi, startup)?;
        }
        crate::daemon_eprintln!("resolved executable analysis: {procedures} issued procedures; selected-reference coverage remains partial");
    }
    if command == BuildCommand::AnalyzeBodies {
        let bodies = crate::analysis_export::write_bodies(&frontend, &mut output)?;
        crate::daemon_eprintln!(
            "source executable analysis: {bodies} issued bodies; semantic gaps remain explicit"
        );
    }
    output.flush()?;
    let timings = &frontend.timings;
    crate::daemon_eprintln!(
        "source analysis: {} semantic, {} occurrence, {} body rows; planning={:.3}s expansion={:.3}s declarations={:.3}s tree={:.3}s provenance={:.3}s total={:.3}s",
        counts.semantic_rows,
        counts.occurrence_rows,
        counts.body_rows,
        timings.directive_planning.as_secs_f64(),
        timings.expansion.as_secs_f64(),
        timings.declaration_parsing.as_secs_f64(),
        timings.tree_resolution.as_secs_f64(),
        timings.provenance_and_body_indexing.as_secs_f64(),
        timings.total.as_secs_f64(),
    );
    // Partial exports do not certify a compile session. The runner admits the
    // staged original source closure before marking this query frame current.
    Ok(BuildOutcome::Analyzed {
        semantic_rows: counts.semantic_rows,
        occurrence_rows: counts.occurrence_rows,
        body_rows: counts.body_rows,
        seconds: total.elapsed().as_secs_f64(),
    })
}

/// Test fixtures use the original unobserved preparation contract.
#[cfg(test)]
#[allow(clippy::too_many_arguments)]
pub(crate) fn prepare_query(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine_capture: Option<&Arc<crate::runner_host::RetainedEngine>>,
    host_facts: Option<&runner_facts::RetainedHostFacts>,
    executor: &dm_exec::BuildExecutor,
    procedure_memo: Option<&crate::lowering_memo::ProcedureMemo>,
    memo_policy: u128,
    query_attempt: &mut crate::runner_host::query_snapshot::QueryAttempt,
    retained: bool,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    prepare_query_observed(
        frontend,
        engine_capture,
        host_facts,
        executor,
        procedure_memo,
        memo_policy,
        query_attempt,
        retained,
        false,
    )
}

/// Explicit preparation carries the ordinary BuildRequest source configuration.
/// It emits no model and never lowers procedures or publishes executable artifacts.
#[allow(clippy::too_many_arguments)]
pub(crate) fn prepare_query_observed(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine_capture: Option<&Arc<crate::runner_host::RetainedEngine>>,
    host_facts: Option<&runner_facts::RetainedHostFacts>,
    executor: &dm_exec::BuildExecutor,
    procedure_memo: Option<&crate::lowering_memo::ProcedureMemo>,
    memo_policy: u128,
    query_attempt: &mut crate::runner_host::query_snapshot::QueryAttempt,
    retained: bool,
    progress_enabled: bool,
) -> Result<BuildOutcome, Box<dyn std::error::Error>> {
    crate::daemon::control::checkpoint()?;
    let engine = engine_capture.ok_or("query preparation requires pinned engine")?;
    let (resolver, _) = runner_facts::prepare_retained(frontend, engine, host_facts)?;
    let links = engine.link_overlay()?;
    let fallback = crate::lowering_memo::ProcedureMemo::new(memo_policy);
    let memo = procedure_memo.unwrap_or(&fallback);
    let bodies = dm_tree::frontend::BodyArena::new_typed(
        frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let report = |name: &'static str, started: bool, elapsed: std::time::Duration| {
        if started {
            crate::daemon_eprintln!("native stage {name}: started");
        } else {
            crate::daemon_eprintln!("native stage {name}: {:.3}s", elapsed.as_secs_f64());
        }
    };
    let (startup, prepared) = crate::analysis_export::prepare_query_owners_observed(
        frontend,
        &engine.snapshot,
        &resolver,
        &links.inventory.spellings,
        executor,
        memo,
        &bodies,
        progress_enabled.then_some(&report as &dyn Fn(&'static str, bool, std::time::Duration)),
    )?;
    if !prepared.prepared.diagnostics.is_empty() {
        let diagnostics = crate::driver_facts::abi_diagnostics(frontend, &prepared.prepared)?;
        crate::diagnostics::write_lowering_diagnostics(
            &mut crate::daemon::stderr_writer(),
            &diagnostics,
        )?;
        return Err(crate::request_failure::RequestFailure {
            kind: crate::diagnostics::failure_kind(
                diagnostics.iter().map(|diagnostic| diagnostic.kind),
            ),
            message: "query preparation requires complete current ABI owners".into(),
        }
        .into());
    }
    query_attempt.capture_analysis_host(
        frontend,
        resolver,
        Arc::clone(prepared.prepared.units_owner()),
        startup.facts(),
    )?;
    Ok(BuildOutcome::QueryPrepared {
        semantic_revision: format!("{:032x}", frontend.snapshot.tree.identity()),
        source_revision: format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(frontend)
        ),
        policy_revision: query_attempt
            .policy_revision()
            .map(|pin| format!("{pin:032x}")),
        retained,
    })
}
