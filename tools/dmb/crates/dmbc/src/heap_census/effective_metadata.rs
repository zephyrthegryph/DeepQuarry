//! Retained effective metadata shares namespace and predecessor allocations.
use super::*;
use dm_tree::{
    frontend::RetainedSemanticTree,
    owner_metadata::{MetadataAnswer, MetadataDomain, MetadataQuery, MetadataStorageView},
};

fn metadata(census: &mut HeapCensus, value: &Arc<dm_tree::MemberMetadata>) {
    if census.arc_object("semantic_metadata", value) {
        census.declaration(value);
    }
}
fn callable(census: &mut HeapCensus, inputs: &Arc<dm_tree::owner_metadata::CallableInputs>) {
    if census.arc_object("retained_callable.inputs", inputs) {
        census.slice("retained_callable.members", &inputs.members, true);
        census.slice("retained_callable.intrinsic", &inputs.intrinsic, true);
        for member in inputs.members.iter() {
            metadata(census, &member.metadata);
        }
    }
}
fn variable(census: &mut HeapCensus, inputs: &Arc<dm_tree::owner_metadata::VariableInputs>) {
    if census.arc_object("variable_selection.inputs", inputs) {
        census.slice("variable_selection.ancestors", &inputs.ancestors, true);
        census.slice("variable_selection.members", &inputs.members, true);
        census.slice("variable_selection.intrinsic", &inputs.intrinsic, true);
        for member in inputs.members.iter() {
            metadata(census, &member.metadata);
        }
    }
}
fn answer(census: &mut HeapCensus, value: &MetadataAnswer) {
    match value {
        MetadataAnswer::NormalizedOwner(Some(members)) => {
            census.slice("retained_effective_metadata.namespace_rows", members, true);
            // The same rows may already have been visited through namespace
            // storage. Its borrowed metadata traversal independently dedups.
            for member in members.iter() {
                let dm_tree::ResolvedMember {
                    key: _,
                    definition: _,
                    kind: _,
                    metadata: value,
                    previous: _,
                } = member;
                metadata(census, value);
            }
        }
        MetadataAnswer::Effective(Some(value)) => metadata(census, value),
        MetadataAnswer::CallableLocal(inputs) => callable(census, inputs),
        MetadataAnswer::VariableLocal(inputs) => variable(census, inputs),
        MetadataAnswer::Hierarchy(paths) => {
            census.slice("retained_effective_metadata.hierarchy", paths, true);
        }
        MetadataAnswer::NormalizedOwner(None) | MetadataAnswer::Effective(None) => (),
    }
}
pub(super) fn inspect(census: &mut HeapCensus, state: &RetainedSemanticTree) {
    state.visit_effective_metadata_storage(|view| match view {
        MetadataStorageView::Store { buckets, entries } => {
            census.owner("retained_effective_metadata.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("retained_effective_metadata.index", "private ArtifactStore BTree nodes and Arc control blocks excluded; exposed immutable payload capacities counted");
            }
        }
        MetadataStorageView::Buffer { address, length, capacity } => {
            census.buffer("retained_effective_metadata.buffers", address, length, capacity);
        }
        MetadataStorageView::Entry { key, reads, versions, address, size } => {
            census.slice("retained_effective_metadata.keys", key, true);
            census.slice("retained_effective_metadata.reads", reads, true);
            census.slice("retained_effective_metadata.versions", versions, true);
            census.buffer("retained_effective_metadata.values", address, size, size);
            for read in reads.iter() {
                match read.query {
                    MetadataQuery::NormalizedOwner(_) | MetadataQuery::Effective(_) | MetadataQuery::Hierarchy(_) | MetadataQuery::CallableLocal(_) | MetadataQuery::CallableSelection(..) | MetadataQuery::CallablePresence(..) | MetadataQuery::VariableLocal(..) => (),
                }
                match read.domain {
                    MetadataDomain::Namespace | MetadataDomain::EffectiveMembers => (),
                }
                answer(census, &read.answer);
            }
        }
        MetadataStorageView::Selection(value) => selection(census,value),
        MetadataStorageView::CallableLocal(inputs) => callable(census, inputs),
        MetadataStorageView::VariableLocal(inputs)=>variable(census,inputs),
        MetadataStorageView::Hierarchy(paths) => {
            census.slice("retained_effective_metadata.hierarchy", paths, true);
        }
        MetadataStorageView::Values(values) => {
            census.slice("retained_effective_metadata.members", values, true);
            for (_, value) in values.iter() { metadata(census, value); }
        }
    });
}

