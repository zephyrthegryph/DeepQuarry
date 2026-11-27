//! Effective per-owner metadata over current keyed namespace contributions.
//! Both misses and full construction use the same inheritance resolver.
mod hierarchy;
pub(crate) use hierarchy::ancestry;
#[cfg(test)]
mod sparse_tests;
use crate::{
    declaration_contributions::{DeclarationKey, KeyedDeclarations},
    owner_normalization::ResolvedMember,
    *,
};
use dm_session::{
    observations::{ObservationHost, ObservationLedger},
    ObservedArtifactStore,
};
use std::{
    collections::BTreeMap,
    sync::atomic::{AtomicUsize, Ordering},
};
pub(crate) type OwnerContributions = BTreeMap<SymbolId, Arc<[ResolvedMember]>>;
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum MetadataQuery {
    NormalizedOwner(SymbolId),
    Effective(DeclarationKey),
    Hierarchy(SymbolId),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MetadataAnswer {
    NormalizedOwner(Option<Arc<[ResolvedMember]>>),
    Effective(Option<Arc<MemberMetadata>>),
    Hierarchy(Arc<[SymbolId]>),
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
            Self::Hierarchy(_) => MetadataDomain::Namespace,
        }
    }
}
pub(crate) enum EffectiveOwner {
    Members {
        selection: Arc<crate::HostDeclarationSelection>,
        // Only fields changed by the ordinary inheritance resolver. The exact
        // normalized local roster remains in this entry's observation receipt.
        values: Arc<[(DeclarationKey, Arc<MemberMetadata>)]>,
    },
    Hierarchy {
        paths: Arc<[SymbolId]>,
    },
}
type SharedStore = ObservedArtifactStore<EffectiveOwner, MetadataQuery, MetadataAnswer, MetadataDomain>;
type Lease = dm_session::ObservedArtifactLease<EffectiveOwner, MetadataQuery, MetadataAnswer, MetadataDomain>;
type StorageView<'a> = dm_session::ObservedArtifactStorageView<'a, EffectiveOwner, MetadataQuery, MetadataAnswer, MetadataDomain>;
type Reads = Vec<dm_session::Observation<MetadataQuery, MetadataAnswer, MetadataDomain>>;
/// The engine-scoped store every define variant of a session publishes effective owner metadata into: an owner whose
/// recorded reads still hold under another variant's world is one allocation, not two.
pub(crate) type SharedMetadataStore = SharedStore;
/// A host's metadata artifacts: its own current-revision store, or a lease on the engine-shared store (union of host rosters).
enum Store {
    Local(SharedStore),
    Shared { owner: Arc<SharedStore>, lease: Lease },
}
impl Store {
    fn current_revision() -> Self {
        Self::Local(SharedStore::current_revision())
    }
    fn shared(owner: Arc<SharedStore>) -> Self {
        let lease = owner.lease();
        Self::Shared { owner, lease }
    }
    fn fresh(&self) -> Self {
        match self {
            Self::Local(_) => Self::current_revision(),
            Self::Shared { owner, .. } => Self::shared(Arc::clone(owner)),
        }
    }
    fn visit_storage(&self, visit: impl FnMut(StorageView<'_>)) {
        match self {
            Self::Local(store) => store.visit_storage(visit),
            Self::Shared { lease, .. } => lease.visit_storage(visit),
        }
    }
    fn retain_current_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        match self {
            Self::Local(store) => store.retain_current_keys(keys),
            Self::Shared { lease, .. } => lease.retain_current_keys(keys),
        }
    }
    fn lookup<R: ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain>>(
        &self,
        key: &[u8],
        host: &R,
    ) -> Option<Arc<EffectiveOwner>> {
        match self {
            Self::Local(store) => store.lookup(key, host),
            Self::Shared { lease, .. } => lease.visit_explained(key, host, &mut |_| true).0,
        }
    }
    fn visit_explained<R: ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain>>(
        &self,
        key: &[u8],
        host: &R,
        accept: &mut dyn FnMut(&Arc<EffectiveOwner>) -> bool,
    ) -> (Option<Arc<EffectiveOwner>>, Option<MetadataQuery>) {
        match self {
            Self::Local(store) => store.visit_explained(key, host, accept),
            Self::Shared { lease, .. } => lease.visit_explained(key, host, accept),
        }
    }
    fn insert_with(
        &self,
        key: Arc<[u8]>,
        reads: Reads,
        weight: usize,
        create: impl FnOnce() -> EffectiveOwner,
    ) -> bool {
        match self {
            Self::Local(store) => store.insert_with(key, reads, weight, create),
            Self::Shared { lease, .. } => lease.insert_with(key, reads, weight, create),
        }
    }
}
/// Cumulative diagnostic counts for the effective metadata artifact stage.
/// Stable-roster updates outside this stage are not included.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MetadataResolutionStats {
    pub common_resolved_members: usize,
    pub structurally_reused_members: usize,
    pub structurally_dirty_members: usize,
}
pub struct RetainedMetadata {
    store: Store,
    hits: AtomicUsize,
    common_resolved_members: AtomicUsize,
    structurally_reused_members: AtomicUsize,
    structurally_dirty_members: AtomicUsize,
}
impl RetainedMetadata {
    pub(crate) fn with_shared(owner: Arc<SharedMetadataStore>) -> Self {
        Self { store: Store::shared(owner), ..Self::default() }
    }
    pub(crate) fn fresh(&self) -> Self {
        Self { store: self.store.fresh(), ..Self::default() }
    }
}
impl Default for RetainedMetadata {
    fn default() -> Self {
        Self {
            store: Store::current_revision(),
            hits: AtomicUsize::new(0),
            common_resolved_members: AtomicUsize::new(0),
            structurally_reused_members: AtomicUsize::new(0),
            structurally_dirty_members: AtomicUsize::new(0),
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
        address: usize,
        size: usize,
    },
    Values(&'a Arc<[(DeclarationKey, Arc<MemberMetadata>)]>),
    Selection(&'a Arc<crate::HostDeclarationSelection>),
    Hierarchy(&'a Arc<[SymbolId]>),
}
impl RetainedMetadata {
    pub fn resolution_stats(&self) -> MetadataResolutionStats {
        MetadataResolutionStats {
            common_resolved_members: self.common_resolved_members.load(Ordering::Relaxed),
            structurally_reused_members: self.structurally_reused_members.load(Ordering::Relaxed),
            structurally_dirty_members: self.structurally_dirty_members.load(Ordering::Relaxed),
        }
    }
    fn count(counter: &AtomicUsize, amount: usize) {
        let _ = counter.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |previous| {
            Some(previous.saturating_add(amount))
        });
    }
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
                value,
            } => {
                visit(MetadataStorageView::Entry {
                    key,
                    reads,
                    address: Arc::as_ptr(value) as usize,
                    size: std::mem::size_of::<EffectiveOwner>(),
                });
                match value.as_ref() {
                    EffectiveOwner::Members { values, selection } => {
                        visit(MetadataStorageView::Values(values));
                        visit(MetadataStorageView::Selection(selection));
                    }
                    EffectiveOwner::Hierarchy { paths } => {
                        visit(MetadataStorageView::Hierarchy(paths))
                    }
                }
            }
        });
    }
    pub(crate) fn resolve<M: crate::member_binding::MemberWrite + Sync + ?Sized>(
        &self,
        tree: &SemanticTree,
        members: &mut M,
        normalized: &OwnerContributions,
        order: &[MemberId],
        current_projection: &crate::member_binding::CurrentProjection,
        structural: Option<(
            crate::metadata_update::StructuralMetadata<'_>,
            &KeyedDeclarations,
        )>,
        executor: Option<&dm_exec::BuildExecutor>,
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
            Self::count(&self.common_resolved_members, order.len());
            crate::metadata_update::resolve_metadata(tree, members, order);
            return crate::host_declaration_selection::collect(
                tree,
                members,
                order.iter().copied(),
            );
        }
        let structural_timer = dm_profile::detail_timer("tree.metadata.structural_apply");
        let structural_dirty = structural.and_then(|(prior, declarations)| {
            prior.apply(tree, declarations, members, current_projection, order)
        });
        drop(structural_timer);
        if let Some(dirty) = &structural_dirty {
            Self::count(&self.structurally_dirty_members, dirty.len());
            Self::count(
                &self.structurally_reused_members,
                order.len().saturating_sub(dirty.len()),
            );
        }
        let keys_timer = dm_profile::detail_timer("tree.metadata.keys_and_retain");
        let keys: Vec<_> = normalized.keys().map(|&owner| key(owner)).collect();
        let mut keys = keys;
        keys.extend(tree.types.iter().map(|node| hierarchy::key(node.path)));
        self.store
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        drop(keys_timer);
        let _owner_loop_timer = dm_profile::detail_timer("tree.metadata.owner_loop");
        // Owners by depth below the root: a member's predecessor is in its own
        // owner or an ancestor, so the owners of one depth are independent once
        // the shallower ones are applied. Each owner resolves over the shared
        // members with its own overlay, on every core when a depth has many;
        // the overlays are applied in owner order before the next depth.
        let owners = crate::metadata_update::dependency_order(tree.types.len(), |index| {
            tree.types[index].parent.map(|id| id.index())
        });
        let mut depths = vec![0usize; tree.types.len()];
        let mut levels = BTreeMap::<usize, Vec<SymbolId>>::new();
        for owner_index in owners {
            depths[owner_index] = tree.types[owner_index].parent.map_or(0, |id| depths[id.index()] + 1);
            let owner = tree.types[owner_index].path;
            if by_owner.contains_key(&owner) {
                levels.entry(depths[owner_index]).or_default().push(owner);
            }
        }
        for level in levels.into_values() {
            let outcomes: Vec<OwnerOutcome> = {
                let members: &M = &*members;
                let resolve_owner = |owner: SymbolId| -> OwnerOutcome {
                    let ids = &by_owner[&owner];
                    let (accepted, reads) = {
                        let host = Host {
                            tree,
                            normalized,
                            members,
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
                            ledger.record(query, host.answer(&query), query.domain());
                            for &id in ids {
                                let member = members.member(id.index());
                                if member.definition == DefinitionMode::Override
                                    && member.kind == MemberKind::Var
                                {
                                    if let Some(previous) = member.previous {
                                        if members.member(previous.index()).owner != member.owner {
                                            let query =
                                                MetadataQuery::Effective(keys_by_id[previous.index()]);
                                            ledger.record(query, host.answer(&query), query.domain());
                                        }
                                    }
                                }
                            }
                        }
                        (accepted, ledger.reads())
                    };
                    if let Some(value) = accepted {
                        let EffectiveOwner::Members { selection, values } = value.as_ref() else {
                            unreachable!("member payload admitted above")
                        };
                        self.hits.fetch_add(1, Ordering::Relaxed);
                        // Current exact normalized observations, not old dense IDs,
                        // supply every unchanged local field before applying deltas.
                        // Namespace admission installed the exact current immutable local
                        // owner before this pass. Only effective deltas need rebinding.
                        OwnerOutcome {
                            owner,
                            selection: Arc::clone(selection),
                            metadata: values
                                .iter()
                                .map(|(key, metadata)| (projection[key].index(), Arc::clone(metadata)))
                                .collect(),
                            previous: Vec::new(),
                        }
                    } else {
                        let dirty_ids;
                        let resolve_ids = if let Some(dirty) = &structural_dirty {
                            dirty_ids = ids
                                .iter()
                                .copied()
                                .filter(|id| dirty.contains(&keys_by_id[id.index()]))
                                .collect::<Vec<_>>();
                            dirty_ids.as_slice()
                        } else {
                            ids.as_slice()
                        };
                        Self::count(&self.common_resolved_members, resolve_ids.len());
                        let mut overlay = OwnerOverlay::new(members);
                        crate::metadata_update::resolve_metadata(tree, &mut overlay, resolve_ids);
                        let values: Arc<[_]> = normalized[&owner]
                            .iter()
                            .filter_map(|input| {
                                let effective = overlay.member(projection[&input.key].index()).metadata;
                                (!(Arc::ptr_eq(effective, &input.metadata) || effective == &input.metadata))
                                    .then(|| (input.key, Arc::clone(effective)))
                            })
                            .collect::<Vec<_>>()
                            .into();
                        // Full-current-roster retention has no fabricated byte weight;
                        // exact retained owners are exposed to the diagnostic census.
                        let selection =
                            crate::host_declaration_selection::select(owner, &overlay, ids.iter().copied());
                        self.store.insert_with(key(owner), reads,0, || {
                            EffectiveOwner::Members { values, selection: Arc::clone(&selection) }
                        });
                        let (metadata, previous) = overlay.into_writes();
                        OwnerOutcome { owner, selection, metadata, previous }
                    }

                };
                match executor {
                    Some(executor) => crate::frontend::parallel::chunked_map_above(executor, &level, 256, |_, part| {
                        Ok::<_, std::convert::Infallible>(part.iter().map(|&owner| resolve_owner(owner)).collect())
                    })
                    .unwrap_or_else(|never| match never {}),
                    None => level.iter().map(|&owner| resolve_owner(owner)).collect(),
                }
            };
            for outcome in outcomes {
                for (index, metadata) in outcome.metadata {
                    members.set_metadata(index, metadata);
                }
                for (index, previous) in outcome.previous {
                    members.set_previous(index, previous);
                }
                selections.insert(outcome.owner, outcome.selection);
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

/// One owner's effective metadata, computed over the shared current members.
struct OwnerOutcome {
    owner: SymbolId,
    selection: Arc<crate::host_declaration_selection::HostDeclarationSelection>,
    metadata: Vec<(usize, Arc<MemberMetadata>)>,
    previous: Vec<(usize, Option<MemberId>)>,
}

/// One owner's writes over shared current members: reads see the writes first.
struct OwnerOverlay<'a, M: ?Sized> {
    base: &'a M,
    metadata: std::collections::HashMap<usize, Arc<MemberMetadata>>,
    previous: std::collections::HashMap<usize, Option<MemberId>>,
}
impl<'a, M: crate::member_binding::MemberRead + ?Sized> OwnerOverlay<'a, M> {
    fn new(base: &'a M) -> Self {
        Self { base, metadata: Default::default(), previous: Default::default() }
    }
    /// The writes in index order (the order the members are later written in does not matter).
    #[allow(clippy::type_complexity)]
    fn into_writes(self) -> (Vec<(usize, Arc<MemberMetadata>)>, Vec<(usize, Option<MemberId>)>) {
        let mut metadata: Vec<_> = self.metadata.into_iter().collect();
        metadata.sort_unstable_by_key(|write| write.0);
        let mut previous: Vec<_> = self.previous.into_iter().collect();
        previous.sort_unstable_by_key(|write| write.0);
        (metadata, previous)
    }
}
impl<M: crate::member_binding::MemberRead + ?Sized> crate::member_binding::MemberRead for OwnerOverlay<'_, M> {
    fn member(&self, index: usize) -> crate::member_binding::MemberView<'_> {
        let mut row = self.base.member(index);
        if let Some(metadata) = self.metadata.get(&index) {
            row.metadata = metadata;
        }
        if let Some(previous) = self.previous.get(&index) {
            row.previous = *previous;
        }
        row
    }
}
impl<M: crate::member_binding::MemberRead + ?Sized> crate::member_binding::MemberWrite for OwnerOverlay<'_, M> {
    fn set_previous(&mut self, index: usize, previous: Option<MemberId>) {
        if self.member(index).previous != previous {
            self.previous.insert(index, previous);
        }
    }
    fn set_metadata(&mut self, index: usize, metadata: Arc<MemberMetadata>) {
        let current = self.member(index).metadata;
        if !(Arc::ptr_eq(current, &metadata) || current == &metadata) {
            self.metadata.insert(index, metadata);
        }
    }
}
