//! Exact symbolic ancestry receipts, with fresh current allocation placement.
use super::*;
use dm_session::{Observation, ObservationHost};
use std::sync::atomic::{AtomicU64, Ordering};
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
    values: dm_session::ObservedArtifactStore<Closure, SymbolId, Option<Option<SymbolId>>, ()>,
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
            values: dm_session::ObservedArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }
}
impl RequiredTypeArtifacts {
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
            if let Some(value) = store.values.lookup(&key, &Parents(parents)) {
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
