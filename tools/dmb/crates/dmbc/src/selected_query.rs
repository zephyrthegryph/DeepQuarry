//! Current executable queries use the compiler producer and its exact memo admission.
//! No independently resolved tree, persisted absolute coordinates, or full-program
//! output certificate is manufactured by this API.
use crate::lowering::{
    self, AbiPolicy, LoweringConfig, LoweringDiagnostic, LoweringExecution, UnitIdentity,
};
use dm_ir::{Resolver, SelectedMeaning, SymbolId};
use dm_tree::frontend::{BodyOccurrence, ColdFrontend, DiagnosticKind, SourceLocation};
#[path = "selected_query_pages.rs"]
mod pages;
pub use pages::{visit, VisitFailure};

pub struct CurrentReference {
    pub name: SymbolId,
    pub meaning: SelectedMeaning,
    pub path: Vec<dm_syntax::NodeStep>,
    pub source: SourceLocation,
    pub expanded_span: std::ops::Range<usize>,
}

/// Issued only by the current lowering query. Missing facts never mean unresolved.
pub struct CurrentProcedureReferences {
    identity: UnitIdentity,
    declaration: dm_tree::frontend::BodyOccurrence,
    references: Vec<CurrentReference>,
    unavailable_coordinates: usize,
    unbound_selections: usize,
}
impl CurrentProcedureReferences {
    pub fn identity(&self) -> UnitIdentity {
        self.identity
    }
    pub fn occurrence(&self) -> &BodyOccurrence {
        &self.declaration
    }
    pub fn references(&self) -> &[CurrentReference] {
        &self.references
    }
    pub fn unavailable_coordinates(&self) -> usize {
        self.unavailable_coordinates
    }
    pub fn unbound_selections(&self) -> usize {
        self.unbound_selections
    }
    pub fn complete(&self) -> bool {
        false
    }
    /// Serialize current coordinates without parsing the body a second time.
    pub fn write_jsonl(&self, writer: &mut impl std::io::Write) -> Result<usize, String> {
        use dm_analysis::typed_body::selected::{BoundReference, SelectionCoverage};
        dm_analysis::typed_body::selected::write_bound_jsonl(
            &self.declaration,
            self.references.iter().map(|reference| BoundReference {
                name: reference.name,
                spelling: None,
                meaning: &reference.meaning,
                path: &reference.path,
                source: &reference.source,
                expanded_span: &reference.expanded_span,
            }),
            SelectionCoverage {
                complete: false,
                unavailable_coordinates: self.unavailable_coordinates,
                unbound_selections: self.unbound_selections,
            },
            writer,
        )
    }
}

#[allow(clippy::too_many_arguments)]
pub fn query<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    memo: &crate::lowering_memo::ProcedureMemo,
    execution: LoweringExecution<'_, '_>,
) -> Result<Vec<CurrentProcedureReferences>, Vec<LoweringDiagnostic>> {
    let batch = query_partial(frontend, host, policy, config, startup, memo, execution)?;
    if batch.diagnostics.is_empty() {
        Ok(batch.units)
    } else {
        Err(batch.diagnostics)
    }
}

pub struct QueryBatch {
    pub units: Vec<CurrentProcedureReferences>,
    /// Source, unsupported-model, and internal errors remain separately typed.
    pub diagnostics: Vec<LoweringDiagnostic>,
}

#[allow(clippy::too_many_arguments)]
pub fn query_partial<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    memo: &crate::lowering_memo::ProcedureMemo,
    execution: LoweringExecution<'_, '_>,
) -> Result<QueryBatch, Vec<LoweringDiagnostic>> {
    let selected: Vec<_> = execution.selected_bodies.map_or_else(
        || frontend.bodies.iter().collect(),
        |bodies| bodies.to_vec(),
    );
    let mut current = std::collections::BTreeMap::new();
    for body in selected {
        match lowering::source_unit_identity(frontend, body) {
            Ok(identity) if current.insert(identity.identity, body).is_none() => (),
            _ => {
                return Err(vec![diagnostic(
                    body,
                    "query requires unique current body issuance",
                )])
            }
        }
    }
    let batch = lowering::lower_frontend_with_memo_on_executor_and_bodies(
        frontend,
        host,
        policy,
        config,
        startup,
        memo,
        execution.with_reference_capture(),
    );
    let diagnostics = batch.diagnostics;
    let mut result = Vec::with_capacity(batch.units.len());
    for unit in batch.units {
        let Some(body) = current.remove(&unit.identity) else {
            return Err(vec![LoweringDiagnostic {
                kind: DiagnosticKind::Internal,
                identity: Some(unit.identity),
                origin: unit.origin.source.clone(),
                message: "query producer returned an unissued procedure".into(),
            }]);
        };
        let mut bound = CurrentProcedureReferences {
            identity: unit.identity,
            declaration: body.clone(),
            references: Vec::new(),
            unavailable_coordinates: 0,
            unbound_selections: 0,
        };
        if let Some(facts) = unit.selected_references {
            bound.unbound_selections = facts.unbound_selections;
            for reference in &facts.references {
                let Some((start, end)) = reference.relative_span else {
                    bound.unavailable_coordinates += 1;
                    continue;
                };
                let length = body.expanded_span.end - body.expanded_span.start;
                if start > end || end > length {
                    return Err(vec![diagnostic(
                        body,
                        "admitted reference coordinate exceeds current body",
                    )]);
                }
                let Some(start) = body.expanded_span.start.checked_add(start) else {
                    return Err(vec![diagnostic(body, "reference coordinate overflow")]);
                };
                let Some(end) = body.expanded_span.start.checked_add(end) else {
                    return Err(vec![diagnostic(body, "reference coordinate overflow")]);
                };
                let Some(source) = frontend.location(start) else {
                    return Err(vec![diagnostic(
                        body,
                        "reference has no current source origin",
                    )]);
                };
                bound.references.push(CurrentReference {
                    name: reference.name,
                    meaning: reference.meaning.clone(),
                    path: reference.path.clone(),
                    source,
                    expanded_span: start..end,
                });
            }
        } else {
            bound.unavailable_coordinates = 1;
        }
        result.push(bound);
    }
    if diagnostics.is_empty() && !current.is_empty() {
        return Err(current
            .into_values()
            .map(|body| diagnostic(body, "query producer omitted a requested procedure"))
            .collect());
    }
    Ok(QueryBatch {
        units: result,
        diagnostics,
    })
}

fn diagnostic(body: &BodyOccurrence, message: &str) -> LoweringDiagnostic {
    LoweringDiagnostic {
        kind: DiagnosticKind::Internal,
        identity: None,
        origin: body.source.clone(),
        message: message.into(),
    }
}
