//! Exact lexical type-path contributions, independent of current dense IDs.
use crate::{SymbolId, SymbolTable, TreeError};
use dm_session::{
    ObservationHost, ObservationLedger, ObservedArtifactStorageView, ObservedArtifactStore,
};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LexicalPath {
    pub parent: Option<Arc<str>>,
}
struct Host<'a>(&'a SymbolTable);
impl ObservationHost<SymbolId, Option<String>, ()> for Host<'_> {
    fn answer(&self, query: &SymbolId) -> Option<String> {
        self.0.text(*query).map(str::to_owned)
    }
}
type Store = ObservedArtifactStore<LexicalPath, SymbolId, Option<String>, ()>;
pub(crate) struct RetainedTypePaths {
    store: Store,
    hits: AtomicUsize,
}
impl Default for RetainedTypePaths {
    fn default() -> Self {
        Self {
            store: Store::current_revision(),
            hits: AtomicUsize::new(0),
        }
    }
}
fn key(path: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"type-lexical-path-v1".to_vec();
    bytes.extend_from_slice(&path.bits().to_le_bytes());
    bytes.into()
}
impl RetainedTypePaths {
    pub(crate) fn resolve(
        &self,
        path: SymbolId,
        symbols: &SymbolTable,
    ) -> Result<Arc<LexicalPath>, TreeError> {
        let host = Host(symbols);
        if let Some(value) = self.store.lookup(&key(path), &host) {
            self.hits.fetch_add(1, Ordering::Relaxed);
            return Ok(value);
        }
        let answer = host.answer(&path);
        let text = answer.as_deref().ok_or(TreeError::UnknownSymbol(path))?;
        let parsed = dm_ir::TypePath::parse(text).map_err(|_| TreeError::InvalidPath(path))?;
        let parent = parsed
            .parent()
            .map(|parent| Arc::<str>::from(parent.as_str()));
        let ledger = ObservationLedger::default();
        ledger.record(path, answer, (), None);
        self.store.insert_with(
            key(path),
            ledger.reads(),
            ledger.domain_receipts(),
            0,
            || LexicalPath {
                parent: parent.clone(),
            },
        );
        Ok(Arc::new(LexicalPath { parent }))
    }
    pub(crate) fn retain(&self, paths: &[SymbolId]) {
        let keys: Vec<_> = paths.iter().map(|path| key(*path)).collect();
        self.store
            .retain_current_keys(keys.iter().map(|key| key.as_ref()));
    }
    pub(crate) fn hits(&self) -> usize {
        self.hits.load(Ordering::Relaxed)
    }
    pub(crate) fn visit_storage(
        &self,
        visit: impl FnMut(ObservedArtifactStorageView<'_, LexicalPath, SymbolId, Option<String>, ()>),
    ) {
        self.store.visit_storage(visit);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn paths_reuse_across_dense_projection_changes_and_reject_missing_spelling() {
        let retained = RetainedTypePaths::default();
        let mut symbols = SymbolTable::default();
        let child = symbols.intern("/datum/example/child").unwrap();
        let first = retained.resolve(child, &symbols).unwrap();
        symbols.intern("/datum/unrelated").unwrap();
        let second = retained.resolve(child, &symbols).unwrap();
        assert_eq!(first.parent.as_deref(), Some("/datum/example"));
        assert_eq!(second.parent, first.parent);
        assert_eq!(retained.hits(), 1);
        assert!(
            matches!(retained.resolve(child, &SymbolTable::default()), Err(TreeError::UnknownSymbol(id)) if id == child)
        );
    }
    #[test]
    fn retained_graph_rebinds_ids_and_matches_fresh_parent_projection() {
        let retained = crate::owner_normalization::RetainedNormalization::default();
        let mut symbols = SymbolTable::default();
        let datum = symbols.intern("/datum").unwrap();
        let child = symbols.intern("/datum/child").unwrap();
        let unrelated = symbols.intern("/datum/unrelated").unwrap();
        let initial = vec![
            crate::Skeleton::Type {
                path: datum,
                explicit_parent: None,
            },
            crate::Skeleton::Type {
                path: child,
                explicit_parent: None,
            },
        ];
        let (index, _) =
            crate::declaration_contributions::KeyedDeclarations::capture(None, &initial).unwrap();
        crate::build_with_intrinsic_members_indexed(
            symbols.clone(),
            (&initial).into(),
            &[],
            &[],
            false,
            Some((&index, &retained)),
        )
        .unwrap();
        let changed = vec![
            initial[0].clone(),
            crate::Skeleton::Type {
                path: unrelated,
                explicit_parent: None,
            },
            initial[1].clone(),
        ];
        let (index, _) =
            crate::declaration_contributions::KeyedDeclarations::capture(Some(&index), &changed)
                .unwrap();
        let actual = crate::build_with_intrinsic_members_indexed(
            symbols.clone(),
            (&changed).into(),
            &[],
            &[],
            false,
            Some((&index, &retained)),
        )
        .unwrap();
        let fresh = crate::build_with_intrinsic_members_indexed(
            symbols,
            (&changed).into(),
            &[],
            &[],
            false,
            None,
        )
        .unwrap();
        assert!(retained.paths.hits() >= 3);
        let facts = |tree: &crate::SemanticTree| {
            tree.types
                .iter()
                .map(|node| {
                    (
                        node.path,
                        node.parent.map(|id| tree.types[id.index()].path),
                        node.explicit_parent,
                        node.synthetic,
                    )
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(facts(&actual), facts(&fresh));
        assert_ne!(actual.lookup_type(child), Some(dm_ir::TypeId(2)));
    }
}
