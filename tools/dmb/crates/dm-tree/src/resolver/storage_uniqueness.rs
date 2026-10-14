//! Name-specific receipts of the already reduced global storage inventory.
use super::*;
use std::sync::atomic::AtomicU64;

pub(super) const UNIQUE_PREFIX: &[u8] = b"unique-storage-name-v1\0";
static NEXT: AtomicU64 = AtomicU64::new(1);
pub(super) fn unique_inputs(tree: &SemanticTree, name: SymbolId) -> UniqueStorageInputs {
    UniqueStorageInputs {
        slot: tree.inventory.unique.get(&name).copied().flatten(),
        non_unique: tree.inventory.non_unique.contains(&name),
        complete: tree.inventory.complete,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ReadDomain, ResolveQuery, Resolver};
    fn capture(retained: &RetainedStorage, source: &str, complete: bool) -> SemanticTree {
        let (mut tree, declarations) = super::super::tests::source(source);
        Arc::make_mut(&mut tree.inventory).complete = complete;
        inventory::rebuild_retained(&mut tree, None, &declarations, retained);
        tree
    }
    fn version(tree: &SemanticTree, name: &str) -> Option<u128> {
        tree.domain_version(ReadDomain::OwnerVariable(ResolveQuery::UniqueStaticVar(
            SymbolId::of(name),
        )))
    }
    #[test]
    fn global_name_receipts_track_ambiguity_completeness_and_current_roster() {
        let retained = RetainedStorage::default();
        let first = capture(&retained, "/datum/a\n    var/static/shared = 1\n", true);
        let token = version(&first, "shared").unwrap();
        let edited = capture(
            &retained,
            "/datum/a\n    var/static/shared = 2\n/datum/b\n    var/unrelated = 3\n",
            true,
        );
        assert_eq!(version(&edited, "shared"), Some(token));
        assert_eq!(
            Resolver::resolve(
                &edited,
                ResolveQuery::UniqueStaticVar(SymbolId::of("shared"))
            ),
            Resolver::resolve(
                &first,
                ResolveQuery::UniqueStaticVar(SymbolId::of("shared"))
            )
        );
        let ambiguous = capture(
            &retained,
            "/datum/a\n    var/static/shared = 2\n/datum/b\n    var/shared = 3\n",
            true,
        );
        assert_ne!(version(&ambiguous, "shared"), Some(token));
        assert_eq!(
            Resolver::resolve(
                &ambiguous,
                ResolveQuery::UniqueStaticVar(SymbolId::of("shared"))
            ),
            M::Missing
        );
        let incomplete = capture(&retained, "/datum/a\n    var/static/shared = 2\n", false);
        assert_ne!(version(&incomplete, "shared"), version(&edited, "shared"));
        assert!(matches!(
            Resolver::resolve(
                &incomplete,
                ResolveQuery::UniqueStaticVar(SymbolId::of("shared"))
            ),
            M::Unsupported(_)
        ));
        let removed = capture(&retained, "/datum/a\n", true);
        assert_eq!(version(&removed, "shared"), None);
        assert_eq!(version(&removed, "unknown"), None);
        assert_eq!(
            version(&first, "shared"),
            Some(token),
            "old immutable receipts remain stable"
        );
    }
}
struct UniqueHost<'a>(&'a SemanticTree);
impl ObservationHost<StorageQuery, StorageAnswer, ()> for UniqueHost<'_> {
    fn answer(&self, query: &StorageQuery) -> StorageAnswer {
        match *query {
            StorageQuery::Unique(name) => StorageAnswer::Unique(unique_inputs(self.0, name)),
            _ => unreachable!("uniqueness artifacts only record name inventory answers"),
        }
    }
}
fn unique_key(name: SymbolId) -> Arc<[u8]> {
    let mut bytes = UNIQUE_PREFIX.to_vec();
    bytes.extend_from_slice(&name.bits().to_le_bytes());
    bytes.into()
}
impl RetainedStorage {
    pub(in crate::resolver) fn certify_uniqueness(
        &self,
        tree: &SemanticTree,
    ) -> BTreeMap<SymbolId, u64> {
        let names: std::collections::BTreeSet<_> = tree
            .inventory
            .unique
            .keys()
            .copied()
            .chain(tree.inventory.non_unique.iter().copied())
            .collect();
        let mut keys = Vec::<Arc<[u8]>>::new();
        self.store.visit_storage(|view| {
            if let ObservedArtifactStorageView::Entry { key, .. } = view {
                if !key.starts_with(UNIQUE_PREFIX) {
                    keys.push(Arc::clone(key));
                }
            }
        });
        let host = UniqueHost(tree);
        let mut certificates = BTreeMap::new();
        for name in names {
            let key = unique_key(name);
            keys.push(Arc::clone(&key));
            let owner = self.store.lookup(&key, &host).or_else(|| {
                let token = NEXT
                    .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
                        value.checked_add(1)
                    })
                    .ok()?;
                let ledger = ObservationLedger::default();
                let query = StorageQuery::Unique(name);
                ledger.record(query, host.answer(&query), (), None);
                self.store.insert_with_owned(
                    key,
                    ledger.reads(),
                    ledger.domain_receipts(),
                    0,
                    || StorageOwner {
                        facts: Arc::from([]),
                        unique_token: Some(token),
                    },
                )
            });
            if let Some(token) = owner.and_then(|owner| owner.unique_token) {
                certificates.insert(name, token);
            }
        }
        self.store
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        certificates
    }
}
