//! Source allocation prefix admitted by issued roster, current fixed types and parents.
use super::*;
use dm_session::{Observation, ObservationHost, ObservedArtifactStore};
use std::sync::Arc;
#[derive(Clone)]
pub(crate) struct Prefix {
    pub(crate) needed: HashSet<SymbolId>,
    pub(crate) order: Vec<SymbolId>,
    pub(crate) requests: Vec<SymbolId>,
}
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct Inputs {
    pub(crate) source: Arc<crate::type_creation_order::AllocationRoster>,
    pub(crate) fixed: Vec<SymbolId>,
    pub(crate) parents: Arc<BTreeMap<SymbolId, Option<SymbolId>>>,
}
struct Current(Inputs);
impl ObservationHost<(), Inputs, ()> for Current {
    fn answer(&self, _: &()) -> Inputs {
        self.0.clone()
    }
}
pub(crate) struct SourcePrefixes {
    values: ObservedArtifactStore<Prefix, (), Inputs, ()>,
}
impl Default for SourcePrefixes {
    fn default() -> Self {
        Self {
            values: ObservedArtifactStore::current_revision(),
        }
    }
}
impl SourcePrefixes {
    pub(super) fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(super) fn obtain(
        &self,
        source: &Arc<crate::type_creation_order::AllocationRoster>,
        fixed: &HashSet<SymbolId>,
        parents: &Arc<BTreeMap<SymbolId, Option<SymbolId>>>,
        ancestry: &mut ancestry::Request<'_>,
    ) -> Result<Arc<Prefix>, String> {
        let mut fixed_order: Vec<_> = fixed.iter().copied().collect();
        fixed_order.sort_unstable();
        let current = Current(Inputs {
            source: Arc::clone(source),
            fixed: fixed_order,
            parents: Arc::clone(parents),
        });
        const KEY: &[u8] = b"dmbc-required-source-prefix-v1\0";
        if let Some(value) = self.values.lookup(KEY, &current) {
            return Ok(value);
        }
        let value = produce(source.order(), fixed, parents, ancestry)?;
        Ok(self
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
            .expect("current-revision source prefix admits current roster"))
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(dm_session::ObservedArtifactStorageView<'_, Prefix, (), Inputs, ()>),
    ) {
        self.values.visit_storage(visitor);
    }
}
pub(super) fn produce(
    source_order: &[SymbolId],
    retained: &HashSet<SymbolId>,
    parents: &BTreeMap<SymbolId, Option<SymbolId>>,
    ancestry: &mut ancestry::Request<'_>,
) -> Result<Prefix, String> {
    let mut needed = retained.clone();
    needed.insert(SymbolId::of("/"));
    needed.insert(SymbolId::of("/world"));
    let mut order = Vec::new();
    let mut requests = Vec::new();
    let mut source_seen = HashSet::new();
    for &path in source_order {
        if !source_seen.insert(path) {
            return Err("duplicate explicit source class order".into());
        }
        if dm_codegen_byond::NativePrimitiveType::from_symbol(path).is_some() {
            continue;
        }
        if !needed.contains(&path) {
            if !parents.contains_key(&path) {
                return Err("source allocation class absent from semantic skeleton".into());
            }
            needed.insert(path);
            order.push(path);
        }
        requests.push(path);
    }
    // Forward parent assignments append unseen parents only after all authored
    // allocations, preserving the original allocation encounter order.
    for &path in source_order {
        if dm_codegen_byond::NativePrimitiveType::from_symbol(path).is_some() {
            continue;
        }
        if let Some(Some(parent)) = parents.get(&path) {
            ancestry.require(*parent, parents, &mut needed, &mut order)?;
        }
    }
    Ok(Prefix {
        needed,
        order,
        requests,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn source() -> Arc<crate::type_creation_order::AllocationRoster> {
        let source = "/datum/a\n/datum/a/child\n";
        let parsed = dm_syntax::parse(source);
        assert!(parsed.diagnostics.is_empty());
        let mut symbols = SymbolTable::default();
        let ledger = dm_tree::allocation_ledger::capture(&parsed.items, "/", &mut symbols).unwrap();
        crate::type_creation_order::collect_retained(
            &ledger,
            source,
            &symbols,
            &LinkInventory::default(),
            None,
        )
        .unwrap()
    }
    fn same(actual: &Prefix, expected: &Prefix) {
        assert_eq!(actual.needed, expected.needed);
        assert_eq!(actual.order, expected.order);
        assert_eq!(actual.requests, expected.requests);
    }
    #[test]
    fn source_prefix_hit_matches_fresh_and_revalidates_parent_and_fixed_membership() {
        let source = source();
        let store = SourcePrefixes::default();
        let fixed = HashSet::new();
        let parents = Arc::new(BTreeMap::from([
            (SymbolId::of("/datum"), None),
            (SymbolId::of("/datum/a"), Some(SymbolId::of("/datum"))),
            (
                SymbolId::of("/datum/a/child"),
                Some(SymbolId::of("/datum/a")),
            ),
        ]));
        let mut ancestry = ancestry::Request::new(None);
        let first = store
            .obtain(&source, &fixed, &parents, &mut ancestry)
            .unwrap();
        let mut ancestry = ancestry::Request::new(None);
        let hit = store
            .obtain(&source, &fixed, &parents, &mut ancestry)
            .unwrap();
        assert!(Arc::ptr_eq(&first, &hit));
        let fresh = produce(source.order(), &fixed, &parents, &mut ancestry).unwrap();
        same(&hit, &fresh);
        let changed_fixed = HashSet::from([SymbolId::of("/datum/a")]);
        let changed = store
            .obtain(&source, &changed_fixed, &parents, &mut ancestry)
            .unwrap();
        assert!(!Arc::ptr_eq(&hit, &changed));
        same(
            &changed,
            &produce(source.order(), &changed_fixed, &parents, &mut ancestry).unwrap(),
        );
        let mut edited = (*parents).clone();
        edited.insert(
            SymbolId::of("/datum/a/child"),
            Some(SymbolId::of("/datum/extra")),
        );
        edited.insert(SymbolId::of("/datum/extra"), Some(SymbolId::of("/datum")));
        let edited = Arc::new(edited);
        let changed_parent = store
            .obtain(&source, &fixed, &edited, &mut ancestry)
            .unwrap();
        same(
            &changed_parent,
            &produce(source.order(), &fixed, &edited, &mut ancestry).unwrap(),
        );
        assert_eq!(
            changed_parent.order.last(),
            Some(&SymbolId::of("/datum/extra"))
        );
        assert!(!Arc::ptr_eq(&first, &changed_parent));
        let mut invalid = (*edited).clone();
        invalid.remove(&SymbolId::of("/datum/extra"));
        let invalid = Arc::new(invalid);
        assert_eq!(
            store.obtain(&source, &fixed, &invalid, &mut ancestry).err(),
            produce(source.order(), &fixed, &invalid, &mut ancestry).err(),
        );
        let repaired = store
            .obtain(&source, &fixed, &parents, &mut ancestry)
            .unwrap();
        same(&first, &repaired);
        let duplicate = [SymbolId::of("/datum/a"), SymbolId::of("/datum/a")];
        assert_eq!(
            produce(&duplicate, &fixed, &parents, &mut ancestry)
                .err()
                .as_deref(),
            Some("duplicate explicit source class order")
        );
    }
}
