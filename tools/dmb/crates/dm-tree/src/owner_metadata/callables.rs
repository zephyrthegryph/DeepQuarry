//! Owner-local callable facts, linked by exact parent certificates. No ancestor
//! member roster is copied into descendants.
use super::*;
type MemberKey = (SymbolId, SymbolId, bool, u32);
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallableFact {
    pub key: MemberKey,
    pub definition: DefinitionMode,
    pub content: u128,
    pub metadata: Arc<MemberMetadata>,
    pub previous: Option<MemberKey>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallableInputs {
    pub members: Arc<[CallableFact]>,
    pub intrinsic: Arc<[IntrinsicMember]>,
    pub parent: Option<SymbolId>,
    pub parent_certificate: Option<u128>,
    pub complete: bool,
    pub hierarchy_certified: bool,
}
pub(super) fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-callable-certificate-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
struct Host<'a>(&'a BTreeMap<SymbolId, Arc<CallableInputs>>);
impl ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host<'_> {
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::CallableLocal(owner) => {
                MetadataAnswer::CallableLocal(Arc::clone(&self.0[owner]))
            }
            _ => unreachable!("callable certificates only record owner-local inputs"),
        }
    }
}
impl RetainedMetadata {
    pub(crate) fn certify_callables(&self, tree: &SemanticTree) -> BTreeMap<SymbolId, u128> {
        let mut counts = BTreeMap::<(SymbolId, SymbolId, bool), u32>::new();
        let mut member_keys = BTreeMap::new();
        for (index, member) in tree.members.iter().enumerate() {
            if member.kind == MemberKind::Var {
                continue;
            }
            let family = (
                tree.types[member.owner.index()].path,
                member.name,
                member.kind == MemberKind::Verb,
            );
            let occurrence = counts.entry(family).or_default();
            member_keys.insert(index, (family.0, family.1, family.2, *occurrence));
            let Some(next) = occurrence.checked_add(1) else {
                return BTreeMap::new();
            };
            *occurrence = next;
        }
        let mut certificates = BTreeMap::new();
        let mut inputs = BTreeMap::new();
        let order = crate::metadata_update::dependency_order(tree.types.len(), |index| {
            tree.types[index].parent.map(|id| id.index())
        });
        for index in order {
            let node = &tree.types[index];
            let parent = node.parent.map(|id| tree.types[id.index()].path);
            let parent_certificate = parent.and_then(|owner| certificates.get(&owner).copied());
            if parent.is_some() && parent_certificate.is_none() {
                continue;
            }
            let members = node
                .members
                .iter()
                .filter_map(|id| {
                    let member = &tree.members[id.index()];
                    (member.kind != MemberKind::Var).then(|| CallableFact {
                        key: member_keys[&id.index()],
                        definition: member.definition,
                        content: member.content,
                        metadata: Arc::clone(&member.metadata),
                        previous: member.previous.map(|id| member_keys[&id.index()]),
                    })
                })
                .collect::<Vec<_>>()
                .into();
            let intrinsic = tree
                .inventory
                .intrinsic
                .iter()
                .filter(|member| member.owner == node.path && member.kind != MemberKind::Var)
                .cloned()
                .collect::<Vec<_>>()
                .into();
            inputs.insert(
                node.path,
                Arc::new(CallableInputs {
                    members,
                    intrinsic,
                    parent,
                    parent_certificate,
                    complete: tree.inventory.complete,
                    hierarchy_certified: tree.inventory.hierarchy_certified,
                }),
            );
            let host = Host(&inputs);
            if let Some(value) = self.store.lookup(&key(node.path), &host) {
                if let Some((_, version)) = &value.callable {
                    certificates.insert(node.path, *version);
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
            let version = u128::from(version);
            let query = MetadataQuery::CallableLocal(node.path);
            let ledger = ObservationLedger::default();
            ledger.record(query, host.answer(&query), query.domain(), None);
            self.store.insert_with(
                key(node.path),
                ledger.reads(),
                ledger.domain_receipts(),
                0,
                || EffectiveOwner {
                    values: Arc::from([]),
                    selection: Arc::new(crate::HostDeclarationSelection {
                        callable_names: Arc::from([]),
                        declared_variable_names: Arc::from([]),
                        scalar_requests: Arc::from([]),
                    }),
                    hierarchy: None,
                    callable: Some((Arc::clone(&inputs[&node.path]), version)),
                },
            );
            certificates.insert(node.path, version);
        }
        certificates
    }
}

#[cfg(test)]
#[path = "callable_tests.rs"]
mod tests;
