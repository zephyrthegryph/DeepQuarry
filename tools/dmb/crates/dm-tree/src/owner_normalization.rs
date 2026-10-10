//! Per-owner namespace/predecessor artifacts, rebound through current dense IDs.
use crate::{
    callable_namespace::{self, CallableRequest},
    declaration_contributions::{DeclarationKey, KeyedDeclarations},
    declaration_observations::{DeclarationHost, SourceAnswer, SourceDomain, SourceQuery},
    *,
};
use dm_session::{observations::ObservationLedger, ObservedArtifactStore};
use std::collections::HashSet;
mod receipts;
mod shared;
#[cfg(test)]
mod shared_tests;
use shared::NormalizedValues;
pub use shared::SharedNormalizedDeclarations;
type Ledger = ObservationLedger<SourceQuery, SourceAnswer, SourceDomain>;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ResolvedMember {
    pub key: DeclarationKey,
    pub definition: DefinitionMode,
    pub kind: MemberKind,
    pub metadata: Arc<MemberMetadata>,
    pub previous: Option<DeclarationKey>,
}
struct ResolvedOwner {
    members: Arc<[ResolvedMember]>,
}
pub(crate) struct RetainedNormalization {
    values: NormalizedValues,
    publication: std::sync::Mutex<Option<crate::member_arena::MemberPublication>>,
    hits: std::sync::atomic::AtomicUsize,
    pub(crate) metadata: Arc<crate::owner_metadata::RetainedMetadata>,
    pub(crate) storage: crate::resolver::storage_inventory::RetainedStorage,
    pub(crate) callables: crate::owner_callable::RetainedCallableOwners,
    pub(crate) paths: crate::type_paths::RetainedTypePaths,
    pub(crate) local: crate::owner_local_shape::RetainedOwnerShapes,
}
/// Explicit borrowed census; callbacks must not reenter the retained store.
pub enum NormalizationStorageView<'a> {
    PublicationIndex {
        entries: usize,
    },
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
        reads: &'a dm_session::Receipt<SourceQuery, SourceAnswer, SourceDomain>,
        versions: &'a Arc<[(SourceDomain, u128)]>,
        address: usize,
        size: usize,
    },
    Member {
        metadata: &'a Arc<MemberMetadata>,
    },
}
impl RetainedNormalization {
    /// Metadata updates publish their COW arena directly; do not keep the older
    /// structural publication rooted until a later structural rebuild.
    pub(crate) fn release_publication(&self) {
        let old = self
            .publication
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take();
        drop(old);
    }
    pub(crate) fn publish_members(
        &self,
        members: &crate::member_binding::MemberBindings<'_>,
        projection: Option<&crate::member_binding::CurrentProjection>,
    ) -> MemberArena {
        let mut current = self
            .publication
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let Some(projection) = projection else {
            let old = current.take();
            drop(current);
            drop(old);
            return members.bind_all();
        };
        let published =
            crate::member_arena::MemberPublication::publish(members, projection, current.as_ref());
        let arena = published.arena().clone();
        let old = current.replace(published);
        drop(current);
        drop(old);
        arena
    }
    pub(crate) fn with_shared(owner: Arc<SharedNormalizedDeclarations>) -> Self {
        Self {
            callables: crate::owner_callable::RetainedCallableOwners::with_shared(Arc::clone(
                &owner,
            )),
            values: NormalizedValues::shared(owner),
            ..Self::default()
        }
    }
    pub(crate) fn fresh(&self) -> Self {
        Self {
            values: self.values.fresh(),
            callables: self.callables.fresh(),
            ..Self::default()
        }
    }
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(NormalizationStorageView<'_>)) {
        use dm_session::ObservedArtifactStorageView as View;
        self.values.visit_storage(|view| match view {
            View::Store { buckets, entries } => {
                visit(NormalizationStorageView::Store { buckets, entries })
            }
            View::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => visit(NormalizationStorageView::Buffer {
                address,
                length: len.saturating_mul(element_size),
                capacity: capacity.saturating_mul(element_size),
            }),
            View::Entry {
                key,
                reads,
                versions,
                value,
            } => {
                visit(NormalizationStorageView::Entry {
                    key,
                    reads,
                    versions,
                    address: Arc::as_ptr(value) as usize,
                    size: std::mem::size_of::<ResolvedOwner>(),
                });
                let ResolvedOwner { members } = value.as_ref();
                visit(NormalizationStorageView::Buffer {
                    address: members.as_ptr() as usize,
                    length: members
                        .len()
                        .saturating_mul(std::mem::size_of::<ResolvedMember>()),
                    capacity: members
                        .len()
                        .saturating_mul(std::mem::size_of::<ResolvedMember>()),
                });
                for member in members.iter() {
                    let ResolvedMember {
                        key: _,
                        definition: _,
                        kind: _,
                        metadata,
                        previous: _,
                    } = member;
                    visit(NormalizationStorageView::Member { metadata });
                }
            }
        });
        let publication = self
            .publication
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(publication) = publication.as_ref() {
            publication.visit_storage(|address, length, capacity| {
                visit(NormalizationStorageView::Buffer {
                    address,
                    length,
                    capacity,
                })
            });
            for member in publication.arena() {
                visit(NormalizationStorageView::Member {
                    metadata: &member.metadata,
                });
            }
            visit(NormalizationStorageView::PublicationIndex {
                entries: publication.index_len(),
            });
        }
    }
}
impl Default for RetainedNormalization {
    fn default() -> Self {
        Self {
            values: NormalizedValues::Local(ObservedArtifactStore::current_revision()),
            publication: std::sync::Mutex::new(None),
            hits: std::sync::atomic::AtomicUsize::new(0),
            metadata: Arc::new(crate::owner_metadata::RetainedMetadata::default()),
            storage: crate::resolver::storage_inventory::RetainedStorage::default(),
            callables: crate::owner_callable::RetainedCallableOwners::default(),
            paths: crate::type_paths::RetainedTypePaths::default(),
            local: crate::owner_local_shape::RetainedOwnerShapes::default(),
        }
    }
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-normalization-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
pub(crate) fn observe(
    host: &DeclarationHost<'_>,
    ledger: &Ledger,
    query: SourceQuery,
) -> SourceAnswer {
    let answer = host.answer(query);
    ledger.record(query, answer.clone(), query.domain(), None);
    answer
}
pub(crate) fn parent(
    host: &DeclarationHost<'_>,
    ledger: &Ledger,
    path: SymbolId,
) -> Option<SymbolId> {
    match observe(host, ledger, SourceQuery::Parent { path }) {
        SourceAnswer::Parent(parent) => parent.flatten(),
        _ => unreachable!("typed parent query"),
    }
}
pub(crate) fn anchor(
    host: &DeclarationHost<'_>,
    ledger: &Ledger,
    owner: SymbolId,
    name: SymbolId,
) -> Option<MemberKind> {
    match observe(host, ledger, SourceQuery::CallableAnchor { owner, name }) {
        SourceAnswer::CallableAnchor(value) => value,
        _ => unreachable!("typed callable query"),
    }
}
fn record_member(
    host: &DeclarationHost<'_>,
    ledger: &Ledger,
    node: crate::member_binding::MemberView<'_>,
    mode: DefinitionMode,
    root: SymbolId,
) -> Result<(), TreeError> {
    let owner = host.tree.types[node.owner.index()].path;
    let request = CallableRequest {
        owner,
        name: node.name,
        kind: node.kind,
        mode,
        root,
    };
    callable_namespace::effective_kind_from(
        request,
        |path| parent(host, ledger, path),
        |owner, name| anchor(host, ledger, owner, name),
    );
    callable_namespace::validate_explicit_from(
        request,
        |path| parent(host, ledger, path),
        |owner, name| anchor(host, ledger, owner, name),
    )?;
    // Same-owner normalized links depend on this owner's exact authored rows.
    // Cross-owner selection includes every negative lookup before the anchor.
    let local = node
        .previous
        .is_some_and(|id| host.member_keys[id.index()].owner == owner);
    if !local {
        let mut cursor = parent(host, ledger, owner);
        while let Some(candidate) = cursor {
            if candidate == root {
                break;
            }
            if matches!(
                observe(
                    host,
                    ledger,
                    SourceQuery::SelectedPredecessor {
                        owner: candidate,
                        name: node.name,
                        kind: node.kind
                    }
                ),
                SourceAnswer::SelectedPredecessor(Some(_))
            ) {
                break;
            }
            cursor = parent(host, ledger, candidate);
        }
    }
    if mode == DefinitionMode::Override && node.previous.is_none() && node.kind == MemberKind::Var {
        let mut cursor = Some(owner);
        while let Some(candidate) = cursor {
            if matches!(
                observe(
                    host,
                    ledger,
                    SourceQuery::OpaqueField {
                        owner: candidate,
                        name: node.name
                    }
                ),
                SourceAnswer::OpaqueField(Some(_))
            ) {
                break;
            }
            cursor = parent(host, ledger, candidate);
        }
    }
    Ok(())
}
impl RetainedNormalization {
    pub(crate) fn hits(&self) -> usize {
        self.hits.load(std::sync::atomic::Ordering::Relaxed)
    }
    pub(crate) fn resolve<M: crate::member_binding::MemberWrite + ?Sized>(
        &self,
        tree: &SemanticTree,
        members: &mut M,
        modes: &[DefinitionMode],
        callable_kinds: &callable_namespace::CallableKinds,
        declarations: &KeyedDeclarations,
        current_projection: Option<&crate::member_binding::CurrentProjection>,
    ) -> Result<Option<crate::owner_metadata::OwnerContributions>, TreeError> {
        let root = SymbolId::of("/");
        let Some(current_projection) = current_projection else {
            crate::member_normalization::resolve_previous(
                tree,
                members,
                modes,
                root,
                callable_kinds,
                0..modes.len(),
            )?;
            return Ok(None);
        };
        let member_keys = &current_projection.keys;
        let owners = &current_projection.owners;
        let projection = &current_projection.ids;
        let host = DeclarationHost {
            declarations,
            tree,
            member_keys,
            callable_kinds,
        };
        let keys: Vec<_> = owners.keys().map(|owner| key(*owner)).collect();
        self.values
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let mut current = crate::owner_metadata::OwnerContributions::new();
        let mut reused = HashSet::new();
        for (owner, _) in declarations.owners() {
            let accepted = self
                .values
                .visit_explained(&key(*owner), &host, &mut |value| {
                    let indices = owners.get(owner).map(Vec::as_slice).unwrap_or(&[]);
                    value.members.len() == indices.len()
                        && value.members.iter().zip(indices).all(|(member, &index)| {
                            member.key == member_keys[index]
                                && projection.get(&member.key).is_some_and(|id| {
                                    members.member(id.index()).kind == member.kind
                                })
                                && member
                                    .previous
                                    .is_none_or(|key| projection.contains_key(&key))
                        })
                })
                .0;
            if let Some(value) = accepted {
                current.insert(*owner, Arc::clone(&value.members));
                self.hits.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                for cached in value.members.iter() {
                    let id = projection[&cached.key];
                    reused.insert(id.index());
                }
            }
        }
        let count = modes.len();
        crate::member_normalization::resolve_previous(
            tree,
            members,
            modes,
            root,
            callable_kinds,
            (0..count).filter(|index| !reused.contains(index)),
        )?;
        let receipt_pool = receipts::Pool::default();
        let branching_paths = receipts::branching_paths(tree);
        for (owner, _) in declarations.owners() {
            let Some(indices) = owners.get(owner) else {
                continue;
            };
            if indices.iter().all(|index| reused.contains(index)) {
                continue;
            }
            let ledger = Ledger::default();
            observe(&host, &ledger, SourceQuery::Owner { owner: *owner });
            let mut payload = Vec::with_capacity(indices.len());
            for &index in indices {
                record_member(&host, &ledger, members.member(index), modes[index], root)?;
                let member = members.member(index);
                payload.push(ResolvedMember {
                    key: member_keys[index],
                    definition: member.definition,
                    kind: member.kind,
                    metadata: Arc::clone(member.metadata),
                    previous: member.previous.map(|id| member_keys[id.index()]),
                });
            }
            // Current-roster mode does not use a byte budget. Zero is not a
            // fabricated heap estimate; borrowed census must report its owners.
            let payload: Arc<[ResolvedMember]> = payload.into();
            let retained = self
                .values
                .insert_with_receipt(
                    key(*owner),
                    receipts::share(ledger.reads(), &receipt_pool, &branching_paths),
                    ledger.domain_receipts(),
                    0,
                    || ResolvedOwner { members: payload },
                )
                .expect("current-roster admission is not budgeted");
            current.insert(*owner, Arc::clone(&retained.members));
        }
        for (&owner, rows) in &current {
            members.install_namespace(owner, rows, current_projection);
        }
        Ok(Some(current))
    }
}
