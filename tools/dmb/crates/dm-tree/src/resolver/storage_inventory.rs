//! Per-owner resolved storage facts, observed through the common artifact kernel.
use super::*;
use crate::declaration_contributions::{DeclarationKey, KeyedDeclarations};
use dm_session::{
    ObservationHost, ObservationLedger, ObservedArtifactStorageView, ObservedArtifactStore,
};
use std::{
    collections::BTreeMap,
    sync::atomic::{AtomicUsize, Ordering},
};
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StorageFact {
    pub name: SymbolId,
    pub slot: Option<(SymbolId, SymbolId)>,
    pub instance: bool,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StorageInput {
    pub key: DeclarationKey,
    pub definition: DefinitionMode,
    pub flags: u32,
    pub opaque: Option<dm_ir::OpaqueFieldBase>,
    pub previous: Option<DeclarationKey>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum StorageQuery {
    Owner(SymbolId),
    Predecessor(DeclarationKey),
    Intrinsic(SymbolId, SymbolId),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StorageAnswer {
    Owner(Option<Arc<[StorageInput]>>),
    Predecessor(Option<StorageFact>),
    Intrinsic(Option<IntrinsicMember>),
}
pub struct StorageOwner {
    pub facts: Arc<[(DeclarationKey, StorageFact)]>,
}
type Store = ObservedArtifactStore<StorageOwner, StorageQuery, StorageAnswer, ()>;
pub(crate) struct RetainedStorage {
    store: Store,
    hits: AtomicUsize,
}
impl Default for RetainedStorage {
    fn default() -> Self {
        Self {
            store: Store::current_revision(),
            hits: AtomicUsize::new(0),
        }
    }
}
struct Host<'a> {
    inputs: &'a BTreeMap<SymbolId, Arc<[StorageInput]>>,
    resolved: &'a BTreeMap<DeclarationKey, StorageFact>,
    tree: &'a SemanticTree,
}
impl ObservationHost<StorageQuery, StorageAnswer, ()> for Host<'_> {
    fn answer(&self, query: &StorageQuery) -> StorageAnswer {
        match *query {
            StorageQuery::Owner(owner) => StorageAnswer::Owner(self.inputs.get(&owner).cloned()),
            StorageQuery::Predecessor(key) => {
                StorageAnswer::Predecessor(self.resolved.get(&key).copied())
            }
            StorageQuery::Intrinsic(owner, name) => StorageAnswer::Intrinsic(
                self.tree
                    .inventory
                    .index
                    .get(&(owner, name, MemberKind::Var))
                    .cloned(),
            ),
        }
    }
}
fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-storage-facts-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
impl RetainedStorage {
    pub(crate) fn hits(&self) -> usize {
        self.hits.load(Ordering::Relaxed)
    }
    pub(crate) fn visit_storage(
        &self,
        visit: impl FnMut(
            ObservedArtifactStorageView<'_, StorageOwner, StorageQuery, StorageAnswer, ()>,
        ),
    ) {
        self.store.visit_storage(visit);
    }
    fn owner(
        &self,
        owner: SymbolId,
        owner_ids: &[MemberId],
        member_keys: &[DeclarationKey],
        host: &Host<'_>,
    ) -> Arc<StorageOwner> {
        if let Some(payload) = self.store.lookup(&key(owner), host) {
            self.hits.fetch_add(1, Ordering::Relaxed);
            payload
        } else {
            let ledger = ObservationLedger::default();
            let query = StorageQuery::Owner(owner);
            ledger.record(query, host.answer(&query), (), None);
            for input in host.inputs[&owner].iter() {
                let query = if let Some(opaque) = &input.opaque {
                    Some(StorageQuery::Intrinsic(opaque.owner, opaque.name))
                } else if matches!(
                    input.definition,
                    DefinitionMode::Override | DefinitionMode::Reopen
                ) {
                    input
                        .previous
                        .filter(|previous| previous.owner != owner)
                        .map(StorageQuery::Predecessor)
                } else {
                    None
                };
                if let Some(query) = query {
                    ledger.record(query, host.answer(&query), (), None);
                }
            }
            let facts: Arc<[_]> = owner_ids
                .iter()
                .filter_map(|&id| {
                    inventory::fact(host.tree, id).map(|fact| (member_keys[id.index()], fact))
                })
                .collect::<Vec<_>>()
                .into();
            self.store.insert_with(
                key(owner),
                ledger.reads(),
                ledger.domain_receipts(),
                0,
                || StorageOwner {
                    facts: Arc::clone(&facts),
                },
            );
            Arc::new(StorageOwner { facts })
        }
    }
    #[cfg(test)]
    fn facts(
        &self,
        tree: &SemanticTree,
        declarations: &KeyedDeclarations,
    ) -> Option<Vec<Option<StorageFact>>> {
        self.facts_on_executor(tree, declarations, None)
    }
    pub(crate) fn facts_on_executor(
        &self,
        tree: &SemanticTree,
        declarations: &KeyedDeclarations,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Option<Vec<Option<StorageFact>>> {
        let member_keys: Vec<_> = declarations
            .ordered()
            .filter_map(|row| matches!(row.skeleton, Skeleton::Member { .. }).then_some(row.key))
            .collect();
        if member_keys.len() != tree.members.len() {
            return None;
        }
        let mut ids = BTreeMap::<SymbolId, Vec<MemberId>>::new();
        let mut inputs = BTreeMap::<SymbolId, Vec<StorageInput>>::new();
        for (index, member) in tree.members.iter().enumerate() {
            if member.kind != MemberKind::Var {
                continue;
            }
            let owner = tree.types[member.owner.index()].path;
            let key = member_keys[index];
            if key.owner != owner
                || !matches!(key.family,crate::declaration_contributions::DeclarationFamily::Member {name,kind:MemberKind::Var} if name==member.name)
            {
                return None;
            }
            ids.entry(owner).or_default().push(MemberId(index as u32));
            inputs.entry(owner).or_default().push(StorageInput {
                key,
                definition: member.definition,
                flags: member.metadata.flags & (1 | 2 | 8),
                opaque: member.metadata.inherited_opaque.clone(),
                previous: member.previous.map(|id| member_keys[id.index()]),
            });
        }
        let inputs: BTreeMap<_, Arc<[_]>> = inputs
            .into_iter()
            .map(|(owner, rows)| (owner, rows.into()))
            .collect();
        let keys: Vec<_> = inputs.keys().map(|owner| key(*owner)).collect();
        self.store
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        let owners = crate::metadata_update::dependency_order(tree.types.len(), |index| {
            tree.types[index].parent.map(|id| id.index())
        });
        let mut depths = vec![0usize; tree.types.len()];
        let mut levels = BTreeMap::<usize, Vec<SymbolId>>::new();
        for owner_index in owners {
            depths[owner_index] = tree.types[owner_index]
                .parent
                .map_or(0, |id| depths[id.index()] + 1);
            let owner = tree.types[owner_index].path;
            if ids.contains_key(&owner) {
                levels.entry(depths[owner_index]).or_default().push(owner);
            }
        }
        let mut resolved = BTreeMap::new();
        let mut output = vec![None; tree.members.len()];
        for level in levels.into_values() {
            let host = Host {
                inputs: &inputs,
                resolved: &resolved,
                tree,
            };
            let payloads = if let Some(executor) =
                executor.filter(|executor| executor.workers() > 1 && level.len() > 1)
            {
                let next = AtomicUsize::new(0);
                let slots: Vec<_> = (0..level.len())
                    .map(|_| std::sync::Mutex::new(None))
                    .collect();
                executor.scope(|scope| {
                    for _ in 0..executor.workers().min(level.len()) {
                        let next = &next;
                        let slots = &slots;
                        let level = &level;
                        let host = &host;
                        let ids = &ids;
                        let member_keys = &member_keys;
                        scope.spawn(move |_| {
                            let _stage = dm_profile::stage("frontend.tree_resolution");
                            loop {
                                let index = next.fetch_add(1, Ordering::Relaxed);
                                let Some(&owner) = level.get(index) else {
                                    break;
                                };
                                let value = self.owner(owner, &ids[&owner], member_keys, host);
                                *slots[index]
                                    .lock()
                                    .expect("storage inventory result lock poisoned") = Some(value);
                            }
                        });
                    }
                });
                slots
                    .into_iter()
                    .map(|slot| {
                        slot.into_inner()
                            .expect("storage inventory result lock poisoned")
                            .expect("storage inventory worker did not publish owner")
                    })
                    .collect::<Vec<_>>()
            } else {
                level
                    .iter()
                    .map(|&owner| self.owner(owner, &ids[&owner], &member_keys, &host))
                    .collect()
            };
            for (owner, payload) in level.into_iter().zip(payloads) {
                let owner_ids = &ids[&owner];
                if payload.facts.len() != owner_ids.len() {
                    return None;
                }
                for (&id, &(key, fact)) in owner_ids.iter().zip(payload.facts.iter()) {
                    if key != member_keys[id.index()] {
                        return None;
                    }
                    resolved.insert(key, fact);
                    output[id.index()] = Some(fact);
                }
            }
        }
        Some(output)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn source(source: &str) -> (SemanticTree, KeyedDeclarations) {
        let adapted = crate::from_ast(
            &dm_syntax::parse(source),
            SymbolTable::default(),
            dm_ir::FileId(0),
            0,
            0,
        )
        .unwrap();
        let declarations = KeyedDeclarations::capture(None, &adapted.skeletons)
            .unwrap()
            .0;
        let tree = crate::build(adapted.symbols, &adapted.skeletons).unwrap();
        (tree, declarations)
    }
    fn fresh(tree: &SemanticTree) -> Vec<Option<StorageFact>> {
        (0..tree.members.len())
            .map(|index| inventory::fact(tree, MemberId(index as u32)))
            .collect()
    }
    #[test]
    fn initializer_edits_reuse_storage_but_inherited_storage_changes_invalidate() {
        let retained = RetainedStorage::default();
        let (initial,index)=source("/datum/base\n    var/static/shared = 1\n/datum/base/child\n    shared = 2\n/datum/other\n    var/value = 3\n");
        assert_eq!(retained.facts(&initial, &index).unwrap(), fresh(&initial));
        let (edited,index)=source("/datum/base\n    var/static/shared = 4\n/datum/base/child\n    shared = 5\n/datum/other\n    var/value = 6\n");
        assert_eq!(retained.facts(&edited, &index).unwrap(), fresh(&edited));
        assert_eq!(retained.hits(), 3);
        let mut recorded_predecessor = false;
        retained.visit_storage(|view| {
            if let ObservedArtifactStorageView::Entry { reads, .. } = view {
                recorded_predecessor |= reads
                    .iter()
                    .any(|read| matches!(read.query, StorageQuery::Predecessor(_)));
            }
        });
        assert!(
            recorded_predecessor,
            "inherited facts carry explicit predecessor observations"
        );
        let (changed,index)=source("/datum/base\n    var/shared = 4\n/datum/base/child\n    shared = 5\n/datum/other\n    var/value = 6\n");
        let facts = retained.facts(&changed, &index).unwrap();
        assert_eq!(facts, fresh(&changed));
        assert_eq!(retained.hits(), 4, "only unrelated owner reused");
        assert!(facts[1].unwrap().instance);
        assert_eq!(facts[1].unwrap().slot, None);
    }
    #[test]
    fn insertion_rebinds_cached_facts_to_current_member_indices() {
        let retained = RetainedStorage::default();
        let (initial, index) = source("/datum/a\n    var/static/a = 1\n/datum/b\n    var/b = 2\n");
        retained.facts(&initial, &index).unwrap();
        let (changed,index)=source("/datum/inserted\n    var/added = 7\n/datum/a\n    var/static/a = 1\n/datum/b\n    var/b = 2\n");
        let facts = retained.facts(&changed, &index).unwrap();
        assert_eq!(facts, fresh(&changed));
        assert_eq!(retained.hits(), 2);
        assert_eq!(facts[0].unwrap().name, SymbolId::of("added"));
        assert_eq!(
            facts[1].unwrap().slot,
            Some((SymbolId::of("/datum/a"), SymbolId::of("a")))
        );
    }
    #[test]
    fn opaque_intrinsic_storage_is_observed_and_engine_change_invalidates() {
        let retained = RetainedStorage::default();
        let make = |shared: bool| {
            let adapted = crate::from_ast(
                &dm_syntax::parse("/datum/base\n/datum/base/child\n    native = 1\n"),
                SymbolTable::default(),
                dm_ir::FileId(0),
                0,
                0,
            )
            .unwrap();
            let declarations = KeyedDeclarations::capture(None, &adapted.skeletons)
                .unwrap()
                .0;
            let owner = SymbolId::of("/datum/base");
            let name = SymbolId::of("native");
            let field = dm_ir::OpaqueFieldBase {
                owner,
                name,
                declared_type: dm_ir::DeclaredTypeKnowledge::KnownUntyped,
            };
            let tree =
                crate::build_with_intrinsic_fields(adapted.symbols, &adapted.skeletons, &[field])
                    .unwrap();
            let hierarchy = EngineHierarchy {
                schema: 1,
                parents: tree
                    .types
                    .iter()
                    .map(|node| (node.path, node.parent.map(|id| tree.types[id.index()].path)))
                    .collect(),
            };
            let entry = IntrinsicMember {
                owner,
                name,
                kind: MemberKind::Var,
                shared_owner: shared.then_some(owner),
                instance_storage_proven: !shared,
            };
            (
                tree.with_engine_intrinsics(hierarchy, vec![entry]).unwrap(),
                declarations,
            )
        };
        let (shared, index) = make(true);
        let before = retained.facts(&shared, &index).unwrap();
        assert_eq!(before, fresh(&shared));
        assert_eq!(
            before[0].unwrap().slot,
            Some((SymbolId::of("/datum/base"), SymbolId::of("native")))
        );
        let (instance, index) = make(false);
        let after = retained.facts(&instance, &index).unwrap();
        assert_eq!(after, fresh(&instance));
        assert!(after[0].unwrap().instance);
        assert_eq!(retained.hits(), 0);
        assert_eq!(retained.facts(&instance, &index).unwrap(), after);
        assert_eq!(retained.hits(), 1);
    }
    #[test]
    fn parallel_owner_levels_preserve_facts_and_production_intrinsic_rebuild() {
        let source_text="/datum/base\n    var/static/shared = 1\n/datum/base/a\n    shared = 2\n/datum/base/b\n    shared = 3\n/datum/other\n    var/value = 4\n";
        let (tree, index) = source(source_text);
        let pool = dm_exec::BuildExecutor::new(2).unwrap();
        let retained = RetainedStorage::default();
        let expected = fresh(&tree);
        assert_eq!(
            retained
                .facts_on_executor(&tree, &index, Some(&pool))
                .unwrap(),
            expected
        );
        assert_eq!(
            retained
                .facts_on_executor(&tree, &index, Some(&pool))
                .unwrap(),
            expected
        );
        assert_eq!(retained.hits(), 4);
        let hierarchy = EngineHierarchy {
            schema: 1,
            parents: tree
                .types
                .iter()
                .map(|node| (node.path, node.parent.map(|id| tree.types[id.index()].path)))
                .collect(),
        };
        let retained_tree = tree
            .clone()
            .with_engine_intrinsics_retained(
                hierarchy.clone(),
                vec![],
                Some(&pool),
                &index,
                &retained,
            )
            .unwrap();
        let fresh_tree = tree.with_engine_intrinsics(hierarchy, vec![]).unwrap();
        assert_eq!(retained.hits(), 8, "actual attachment uses retained facts");
        for name in [
            SymbolId::of("shared"),
            SymbolId::of("value"),
            SymbolId::of("absent"),
        ] {
            assert_eq!(
                retained_tree.captured_variable_uniqueness(name),
                fresh_tree.captured_variable_uniqueness(name)
            );
        }
    }
}
