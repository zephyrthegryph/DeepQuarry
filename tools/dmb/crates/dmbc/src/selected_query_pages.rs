//! Bound query working sets without adding a second semantic producer.
use super::*;

pub enum VisitFailure<E> {
    Admission(Vec<LoweringDiagnostic>),
    Visitor(E),
}

/// Emit source-ordered results in bounded pages. The callback may stop output
/// or cancel the request; a page is dropped before the next page is lowered.
/// Persistent memo residency is managed by its existing independent budget.
#[allow(clippy::too_many_arguments)]
pub fn visit<'frontend, R: Resolver, P: AbiPolicy, E>(
    frontend: &'frontend ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup<'frontend>,
    memo: &crate::lowering_memo::ProcedureMemo,
    execution: LoweringExecution<'_, 'frontend>,
    page_size: usize,
    mut visitor: impl FnMut(&CurrentProcedureReferences) -> Result<(), E>,
) -> Result<Vec<LoweringDiagnostic>, VisitFailure<E>> {
    let mut bodies: Vec<_> = execution.selected_bodies.map_or_else(
        || frontend.bodies.iter().collect(),
        |bodies| bodies.to_vec(),
    );
    // Validate the entire request before emitting anything. Duplicates spanning
    // page boundaries must not bypass current issuance or execute twice.
    let mut seen = std::collections::BTreeSet::new();
    for body in &bodies {
        if frontend.body_input(body).is_err() || !seen.insert(body.declaration.0) {
            return Err(VisitFailure::Admission(vec![diagnostic(
                body,
                "query requires unique current body issuance",
            )]));
        }
    }
    bodies.sort_by_key(|body| {
        (
            body.source.encounter_ordinal,
            body.expanded_span.start,
            body.declaration.0,
        )
    });
    let mut diagnostics = Vec::new();
    for page in bodies.chunks(page_size.clamp(1, 256)) {
        let batch = query_partial(
            frontend,
            host,
            policy,
            config,
            startup,
            memo,
            LoweringExecution::new(execution.executor, execution.bodies).with_selected_bodies(page),
        )
        .map_err(VisitFailure::Admission)?;
        for unit in &batch.units {
            visitor(unit).map_err(VisitFailure::Visitor)?;
        }
        diagnostics.extend(batch.diagnostics);
    }
    Ok(diagnostics)
}
