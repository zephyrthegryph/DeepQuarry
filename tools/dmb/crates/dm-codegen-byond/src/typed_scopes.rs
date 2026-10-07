//! Typed lexical slices for one initializer VM invocation. Scopes change only
//! lexical lookup; code labels, consumed resolver receipts and debug ordinals
//! belong to the single shared compiler accumulator.
use crate::{LowerBindings, LowerError, ProcedureInputs};
use dm_syntax::Statement;

pub struct TypedScope<'a> {
    pub inputs: &'a ProcedureInputs,
    pub statements: &'a [Statement],
}
pub(crate) struct PreparedScope<'a> {
    pub bindings: LowerBindings,
    pub statements: &'a [Statement],
}
pub(crate) struct PreparedScopes<'a> {
    pub scopes: Vec<PreparedScope<'a>>,
    pub resource_search_context: Option<u128>,
}
pub(crate) fn prepare<'a>(
    scopes: &[TypedScope<'a>],
) -> Result<PreparedScopes<'a>, Vec<LowerError>> {
    let resource_search_context = scopes
        .first()
        .and_then(|scope| scope.inputs.resource_search_context);
    let mut prepared = Vec::with_capacity(scopes.len());
    for scope in scopes {
        let input = scope.inputs;
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
            statements: scope.statements,
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
