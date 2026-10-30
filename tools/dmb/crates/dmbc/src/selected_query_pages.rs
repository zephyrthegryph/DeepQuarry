//! Bound query working sets without adding a second semantic producer.
use super::*;

pub enum VisitFailure<E> {
    Admission(Vec<LoweringDiagnostic>),
    Visitor(E),
}

pub enum CheckedVisitFailure<E> {
    Admission(Vec<LoweringDiagnostic>),
    Operational(std::io::Error),
    Visitor(E),
}
enum PageFailure<E,F> {Admission(F),Visitor(E)}

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
    visitor: impl FnMut(&CurrentProcedureReferences) -> Result<(), E>,
) -> Result<Vec<LoweringDiagnostic>, VisitFailure<E>> {
    visit_with::<CompatibilitySelection,_,_,_>(frontend,host,policy,config,startup,memo,execution,page_size,visitor).map_err(|error|match error{
        PageFailure::Admission(errors)=>VisitFailure::Admission(errors),
        PageFailure::Visitor(error)=>VisitFailure::Visitor(error),
    })
}
#[allow(clippy::too_many_arguments)]
pub fn visit_checked<'frontend, R: Resolver, P: AbiPolicy, E>(
    frontend: &'frontend ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup<'frontend>,
    memo: &crate::lowering_memo::ProcedureMemo,
    execution: LoweringExecution<'_, 'frontend>,
    page_size: usize,
    visitor: impl FnMut(&CurrentProcedureReferences) -> Result<(), E>,
) -> Result<Vec<LoweringDiagnostic>, CheckedVisitFailure<E>> {
    crate::daemon::control::checkpoint().map_err(CheckedVisitFailure::Operational)?;
    let result=visit_with::<CheckedSelection,_,_,_>(frontend,host,policy,config,startup,memo,execution,page_size,visitor).map_err(|error|match error{
        PageFailure::Admission(lowering::LoweringFailure::Diagnostics(errors))=>CheckedVisitFailure::Admission(errors),
        PageFailure::Admission(lowering::LoweringFailure::Operational(error))=>CheckedVisitFailure::Operational(error),
        PageFailure::Visitor(error)=>CheckedVisitFailure::Visitor(error),
    })?;
    crate::daemon::control::checkpoint().map_err(CheckedVisitFailure::Operational)?;
    Ok(result)
}
#[allow(clippy::too_many_arguments)]
fn visit_with<'frontend,D:SelectionDemand,R: Resolver, P: AbiPolicy, E>(
    frontend: &'frontend ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup<'frontend>,
    memo: &crate::lowering_memo::ProcedureMemo,
    execution: LoweringExecution<'_, 'frontend>,
    page_size: usize,
    mut visitor: impl FnMut(&CurrentProcedureReferences) -> Result<(), E>,
) -> Result<Vec<LoweringDiagnostic>, PageFailure<E,D::Failure>> {
    let mut bodies: Vec<_> = execution.selected_bodies.map_or_else(
        || frontend.bodies.iter().collect(),
        |bodies| bodies.to_vec(),
    );
    // Validate the entire request before emitting anything. Duplicates spanning
    // page boundaries must not bypass current issuance or execute twice.
    let mut seen = std::collections::BTreeSet::new();
    for body in &bodies {
        if frontend.body_input(body).is_err() || !seen.insert(body.declaration.0) {
            return Err(PageFailure::Admission(vec![diagnostic(
                body,
                "query requires unique current body issuance",
)].into()));
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
        let batch = query_partial_with::<D,R,P>(
            frontend,
            host,
            policy,
            config,
            startup,
            memo,
            LoweringExecution::new(execution.executor, execution.bodies).with_selected_bodies(page),
        )
        .map_err(PageFailure::Admission)?;
        for unit in &batch.units {
            visitor(unit).map_err(PageFailure::Visitor)?;
        }
        diagnostics.extend(batch.diagnostics);
    }
    Ok(diagnostics)
}
