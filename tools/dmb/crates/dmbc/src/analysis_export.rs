//! Explicit executable analysis over the same current issued bodies as lowering.
use dm_tree::frontend::{BodyArena, ColdFrontend};
use std::io::Write;
/// Query the ordinary compiler producer against current pinned host facts.
/// This emits selected references, never a whole-program completeness claim.
pub(crate) fn write_resolved<R: dm_ir::Resolver>(
    frontend: &dm_tree::frontend::FrontendRevision,
    engine: &crate::engine::EngineSnapshot,
    resolver: &R,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    memo: &crate::lowering_memo::ProcedureMemo,
    writer: &mut impl Write,
) -> Result<usize, Box<dyn std::error::Error>> {
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
    if !prepared.prepared.diagnostics.is_empty() {
        let diagnostics = crate::driver_facts::abi_diagnostics(frontend, &prepared.prepared)?;
        write_diagnostics(&diagnostics, writer)?;
        coverage(writer, 0, diagnostics.len(), "ABI preparation incomplete")?;
        reject_errors(&diagnostics, writer)?;
        return Ok(0);
    }
    let policy = crate::driver_facts::FrozenPreparedPolicy::new_with_units(
        frontend,
        &prepared.prepared,
        std::sync::Arc::clone(startup.unit_members()),
    )?;
    let batch = match crate::selected_query::query_partial(
        frontend,
        resolver,
        &policy,
        crate::lowering::LoweringConfig {
            workers: executor.workers(),
            ..Default::default()
        },
        &startup,
        memo,
        crate::lowering::LoweringExecution::new(executor, &bodies),
    ) {
        Ok(batch) => batch,
        Err(diagnostics) => {
            write_diagnostics(&diagnostics, writer)?;
            writer.flush()?;
            return Err(crate::request_failure::RequestFailure::internal(
                "selected query issuance or binding failed",
            )
            .into());
        }
    };
    for procedure in &batch.units {
        procedure.write_jsonl(writer)?;
    }
    write_diagnostics(&batch.diagnostics, writer)?;
    coverage(
        writer,
        batch.units.len(),
        batch.diagnostics.len(),
        "compiler-selected reference subset; unsupported and unbound selections remain explicit",
    )?;
    reject_errors(&batch.diagnostics, writer)?;
    Ok(batch.units.len())
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
    procedures: usize,
    diagnostics: usize,
    reason: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    serde_json::to_writer(
        &mut *writer,
        &serde_json::json!({
            "schema":"dm-selected-reference-analysis-v1", "row":"coverage",
            "semantic_resolution_complete":false,
            "procedures":procedures,"diagnostics":diagnostics,"reason":reason,
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