fn selection(census: &mut HeapCensus, value: &Arc<dm_tree::HostDeclarationSelection>) {
    if census.arc_object("host.declaration_selection", value) {
        census.slice(
            "host.declaration_selection.callables",
            &value.callable_names,
            true,
        );
        census.slice(
            "host.declaration_selection.variables",
            &value.declared_variable_names,
            true,
        );
        census.slice(
            "host.declaration_selection.scalars",
            &value.scalar_requests,
            true,
        );
    }
}
pub(super) fn selections(census: &mut HeapCensus, tree: &dm_tree::SemanticTree) {
    if let Some(issuer) = tree.owner_certificate_issuer() {
        census.arc_object("owner_certificates.issuer", issuer);
    }
    let variables = tree.owner_variable_selection_certificates();
    if census.arc_object("variable_selection.index", variables) {
        census.observe_items("variable_selection.index", variables.len());
        census.unknown("variable_selection.index","private BTree nodes excluded; current local variable-name certificate descriptor counted");
    }
    let demands = tree.owner_callable_demand_certificates();
    if census.arc_object("callable_demands.index", demands) {
        demands.visit_storage(|_, entries| {
            census.observe_items("callable_demands.index", entries);
            census.unknown("callable_demands.index", "private BTree node backing excluded; exact demanded certificate cardinality reported");
        });
    }
    let selections = tree.owner_callable_selection_certificates();
    if census.arc_object("callable_selection.index", selections) {
        census.observe_items("callable_selection.index", selections.len());
        census.unknown("callable_selection.index", "private BTree nodes excluded; current name-qualified certificate index descriptor counted");
    }
    let callables = tree.owner_callable_certificates();
    if census.arc_object("owner_callable.index", callables) {
        census.observe_items("owner_callable.index", callables.len());
        census.unknown(
            "owner_callable.index",
            "private BTree node backing excluded",
        );
    }
    let hierarchy = tree.owner_hierarchy_certificates();
    if census.arc_object("owner_hierarchy.index", hierarchy) {
        census.observe_items("owner_hierarchy.index", hierarchy.len());
        census.unknown(
            "owner_hierarchy.index",
            "private BTree node backing excluded",
        );
    }

    let owners = tree.host_declaration_selection_storage();
    if census.arc_object("host.declaration_selection.index", owners) {
        census.observe_items("host.declaration_selection.index", owners.len());
        census.unknown(
            "host.declaration_selection.index",
            "private BTree node backing excluded",
        );
        for value in owners.values() {
            selection(census, value);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn namespace_rows_and_predecessor_answers_share_exact_metadata_backing() {
        let value = Arc::new(dm_tree::MemberMetadata::default());
        let member = dm_tree::ResolvedMember {
            key: dm_tree::declaration_contributions::DeclarationKey {
                owner: dm_ir::SymbolId::of("/datum/probe"),
                family: dm_tree::declaration_contributions::DeclarationFamily::Member {
                    name: dm_ir::SymbolId::of("value"),
                    kind: dm_tree::MemberKind::Var,
                },
                occurrence: 0,
            },
            definition: dm_tree::DefinitionMode::Declare,
            kind: dm_tree::MemberKind::Var,
            metadata: Arc::clone(&value),
            previous: None,
        };
        let members: Arc<[dm_tree::ResolvedMember]> = Arc::from([member]);
        let mut census = HeapCensus::new("shared_effective_metadata");
        census.slice("namespace_existing", &members, true);
        metadata(&mut census, &value);
        let before = census.allocations.len();
        answer(
            &mut census,
            &MetadataAnswer::NormalizedOwner(Some(Arc::clone(&members))),
        );
        answer(&mut census, &MetadataAnswer::Effective(Some(value)));
        assert_eq!(before, census.allocations.len());
        let report = census.finish();
        assert_eq!(
            report
                .owners
                .iter()
                .find(|owner| owner.owner == "retained_effective_metadata.namespace_rows")
                .unwrap()
                .unique_known_capacity_bytes,
            0
        );
    }
}
