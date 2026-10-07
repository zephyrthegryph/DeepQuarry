//! Whole-tree reuse, separate from current source occurrences and scalar folds.
use crate::{frontend::EngineSeed, AdaptedDeclarations, SemanticTree, Skeleton};
use dm_ir::{OpaqueFieldBase, SymbolId};
use serde::Serialize;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};

/// Disposable storage. Implementations must bound IO; errors merely miss.
/// Exact framed keys are compared inside dm-tree, not trusted from hash indexes.
pub type ExactTreeKey = Vec<Vec<u8>>;
#[derive(Clone, Copy, Debug, Default)]
pub struct TreePublication {
    pub envelope_bytes: u64,
    pub envelope_oversize: bool,
}
pub trait TreeReuseStorage: Send + Sync {
    /// The storage layer checks complete ordered exact-key chunks before invoking
    /// admission once. The callback rejects malformed semantic payloads.
    fn load(
        &self,
        exact_key: &[Vec<u8>],
        admit: &mut dyn FnMut(&[Vec<u8>]) -> Result<(), String>,
    ) -> Result<bool, String>;
    fn publish(
        &self,
        exact_key: &[Vec<u8>],
        payload: Vec<Vec<u8>>,
    ) -> Result<TreePublication, String>;
}
#[derive(Default)]
pub struct ReuseCounts {
    pub resident_hits: AtomicU64,
    pub disk_hits: AtomicU64,
    pub resolved: AtomicU64,
    pub rejected: AtomicU64,
    pub skipped_budget: AtomicU64,
    pub publication_failed: AtomicU64,
    pub key_bytes: AtomicU64,
    pub payload_bytes: AtomicU64,
    pub key_oversize: AtomicU64,
    pub payload_oversize: AtomicU64,
    pub envelope_bytes: AtomicU64,
    pub envelope_oversize: AtomicU64,
}
struct Resident {
    key: Arc<[Vec<u8>]>,
    tree: Arc<SemanticTree>,
}
pub struct TreeReuse {
    policy: u128,
    budget: usize,
    storage: Option<Arc<dyn TreeReuseStorage>>,
    resident: Mutex<Option<Resident>>,
    pub counts: ReuseCounts,
}
#[derive(Serialize)]
struct Key<'a> {
    policy: u128,
    engine: Option<u128>,
    hierarchy_schema: Option<u128>,
    parents: &'a [(SymbolId, Option<SymbolId>)],
    intrinsics: Vec<(
        SymbolId,
        SymbolId,
        crate::MemberKind,
        Option<SymbolId>,
        bool,
    )>,
    fields: Vec<Vec<u8>>,
    skeleton_count: usize,
    symbol_count: usize,
}
#[derive(Serialize)]
enum SkeletonKey {
    Type(SymbolId, Option<SymbolId>),
    Member(
        SymbolId,
        SymbolId,
        crate::MemberKind,
        crate::DefinitionMode,
        Vec<u8>,
        u128,
    ),
}
impl TreeReuse {
    pub fn new(policy: u128, byte_budget: usize) -> Self {
        Self {
            policy,
            budget: byte_budget,
            storage: None,
            resident: Mutex::new(None),
            counts: ReuseCounts::default(),
        }
    }
    pub fn with_storage(mut self, storage: Arc<dyn TreeReuseStorage>) -> Self {
        self.storage = Some(storage);
        self
    }
    pub fn validate_payload(bytes: &[Vec<u8>]) -> Result<(), String> {
        crate::tree_wire::validate(bytes)
    }
    pub(crate) fn key(
        &self,
        adapted: &AdaptedDeclarations,
        seed: Option<&EngineSeed>,
    ) -> Option<ExactTreeKey> {
        let symbols = adapted.symbols.ordered();
        let header = Key {
            policy: self.policy,
            engine: seed.map(|s| s.identity),
            hierarchy_schema: seed.map(|s| s.hierarchy.schema),
            parents: seed.map_or(&[], |s| s.hierarchy.parents.as_slice()),
            intrinsics: seed.map_or_else(Vec::new, |s| {
                s.intrinsics
                    .iter()
                    .map(|i| {
                        (
                            i.owner,
                            i.name,
                            i.kind,
                            i.shared_owner,
                            i.instance_storage_proven,
                        )
                    })
                    .collect()
            }),
            fields: seed.map_or_else(Vec::new, |s| {
                s.fields
                    .iter()
                    .map(OpaqueFieldBase::canonical_bytes)
                    .collect()
            }),
            skeleton_count: adapted.skeletons.len(),
            symbol_count: symbols.len(),
        };
        let mut chunks = Vec::new();
        let mut bytes = 0usize;
        let result = (|| {
            key_chunk(&header, &mut chunks, &mut bytes)?;
            for rows in adapted.skeletons.chunks(1024) {
                let rows: Vec<_> = rows
                    .iter()
                    .map(|row| match row {
                        Skeleton::Type {
                            path,
                            explicit_parent,
                        } => SkeletonKey::Type(*path, *explicit_parent),
                        Skeleton::Member {
                            owner,
                            name,
                            kind,
                            mode,
                            metadata,
                            content,
                        } => SkeletonKey::Member(
                            *owner,
                            *name,
                            *kind,
                            *mode,
                            metadata.canonical_bytes(),
                            *content,
                        ),
                    })
                    .collect();
                key_chunk(&rows, &mut chunks, &mut bytes)?;
            }
            for rows in symbols.chunks(1024) {
                key_chunk(&rows, &mut chunks, &mut bytes)?;
            }
            Ok::<(), String>(())
        })();
        self.counts.key_bytes.store(bytes as u64, Ordering::Relaxed);
        if result.is_err() {
            self.counts.key_oversize.fetch_add(1, Ordering::Relaxed);
            self.counts.skipped_budget.fetch_add(1, Ordering::Relaxed);
            None
        } else {
            Some(chunks)
        }
    }
    pub(crate) fn lookup(
        &self,
        key: &[Vec<u8>],
        adapted: &AdaptedDeclarations,
        seed: Option<&EngineSeed>,
    ) -> Option<Arc<SemanticTree>> {
        if let Some(tree) = self
            .resident
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .filter(|r| r.key.as_ref() == key)
            .map(|r| r.tree.clone())
        {
            self.counts.resident_hits.fetch_add(1, Ordering::Relaxed);
            return Some(tree);
        }
        if let Some(storage) = &self.storage {
            let mut issued = None;
            let mut payload_size = 0;
            let result = storage.load(key, &mut |chunks| {
                let tree = crate::tree_wire::replay(chunks, adapted, seed)?;
                payload_size = chunks.iter().map(Vec::len).sum();
                issued = Some(Arc::new(tree));
                Ok(())
            });
            match (result, issued) {
                (Ok(true), Some(tree)) => {
                    self.counts.disk_hits.fetch_add(1, Ordering::Relaxed);
                    self.retain(key, &tree, payload_size);
                    return Some(tree);
                }
                (Ok(false), _) => {}
                _ => {
                    self.counts.rejected.fetch_add(1, Ordering::Relaxed);
                }
            }
        }
        self.counts.resolved.fetch_add(1, Ordering::Relaxed);
        None
    }
    fn retain(&self, key: &[Vec<u8>], tree: &Arc<SemanticTree>, payload: usize) {
        if payload
            .checked_mul(16)
            .and_then(|n| n.checked_add(key.iter().map(Vec::len).sum()))
            .is_some_and(|charge| charge <= self.budget)
        {
            *self.resident.lock().unwrap_or_else(|e| e.into_inner()) = Some(Resident {
                key: Arc::from(key),
                tree: tree.clone(),
            });
        } else {
            self.counts.skipped_budget.fetch_add(1, Ordering::Relaxed);
        }
    }
    pub(crate) fn remember(
        &self,
        key: &[Vec<u8>],
        tree: &Arc<SemanticTree>,
        adapted_skeletons: &[Skeleton],
        seed: Option<&EngineSeed>,
    ) {
        let mut size = 0;
        let encoded = crate::tree_wire::encode(tree, adapted_skeletons, seed, &mut size);
        self.counts
            .payload_bytes
            .store(size as u64, Ordering::Relaxed);
        match encoded {
            Ok(bytes) => {
                self.retain(key, tree, bytes.iter().map(Vec::len).sum());
                if let Some(storage) = &self.storage {
                    match storage.publish(key, bytes) {
                        Ok(report) => {
                            self.counts
                                .envelope_bytes
                                .store(report.envelope_bytes, Ordering::Relaxed);
                            if report.envelope_oversize {
                                self.counts
                                    .envelope_oversize
                                    .fetch_add(1, Ordering::Relaxed);
                            }
                        }
                        Err(_) => {
                            self.counts
                                .publication_failed
                                .fetch_add(1, Ordering::Relaxed);
                        }
                    }
                }
            }
            Err(_) => {
                if size > 0 {
                    self.counts.payload_oversize.fetch_add(1, Ordering::Relaxed);
                }
                self.counts.skipped_budget.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
}

fn key_chunk<T: Serialize>(
    value: &T,
    out: &mut ExactTreeKey,
    total: &mut usize,
) -> Result<(), String> {
    let size = dm_wire::encoded_len(4, value)?;
    *total = total.checked_add(size).ok_or("tree key length overflow")?;
    if size > 8 * 1024 * 1024 || *total > 256 * 1024 * 1024 || out.len() >= 4096 {
        return Err("tree key chunk stream exceeds bound".into());
    }
    out.push(dm_wire::encode(4, value)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{from_ast, MemberKind};
    use dm_ir::{FileId, ResolveQuery, SymbolTable};
    use std::collections::BTreeMap;
    #[derive(Default)]
    struct Storage(Mutex<BTreeMap<Vec<Vec<u8>>, Vec<Vec<u8>>>>);
    impl TreeReuseStorage for Storage {
        fn load(
            &self,
            key: &[Vec<u8>],
            admit: &mut dyn FnMut(&[Vec<u8>]) -> Result<(), String>,
        ) -> Result<bool, String> {
            let value = self.0.lock().unwrap().get(key).cloned();
            match value {
                Some(value) => {
                    admit(&value)?;
                    Ok(true)
                }
                None => Ok(false),
            }
        }
        fn publish(&self, key: &[Vec<u8>], bytes: Vec<Vec<u8>>) -> Result<TreePublication, String> {
            self.0.lock().unwrap().insert(key.to_vec(), bytes);
            Ok(TreePublication::default())
        }
    }
    fn source(text: &str, file: u32) -> AdaptedDeclarations {
        from_ast(
            &dm_syntax::parse(text),
            SymbolTable::default(),
            FileId(file),
            0,
            1,
        )
        .unwrap()
    }
    fn finish(source: AdaptedDeclarations, reuse: &TreeReuse) -> crate::TreeSnapshot {
        source
            .finish_with_engine_reuse_observed(None, Some(reuse), |_, _, _| {})
            .unwrap()
    }
    #[test]
    fn resolved_tree_reuse_excludes_bodies_and_rebinds_current_origins() {
        let reuse = TreeReuse::new(1, 32 * 1024 * 1024);
        let first = finish(
            source(
                "/datum/demo\n    var/value = 1\n    proc/p()\n        return 1\n",
                1,
            ),
            &reuse,
        );
        let second = finish(
            source(
                "/datum/demo\n    var/value = 1\n    proc/p()\n        return 200\n",
                2,
            ),
            &reuse,
        );
        assert!(Arc::ptr_eq(&first.tree, &second.tree));
        assert_eq!(
            second.occurrences.source_order()[0].provenance.span.file,
            FileId(2)
        );
        assert_eq!(reuse.counts.resident_hits.load(Ordering::Relaxed), 1);
        let changed = finish(
            source(
                "/datum/demo\n    var/value = 2\n    proc/p()\n        return 200\n",
                3,
            ),
            &reuse,
        );
        assert!(!Arc::ptr_eq(&first.tree, &changed.tree));
    }
    #[test]
    fn persistent_tree_replay_keeps_forward_formals_and_exact_order() {
        let storage = Arc::new(Storage::default());
        let text="/datum/base/child\n    value = 7\n/datum/base\n    var/value = 3\n    p()\n        return 1\n    proc/p()\n        return 2\n";
        let first = finish(
            source(text, 1),
            &TreeReuse::new(1, 0).with_storage(storage.clone()),
        );
        let reuse = TreeReuse::new(1, 0).with_storage(storage.clone());
        let second = finish(source(text, 2), &reuse);
        assert_eq!(reuse.counts.disk_hits.load(Ordering::Relaxed), 1);
        assert_eq!(first.tree.identity(), second.tree.identity());
        for query in [
            ResolveQuery::Var {
                owner: SymbolId::of("/datum/base/child"),
                name: SymbolId::of("value"),
            },
            ResolveQuery::ProcedureValue {
                owner: SymbolId::of("/datum/base"),
                name: SymbolId::of("p"),
                verb: false,
                formal: true,
            },
        ] {
            assert_eq!(
                dm_ir::Resolver::resolve(first.tree.as_ref(), query).canonical_bytes(),
                dm_ir::Resolver::resolve(second.tree.as_ref(), query).canonical_bytes()
            );
        }
        let formal = second
            .tree
            .members()
            .iter()
            .find(|node| {
                node.kind == MemberKind::Proc && node.definition == crate::DefinitionMode::Declare
            })
            .unwrap();
        assert!(formal.previous.is_none());
        let changed = finish(
            source(
                "/datum/base\n    var/value = 3\n/datum/base/child\n    value = 7\n",
                3,
            ),
            &reuse,
        );
        assert_ne!(first.tree.identity(), changed.tree.identity());
    }
    #[test]
    fn chunked_tree_replay_crosses_sections_with_disk_only_retention() {
        let storage = Arc::new(Storage::default());
        let mut text = String::from("/datum/demo\n");
        for i in 0..2100 {
            text.push_str(&format!("    var/field_{i} = {i}\n"));
        }
        let first = finish(
            source(&text, 1),
            &TreeReuse::new(7, 0).with_storage(storage.clone()),
        );
        assert!(storage.0.lock().unwrap().values().next().unwrap().len() > 4);
        let reuse = TreeReuse::new(7, 0).with_storage(storage);
        let second = finish(source(&text, 2), &reuse);
        assert_eq!(reuse.counts.disk_hits.load(Ordering::Relaxed), 1);
        assert_eq!(reuse.counts.resident_hits.load(Ordering::Relaxed), 0);
        assert_eq!(first.tree.identity(), second.tree.identity());
        assert_eq!(
            second.occurrences.source_order()[2100].provenance.span.file,
            FileId(2)
        );
    }
    #[test]
    fn corrupted_tree_record_is_a_cold_miss_not_an_origin_or_semantic_change() {
        let storage = Arc::new(Storage::default());
        let text = "/datum/demo\n    var/value = 1\n";
        let first = finish(
            source(text, 1),
            &TreeReuse::new(1, 0).with_storage(storage.clone()),
        );
        for bytes in storage.0.lock().unwrap().values_mut() {
            let final_chunk = bytes.last_mut().unwrap();
            let end = final_chunk.len() - 1;
            final_chunk[end] ^= 1;
        }
        let reuse = TreeReuse::new(1, 0).with_storage(storage);
        let second = finish(source(text, 2), &reuse);
        assert_eq!(reuse.counts.rejected.load(Ordering::Relaxed), 1);
        assert_eq!(first.tree.identity(), second.tree.identity());
        assert_eq!(
            second.occurrences.source_order()[0].provenance.span.file,
            FileId(2)
        );
    }
}
