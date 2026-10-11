//! An exact full current type roster admits its derived parent lookup index.
use crate::class_projection::TypeProjection;
use crate::initializer_lowering::receipts::publication_store::PublicationStore as ObservedArtifactStore;
use dm_ir::SymbolId;
use dm_session::{Observation, ObservationHost};
use std::{collections::BTreeMap, sync::Arc};
type Parents = BTreeMap<SymbolId, Option<SymbolId>>;
const KEY: &[u8] = b"dmbc-required-parent-index-v1\0";
pub(crate) struct ParentIndex {
    values: ObservedArtifactStore<Parents, (), Arc<[TypeProjection]>, ()>,
}
impl Default for ParentIndex {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
        }
    }
}
struct Current<'a>(&'a Arc<[TypeProjection]>);
impl ObservationHost<(), Arc<[TypeProjection]>, ()> for Current<'_> {
    fn answer(&self, _: &()) -> Arc<[TypeProjection]> {
        Arc::clone(self.0)
    }
}
pub(super) fn produce(types: &[TypeProjection]) -> Parents {
    // Preserve the original ordered collect semantics: later duplicate paths win.
    types.iter().map(|ty| (ty.path, ty.parent)).collect()
}
impl ParentIndex {
    pub(crate) fn for_request(&self, publishable: bool) -> Self {
        Self {
            values: self.values.for_request(publishable),
        }
    }
    pub(crate) fn publish_successful(&self) -> bool {
        self.values.publish_successful()
    }

    pub(super) fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(super) fn obtain(&self, types: &Arc<[TypeProjection]>) -> Arc<Parents> {
        if let Some(value) = self.values.lookup(KEY, &Current(types)) {
            return value;
        }
        let value = produce(types);
        self.values
            .insert_with_owned(
                Arc::from(KEY),
                vec![Observation {
                    domain: (),
                    query: (),
                    answer: Arc::clone(types),
                }],
                Vec::new(),
                0,
                || value,
            )
            .expect("current-revision parent index admits current roster")
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, Parents, (), Arc<[TypeProjection]>, ()>,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn ty(path: &str, parent: Option<&str>) -> TypeProjection {
        TypeProjection {
            path: SymbolId::of(path),
            parent: parent.map(SymbolId::of),
        }
    }
    #[test]
    fn full_roster_admission_reuses_index_and_changes_preserve_last_duplicate_winner() {
        let store = ParentIndex::default();
        let types: Arc<[TypeProjection]> = Arc::from([
            ty("/datum/a", Some("/datum")),
            ty("/datum", None),
            ty("/datum/a", Some("/datum/b")),
        ]);
        let first = store.obtain(&types);
        let distinct: Arc<[TypeProjection]> = types.iter().cloned().collect::<Vec<_>>().into();
        assert!(!Arc::ptr_eq(&types, &distinct));
        assert!(Arc::ptr_eq(&first, &store.obtain(&distinct)));
        assert_eq!(
            first.get(&SymbolId::of("/datum/a")),
            Some(&Some(SymbolId::of("/datum/b")))
        );
        let mut edited = types.to_vec();
        edited.reverse();
        let edited: Arc<[TypeProjection]> = edited.into();
        let changed = store.obtain(&edited);
        assert!(!Arc::ptr_eq(&first, &changed));
        let expected: Parents = edited.iter().map(|ty| (ty.path, ty.parent)).collect();
        assert_eq!(*changed, expected);
        let missing: Arc<[TypeProjection]> = Arc::from([ty("/datum/a", Some("/missing"))]);
        assert_eq!(
            *store.obtain(&missing),
            BTreeMap::from([(SymbolId::of("/datum/a"), Some(SymbolId::of("/missing"))),])
        );
        let empty: Arc<[TypeProjection]> = Arc::from([]);
        assert!(store.obtain(&empty).is_empty());
        // A reader of the prior roster remains valid after replacement/clear.
        store.clear();
        assert_eq!(first.len(), 2);
    }
}
