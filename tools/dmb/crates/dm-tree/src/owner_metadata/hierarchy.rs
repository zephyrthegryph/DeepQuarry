//! Hierarchy receipts share the effective-owner artifact store. Dense IDs,
//! unrelated members and source coordinates do not enter these answers.
use super::*;

pub(super) fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-hierarchy-certificate-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
pub(super) fn ancestry(tree: &SemanticTree, owner: SymbolId) -> Arc<[SymbolId]> {
    let mut paths = Vec::new();
    let mut current = tree.lookup_type(owner);
    while let Some(id) = current {
        paths.push(tree.types[id.index()].path);
        current = tree.parent(id);
    }
    paths.into()
}
struct HierarchyHost<'a>(&'a SemanticTree);
impl ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for HierarchyHost<'_> {
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::Hierarchy(owner) => MetadataAnswer::Hierarchy(ancestry(self.0, *owner)),
            _ => unreachable!("hierarchy artifact only records hierarchy queries"),
        }
    }
}
impl RetainedMetadata {
    pub(crate) fn certify_hierarchy(&self, tree: &SemanticTree) -> BTreeMap<SymbolId, u128> {
        let host = HierarchyHost(tree);
        tree.types
            .iter()
            .filter_map(|node| {
                let owner = node.path;
                let key = key(owner);
                if let Some(value) = self.store.lookup(&key, &host) {
                    if let EffectiveOwner::Hierarchy { version, .. } = value.as_ref() {
                        return Some((owner, *version));
                    }
                }
                let query = MetadataQuery::Hierarchy(owner);
                let answer = host.answer(&query);
                let MetadataAnswer::Hierarchy(paths) = &answer else {
                    unreachable!()
                };
                // This is a process-local issuer token, not a semantic hash. It
                // survives only exact observation replay of this retained entry.
                // Persistent consumers must omit this domain's version receipt.
                static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
                let Ok(version) = NEXT.fetch_update(
                    std::sync::atomic::Ordering::Relaxed,
                    std::sync::atomic::Ordering::Relaxed,
                    |value| value.checked_add(1),
                ) else {
                    return None;
                };
                let version = u128::from(version);
                let ledger = ObservationLedger::default();
                ledger.record(query, answer.clone(), query.domain(), None);
                let paths = Arc::clone(paths);
                self.store
                    .insert_with(key, ledger.reads(), ledger.domain_receipts(), 0, || {
                        EffectiveOwner::Hierarchy { paths, version }
                    });
                Some((owner, version))
            })
            .collect()
    }
}

#[cfg(test)]
#[path = "hierarchy_tests.rs"]
mod tests;
