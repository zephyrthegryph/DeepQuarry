//! Exact symbolic ancestry receipts, with fresh current allocation placement.
use super::*;
use dm_session::{Observation, ObservationHost};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
#[derive(Clone)]
pub(crate) struct Closure {
    pub boundary: Option<SymbolId>,
    pub ordered: Vec<SymbolId>,
}
struct Parents<'a>(&'a BTreeMap<SymbolId, Option<SymbolId>>);
impl ObservationHost<SymbolId, Option<Option<SymbolId>>, ()> for Parents<'_> {
    fn answer(&self, path: &SymbolId) -> Option<Option<SymbolId>> {
        self.0.get(path).copied()
    }
}
pub struct RequiredTypeArtifacts {
    pub(crate) selected: super::selected_roster::SelectedRosters,
    pub(crate) prefixes: super::source_prefix::SourcePrefixes,
    pub(crate) allocations: crate::type_creation_order::AllocationArtifacts,
    pub(crate) parents: super::parent_index::ParentIndex,
    pub(crate) fields: super::field_requests::FieldRequests,
    values: crate::initializer_lowering::receipts::publication_store::PublicationStore<
        Closure,
        SymbolId,
        Option<Option<SymbolId>>,
        (),
    >,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
}
impl Default for RequiredTypeArtifacts {
    fn default() -> Self {
        Self {
            fields: Default::default(),
            selected: Default::default(),
            prefixes: Default::default(),
            allocations: Default::default(),
            parents: Default::default(),
            values: crate::initializer_lowering::receipts::publication_store::PublicationStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }
}
impl RequiredTypeArtifacts {
    pub(crate) fn for_request(&self, publishable: bool) -> Arc<Self> {
        Arc::new(Self {
            fields: self.fields.for_request(publishable),
            selected: self.selected.for_request(publishable),
            prefixes: self.prefixes.for_request(publishable),
            allocations: self.allocations.for_request(publishable),
            parents: self.parents.for_request(publishable),
            values: self.values.for_request(publishable),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        })
    }
    pub(crate) fn publish_successful(&self) -> bool {
        let results = [
            self.fields.publish_successful(),
            self.selected.publish_successful(),
            self.prefixes.publish_successful(),
            self.allocations.publish_successful(),
            self.parents.publish_successful(),
            self.values.publish_successful(),
        ];
        results.into_iter().all(|published| published)
    }

