//! Ordered output type selection; every hit observes current type contents and membership.
use super::*;
use crate::class_projection::TypeProjection;
use dm_session::{Observation, ObservationHost, ObservedArtifactStore};
use std::sync::Arc;
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct Selection {
    pub(crate) types: Arc<[TypeProjection]>,
    pub(crate) needed: Arc<HashSet<SymbolId>>,
}
struct Current(Selection);
impl ObservationHost<(), Selection, ()> for Current {
    fn answer(&self, _: &()) -> Selection {
        self.0.clone()
    }
}
pub(crate) struct SelectedRosters {
    values: ObservedArtifactStore<Arc<[TypeProjection]>, (), Selection, ()>,
}
impl Default for SelectedRosters {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
        }
    }
}
pub(super) fn produce(
    types: &[TypeProjection],
    needed: &HashSet<SymbolId>,
) -> Arc<[TypeProjection]> {
    types
        .iter()
        .filter(|ty| needed.contains(&ty.path))
        .cloned()
        .collect::<Vec<_>>()
        .into()
}
impl SelectedRosters {
    pub(super) fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(super) fn obtain(
        &self,
        types: &Arc<[TypeProjection]>,
        needed: HashSet<SymbolId>,
    ) -> Arc<[TypeProjection]> {
        const KEY: &[u8] = b"dmbc-required-selected-roster-v1\0";
        let current = Current(Selection {
            types: Arc::clone(types),
            needed: Arc::new(needed),
        });
        if let Some(value) = self.values.lookup(KEY, &current) {
            return Arc::clone(&value);
        }
        let value = produce(&current.0.types, &current.0.needed);
        let stored = self
            .values
            .insert_with_owned(
                Arc::from(KEY),
                vec![Observation {
                    domain: (),
                    query: (),
                    answer: current.0,
                }],
                Vec::new(),
                0,
                || value,
            )
            .expect("current-revision selected roster admits current type membership");
        Arc::clone(&stored)
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, Arc<[TypeProjection]>, (), Selection, ()>,
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
    fn exact_current_selection_shares_output_and_rebinds_membership_parent_and_order_changes() {
        let store = SelectedRosters::default();
        let types: Arc<[TypeProjection]> = Arc::from([
            ty("/datum/z", Some("/datum")),
            ty("/datum", None),
            ty("/datum/a", Some("/datum")),
            ty("/datum/z", Some("/datum/a")),
        ]);
        let selected: HashSet<_> = [SymbolId::of("/datum/z"), SymbolId::of("/datum")]
            .into_iter()
            .collect();
        let first = store.obtain(&types, selected.clone());
        let distinct: Arc<[TypeProjection]> = types.to_vec().into();
        assert!(Arc::ptr_eq(
            &first,
            &store.obtain(&distinct, selected.clone())
        ));
        let expected: Vec<_> = types
            .iter()
            .filter(|ty| selected.contains(&ty.path))
            .cloned()
            .collect();
        assert_eq!(first.as_ref(), expected);
        // Membership changes remain visible even when the full type owner is identical.
        let expanded: HashSet<_> = types.iter().map(|ty| ty.path).collect();
        let changed = store.obtain(&types, expanded);
        assert_eq!(changed.as_ref(), types.as_ref());
        assert!(!Arc::ptr_eq(&first, &changed));
        let mut reordered = types.to_vec();
        reordered.reverse();
        reordered[0].parent = None;
        let reordered: Arc<[TypeProjection]> = reordered.into();
        let output = store.obtain(&reordered, selected.clone());
        let expected: Vec<_> = reordered
            .iter()
            .filter(|ty| selected.contains(&ty.path))
            .cloned()
            .collect();
        assert_eq!(output.as_ref(), expected);
        assert!(!Arc::ptr_eq(&first, &output));
        assert!(store.obtain(&types, HashSet::new()).is_empty());
        store.clear();
        assert_eq!(first.len(), 3);
    }
}
