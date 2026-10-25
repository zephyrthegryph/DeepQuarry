//! Hierarchy receipts share the effective-owner artifact store. Dense IDs,
//! unrelated members and source coordinates do not enter these answers.
use super::*;
use crate::token_digest::TokenDigest;

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
    pub(crate) fn certify_hierarchy(
        &self,
        tree: &SemanticTree,
    ) -> (
        BTreeMap<SymbolId, u128>,
        BTreeMap<SymbolId, Arc<[SymbolId]>>,
    ) {
        let host = HierarchyHost(tree);
        tree.types
            .iter()
            .filter_map(|node| {
                let owner = node.path;
                let key = key(owner);
                if let Some(value) = self.store.lookup(&key, &host) {
                    if let EffectiveOwner::Hierarchy { version, paths } = value.as_ref() {
                        return Some(((owner, *version), (owner, Arc::clone(paths))));
                    }
                }
                let query = MetadataQuery::Hierarchy(owner);
                let answer = host.answer(&query);
                let MetadataAnswer::Hierarchy(paths) = &answer else {
                    unreachable!()
                };
                // The token is the digest of the owner's ancestry (see `token_digest`): equal ancestry in any session
                // or restart is the same token, a changed ancestry is a different one.
                let version = {
                    let mut digest = TokenDigest::new(b"owner-hierarchy-token-v1");
                    digest.bytes(&key);
                    digest.len(paths.len());
                    for path in paths.iter() {
                        digest.symbol(*path);
                    }
                    digest.finish()
                };
                let ledger = ObservationLedger::default();
                ledger.record(query, answer.clone(), query.domain(), None);
                let paths = Arc::clone(paths);
                let stored_paths = Arc::clone(&paths);
                self.store
                    .insert_with(key, ledger.reads(), ledger.domain_receipts(), 0, || {
                        EffectiveOwner::Hierarchy { paths, version }
                    });
                Some(((owner, version), (owner, stored_paths)))
            })
            .unzip()
    }
}

#[cfg(test)]
#[path = "hierarchy_tests.rs"]
mod tests;
