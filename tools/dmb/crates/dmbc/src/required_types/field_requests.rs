//! Current immutable field observations issue symbolic reachability requests.
//! Encounter placement stays request-local; source-bearing defaults decline.
use crate::class_projection::{FieldProjection, FieldRole};
use crate::initializer_lowering::receipts::publication_store::PublicationStore as ObservedArtifactStore;
use crate::initializer_policy::DefaultValue;
use dm_ir::{SemanticValue, SymbolId};
use dm_session::{Observation, ObservationHost};
use std::sync::Arc;
pub(crate) struct FieldRequests {
    values: ObservedArtifactStore<Vec<SymbolId>, (), Arc<FieldProjection>, ()>,
}
impl Default for FieldRequests {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
        }
    }
}
struct Current<'a>(&'a Arc<FieldProjection>);
impl ObservationHost<(), Arc<FieldProjection>, ()> for Current<'_> {
    fn answer(&self, _: &()) -> Arc<FieldProjection> {
        Arc::clone(self.0)
    }
}
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
fn key(index: usize) -> Vec<u8> {
    let mut key = b"dmbc-required-field-requests-v1\0".to_vec();
    key.extend_from_slice(&(index as u64).to_le_bytes());
    key
}
impl FieldRequests {
    pub(crate) fn for_request(&self, publishable: bool) -> Self {
        Self {
            values: self.values.for_request(publishable),
        }
    }
    pub(crate) fn publish_successful(&self) -> bool {
        self.values.publish_successful()
    }

    pub(super) fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, Vec<SymbolId>, (), Arc<FieldProjection>, ()>,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
    pub(super) fn append(&self, fields: &[Arc<FieldProjection>], requests: &mut Vec<SymbolId>) {
        let mut keys = Vec::with_capacity(fields.len());
        for (index, field) in fields.iter().enumerate() {
            let key = key(index);
            if let Some(value) = self.values.lookup(&key, &Current(field)) {
                keys.push(key);
                requests.extend_from_slice(&value);
                continue;
            }
            let mut value = Vec::new();
            let retainable = produce(field, &mut value);
            requests.extend_from_slice(&value);
            if retainable {
                keys.push(key.clone());
                self.values.insert_with(
                    key.into(),
                    vec![Observation {
                        domain: (),
                        query: (),
                        answer: Arc::clone(field),
                    }],
                    Vec::new(),
                    0,
                    || value,
                );
            }
        }
        self.values
            .retain_current_keys(keys.iter().map(Vec::as_slice));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
    fn current_fields_revalidate_reorder_prune_and_preserve_nested_value_encounter_order() {
        let store = FieldRequests::default();
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
        let run = |fields: &[Arc<FieldProjection>]| {
            let mut actual = Vec::new();
            store.append(fields, &mut actual);
            assert_eq!(actual, legacy(fields));
        };
        run(&fields);
        // Different Arc owners with equal immutable contents must also admit.
        run(&fields
            .iter()
            .map(|field| Arc::new((**field).clone()))
            .collect::<Vec<_>>());
        let mut changed = fields.clone();
        changed[0] = field(
            "/datum/a",
            SemanticValue::Type(SymbolId::of("/datum/changed")),
        );
        run(&changed);
        changed.reverse();
        run(&changed);
        run(&changed[..1]);
        let mut count = 0;
        store.visit_storage(|view| {
            if matches!(view, dm_session::ObservedArtifactStorageView::Entry { .. }) {
                count += 1;
            }
        });
        assert_eq!(count, 1);
        run(&[]);
        let mut count = 0;
        store.visit_storage(|view| {
            if matches!(view, dm_session::ObservedArtifactStorageView::Entry { .. }) {
                count += 1;
            }
        });
        assert_eq!(count, 0);
    }
}
