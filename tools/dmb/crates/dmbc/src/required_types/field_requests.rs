//! The symbolic reachability requests a field issues (its owners and the types its default names). Computed for every
//! field of every request: a few pushes, cheaper than any stored lookup keyed by the field.
use crate::class_projection::{FieldProjection, FieldRole};
use crate::initializer_policy::DefaultValue;
use dm_ir::{SemanticValue, SymbolId};
fn values(value: &SemanticValue, requests: &mut Vec<SymbolId>) -> bool {
    match value {
        SemanticValue::Type(path)
            if dm_codegen_byond::NativePrimitiveType::from_symbol(*path).is_some() =>
        {
            true
        }
        SemanticValue::Type(path) => {
            requests.push(*path);
            true
        }
        SemanticValue::Procedure(identity) => {
            requests.push(identity.owner);
            true
        }
        SemanticValue::ModifiedInstance(instance) => {
            requests.push(instance.runtime_type());
            false
        }
        SemanticValue::List(entries) => {
            let mut retainable = true;
            for (key, value) in entries.iter() {
                if let Some(key) = key {
                    retainable &= values(key, requests);
                }
                retainable &= values(value, requests);
            }
            retainable
        }
        _ => true,
    }
}
pub(super) fn produce(field: &FieldProjection, requests: &mut Vec<SymbolId>) -> bool {
    let savefile_header = field.owner == SymbolId::of("/savefile")
        && field.declaring_owner == SymbolId::of("/savefile")
        && field.name == SymbolId::of("byond_version")
        && field.role == FieldRole::Assignment
        && field.intrinsic
        && !field.shared;
    if !savefile_header {
        requests.push(field.owner);
        requests.push(field.declaring_owner);
    }
    match &field.value {
        DefaultValue::Scalar(value) => values(value, requests),
        _ => true,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    fn field(owner: &str, value: SemanticValue) -> Arc<FieldProjection> {
        Arc::new(FieldProjection {
            owner: SymbolId::of(owner),
            declaring_owner: SymbolId::of(owner),
            name: SymbolId::of("value"),
            role: FieldRole::Declaration,
            wire_flags: Some(0),
            intrinsic: false,
            shared: false,
            value: DefaultValue::Scalar(value),
        })
    }
    fn legacy(fields: &[Arc<FieldProjection>]) -> Vec<SymbolId> {
        fn scalar(value: &SemanticValue, out: &mut Vec<SymbolId>) {
            match value {
                SemanticValue::Type(id) => {
                    if dm_codegen_byond::NativePrimitiveType::from_symbol(*id).is_none() {
                        out.push(*id);
                    }
                }
                SemanticValue::Procedure(id) => out.push(id.owner),
                SemanticValue::ModifiedInstance(value) => out.push(value.runtime_type()),
                SemanticValue::List(entries) => {
                    for (key, value) in entries.iter() {
                        if let Some(key) = key {
                            scalar(key, out);
                        }
                        scalar(value, out);
                    }
                }
                _ => (),
            }
        }
        let mut out = Vec::new();
        for field in fields {
            if !(field.owner == SymbolId::of("/savefile")
                && field.declaring_owner == field.owner
                && field.name == SymbolId::of("byond_version")
                && field.role == FieldRole::Assignment
                && field.intrinsic
                && !field.shared)
            {
                out.extend([field.owner, field.declaring_owner]);
            }
            if let DefaultValue::Scalar(value) = &field.value {
                scalar(value, &mut out);
            }
        }
        out
    }
    #[test]
    fn produce_matches_the_reference_order_including_nested_values_and_the_savefile_header() {
        let nested = SemanticValue::List(Arc::from([
            (
                Some(SemanticValue::Type(SymbolId::of("/datum/key"))),
                SemanticValue::List(Arc::from([(
                    None,
                    SemanticValue::Type(SymbolId::of("/datum/value")),
                )])),
            ),
            (None, SemanticValue::Type(SymbolId::of("/list"))),
        ]));
        let mut header = (*field("/savefile", SemanticValue::Null)).clone();
        header.name = SymbolId::of("byond_version");
        header.role = FieldRole::Assignment;
        header.intrinsic = true;
        let fields = vec![field("/datum/a", nested), Arc::new(header)];
        let mut actual = Vec::new();
        for field in &fields {
            produce(field, &mut actual);
        }
        assert_eq!(actual, legacy(&fields));
    }
}
