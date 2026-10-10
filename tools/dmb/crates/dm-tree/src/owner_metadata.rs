//! Effective per-owner metadata over current keyed namespace contributions.
//! Both misses and full construction use the same inheritance resolver.
use crate::{declaration_contributions::DeclarationKey, owner_normalization::ResolvedMember, *};
use dm_session::{
    observations::{Observation, ObservationHost, ObservationLedger},
    ObservedArtifactStore,
};
use std::{
    collections::BTreeMap,
    ops::{Index, IndexMut},
    sync::atomic::{AtomicUsize, Ordering},
};
pub(crate) type OwnerContributions = BTreeMap<SymbolId, Arc<[ResolvedMember]>>;
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum MetadataQuery {
    NormalizedOwner(SymbolId),
    Effective(DeclarationKey),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MetadataAnswer {
    NormalizedOwner(Option<Arc<[ResolvedMember]>>),
    Effective(Option<Arc<MemberMetadata>>),
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
        }
    }
}
struct EffectiveOwner {
    selection: Arc<crate::HostDeclarationSelection>,
    values: Arc<[(DeclarationKey, Arc<MemberMetadata>)]>,
}
type Store = ObservedArtifactStore<EffectiveOwner, MetadataQuery, MetadataAnswer, MetadataDomain>;
pub(crate) struct RetainedMetadata {
    store: Store,
    hits: AtomicUsize,
}
impl Default for RetainedMetadata {
    fn default() -> Self {
        Self {
            store: Store::current_revision(),
            hits: AtomicUsize::new(0),
        }
    }
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-effective-metadata-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
struct Host<'a, M> {
    normalized: &'a OwnerContributions,
    members: &'a M,
    projection: &'a BTreeMap<DeclarationKey, MemberId>,
}
impl<M: Index<usize, Output = MemberNode>>
    ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host<'_, M>
{
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::NormalizedOwner(owner) => {
                MetadataAnswer::NormalizedOwner(self.normalized.get(owner).cloned())
            }
            MetadataQuery::Effective(key) => MetadataAnswer::Effective(
                self.projection
                    .get(key)
                    .map(|id| Arc::clone(&self.members[id.index()].metadata)),
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
        reads: &'a Arc<[Observation<MetadataQuery, MetadataAnswer, MetadataDomain>]>,
        versions: &'a Arc<[(MetadataDomain, u128)]>,
        address: usize,
        size: usize,
    },
    Values(&'a Arc<[(DeclarationKey, Arc<MemberMetadata>)]>),
    Selection(&'a Arc<crate::HostDeclarationSelection>),
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
                visit(MetadataStorageView::Values(&value.values));
                visit(MetadataStorageView::Selection(&value.selection));
            }
        });
    }
    pub(crate) fn resolve<M: Index<usize, Output = MemberNode> + IndexMut<usize>>(
        &self,
        tree: &SemanticTree,
        members: &mut M,
        normalized: &OwnerContributions,
        order: &[MemberId],
    ) -> crate::host_declaration_selection::Selections {
        let mut selections = crate::host_declaration_selection::Selections::new();
        let mut projection = BTreeMap::new();
        let mut keys_by_id = std::collections::HashMap::new();
        // Current projection is certified by the successful namespace phase;
        // matching owner-local source order determines the new dense IDs.
        let mut by_owner = BTreeMap::<SymbolId, Vec<MemberId>>::new();
        for &id in order {
            by_owner
                .entry(tree.types[members[id.index()].owner.index()].path)
                .or_default()
                .push(id);
        }
        for (owner, source) in normalized {
            let Some(ids) = by_owner.get(owner) else {
                continue;
            };
            let mut ids = ids.clone();
            ids.sort_unstable_by_key(|id| id.index());
            if ids.len() != source.len() {
                crate::metadata_update::resolve_metadata(tree, members, order);
                return crate::host_declaration_selection::collect(
                    tree,
                    members,
                    order.iter().copied(),
                );
            }
            for (input, id) in source.iter().zip(ids) {
                projection.insert(input.key, id);
                keys_by_id.insert(id, input.key);
            }
        }
        if projection.len() != order.len() {
            crate::metadata_update::resolve_metadata(tree, members, order);
            return crate::host_declaration_selection::collect(
                tree,
                members,
                order.iter().copied(),
            );
        }
        let keys: Vec<_> = normalized.keys().map(|&owner| key(owner)).collect();
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
                    normalized,
                    members: &*members,
                    projection: &projection,
                };
                let accepted = self.store.lookup(&key(owner), &host);
                let ledger = ObservationLedger::default();
                if accepted.is_none() {
                    let query = MetadataQuery::NormalizedOwner(owner);
                    ledger.record(query, host.answer(&query), query.domain(), None);
                    for &id in ids {
                        let member = &members[id.index()];
                        if member.definition == DefinitionMode::Override
                            && member.kind == MemberKind::Var
                        {
                            if let Some(previous) = member.previous {
                                if members[previous.index()].owner != member.owner {
                                    let query = MetadataQuery::Effective(keys_by_id[&previous]);
                                    ledger.record(query, host.answer(&query), query.domain(), None);
                                }
                            }
                        }
                    }
                }
                (accepted, ledger.reads(), ledger.domain_receipts())
            };
            if let Some(value) = accepted {
                self.hits.fetch_add(1, Ordering::Relaxed);
                selections.insert(owner, Arc::clone(&value.selection));
                for (key, metadata) in value.values.iter() {
                    members[projection[key].index()].metadata = Arc::clone(metadata);
                }
            } else {
                crate::metadata_update::resolve_metadata(tree, members, ids);
                let values: Arc<[_]> = ids
                    .iter()
                    .map(|&id| (keys_by_id[&id], Arc::clone(&members[id.index()].metadata)))
                    .collect::<Vec<_>>()
                    .into();
                // Full-current-roster retention has no fabricated byte weight;
                // exact retained owners are exposed to the diagnostic census.
                let selection =
                    crate::host_declaration_selection::select(owner, members, ids.iter().copied());
                selections.insert(owner, Arc::clone(&selection));
                self.store
                    .insert_with(key(owner), reads, versions, 0, || EffectiveOwner {
                        values,
                        selection,
                    });
            }
        }
        selections
    }
}
