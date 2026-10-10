//! Typed lexical slices for one initializer VM invocation. Scopes change only
//! lexical lookup; code labels, consumed resolver receipts and debug ordinals
//! belong to the single shared compiler accumulator.
use crate::{LowerBindings, LowerError, ProcedureInputs};
use dm_syntax::{Expr, Span, Statement};

pub(crate) struct AssignmentScope<'a> {
    pub inputs: &'a ProcedureInputs,
    pub target: &'a Expr,
    pub value: &'a Expr,
    pub occurrence: Span,
    pub double_receiver: bool,
}
#[derive(Clone, Copy)]
pub(crate) enum ScopeBody<'a> {
    Statements(&'a [Statement]),
    Assignment {
        target: &'a Expr,
        value: &'a Expr,
        occurrence: Span,
        double_receiver: bool,
    },
}

pub struct TypedScope<'a> {
    pub inputs: &'a ProcedureInputs,
    pub statements: &'a [Statement],
}
pub(crate) struct PreparedScope<'a> {
    pub bindings: LowerBindings,
    pub body: ScopeBody<'a>,
}
pub(crate) struct PreparedScopes<'a> {
    pub scopes: Vec<PreparedScope<'a>>,
    pub resource_search_context: Option<u128>,
}
pub(crate) fn prepare<'a>(
    scopes: &[TypedScope<'a>],
) -> Result<PreparedScopes<'a>, Vec<LowerError>> {
    prepare_bodies(
        scopes
            .iter()
            .map(|scope| (scope.inputs, ScopeBody::Statements(scope.statements))),
    )
}
pub(crate) fn prepare_assignments<'a>(
    scopes: &[AssignmentScope<'a>],
) -> Result<PreparedScopes<'a>, Vec<LowerError>> {
    prepare_bodies(scopes.iter().map(|scope| {
        (
            scope.inputs,
            ScopeBody::Assignment {
                target: scope.target,
                value: scope.value,
                occurrence: scope.occurrence,
                double_receiver: scope.double_receiver,
            },
        )
    }))
}
fn prepare_bodies<'a>(
    scopes: impl ExactSizeIterator<Item = (&'a ProcedureInputs, ScopeBody<'a>)>,
) -> Result<PreparedScopes<'a>, Vec<LowerError>> {
    let mut resource_search_context = None;
    let mut prepared = Vec::with_capacity(scopes.len());
    for (index, (input, body)) in scopes.enumerate() {
        if index == 0 {
            resource_search_context = input.resource_search_context;
        }
        if input.current_proc_path.is_some()
            || !input.parameters.is_empty()
            || !input.parameter_type_flags.is_empty()
            || !input.parameter_value_sources.is_empty()
            || !input.parameter_defaults.is_empty()
            || !input.parameter_types.is_empty()
            || !input.readonly_parameters.is_empty()
        {
            return Err(vec![LowerError { statement:"initializer scopes".into(),
                reason:"initializer lexical slices cannot supply procedure frames or parameter metadata".into(), ..LowerError::default() }]);
        }
        if input.resource_search_context != resource_search_context {
            return Err(vec![LowerError {
                statement: "initializer scopes".into(),
                reason: "initializer slices require one explicit captured resource search context"
                    .into(),
                ..LowerError::default()
            }]);
        }
        prepared.push(PreparedScope {
            bindings: LowerBindings {
                current_type_path: input.current_type_path.clone(),
                procedure_identity: input.procedure_identity,
                ..LowerBindings::default()
            },
            body,
        });
    }
    Ok(PreparedScopes {
        scopes: prepared,
        resource_search_context,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn captures_only_lexical_owner_and_rejects_frames_or_context_changes() {
        let first = ProcedureInputs {
            current_type_path: Some("/datum/a".into()),
            resource_search_context: Some(7),
            ..Default::default()
        };
        let mut second = ProcedureInputs {
            current_type_path: Some("/datum/b".into()),
            resource_search_context: Some(7),
            ..Default::default()
        };
        let prepared = prepare(&[
            TypedScope {
                inputs: &first,
                statements: &[],
            },
            TypedScope {
                inputs: &second,
                statements: &[],
            },
        ])
        .unwrap();
        assert_eq!(
            prepared.scopes[1].bindings.current_type_path.as_deref(),
            Some("/datum/b")
        );
        assert!(prepared
            .scopes
            .iter()
            .all(|scope| scope.bindings.shared.is_none()));
        second.resource_search_context = Some(8);
        assert!(prepare(&[
            TypedScope {
                inputs: &first,
                statements: &[]
            },
            TypedScope {
                inputs: &second,
                statements: &[]
            }
        ])
        .is_err());
        second.resource_search_context = Some(7);
        second.parameters.push("argument".into());
        assert!(prepare(&[TypedScope {
            inputs: &second,
            statements: &[]
        }])
        .is_err());
    }
}
