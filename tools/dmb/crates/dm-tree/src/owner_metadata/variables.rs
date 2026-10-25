//! Exact local variable-name receipts. Enriched scalar queries remain separate.
use super::*;
use crate::token_digest::{self, TokenDigest};
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
impl VariableInputs {
    /// The token of this exact input state under the artifact `key` (see `token_digest`).
    pub(super) fn token(&self, key: &[u8]) -> u128 {
        let mut digest = TokenDigest::new(b"owner-variable-token-v1");
        digest.bytes(key);
        digest.len(self.ancestors.len());
        for ancestor in self.ancestors.iter() {
            digest.symbol(*ancestor);
        }
        digest.opt_u128(self.parent_certificate);
        digest.len(self.members.len());
        for fact in self.members.iter() {
            digest
                .symbol(fact.owner)
                .u8(token_digest::definition_byte(fact.definition))
                .u128(crate::tree_identity::metadata_fingerprint(&fact.metadata));
        }
        digest.len(self.intrinsic.len());
        for member in self.intrinsic.iter() {
            token_digest::intrinsic(&mut digest, member);
        }
        digest
            .bool(self.complete)
            .bool(self.hierarchy_certified)
            .finish()
    }
}
pub(super) fn local_inputs(
    tree: &SemanticTree,
    index: usize,
    name: SymbolId,
    parent_certificate: Option<u128>,
) -> Option<Arc<VariableInputs>> {
    let node = tree.types.get(index)?;
    let demand_index = tree.owner_callable_demands.index(tree);
    Some(Arc::new(VariableInputs {
        ancestors: Arc::from([node.path]),
        parent_certificate,
        members: demand_index
            .members(index, name)
            .iter()
            .filter_map(|id| {
                let member = &tree.members[id.index()];
                (member.kind == MemberKind::Var).then(|| VariableFact {
                    owner: node.path,
                    definition: member.definition,
                    metadata: Arc::clone(&member.metadata),
                })
            })
            .collect::<Vec<_>>()
            .into(),
        intrinsic: demand_index
            .intrinsics(node.path, name)
            .iter()
            .filter(|member| member.kind == MemberKind::Var)
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
