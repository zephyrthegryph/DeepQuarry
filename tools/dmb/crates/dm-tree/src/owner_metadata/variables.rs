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
    pub members: Arc<[VariableFact]>,
    pub intrinsic: Arc<[IntrinsicMember]>,
    pub complete: bool,
    pub hierarchy_certified: bool,
}
pub(super) fn key(owner: SymbolId, name: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"variable-selection-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.extend_from_slice(&name.bits().to_le_bytes());
    bytes.into()
}
pub(super) fn keys<M: Index<usize, Output = MemberNode>>(
    tree: &SemanticTree,
    members: &M,
    order: &[MemberId],
) -> Vec<Arc<[u8]>> {
    order
        .iter()
        .filter_map(|id| {
            let member = &members[id.index()];
            (member.kind == MemberKind::Var)
                .then(|| key(tree.types[member.owner.index()].path, member.name))
        })
        .collect()
}
struct Host<'a>(&'a Arc<VariableInputs>);
impl ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host<'_> {
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::VariableLocal(..) => MetadataAnswer::VariableLocal(Arc::clone(self.0)),
            _ => unreachable!("variable receipt"),
        }
    }
}
impl RetainedMetadata {
    pub(crate) fn certify_variables(
        &self,
        tree: &SemanticTree,
    ) -> BTreeMap<(SymbolId, SymbolId), u128> {
        let mut certificates = BTreeMap::new();
        for node in tree.types.iter() {
            let names = node
                .members
                .iter()
                .filter_map(|id| {
                    let member = &tree.members[id.index()];
                    if member.kind == MemberKind::Var {
                        Some(member.name)
                    } else {
                        None
                    }
                })
                .collect::<std::collections::BTreeSet<_>>();
            if names.is_empty() {
                continue;
            }
            let ancestors = hierarchy::ancestry(tree, node.path);
            for name in names {
                let members = ancestors
                    .iter()
                    .flat_map(|owner| {
                        let id = tree.lookup_type(*owner).expect("issued ancestor");
                        tree.types[id.index()].members.iter().filter_map(move |id| {
                            let member = &tree.members[id.index()];
                            if member.kind == MemberKind::Var && member.name == name {
                                Some(VariableFact {
                                    owner: *owner,
                                    definition: member.definition,
                                    metadata: Arc::clone(&member.metadata),
                                })
                            } else {
                                None
                            }
                        })
                    })
                    .collect::<Vec<_>>()
                    .into();
                let inputs = Arc::new(VariableInputs {
                    ancestors: Arc::clone(&ancestors),
                    members,
                    intrinsic: tree
                        .inventory
                        .intrinsic
                        .iter()
                        .filter(|member| {
                            member.kind == MemberKind::Var
                                && member.name == name
                                && ancestors.contains(&member.owner)
                        })
                        .cloned()
                        .collect::<Vec<_>>()
                        .into(),
                    complete: tree.inventory.complete,
                    hierarchy_certified: tree.inventory.hierarchy_certified,
                });
                let host = Host(&inputs);
                if let Some(value) = self.store.lookup(&key(node.path, name), &host) {
                    if let Some((_, version)) = &value.variable {
                        certificates.insert((node.path, name), *version);
                        continue;
                    }
                }
                static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
                let Ok(version) = NEXT.fetch_update(
                    std::sync::atomic::Ordering::Relaxed,
                    std::sync::atomic::Ordering::Relaxed,
                    |value| value.checked_add(1),
                ) else {
                    continue;
                };
                let query = MetadataQuery::VariableLocal(node.path, name);
                let ledger = ObservationLedger::default();
                ledger.record(query, host.answer(&query), query.domain(), None);
                self.store.insert_with(
                    key(node.path, name),
                    ledger.reads(),
                    ledger.domain_receipts(),
                    0,
                    || EffectiveOwner {
                        selection: Arc::new(crate::HostDeclarationSelection {
                            callable_names: Arc::from([]),
                            declared_variable_names: Arc::from([]),
                            scalar_requests: Arc::from([]),
                        }),
                        values: Arc::from([]),
                        hierarchy: None,
                        callable: None,
                        variable: Some((inputs, u128::from(version))),
                    },
                );
                certificates.insert((node.path, name), u128::from(version));
            }
        }
        certificates
    }
}

#[cfg(test)]
#[path = "variable_tests.rs"]
mod tests;
