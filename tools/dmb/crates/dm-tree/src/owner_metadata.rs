//! Effective per-owner metadata over current keyed namespace contributions.
//! Both misses and full construction use the same inheritance resolver.
mod callables;
mod demanded_selections;
mod hierarchy;
mod selections;
pub use demanded_selections::CallableDemands;
#[cfg(test)]
mod sparse_tests;
mod variables;
use crate::{declaration_contributions::DeclarationKey, owner_normalization::ResolvedMember, *};
pub use callables::{CallableFact, CallableInputs};
use dm_session::{
    observations::{ObservationHost, ObservationLedger},
    ObservedArtifactStore,
};
use std::{
    collections::BTreeMap,
    sync::atomic::{AtomicUsize, Ordering},
};
pub use variables::{VariableFact, VariableInputs};
pub(crate) type OwnerContributions = BTreeMap<SymbolId, Arc<[ResolvedMember]>>;
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum MetadataQuery {
    NormalizedOwner(SymbolId),
    Effective(DeclarationKey),
    Hierarchy(SymbolId),
    CallableLocal(SymbolId),
    CallableSelection(SymbolId, SymbolId, bool),
    CallablePresence(SymbolId, SymbolId),
    VariableLocal(SymbolId, SymbolId),
    MemberName(SymbolId),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MetadataAnswer {
    NormalizedOwner(Option<Arc<[ResolvedMember]>>),
    Effective(Option<Arc<MemberMetadata>>),
    Hierarchy(Arc<[SymbolId]>),
    CallableLocal(Arc<CallableInputs>),
    VariableLocal(Arc<VariableInputs>),
    MemberName(bool),
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum MetadataDomain {
    Namespace,
    EffectiveMembers,
}
impl MetadataQuery {
    fn domain(self) -> MetadataDomain {
        match self {
            Self::NormalizedOwner(_) => MetadataDomain::Namespace,
            Self::Effective(_) => MetadataDomain::EffectiveMembers,
            Self::Hierarchy(_)
            | Self::CallableLocal(_)
            | Self::CallableSelection(..)
            | Self::CallablePresence(..)
            | Self::VariableLocal(..)
            | Self::MemberName(_) => MetadataDomain::Namespace,
        }
    }
}
enum EffectiveOwner {
    MemberName {
        version: u128,
    },
    Members {
        selection: Arc<crate::HostDeclarationSelection>,
        // Only fields changed by the ordinary inheritance resolver. The exact
        // normalized local roster remains in this entry's observation receipt.
        values: Arc<[(DeclarationKey, Arc<MemberMetadata>)]>,
    },
    Hierarchy {
        paths: Arc<[SymbolId]>,
        version: u128,
    },
    Callable {
        inputs: Arc<CallableInputs>,
        version: u128,
    },
    Variable {
        inputs: Arc<VariableInputs>,
        version: u128,
    },
}
impl EffectiveOwner {
    fn callable_token(&self) -> Option<u128> {
        match self {
            Self::Callable { version, .. } => Some(*version),
            _ => None,
        }
    }
    fn variable_token(&self) -> Option<u128> {
        match self {
            Self::Variable { version, .. } => Some(*version),
            _ => None,
        }
    }
}
type Store = ObservedArtifactStore<EffectiveOwner, MetadataQuery, MetadataAnswer, MetadataDomain>;
pub struct RetainedMetadata {
    store: Store,
    current_demands: demanded_selections::CurrentDemands,
    hits: AtomicUsize,
}
impl Default for RetainedMetadata {
    fn default() -> Self {
        Self {
            store: Store::current_revision(),
            current_demands: Default::default(),
            hits: AtomicUsize::new(0),
        }
    }
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-effective-metadata-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
struct Host<'a, M: ?Sized> {
    tree: &'a SemanticTree,
    normalized: &'a OwnerContributions,
    members: &'a M,
    projection: &'a std::collections::HashMap<DeclarationKey, MemberId>,
}
impl<M: crate::member_binding::MemberRead + ?Sized>
    ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host<'_, M>
{
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::NormalizedOwner(owner) => {
                MetadataAnswer::NormalizedOwner(self.normalized.get(owner).cloned())
            }
            MetadataQuery::CallableLocal(_)
            | MetadataQuery::CallableSelection(..)
            | MetadataQuery::CallablePresence(..)
            | MetadataQuery::VariableLocal(..)
            | MetadataQuery::MemberName(_) => {
                unreachable!("effective metadata records no callable certificate inputs")
            }
            MetadataQuery::Hierarchy(owner) => {
                MetadataAnswer::Hierarchy(hierarchy::ancestry(self.tree, *owner))
            }
            MetadataQuery::Effective(key) => MetadataAnswer::Effective(
                self.projection
                    .get(key)
                    .map(|id| Arc::clone(self.members.member(id.index()).metadata)),
            ),
        }
    }
}
pub enum MetadataStorageView<'a> {
    Store {
        buckets: usize,
        entries: usize,
    },
    Buffer {
        address: usize,
        length: usize,
        capacity: usize,
    },
    Entry {
        key: &'a Arc<[u8]>,
        reads: &'a dm_session::Receipt<MetadataQuery, MetadataAnswer, MetadataDomain>,
        versions: &'a Arc<[(MetadataDomain, u128)]>,
        address: usize,
        size: usize,
    },
    Values(&'a Arc<[(DeclarationKey, Arc<MemberMetadata>)]>),
    Selection(&'a Arc<crate::HostDeclarationSelection>),
    Hierarchy(&'a Arc<[SymbolId]>),
    CallableLocal(&'a Arc<CallableInputs>),
    VariableLocal(&'a Arc<VariableInputs>),
}
impl RetainedMetadata {
    pub(crate) fn hits(&self) -> usize {
        self.hits.load(Ordering::Relaxed)
    }
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(MetadataStorageView<'_>)) {
        use dm_session::ObservedArtifactStorageView as V;
        self.store.visit_storage(|view| match view {
            V::Store { buckets, entries } => visit(MetadataStorageView::Store { buckets, entries }),
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => visit(MetadataStorageView::Buffer {
                address,
                length: len.saturating_mul(element_size),
                capacity: capacity.saturating_mul(element_size),
            }),
            V::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                visit(MetadataStorageView::Entry {
                    key,
                    reads,
                    versions,
                    address: Arc::as_ptr(value) as usize,
                    size: std::mem::size_of::<EffectiveOwner>(),
                });
                match value.as_ref() {
                    EffectiveOwner::Members { values, selection } => {
                        visit(MetadataStorageView::Values(values));
                        visit(MetadataStorageView::Selection(selection));
                    }
                    EffectiveOwner::Callable { inputs, .. } => {
                        visit(MetadataStorageView::CallableLocal(inputs))
                    }
                    EffectiveOwner::MemberName { .. } => (),
                    EffectiveOwner::Variable { inputs, .. } => {
                        visit(MetadataStorageView::VariableLocal(inputs))
                    }
                    EffectiveOwner::Hierarchy { paths, .. } => {
                        visit(MetadataStorageView::Hierarchy(paths))
                    }
                }
            }
        });
    }
    pub(crate) fn resolve<M: crate::member_binding::MemberWrite + ?Sized>(
        &self,
        tree: &SemanticTree,
        members: &mut M,
        normalized: &OwnerContributions,
        order: &[MemberId],
        current_projection: &crate::member_binding::CurrentProjection,
    ) -> crate::host_declaration_selection::Selections {
        let mut selections = crate::host_declaration_selection::Selections::new();
        let projection = &current_projection.ids;
        let keys_by_id = &current_projection.keys;
        let mut by_owner = BTreeMap::<SymbolId, Vec<MemberId>>::new();
        for &id in order {
            by_owner
                .entry(tree.types[members.member(id.index()).owner.index()].path)
                .or_default()
                .push(id);
        }
        if current_projection.keys.len() != order.len() {
            crate::metadata_update::resolve_metadata(tree, members, order);
            return crate::host_declaration_selection::collect(
                tree,
                members,
                order.iter().copied(),
            );
        }
        let keys: Vec<_> = normalized.keys().map(|&owner| key(owner)).collect();
        let mut keys = keys;
        keys.extend(tree.types.iter().map(|node| hierarchy::key(node.path)));
        keys.extend(tree.types.iter().map(|node| callables::key(node.path)));
        keys.extend(selections::keys(tree, &*members, order));
        keys.extend(self.demanded_keys(tree));
        self.store
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let owners = crate::metadata_update::dependency_order(tree.types.len(), |index| {
            tree.types[index].parent.map(|id| id.index())
        });
        for owner_index in owners {
            let owner = tree.types[owner_index].path;
            let Some(ids) = by_owner.get(&owner) else {
                continue;
            };
            let (accepted, reads, versions) = {
                let host = Host {
                    tree,
                    normalized,
                    members: &*members,
                    projection,
                };
                let accepted = self
                    .store
                    .visit_explained(&key(owner), &host, &mut |value| match value.as_ref() {
                        EffectiveOwner::Members { values, .. } => values
                            .iter()
                            .all(|(key, _)| key.owner == owner && projection.contains_key(key)),
                        _ => false,
                    })
                    .0;
                let ledger = ObservationLedger::default();
                if accepted.is_none() {
                    let query = MetadataQuery::NormalizedOwner(owner);
                    ledger.record(query, host.answer(&query), query.domain(), None);
                    for &id in ids {
                        let member = members.member(id.index());
                        if member.definition == DefinitionMode::Override
                            && member.kind == MemberKind::Var
                        {
                            if let Some(previous) = member.previous {
                                if members.member(previous.index()).owner != member.owner {
                                    let query =
                                        MetadataQuery::Effective(keys_by_id[previous.index()]);
                                    ledger.record(query, host.answer(&query), query.domain(), None);
                                }
                            }
                        }
                    }
                }
                (accepted, ledger.reads(), ledger.domain_receipts())
            };
            if let Some(value) = accepted {
                let EffectiveOwner::Members { selection, values } = value.as_ref() else {
                    unreachable!("member payload admitted above")
                };
                self.hits.fetch_add(1, Ordering::Relaxed);
                selections.insert(owner, Arc::clone(selection));
                // Current exact normalized observations, not old dense IDs,
                // supply every unchanged local field before applying deltas.
                // Namespace admission installed the exact current immutable local
                // owner before this pass. Only effective deltas need rebinding.
                for (key, metadata) in values.iter() {
                    members.set_metadata(projection[key].index(), Arc::clone(metadata));
                }
            } else {
                crate::metadata_update::resolve_metadata(tree, members, ids);
                let values: Arc<[_]> = normalized[&owner]
                    .iter()
                    .filter_map(|input| {
                        let effective = members.member(projection[&input.key].index()).metadata;
                        (!(Arc::ptr_eq(effective, &input.metadata) || effective == &input.metadata))
                            .then(|| (input.key, Arc::clone(effective)))
                    })
                    .collect::<Vec<_>>()
                    .into();
                // Full-current-roster retention has no fabricated byte weight;
                // exact retained owners are exposed to the diagnostic census.
                let selection =
                    crate::host_declaration_selection::select(owner, members, ids.iter().copied());
                selections.insert(owner, Arc::clone(&selection));
                self.store.insert_with(key(owner), reads, versions, 0, || {
                    EffectiveOwner::Members { values, selection }
                });
            }
        }
        selections
    }
}

impl std::fmt::Debug for RetainedMetadata {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RetainedMetadata").finish_non_exhaustive()
    }
}
