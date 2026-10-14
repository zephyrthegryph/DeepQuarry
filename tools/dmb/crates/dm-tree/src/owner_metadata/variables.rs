//! Exact local variable-name receipts. Enriched scalar queries remain separate.
use super::*;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VariableFact {
    pub owner: SymbolId,
    pub definition: DefinitionMode,
    pub metadata: Arc<MemberMetadata>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VariableInputs {
    pub ancestors: Arc<[SymbolId]>,
    pub parent_certificate: Option<u128>,
    pub members: Arc<[VariableFact]>,
    pub intrinsic: Arc<[IntrinsicMember]>,
    pub complete: bool,
    pub hierarchy_certified: bool,
}
pub(super) fn local_inputs(
    tree: &SemanticTree,
    index: usize,
    name: SymbolId,
    parent_certificate: Option<u128>,
) -> Option<Arc<VariableInputs>> {
    let node = tree.types.get(index)?;
    Some(Arc::new(VariableInputs {
        ancestors: Arc::from([node.path]),
        parent_certificate,
        members: node
            .members
            .iter()
            .filter_map(|id| {
                let member = &tree.members[id.index()];
                (member.kind == MemberKind::Var && member.name == name).then(|| VariableFact {
                    owner: node.path,
                    definition: member.definition,
                    metadata: Arc::clone(&member.metadata),
                })
            })
            .collect::<Vec<_>>()
            .into(),
        intrinsic: tree
            .inventory
            .intrinsic
            .iter()
            .filter(|member| {
                member.kind == MemberKind::Var && member.name == name && member.owner == node.path
            })
            .cloned()
            .collect::<Vec<_>>()
            .into(),
        complete: tree.inventory.complete,
        hierarchy_certified: tree.inventory.hierarchy_certified,
    }))
}
impl RetainedMetadata {
    pub(crate) fn certify_variables(
        &self,
        tree: &SemanticTree,
    ) -> BTreeMap<(SymbolId, SymbolId), u128> {
        // Register the current immutable issuer without eagerly materializing
        // every local name and its negative ancestor receipts. Resolver queries
        // use the same demanded_variable core, including the complete parent
        // chain. Previously issued old-snapshot tokens remain readable; an
        // unqueried old snapshot declines instead of minting current authority.
        self.begin_selection_revision(tree);
        BTreeMap::new()
    }
}

#[cfg(test)]
#[path = "variable_tests.rs"]
mod tests;
