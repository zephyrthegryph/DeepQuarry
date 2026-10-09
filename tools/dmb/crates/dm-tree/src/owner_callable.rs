//! Authored callable anchor contributions, independent of dense IDs and engine tables.
use crate::{
    callable_namespace::{self, CallableKinds},
    declaration_contributions::{DeclarationFamily, DeclarationKey, KeyedDeclarations},
    declaration_observations::{DeclarationHost, SourceAnswer, SourceDomain, SourceQuery},
    *,
};
use dm_session::{ObservationLedger, ObservedArtifactStorageView, ObservedArtifactStore};
use std::{
    collections::BTreeMap,
    sync::atomic::{AtomicUsize, Ordering},
};
pub struct CallableOwner {
    pub anchors: Arc<[(SymbolId, MemberKind)]>,
    pub duplicate: Option<(DeclarationKey, MemberKind)>,
}
type Store = ObservedArtifactStore<CallableOwner, SourceQuery, SourceAnswer, SourceDomain>;
pub(crate) struct RetainedCallableOwners {
    store: Store,
    hits: AtomicUsize,
}
impl Default for RetainedCallableOwners {
    fn default() -> Self {
        Self {
            store: Store::current_revision(),
            hits: AtomicUsize::new(0),
        }
    }
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-callable-anchors-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
impl RetainedCallableOwners {
    pub(crate) fn hits(&self) -> usize {
        self.hits.load(Ordering::Relaxed)
    }
    pub(crate) fn visit_storage(
        &self,
        visit: impl FnMut(
            ObservedArtifactStorageView<'_, CallableOwner, SourceQuery, SourceAnswer, SourceDomain>,
        ),
    ) {
        self.store.visit_storage(visit);
    }
    pub(crate) fn collect(
        &self,
        tree: &SemanticTree,
        declarations: &KeyedDeclarations,
        intrinsics: &[IntrinsicMember],
    ) -> Result<CallableKinds, TreeError> {
        let keys: Vec<_> = declarations
            .owners()
            .map(|(owner, _)| key(*owner))
            .collect();
        self.store
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let empty = CallableKinds::new();
        let host = DeclarationHost {
            declarations,
            tree,
            member_keys: &[],
            callable_kinds: &empty,
        };
        let mut owners = BTreeMap::new();
        for (owner, contribution) in declarations.owners() {
            if let Some(value) = self.store.lookup(&key(*owner), &host) {
                self.hits.fetch_add(1, Ordering::Relaxed);
                owners.insert(*owner, value);
                continue;
            }
            let ledger = ObservationLedger::default();
            crate::owner_normalization::observe(
                &host,
                &ledger,
                SourceQuery::OwnerShape { owner: *owner },
            );
            let mut anchors = CallableKinds::new();
            let mut formals = HashSet::new();
            let mut duplicate = None;
            for shape in contribution.shared_shape().iter() {
                if let DeclarationFamily::Member { name, kind } = shape.key.family {
                    let mode = shape.mode.expect("member shape has definition mode");
                    if callable_namespace::insert_anchor(
                        *owner,
                        name,
                        kind,
                        mode,
                        &mut anchors,
                        &mut formals,
                    )
                    .is_some()
                    {
                        duplicate = Some((shape.key, kind));
                        break;
                    }
                }
            }
            let mut anchors: Vec<_> = anchors
                .into_iter()
                .map(|((_, name), kind)| (name, kind))
                .collect();
            anchors.sort_unstable_by_key(|(name, _)| *name);
            let anchors: Arc<[_]> = anchors.into();
            self.store.insert_with(
                key(*owner),
                ledger.reads(),
                ledger.domain_receipts(),
                0,
                || CallableOwner {
                    anchors: Arc::clone(&anchors),
                    duplicate,
                },
            );
            owners.insert(*owner, Arc::new(CallableOwner { anchors, duplicate }));
        }
        // Validation retains global authored encounter order even though independent
        // owner contributions were computed in symbol order.
        if owners.values().any(|owner| owner.duplicate.is_some()) {
            for handle in declarations.roster() {
                if let Some((duplicate, kind)) = owners[&handle.owner].duplicate {
                    if declarations
                        .owner(handle.owner)
                        .expect("roster owner exists")
                        .rows()[handle.row as usize]
                        .key
                        == duplicate
                    {
                        let DeclarationFamily::Member { name, .. } = duplicate.family else {
                            unreachable!("duplicate is callable")
                        };
                        return Err(TreeError::Duplicate {
                            owner: handle.owner,
                            name,
                            kind,
                        });
                    }
                }
            }
        }
        let mut result = CallableKinds::new();
        for intrinsic in intrinsics {
            if matches!(intrinsic.kind, MemberKind::Proc | MemberKind::Verb) {
                result.insert((intrinsic.owner, intrinsic.name), intrinsic.kind);
            }
        }
        for (owner, contribution) in owners {
            for &(name, kind) in contribution.anchors.iter() {
                result.insert((owner, name), kind);
            }
        }
        Ok(result)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn member(owner: SymbolId, name: SymbolId, kind: MemberKind, mode: DefinitionMode) -> Skeleton {
        Skeleton::Member {
            owner,
            name,
            kind,
            mode,
            metadata: Arc::new(MemberMetadata::default()),
            content: 0,
        }
    }
    #[test]
    fn keyed_catalog_matches_encounter_precedence_and_reuses_unchanged_shapes() {
        let retained = RetainedCallableOwners::default();
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/datum/a").unwrap();
        let other = symbols.intern("/datum/b").unwrap();
        let name = symbols.intern("callback").unwrap();
        let tree = crate::build(symbols, &[]).unwrap();
        let rows = vec![
            member(owner, name, MemberKind::Proc, DefinitionMode::Implicit),
            member(owner, name, MemberKind::Verb, DefinitionMode::Declare),
            member(other, name, MemberKind::Proc, DefinitionMode::Declare),
        ];
        let (index, _) = KeyedDeclarations::capture(None, &rows).unwrap();
        let intrinsic = IntrinsicMember {
            owner,
            name,
            kind: MemberKind::Proc,
            shared_owner: None,
            instance_storage_proven: false,
        };
        let first = retained
            .collect(&tree, &index, std::slice::from_ref(&intrinsic))
            .unwrap();
        assert_eq!(
            first,
            callable_namespace::collect(&rows, std::slice::from_ref(&intrinsic)).unwrap()
        );
        assert_eq!(first[&(owner, name)], MemberKind::Verb);
        let mut changed = rows.clone();
        if let Skeleton::Member {
            metadata, content, ..
        } = &mut changed[1]
        {
            *content = 9;
            Arc::make_mut(metadata).flags = 7;
        }
        changed.push(member(
            other,
            SymbolId::of("new_name"),
            MemberKind::Proc,
            DefinitionMode::Implicit,
        ));
        let (index, _) = KeyedDeclarations::capture(Some(&index), &changed).unwrap();
        let next = retained.collect(&tree, &index, &[]).unwrap();
        assert_eq!(next, callable_namespace::collect(&changed, &[]).unwrap());
        assert_eq!(
            retained.hits(),
            1,
            "metadata-only owner reused; changed owner recomputed"
        );
        // Engine-only anchors always come from this invocation, never old cache.
        let empty = KeyedDeclarations::capture(None, &[]).unwrap().0;
        assert!(retained.collect(&tree, &empty, &[]).unwrap().is_empty());
    }
    #[test]
    fn duplicate_diagnostic_preserves_global_authored_order_across_owners() {
        let retained = RetainedCallableOwners::default();
        let mut symbols = SymbolTable::default();
        let a = symbols.intern("/datum/a").unwrap();
        let b = symbols.intern("/datum/b").unwrap();
        let name = symbols.intern("x").unwrap();
        let tree = crate::build(symbols, &[]).unwrap();
        let rows = vec![
            member(a, name, MemberKind::Proc, DefinitionMode::Declare),
            member(b, name, MemberKind::Verb, DefinitionMode::Declare),
            member(b, name, MemberKind::Proc, DefinitionMode::Declare),
            member(a, name, MemberKind::Verb, DefinitionMode::Declare),
        ];
        let index = KeyedDeclarations::capture(None, &rows).unwrap().0;
        let expected = TreeError::Duplicate {
            owner: b,
            name,
            kind: MemberKind::Proc,
        };
        assert_eq!(
            callable_namespace::collect(&rows, &[]),
            Err(expected.clone())
        );
        assert_eq!(retained.collect(&tree, &index, &[]), Err(expected.clone()));
        assert_eq!(retained.collect(&tree, &index, &[]), Err(expected));
        assert_eq!(retained.hits(), 2);
    }
}
