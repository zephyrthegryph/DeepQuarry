//! Project the authoritative immutable semantic type owner once per admitted roster.
use super::TypeProjection;
use dm_session::{Observation, ObservationHost, ObservedArtifactStore};
use std::sync::Arc;
pub(crate) struct ProjectedTypes {
    pub(crate) types: Arc<[TypeProjection]>,
    pub(crate) construction: Arc<super::type_construction::TypeConstruction>,
}
const KEY: &[u8] = b"dmbc-projected-type-roster-v1\0";
#[derive(Clone)]
pub(crate) struct TypesObservation(pub(crate) Arc<[dm_tree::TypeNode]>);
impl PartialEq for TypesObservation {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
            || (self.0.len() == other.0.len()
                && self
                    .0
                    .iter()
                    .zip(other.0.iter())
                    .all(|(a, b)| a.path == b.path && a.parent == b.parent))
    }
}
impl Eq for TypesObservation {}
struct Current(TypesObservation);
impl ObservationHost<(), TypesObservation, ()> for Current {
    fn answer(&self, _: &()) -> TypesObservation {
        self.0.clone()
    }
}
pub(super) type TypeLease =
    dm_session::ObservedArtifactLease<ProjectedTypes, (), TypesObservation, ()>;
pub(crate) struct TypeRoster {
    values: Arc<ObservedArtifactStore<ProjectedTypes, (), TypesObservation, ()>>,
    local: Option<Arc<TypeLease>>,
    attempt: Option<Arc<super::retained::ProjectionAttempt>>,
}
impl Default for TypeRoster {
    fn default() -> Self {
        let values = ObservedArtifactStore::shared_current_rosters();
        let local = Some(Arc::new(values.lease()));
        Self {
            values,
            local,
            attempt: None,
        }
    }
}
pub(super) fn produce(types: &[dm_tree::TypeNode]) -> Arc<[TypeProjection]> {
    types
        .iter()
        .map(|node| TypeProjection {
            path: node.path,
            parent: node
                .parent
                .and_then(|id| types.get(id.index()))
                .map(|parent| parent.path),
        })
        .collect::<Vec<_>>()
        .into()
}
impl TypeRoster {
    pub(super) fn lease(&self) -> TypeLease {
        self.values.lease()
    }
    pub(super) fn for_attempt(&self, attempt: Arc<super::retained::ProjectionAttempt>) -> Self {
        Self {
            values: Arc::clone(&self.values),
            local: None,
            attempt: Some(attempt),
        }
    }
    fn with_lease<T>(&self, operation: impl FnOnce(&TypeLease) -> T) -> Option<T> {
        match &self.attempt {
            Some(attempt) => attempt.with_pending(|leases| operation(&leases.types)),
            None => self.local.as_deref().map(operation),
        }
    }
    pub(super) fn obtain(&self, tree: &dm_tree::SemanticTree) -> Arc<ProjectedTypes> {
        self.obtain_payload(tree.shared_types())
    }
    #[cfg(test)]
    fn obtain_types(&self, types: Arc<[dm_tree::TypeNode]>) -> Arc<[TypeProjection]> {
        self.obtain_payload(types).types.clone()
    }
    fn obtain_payload(&self, types: Arc<[dm_tree::TypeNode]>) -> Arc<ProjectedTypes> {
        let current = Current(TypesObservation(types));
        if let Some(value) = self
            .with_lease(|lease| lease.visit_explained(KEY, &current, &mut |_| true).0)
            .flatten()
        {
            return Arc::clone(&value);
        }
        let projected = produce(&current.0 .0);
        let value = ProjectedTypes {
            types: projected,
            construction: Default::default(),
        };
        let mut value = Some(value);
        let admitted = self
            .with_lease(|lease| {
                lease.insert_with_owned(
                    Arc::from(KEY),
                    vec![Observation {
                        domain: (),
                        query: (),
                        answer: current.0,
                    }],
                    Vec::new(),
                    0,
                    || value.take().expect("single producer"),
                )
            })
            .flatten();
        // A sealed compatibility facade cannot add claims to published state.
        let value =
            admitted.unwrap_or_else(|| Arc::new(value.expect("unconsumed sealed producer")));
        Arc::clone(&value)
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, ProjectedTypes, (), TypesObservation, ()>,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn node(path: &str, parent: Option<dm_ir::TypeId>) -> dm_tree::TypeNode {
        dm_tree::TypeNode {
            path: dm_ir::SymbolId::of(path),
            parent,
            explicit_parent: false,
            synthetic: false,
            members: Arc::from([]),
        }
    }
    #[test]
    fn immutable_type_owner_reuses_projection_and_changed_parent_rebinds_exactly() {
        let store = TypeRoster::default();
        let types: Arc<[dm_tree::TypeNode]> = Arc::from([
            node("/", None),
            node("/datum", Some(dm_ir::TypeId(0))),
            node("/datum/a", Some(dm_ir::TypeId(1))),
        ]);
        let first = store.obtain_types(Arc::clone(&types));
        assert!(Arc::ptr_eq(&first, &store.obtain_types(Arc::clone(&types))));
        let distinct: Arc<[dm_tree::TypeNode]> = types.to_vec().into();
        assert!(Arc::ptr_eq(&first, &store.obtain_types(distinct)));
        let mut changed = types.to_vec();
        changed[2].parent = Some(dm_ir::TypeId(0));
        let expected = produce(&changed);
        let changed = store.obtain_types(changed.into());
        assert_eq!(changed, expected);
        assert!(!Arc::ptr_eq(&first, &changed));
        assert_eq!(first[2].parent, Some(dm_ir::SymbolId::of("/datum")));
    }
}
