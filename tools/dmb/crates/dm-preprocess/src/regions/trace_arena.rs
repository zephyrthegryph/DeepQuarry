//! Region-local exact provenance text sharing; no global synchronization.
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::sync::Arc;
type SharedChain = Arc<[Arc<str>]>;
#[derive(Default)]
pub(super) struct TraceArena {
    empty_expansions: Arc<Vec<super::MacroExpansion>>,
    names: HashSet<Arc<str>>,
    chains: HashMap<u64, Vec<SharedChain>>,
}
impl TraceArena {
    pub(super) fn freeze_expansions(
        &self,
        mut expansions: Vec<super::MacroExpansion>,
    ) -> Arc<Vec<super::MacroExpansion>> {
        if expansions.is_empty() {
            return Arc::clone(&self.empty_expansions);
        }
        expansions.shrink_to_fit();
        Arc::new(expansions)
    }

    pub(super) fn name(&mut self, name: &str) -> Arc<str> {
        if let Some(existing) = self.names.get(name) {
            return Arc::clone(existing);
        }
        let owned: Arc<str> = Arc::from(name);
        self.names.insert(Arc::clone(&owned));
        owned
    }
    pub(super) fn chain(&mut self, chain: &[&str]) -> Arc<[Arc<str>]> {
        self.chain_iter(chain.iter().copied())
    }
    fn chain_iter<'a>(&mut self, chain: impl Iterator<Item = &'a str> + Clone) -> Arc<[Arc<str>]> {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        let len = chain.clone().count();
        len.hash(&mut hasher);
        for name in chain.clone() {
            name.hash(&mut hasher);
        }
        let hash = hasher.finish();
        if let Some(existing) = self.chains.get(&hash).and_then(|entries| {
            entries.iter().find(|entry| {
                entry.len() == len && entry.iter().map(|name| name.as_ref()).eq(chain.clone())
            })
        }) {
            return Arc::clone(existing);
        }
        let owned: Arc<[Arc<str>]> = chain.map(|name| self.name(name)).collect();
        self.chains
            .entry(hash)
            .or_default()
            .push(Arc::clone(&owned));
        owned
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_ordered_text_controls_sharing_and_survives_arena_drop() {
        let mut arena = TraceArena::default();
        let first = arena.name("OUTER");
        assert!(Arc::ptr_eq(&first, &arena.name("OUTER")));
        let chain = arena.chain(&["OUTER", "INNER"]);
        let wire = ["OUTER".to_owned(), "INNER".to_owned()];
        let borrowed = [wire[0].as_str(), wire[1].as_str()];
        assert!(Arc::ptr_eq(&chain, &arena.chain(&borrowed)));
        assert!(Arc::ptr_eq(&first, &chain[0]));
        assert_ne!(chain, arena.chain(&["INNER", "OUTER"]));
        let other = arena.chain(&["DIFFERENT"]);
        for bucket in arena.chains.values_mut() {
            bucket.insert(0, Arc::clone(&other));
        }
        assert!(Arc::ptr_eq(&chain, &arena.chain(&borrowed)));
        drop(arena);
        assert_eq!(chain[0].as_ref(), "OUTER");
    }
}
