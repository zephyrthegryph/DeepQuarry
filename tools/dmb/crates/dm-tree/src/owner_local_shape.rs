//! Immutable local namespace shapes; current IDs are assigned separately.
use crate::{
    callable_namespace::{self, CallableRequest},
    declaration_contributions::{DeclarationFamily, DeclarationKey, KeyedDeclarations},
    declaration_observations::{DeclarationHost, SourceAnswer, SourceDomain, SourceQuery},
    *,
};
use dm_session::{ObservationLedger, ObservedArtifactStore};
use std::{
    collections::BTreeMap,
    sync::atomic::{AtomicUsize, Ordering},
};
#[cfg(test)]
mod validation_tests;
#[derive(Clone, Copy, Debug)]
pub struct LocalMember {
    pub key: DeclarationKey,
    pub kind: MemberKind,
    pub previous: Option<DeclarationKey>,
}
pub struct LocalOwner {
    pub rows: Arc<[Option<LocalMember>]>,
    pub selectors: Arc<[((SymbolId, MemberKind), DeclarationKey)]>,
    pub(crate) first_failure: Option<(DeclarationKey, LocalValidationFailure)>,
}
#[derive(Clone, Copy, Debug)]
pub(crate) enum LocalValidationFailure {
    UnknownSymbol(SymbolId),
    Duplicate {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
}
impl LocalValidationFailure {
    pub(crate) fn error(self) -> TreeError {
        match self {
            Self::UnknownSymbol(name) => TreeError::UnknownSymbol(name),
            Self::Duplicate { owner, name, kind } => TreeError::Duplicate { owner, name, kind },
        }
    }
}
pub(crate) type LocalOwners = BTreeMap<SymbolId, Arc<LocalOwner>>;
type Store = ObservedArtifactStore<LocalOwner, SourceQuery, SourceAnswer, SourceDomain>;
pub(crate) struct RetainedOwnerShapes {
    store: Store,
    hits: AtomicUsize,
}
impl Default for RetainedOwnerShapes {
    fn default() -> Self {
        Self {
            store: Store::current_revision(),
            hits: AtomicUsize::new(0),
        }
    }
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut value = b"owner-local-shape-v2".to_vec();
    value.extend_from_slice(&owner.bits().to_le_bytes());
    value.into()
}
pub enum LocalShapeStorageView<'a> {
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
    Payload {
        rows: &'a Arc<[Option<LocalMember>]>,
        selectors: &'a Arc<[((SymbolId, MemberKind), DeclarationKey)]>,
    },
}
impl RetainedOwnerShapes {
    pub(crate) fn hits(&self) -> usize {
        self.hits.load(Ordering::Relaxed)
    }
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(LocalShapeStorageView<'_>)) {
        use dm_session::ObservedArtifactStorageView as V;
        self.store.visit_storage(|view| match view {
            V::Store { buckets, entries } => {
                visit(LocalShapeStorageView::Store { buckets, entries })
            }
            V::Bucket {
                address,
                len,
                capacity,
                element_size,
            } => visit(LocalShapeStorageView::Buffer {
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
                visit(LocalShapeStorageView::Entry {
                    key,
                    reads,
                    versions,
                    address: Arc::as_ptr(value) as usize,
                    size: std::mem::size_of::<LocalOwner>(),
                });
                visit(LocalShapeStorageView::Payload {
                    rows: &value.rows,
                    selectors: &value.selectors,
                });
            }
        });
    }
    pub(crate) fn prepare(
        &self,
        tree: &SemanticTree,
        declarations: &KeyedDeclarations,
        callable_kinds: &callable_namespace::CallableKinds,
    ) -> LocalOwners {
        let keys: Vec<_> = declarations
            .owners()
            .map(|(owner, _)| key(*owner))
            .collect();
        self.store
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let host = DeclarationHost {
            declarations,
            tree,
            member_keys: &[],
            callable_kinds,
        };
        let mut result = LocalOwners::new();
        for (owner, contribution) in declarations.owners() {
            if let Some(payload) = self.store.lookup(&key(*owner), &host) {
                self.hits.fetch_add(1, Ordering::Relaxed);
                result.insert(*owner, payload);
                continue;
            }
            let ledger = ObservationLedger::default();
            crate::owner_normalization::observe(
                &host,
                &ledger,
                SourceQuery::OwnerShape { owner: *owner },
            );
            let mut rows = vec![None; contribution.shared_shape().len()];
            let mut groups = BTreeMap::<(SymbolId, MemberKind), Vec<usize>>::new();
            let mut formal = std::collections::BTreeSet::new();
            let mut first_failure = None;
            for (index, shape) in contribution.shared_shape().iter().enumerate() {
                if let DeclarationFamily::Member { name, kind } = shape.key.family {
                    let present = crate::owner_normalization::observe(
                        &host,
                        &ledger,
                        SourceQuery::SymbolPresence { name },
                    );
                    if present == SourceAnswer::SymbolPresence(false) && first_failure.is_none() {
                        first_failure =
                            Some((shape.key, LocalValidationFailure::UnknownSymbol(name)));
                    }
                    let mode = shape.mode.expect("member shape has definition mode");
                    let kind = callable_namespace::effective_kind_from(
                        CallableRequest {
                            owner: *owner,
                            name,
                            kind,
                            mode,
                            root: SymbolId::of("/"),
                        },
                        |path| crate::owner_normalization::parent(&host, &ledger, path),
                        |owner, name| {
                            crate::owner_normalization::anchor(&host, &ledger, owner, name)
                        },
                    );
                    let duplicate_formal =
                        mode == DefinitionMode::Declare && !formal.insert((name, kind));
                    if duplicate_formal && first_failure.is_none() {
                        first_failure = Some((
                            shape.key,
                            LocalValidationFailure::Duplicate {
                                owner: *owner,
                                name,
                                kind,
                            },
                        ));
                    }
                    rows[index] = Some(LocalMember {
                        key: shape.key,
                        kind,
                        previous: None,
                    });
                    groups.entry((name, kind)).or_default().push(index);
                }
            }
            let mut selectors = Vec::with_capacity(groups.len());
            for (family, indices) in groups {
                let chain = crate::member_normalization::formal_chain(&indices, |index| {
                    contribution.shared_shape()[index].mode == Some(DefinitionMode::Declare)
                });
                let mut previous = None;
                for index in chain {
                    let member = rows[index]
                        .as_mut()
                        .expect("member group points to member shape");
                    member.previous = previous;
                    previous = Some(member.key);
                }
                if let Some(key) = previous {
                    selectors.push((family, key));
                }
            }
            // Current-revision mode has no byte budget. Real shared owners are
            // exposed to census; zero does not stand for an estimated heap size.
            let rows: Arc<[_]> = rows.into();
            let selectors: Arc<[_]> = selectors.into();
            let payload = self.store.insert_with_owned(
                key(*owner),
                ledger.reads(),
                ledger.domain_receipts(),
                0,
                || LocalOwner {
                    rows,
                    selectors,
                    first_failure,
                },
            );
            result.insert(*owner, payload.expect("current roster is not budgeted"));
        }
        result
    }
}
