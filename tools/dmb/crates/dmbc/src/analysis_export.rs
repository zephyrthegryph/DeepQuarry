//! Explicit executable analysis over the same current issued bodies as lowering.
use dm_tree::frontend::{BodyArena, ColdFrontend};
use std::io::Write;
#[derive(Default)]
struct CoverageTotals {
    requested: usize,
    returned: usize,
    unbound_selections: usize,
    unavailable_coordinate_markers: usize,
}
#[cfg(test)]
#[path = "analysis_export_coverage_tests.rs"]
mod coverage_tests;
impl CoverageTotals {
    fn returned(&mut self, unbound: usize, unavailable: usize) -> std::io::Result<()> {
        let add = |left: usize, right: usize| {
            left.checked_add(right)
                .ok_or_else(|| std::io::Error::other("resolved coverage counter overflow"))
        };
        self.returned = add(self.returned, 1)?;
        self.unbound_selections = add(self.unbound_selections, unbound)?;
        self.unavailable_coordinate_markers =
            add(self.unavailable_coordinate_markers, unavailable)?;
        Ok(())
    }
}
/// Query the ordinary compiler producer against current pinned host facts.
/// This emits selected references, never a whole-program completeness claim.
#[cfg(test)]
pub(crate) fn write_resolved<R: dm_ir::Resolver>(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine: &crate::engine::EngineSnapshot,
    resolver: &R,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    memo: &crate::lowering_memo::ProcedureMemo,
    writer: &mut impl Write,
) -> Result<usize, Box<dyn std::error::Error>> {
    write_resolved_observed(
        frontend,
        engine,
        resolver,
        spellings,
        executor,
        memo,
        writer,
        |_| Ok(()),
    )
}
#[cfg(test)]
#[allow(clippy::too_many_arguments)]
pub(crate) fn write_resolved_observed<R: dm_ir::Resolver>(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine: &crate::engine::EngineSnapshot,
    resolver: &R,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    memo: &crate::lowering_memo::ProcedureMemo,
    writer: &mut impl Write,
    observe: impl FnMut(&crate::selected_query::CurrentProcedureReferences) -> std::io::Result<()>,
) -> Result<usize, Box<dyn std::error::Error>> {
    write_resolved_selected(
        frontend, engine, resolver, spellings, executor, memo, writer, None, observe,
    )
}
#[allow(clippy::too_many_arguments)]
pub(crate) fn write_resolved_selected<R: dm_ir::Resolver>(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine: &crate::engine::EngineSnapshot,
    resolver: &R,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    memo: &crate::lowering_memo::ProcedureMemo,
    writer: &mut impl Write,
    selected: Option<&[&dm_tree::frontend::BodyOccurrence]>,
    observe: impl FnMut(&crate::selected_query::CurrentProcedureReferences) -> std::io::Result<()>,
) -> Result<usize, Box<dyn std::error::Error>> {
    write_resolved_selected_with_owners(
        frontend,
        engine,
        resolver,
        spellings,
        executor,
        memo,
        writer,
        selected,
        observe,
        |_, _| Ok(()),
    )
}
/// Transfer only actual immutable preparation owners after successful analysis.
#[allow(clippy::too_many_arguments)]
pub(crate) fn write_resolved_selected_with_owners<R: dm_ir::Resolver>(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine: &crate::engine::EngineSnapshot,
    resolver: &R,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    memo: &crate::lowering_memo::ProcedureMemo,
    writer: &mut impl Write,
    selected: Option<&[&dm_tree::frontend::BodyOccurrence]>,
    mut observe: impl FnMut(&crate::selected_query::CurrentProcedureReferences) -> std::io::Result<()>,
    mut capture: impl FnMut(
        &std::sync::Arc<crate::driver_facts::PreparedAbiUnits>,
        std::sync::Arc<crate::startup::StartupFacts>,
    ) -> std::io::Result<()>,
) -> Result<usize, Box<dyn std::error::Error>> {
    let mut totals = CoverageTotals {
        requested: selected.map_or(frontend.bodies.len(), |bodies| bodies.len()),
        ..Default::default()
    };
    crate::daemon::control::checkpoint()?;
    let bodies = BodyArena::new_typed(
        frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let startup = crate::startup::capture_revision_facts_with_executor_and_bodies_and_artifacts(
        frontend,
        spellings,
        executor,
        &bodies,
        memo.startup.as_deref(),
    )?;
    let startup = startup.view_revision(frontend)?;
    crate::daemon::control::checkpoint()?;
    let prepared =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            frontend,
            engine,
            resolver,
            &startup,
            None,
            executor,
            memo.abi.as_deref(),
        )?;
    crate::daemon::control::checkpoint()?;
    if !prepared.prepared.diagnostics.is_empty() {
        let diagnostics = crate::driver_facts::abi_diagnostics(frontend, &prepared.prepared)?;
        write_diagnostics(&diagnostics, writer)?;
        coverage(
            writer,
            &totals,
            diagnostics.len(),
            "ABI preparation incomplete",
        )?;
        reject_errors(&diagnostics, writer)?;
        return Ok(0);
    }
    let policy = crate::driver_facts::FrozenPreparedPolicy::new_with_units(
        frontend,
        &prepared.prepared,
        std::sync::Arc::clone(startup.unit_members()),
    )?;
    let diagnostics = match crate::selected_query::visit(
        frontend,
        resolver,
        &policy,
        crate::lowering::LoweringConfig {
            workers: executor.workers(),
            ..Default::default()
        },
        &startup,
        memo,
        match selected {
            Some(selected) => crate::lowering::LoweringExecution::new(executor, &bodies)
                .with_selected_bodies(selected),
            None => crate::lowering::LoweringExecution::new(executor, &bodies),
        },
        64,
        |procedure| -> Result<(), Box<dyn std::error::Error>> {
            crate::daemon::control::checkpoint()?;
            procedure.write_jsonl(writer)?;
            observe(procedure)?;
            totals.returned(
                procedure.unbound_selections(),
                procedure.unavailable_coordinates(),
            )?;
            Ok(())
        },
    ) {
        Ok(diagnostics) => diagnostics,
        Err(crate::selected_query::VisitFailure::Visitor(error)) => return Err(error),
        Err(crate::selected_query::VisitFailure::Admission(diagnostics)) => {
            crate::daemon::control::checkpoint()?;
            write_diagnostics(&diagnostics, writer)?;
            writer.flush()?;
            return Err(crate::request_failure::RequestFailure::internal(
                "selected query issuance or binding failed",
            )
            .into());
        }
    };
    crate::daemon::control::checkpoint()?;
    write_diagnostics(&diagnostics, writer)?;
    coverage(
        writer,
        &totals,
        diagnostics.len(),
        "compiler-selected reference subset; unsupported and unbound selections remain explicit",
    )?;
    reject_errors(&diagnostics, writer)?;
    capture(prepared.prepared.units_owner(), startup.facts())?;
    Ok(totals.returned)
}
fn reject_errors(
    diagnostics: &[crate::lowering::LoweringDiagnostic],
    writer: &mut impl Write,
) -> Result<(), Box<dyn std::error::Error>> {
    use dm_tree::frontend::DiagnosticKind;
    if diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == DiagnosticKind::Internal)
    {
        writer.flush()?;
        return Err(crate::request_failure::RequestFailure::internal(
            "resolved analysis encountered an internal error",
        )
        .into());
    }
    if diagnostics
        .iter()
        .any(|diagnostic| diagnostic.kind == DiagnosticKind::SourceError)
    {
        writer.flush()?;
        return Err(crate::request_failure::RequestFailure::source(
            "resolved analysis encountered a source error",
        )
        .into());
    }
    Ok(())
}
fn write_diagnostics(
    diagnostics: &[crate::lowering::LoweringDiagnostic],
    writer: &mut impl Write,
) -> Result<(), Box<dyn std::error::Error>> {
    for diagnostic in diagnostics {
        serde_json::to_writer(
            &mut *writer,
            &serde_json::json!({
                "schema":"dm-selected-reference-analysis-v1", "row":"diagnostic",
                "semantic_resolution_complete":false,
                "kind":format!("{:?}", diagnostic.kind),
                "identity":diagnostic.identity.map(|identity| format!("{identity:?}")),
                "path":diagnostic.origin.path.to_string_lossy(),
                "line":diagnostic.origin.line, "message":diagnostic.message,
            }),
        )?;
        writer.write_all(b"\n")?;
    }
    Ok(())
}
fn coverage(
    writer: &mut impl Write,
    totals: &CoverageTotals,
    diagnostics: usize,
    reason: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let omitted = totals
        .requested
        .checked_sub(totals.returned)
        .ok_or("resolved query returned more procedures than requested")?;
    serde_json::to_writer(
        &mut *writer,
        &serde_json::json!({
            "schema":"dm-selected-reference-analysis-v1", "row":"coverage",
            "semantic_resolution_complete":false,
            "procedures":totals.returned,"diagnostics":diagnostics,"reason":reason,
            "requested_procedures":totals.requested,
            "returned_procedures":totals.returned,
            "omitted_procedures":omitted,
            "unbound_selections":totals.unbound_selections,
            // Missing producer facts contribute one marker; this is not a
            // claim to know the number of selections in an uncaptured body.
            "unavailable_coordinate_markers":totals.unavailable_coordinate_markers,
        }),
    )?;
    writer.write_all(b"\n")?;
    Ok(())
}
pub(crate) fn write_bodies(
    frontend: &ColdFrontend,
    writer: &mut impl Write,
) -> Result<usize, Box<dyn std::error::Error>> {
    let arena = BodyArena::new_typed(frontend, |_| true);
    let mut count = 0;
    for occurrence in frontend.bodies.iter() {
        crate::daemon::control::checkpoint()?;
        let body = arena
            .take_parsed(occurrence)
            .map_err(|error| error.message)?;
        match dm_analysis::typed_body_jsonl::write_jsonl(&body, writer) {
            Ok(_) => (),
            Err(dm_analysis::typed_body_jsonl::ExportError::NoTypedModel(error)) => {
                serde_json::to_writer(
                    &mut *writer,
                    &serde_json::json!({
                        "schema": dm_analysis::typed_body_jsonl::SCHEMA,
                        "row":"unsupported_body", "member":occurrence.member.0,
                        "declaration":occurrence.declaration.0,
                        "semantic_resolution_complete":false,"reason":error.to_string()
                    }),
                )?;
                writer.write_all(b"\n")?;
            }
            Err(error) => return Err(error.into()),
        }
        match dm_analysis::typed_body::lexical::analyze(frontend, &body, None) {
            Ok(lexical) => {
                dm_analysis::typed_body::lexical::jsonl::write_jsonl(&lexical, writer)?;
            }
            Err(error) => {
                serde_json::to_writer(
                    &mut *writer,
                    &serde_json::json!({
                        "schema":"dm-lexical-body-analysis-v1", "row":"unsupported_body",
                        "member":occurrence.member.0,"declaration":occurrence.declaration.0,
                        "semantic_resolution_complete":false,"reason":error.to_string()
                    }),
                )?;
                writer.write_all(b"\n")?;
            }
        }
        count += 1;
    }
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/x/proc/first(x)\n    var/y = x\n    return y\n/datum/x/proc/second(z)\n    return z\n".into())
        }
    }
    #[test]
    fn exports_each_current_body_with_explicit_resolution_status() {
        let frontend =
            dm_tree::frontend::build(Path::new("project.dme"), &Source, &Default::default(), 1)
                .unwrap();
        let mut bytes = Vec::new();
        assert_eq!(write_bodies(&frontend, &mut bytes).unwrap(), 2);
        let rows: Vec<serde_json::Value> = std::str::from_utf8(&bytes)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert!(rows
            .iter()
            .any(|row| row["schema"] == "dm-lexical-body-analysis-v1"));
        assert!(rows
            .iter()
            .filter(|row| row["schema"] == "dm-lexical-body-analysis-v1")
            .all(|row| row["semantic_resolution_complete"] != true));
    }
}
