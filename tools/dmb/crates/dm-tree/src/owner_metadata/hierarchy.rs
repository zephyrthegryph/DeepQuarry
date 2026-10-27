//! Owner ancestries share the effective-owner artifact store. Dense IDs,
//! unrelated members and source coordinates do not enter these answers.
use super::*;

pub(super) fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-hierarchy-paths-v2".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
pub(crate) fn ancestry(tree: &SemanticTree, owner: SymbolId) -> Arc<[SymbolId]> {
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
    /// Every owner's ancestry, shared with the previous request's allocation when it is unchanged.
    pub(crate) fn owner_ancestry(&self, tree: &SemanticTree) -> BTreeMap<SymbolId, Arc<[SymbolId]>> {
        let host = HierarchyHost(tree);
        tree.types
            .iter()
            .map(|node| {
                let owner = node.path;
                let key = key(owner);
                if let Some(value) = self.store.lookup(&key, &host) {
                    if let EffectiveOwner::Hierarchy { paths } = value.as_ref() {
                        return (owner, Arc::clone(paths));
                    }
                }
                let query = MetadataQuery::Hierarchy(owner);
                let answer = host.answer(&query);
                let MetadataAnswer::Hierarchy(paths) = &answer else {
                    unreachable!()
                };
                let ledger = ObservationLedger::default();
                ledger.record(query, answer.clone(), query.domain());
                let paths = Arc::clone(paths);
                let stored_paths = Arc::clone(&paths);
                self.store
                    .insert_with(key, ledger.reads(), Vec::new(), 0, || EffectiveOwner::Hierarchy { paths });
                (owner, stored_paths)
            })
            .collect()
    }
}

