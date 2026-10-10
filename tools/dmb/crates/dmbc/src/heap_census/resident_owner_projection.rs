//! Actual semantic owner payloads, with conservative admission overhead.
use super::*;
use crate::{
    class_projection::member_contribution::MemberContribution, initializer_policy::DefaultValue,
    lowering_memo::ResolverRead,
};
use dm_ir::ReadDomain;

pub(super) fn inspect_field(
    census: &mut HeapCensus,
    field: &Arc<crate::class_projection::FieldProjection>,
) {
    let name = "owner_projection.defaults";
    if !census.arc_object(name, field) {
        return;
    }
    match &field.value {
        DefaultValue::Transform(_) => {}
        DefaultValue::Scalar(value) => census.semantic_value(name, value),
        DefaultValue::InitializerExpression { canonical, .. } => {
            census.slice(name, canonical, true);
        }
    }
}

pub(crate) fn weight(
    values: &Vec<MemberContribution>,
    inputs: &Vec<crate::class_projection::retained::MemberInput>,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    let mut census = HeapCensus::new("resident_owner_projection_admission");
    inspect_inputs(&mut census, inputs);
    census.vec_payload("resident_owner_projection.values", values);
    for value in values {
        match value {
            MemberContribution::Field(field) => inspect_field(&mut census, field),
            MemberContribution::Procedure {
                owner: _,
                name: _,
                verb: _,
                key: _,
                declared: _,
            } => {}
        }
    }
    census.vec_payload("resident_owner_projection.reads", reads);
    census.vec_payload("resident_owner_projection.versions", versions);
    for read in reads {
        super::resident_weight::answer(&mut census, &read.answer);
    }
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    Some(
        usize::try_from(report.unique_known_capacity_bytes)
            .ok()?
            .saturating_add(encounters.saturating_mul(64))
            .saturating_add(size_of::<Vec<MemberContribution>>())
            .saturating_add(key.len())
            .saturating_add(4096),
    )
}

fn inspect_inputs(
    census: &mut HeapCensus,
    inputs: &Vec<crate::class_projection::retained::MemberInput>,
) {
    census.vec_payload("owner_projection.inputs", inputs);
    for input in inputs {
        if census.arc_object("owner_projection.input_metadata", &input.metadata) {
            census.declaration(&input.metadata);
        }
        if let Some(value) = &input.default {
            match value {
                DefaultValue::Transform(_) => {}
                DefaultValue::Scalar(value) => {
                    census.semantic_value("owner_projection.input_defaults", value)
                }
                DefaultValue::InitializerExpression { canonical, .. } => {
                    census.slice("owner_projection.input_defaults", canonical, true);
                }
            }
        }
    }
}

/// Diagnostic accounting separates real backing from private index uncertainty.
pub(crate) fn inspect(store: &crate::class_projection::ClassProjections) -> HeapCensusReport {
    let mut census = HeapCensus::new("retained_owner_projection");
    inspect_into(&mut census, store);
    census.finish()
}
pub(super) fn inspect_into(
    mut census: &mut HeapCensus,
    store: &crate::class_projection::ClassProjections,
) {
    store.visit_storage(|view| match view {
        dm_session::ArtifactStorageView::Store { buckets, entries } => {
            census.owner("owner_projection.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown(
                    "owner_projection.index",
                    "private ArtifactStore BTree backing/control blocks excluded",
                );
            }
        }
        dm_session::ArtifactStorageView::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            census.buffer(
                "owner_projection.buckets",
                address,
                len.saturating_mul(element_size),
                capacity.saturating_mul(element_size),
            );
        }
        dm_session::ArtifactStorageView::Entry {
            key,
            reads,
            versions,
            value,
        } => {
            census.slice("owner_projection.keys", key, true);
            census.receipt("owner_projection.reads", reads);
            census.slice("owner_projection.versions", versions, true);
            for read in reads.iter() {
                super::resident_weight::answer(&mut census, &read.answer);
            }
            if census.arc_object("owner_projection.values", value)
                && census.vec_payload("owner_projection.values", &value.values)
            {
                inspect_inputs(census, &value.inputs);
                for member in value.values.iter() {
                    if let MemberContribution::Field(field) = member {
                        inspect_field(&mut census, field);
                    }
                }
            }
        }
    });
    store.types.visit_storage(|view| match view {
        dm_session::ObservedArtifactStorageView::Store { entries, .. } => {
            census.observe_items("owner_projection.types_index", entries);
        }
        dm_session::ObservedArtifactStorageView::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            census.buffer(
                "owner_projection.types_buckets",
                address,
                len.saturating_mul(element_size),
                capacity.saturating_mul(element_size),
            );
        }
        dm_session::ObservedArtifactStorageView::Entry {
            key,
            reads,
            versions,
            value,
        } => {
            census.slice("owner_projection.types_keys", key, true);
            if census.receipt("owner_projection.types_reads", reads) {
                for read in reads.iter() {
                    if census.slice("semantic_tree", &read.answer.0, true) {
                        for node in read.answer.0.iter() {
                            census.slice("semantic_tree", &node.members, true);
                        }
                    }
                }
            }
            census.slice("owner_projection.types_versions", versions, true);
            if census.arc_object("owner_projection.projected_types_owner", value) {
                census.slice("owner_projection.projected_types", value.as_ref(), true);
            }
        }
    });
    census.unknown(
        "owner_projection.types_index",
        "private observed-store BTree nodes and allocator metadata excluded",
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn owned_nested_default_and_unused_vector_capacity_raise_conservative_charge() {
        let empty = Vec::new();
        let mut values = Vec::new();
        let before = weight(&values, &Vec::new(), b"key", &empty, &Vec::new()).unwrap();
        values.reserve_exact(100);
        let reserved = weight(&values, &Vec::new(), b"key", &empty, &Vec::new()).unwrap();
        assert!(reserved >= before + 100 * size_of::<MemberContribution>());
        values.push(MemberContribution::Field(std::sync::Arc::new(
            crate::class_projection::FieldProjection {
                owner: dm_ir::SymbolId::of("/obj"),
                declaring_owner: dm_ir::SymbolId::of("/obj"),
                name: dm_ir::SymbolId::of("field"),
                role: crate::class_projection::FieldRole::Declaration,
                wire_flags: None,
                intrinsic: false,
                shared: false,
                value: DefaultValue::Scalar(dm_ir::SemanticValue::List(Arc::from([(
                    Some(dm_ir::SemanticValue::Text(Arc::from(b"key".as_slice()))),
                    dm_ir::SemanticValue::Text(Arc::from(b"value".as_slice())),
                )]))),
            },
        )));
        assert!(weight(&values, &Vec::new(), b"key", &empty, &Vec::new()).unwrap() > reserved);
    }
}