    pub fn clear(&self) {
        self.fields.clear();
        self.selected.clear();
        self.prefixes.clear();
        self.allocations.clear();
        self.parents.clear();
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                Closure,
                SymbolId,
                Option<Option<SymbolId>>,
                (),
            >,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
}
pub(super) struct Request<'a> {
    store: Option<&'a RequiredTypeArtifacts>,
    keys: Vec<Vec<u8>>,
}
impl<'a> Request<'a> {
    pub fn new(store: Option<&'a RequiredTypeArtifacts>) -> Self {
        Self {
            store,
            keys: Vec::new(),
        }
    }
    pub fn require(
        &mut self,
        path: SymbolId,
        parents: &BTreeMap<SymbolId, Option<SymbolId>>,
        needed: &mut HashSet<SymbolId>,
        order: &mut Vec<SymbolId>,
    ) -> Result<(), String> {
        primitive(path)?;
        if needed.contains(&path) {
            return Ok(());
        }
        if self.store.is_none() {
            return walk(
                path,
                parents,
                needed,
                order,
                &mut HashSet::new(),
                &mut Vec::new(),
                &mut None,
                false,
            );
        }
        let mut key = b"dmbc-required-ancestry-v1\0".to_vec();
        key.extend_from_slice(&path.bits().to_le_bytes());
        if let Some(store) = self.store {
            self.keys.push(key.clone());
            if let Some(value) = store
                .values
                .visit_explained(&key, &Parents(parents), &mut |value| {
                    value
                        .boundary
                        .is_none_or(|boundary| needed.contains(&boundary))
                })
                .0
            {
                if value
                    .boundary
                    .is_none_or(|boundary| needed.contains(&boundary))
                {
                    let first = value
                        .ordered
                        .iter()
                        .rposition(|path| needed.contains(path))
                        .map_or(0, |index| index + 1);
                    for &path in &value.ordered[first..] {
                        needed.insert(path);
                        order.push(path);
                    }
                    store.hits.fetch_add(1, Ordering::Relaxed);
                    return Ok(());
                }
            }
        }
        let mut reads = Vec::new();
        let mut boundary = None;
        let before = order.len();
        walk(
            path,
            parents,
            needed,
            order,
            &mut HashSet::new(),
            &mut reads,
            &mut boundary,
            true,
        )?;
        if let Some(store) = self.store {
            let value = Closure {
                boundary,
                ordered: order[before..].to_vec(),
            };
            store
                .values
                .insert_with(key.into(), reads, Vec::new(), 0, || value);
            store.recomputed.fetch_add(1, Ordering::Relaxed);
        }
        Ok(())
    }
    pub fn finish(self) {
        if let Some(store) = self.store {
            store
                .values
                .retain_current_keys(self.keys.iter().map(Vec::as_slice));
        }
    }
}
fn primitive(path: SymbolId) -> Result<(), String> {
    if dm_codegen_byond::NativePrimitiveType::from_symbol(path).is_some() {
        Err(format!(
            "native primitive requires explicit physical class ABI: {path:?}"
        ))
    } else {
        Ok(())
    }
}
#[allow(clippy::too_many_arguments)]
fn walk(
    path: SymbolId,
    parents: &BTreeMap<SymbolId, Option<SymbolId>>,
    needed: &mut HashSet<SymbolId>,
    order: &mut Vec<SymbolId>,
    active: &mut HashSet<SymbolId>,
    reads: &mut Vec<Observation<SymbolId, Option<Option<SymbolId>>, ()>>,
    boundary: &mut Option<SymbolId>,
    record: bool,
) -> Result<(), String> {
    primitive(path)?;
    if needed.contains(&path) {
        *boundary = Some(path);
        return Ok(());
    }
    if !active.insert(path) {
        return Err("required class parent cycle".into());
    }
    let answer = parents.get(&path).copied();
    if record {
        reads.push(Observation {
            domain: (),
            query: path,
            answer,
        });
    }
    let parent = answer
        .ok_or_else(|| format!("referenced class absent from semantic skeleton: {path:?}"))?;
    if let Some(parent) = parent {
        walk(
            parent, parents, needed, order, active, reads, boundary, record,
        )?;
    }
    active.remove(&path);
    needed.insert(path);
    order.push(path);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn id(name: &str) -> SymbolId {
        SymbolId::of(name)
    }
    fn graph() -> BTreeMap<SymbolId, Option<SymbolId>> {
        BTreeMap::from([
            (id("/datum/a"), Some(id("/datum"))),
            (id("/datum/a/b"), Some(id("/datum/a"))),
            (id("/datum"), None),
        ])
    }
    #[test]
    fn pending_required_rosters_preserve_published_ancestry_on_failure_and_analysis() {
        let owner = RequiredTypeArtifacts::default();
        let parents = graph();
        let run = |store: &RequiredTypeArtifacts| {
            let mut needed = HashSet::new();
            let mut order = Vec::new();
            let mut request = Request::new(Some(store));
            request
                .require(id("/datum/a/b"), &parents, &mut needed, &mut order)
                .unwrap();
            request.finish();
            let mut fresh_needed = HashSet::new();
            let mut fresh_order = Vec::new();
            Request::new(None)
                .require(
                    id("/datum/a/b"),
                    &parents,
                    &mut fresh_needed,
                    &mut fresh_order,
                )
                .unwrap();
            assert_eq!(needed, fresh_needed);
            assert_eq!(order, fresh_order);
        };
        let first = owner.for_request(true);
        run(&first);
        assert!(first.publish_successful());
        let failed = owner.for_request(true);
        failed.clear();
        drop(failed);
        let next = owner.for_request(true);
        run(&next);
        assert_eq!(next.hits.load(Ordering::Relaxed), 1);
        let analysis = owner.for_request(false);
        analysis.clear();
        assert!(!analysis.publish_successful());
        assert!(next.publish_successful());
        let removed = owner.for_request(true);
        Request::new(Some(&removed)).finish();
        assert!(removed.publish_successful());
        let fresh = owner.for_request(true);
        run(&fresh);
        assert_eq!(fresh.hits.load(Ordering::Relaxed), 0);
        assert_eq!(fresh.recomputed.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn retained_closure_preserves_current_boundary_and_encounter_order() {
        let store = RequiredTypeArtifacts::default();
        let parents = graph();
        for boundary in [
            vec![id("/datum")],
            vec![id("/datum"), id("/datum/a")],
            vec![],
        ] {
            let mut current = boundary.iter().copied().collect::<HashSet<_>>();
            let mut fresh = current.clone();
            let mut actual = Vec::new();
            let mut expected = Vec::new();
            let mut request = Request::new(Some(&store));
            request
                .require(id("/datum/a/b"), &parents, &mut current, &mut actual)
                .unwrap();
            Request::new(None)
                .require(id("/datum/a/b"), &parents, &mut fresh, &mut expected)
                .unwrap();
            assert_eq!(actual, expected);
            assert_eq!(current, fresh);
            request.finish();
        }
        assert_eq!(store.hits.load(Ordering::Relaxed), 1);
        assert_eq!(store.recomputed.load(Ordering::Relaxed), 2);
    }
    #[test]
    fn changed_parent_missing_and_cycle_errors_match_fresh_and_skip_known_ancestors() {
        let store = RequiredTypeArtifacts::default();
        let mut parents = graph();
        let run = |store, parents: &BTreeMap<_, _>, needed: HashSet<_>| {
            let mut needed = needed;
            let mut order = Vec::new();
            let mut request = Request::new(store);
            let result = request.require(id("/datum/a/b"), parents, &mut needed, &mut order);
            (result, order)
        };
        assert!(run(Some(&store), &parents, HashSet::new()).0.is_ok());
        parents.insert(id("/datum/a"), Some(id("/datum/missing")));
        assert_eq!(
            run(Some(&store), &parents, HashSet::new()),
            run(None, &parents, HashSet::new())
        );
        let known = HashSet::from([id("/datum/a")]);
        assert_eq!(
            run(Some(&store), &parents, known.clone()),
            run(None, &parents, known)
        );
        parents.insert(id("/datum/a"), Some(id("/datum/a/b")));
        let actual = run(Some(&store), &parents, HashSet::new());
        assert_eq!(actual, run(None, &parents, HashSet::new()));
        assert_eq!(actual.0.unwrap_err(), "required class parent cycle");
    }
}
