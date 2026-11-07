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
mod shared;
#[cfg(test)]
mod shared_tests;
use shared::CallableValues;
pub struct CallableOwner {
    pub anchors: Arc<[(SymbolId, MemberKind)]>,
    pub duplicate: Option<(DeclarationKey, MemberKind)>,
}
pub(crate) type CallableStore =
    ObservedArtifactStore<CallableOwner, SourceQuery, SourceAnswer, SourceDomain>;
pub(crate) struct RetainedCallableOwners {
    store: CallableValues,
    hits: AtomicUsize,
}
impl Default for RetainedCallableOwners {
    fn default() -> Self {
        Self {
            store: CallableValues::Local(CallableStore::current_revision()),
            hits: AtomicUsize::new(0),
        }
    }
}
/// Optional, request-local borrower of an existing callable artifact owner.
/// The covered roster is funded by the receiving declaration operation.
pub(crate) struct AuthoredCallableLoan<'a> {
    declarations: &'a KeyedDeclarations,
    prior: &'a RetainedCallableOwners,
    covered: Vec<SymbolId>,
    _credit: dm_syntax::SettingRootLease,
}
impl<'a> AuthoredCallableLoan<'a> {
    pub(crate) fn try_new(
        declarations: &'a KeyedDeclarations,
        prior: &'a RetainedCallableOwners,
        admission: &dm_syntax::SettingAdmission<'_>,
    ) -> std::io::Result<Option<Self>> {
        let count = declarations.owners().len();
        let Some(bytes) = count.checked_mul(std::mem::size_of::<SymbolId>()) else {
            return Ok(None);
        };
        let Some(credit) = admission.try_reserve_optimization(bytes)
            .map_err(|proxy| admission.take_operational_error().unwrap_or(proxy))? else {
            return Ok(None);
        };
        let mut covered = Vec::new();
        if covered.try_reserve_exact(count).is_err() || covered.capacity() != count {
            return Ok(None);
        }
        Ok(Some(Self { declarations, prior, covered, _credit: credit }))
    }

    pub(crate) fn seed(&mut self, tree: &SemanticTree, callables: &mut CallableKinds) {
        self.prior.visit_duplicate_free(tree, self.declarations, |owner, anchors| {
            self.covered.push(owner);
            for &(name, kind) in anchors {
                callables.insert((owner, name), kind);
            }
        });
        self.covered.sort_unstable();
    }

    pub(crate) fn covers(&self, owner: SymbolId) -> bool {
        self.covered.binary_search(&owner).is_ok()
    }
}
const KEY_PREFIX: &[u8] = b"owner-callable-anchors-v1";
fn key_bytes(owner: SymbolId) -> [u8; KEY_PREFIX.len() + std::mem::size_of::<u64>()] {
    let mut bytes = [0; KEY_PREFIX.len() + std::mem::size_of::<u64>()];
    bytes[..KEY_PREFIX.len()].copy_from_slice(KEY_PREFIX);
    bytes[KEY_PREFIX.len()..].copy_from_slice(&owner.bits().to_le_bytes());
    bytes
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    Arc::from(key_bytes(owner).as_slice())
}
impl RetainedCallableOwners {
    pub(crate) fn with_shared(owner: Arc<crate::SharedNormalizedDeclarations>) -> Self {
        Self {
            store: CallableValues::shared(owner),
            hits: AtomicUsize::new(0),
        }
    }
    pub(crate) fn fresh(&self) -> Self {
        Self {
            store: self.store.fresh(),
            hits: AtomicUsize::new(0),
        }
    }
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
    /// Probe the existing authored artifact under the recipient's actual
    /// declaration rows. No map or claim from the lender is installed.
    pub(crate) fn visit_duplicate_free(
        &self,
        tree: &SemanticTree,
        declarations: &KeyedDeclarations,
        mut visit: impl FnMut(SymbolId, &[(SymbolId, MemberKind)]),
    ) {
        let empty = CallableKinds::new();
        let host = DeclarationHost {
            declarations,
            tree,
            member_keys: &[],
            callable_kinds: &empty,
        };
        for (owner, _) in declarations.owners() {
            if let Some(value) = self.store.lookup_duplicate_free(&key_bytes(*owner), &host) {
                self.hits.fetch_add(1, Ordering::Relaxed);
                visit(*owner, &value.anchors);
            }
        }
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
            let payload = self.store.insert_with_owned(
                key(*owner),
                ledger.reads(),
                0,
                || CallableOwner { anchors, duplicate },
            );
            owners.insert(*owner, payload.expect("current roster is not budgeted"));
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
    fn authored_callable_loan_funds_its_covered_roster_before_use() {
        use std::sync::atomic::AtomicUsize;
        let prior = RetainedCallableOwners::default();
        let owner = SymbolId::of("/datum/funded");
        let name = SymbolId::of("action");
        let (declarations, _) = KeyedDeclarations::capture(None, &[
            member(owner, name, MemberKind::Proc, DefinitionMode::Declare),
        ]).unwrap();
        let used = Arc::new(AtomicUsize::new(0));
        let exact = std::mem::size_of::<SymbolId>();
        let limited = dm_syntax::SettingAdmission::new(&used, exact - 1, &|| Ok(()));
        assert!(AuthoredCallableLoan::try_new(&declarations, &prior, &limited).unwrap().is_none());
        assert_eq!(used.load(Ordering::Acquire), 0);
        let admitted = dm_syntax::SettingAdmission::new(&used, exact, &|| Ok(()));
        let loan = AuthoredCallableLoan::try_new(&declarations, &prior, &admitted).unwrap().unwrap();
        assert_eq!(loan.covered.capacity(), 1);
        assert_eq!(used.load(Ordering::Acquire), exact);
        drop(loan);
        assert_eq!(used.load(Ordering::Acquire), 0);
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
