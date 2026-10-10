//! Per-owner namespace/predecessor artifacts, rebound through current dense IDs.
use crate::{
    callable_namespace::{self, CallableRequest},
    declaration_contributions::{DeclarationKey, KeyedDeclarations},
    declaration_observations::{DeclarationHost, SourceAnswer, SourceDomain, SourceQuery},
    *,
};
use dm_session::{observations::ObservationLedger, ObservedArtifactStore};
use std::collections::{HashMap, HashSet};
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
    hits: std::sync::atomic::AtomicUsize,
    pub(crate) metadata: Arc<crate::owner_metadata::RetainedMetadata>,
    pub(crate) storage: crate::resolver::storage_inventory::RetainedStorage,
    pub(crate) callables: crate::owner_callable::RetainedCallableOwners,
    pub(crate) paths: crate::type_paths::RetainedTypePaths,
    pub(crate) local: crate::owner_local_shape::RetainedOwnerShapes,
}
/// Explicit borrowed census; callbacks must not reenter the retained store.
pub enum NormalizationStorageView<'a> {
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
        reads: &'a Arc<
            [dm_session::observations::Observation<SourceQuery, SourceAnswer, SourceDomain>],
        >,
        versions: &'a Arc<[(SourceDomain, u128)]>,
        address: usize,
        size: usize,
    },
    Member {
        metadata: &'a Arc<MemberMetadata>,
    },
}
impl RetainedNormalization {
    pub(crate) fn with_shared(owner: Arc<SharedNormalizedDeclarations>) -> Self {
        Self {
            values: NormalizedValues::shared(owner),
            ..Self::default()
        }
    }
    pub(crate) fn fresh(&self) -> Self {
        Self {
            values: self.values.fresh(),
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
    }
}
impl Default for RetainedNormalization {
    fn default() -> Self {
        Self {
            values: NormalizedValues::Local(ObservedArtifactStore::current_revision()),
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
    node: &MemberNode,
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
    pub(crate) fn resolve(
        &self,
        tree: &SemanticTree,
        members: &mut [MemberNode],
        modes: &[DefinitionMode],
        callable_kinds: &callable_namespace::CallableKinds,
        declarations: &KeyedDeclarations,
    ) -> Result<Option<crate::owner_metadata::OwnerContributions>, TreeError> {
        let root = SymbolId::of("/");
        let member_keys: Vec<_> = declarations
            .ordered()
            .filter_map(|row| matches!(row.skeleton, Skeleton::Member { .. }).then_some(row.key))
            .collect();
        if member_keys.len() != members.len() {
            let count = members.len();
            crate::member_normalization::resolve_previous(
                tree,
                members,
                modes,
                root,
                callable_kinds,
                0..count,
            )?;
            return Ok(None);
        }
        let mut owners = std::collections::BTreeMap::<SymbolId, Vec<usize>>::new();
        for (index, key) in member_keys.iter().enumerate() {
            owners.entry(key.owner).or_default().push(index);
        }
        let projection: HashMap<_, _> = member_keys
            .iter()
            .enumerate()
            .map(|(index, key)| (*key, MemberId(index as u32)))
            .collect();
        let host = DeclarationHost {
            declarations,
            tree,
            member_keys: &member_keys,
            callable_kinds,
        };
        let keys: Vec<_> = declarations
            .owners()
            .map(|(owner, _)| key(*owner))
            .collect();
        self.values
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let mut current = crate::owner_metadata::OwnerContributions::new();
        let mut reused = HashSet::new();
        for (owner, _) in declarations.owners() {
            let accepted = self
                .values
                .visit_explained(&key(*owner), &host, &mut |value| {
                    value.members.iter().all(|member| {
                        projection
                            .get(&member.key)
                            .is_some_and(|id| members[id.index()].kind == member.kind)
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
                    members[id.index()].previous = cached.previous.map(|key| projection[&key]);
                    members[id.index()].metadata = Arc::clone(&cached.metadata);
                    reused.insert(id.index());
                }
            }
        }
        let count = members.len();
        crate::member_normalization::resolve_previous(
            tree,
            members,
            modes,
            root,
            callable_kinds,
            (0..count).filter(|index| !reused.contains(index)),
        )?;
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
                record_member(&host, &ledger, &members[index], modes[index], root)?;
                payload.push(ResolvedMember {
                    key: member_keys[index],
                    definition: members[index].definition,
                    kind: members[index].kind,
                    metadata: Arc::clone(&members[index].metadata),
                    previous: members[index].previous.map(|id| member_keys[id.index()]),
                });
            }
            // Current-roster mode does not use a byte budget. Zero is not a
            // fabricated heap estimate; borrowed census must report its owners.
            let payload: Arc<[ResolvedMember]> = payload.into();
            let retained = self
                .values
                .insert_with_owned(
                    key(*owner),
                    ledger.reads(),
                    ledger.domain_receipts(),
                    0,
                    || ResolvedOwner { members: payload },
                )
                .expect("current-roster admission is not budgeted");
            current.insert(*owner, Arc::clone(&retained.members));
        }
        Ok(Some(current))
    }
}
