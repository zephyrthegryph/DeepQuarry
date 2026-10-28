//! Process-wide sharing of the large immutable link tables that two sessions build from the same inputs.
//!
//! Every session of one project builds its own `BindingData` (the key to index map) and content map, and a
//! second worktree or variant of the same tree builds an equal copy: tens of megabytes each. A table is
//! immutable once built, so equal tables can be one allocation. The pool holds weak references only, so an
//! entry lives exactly as long as some session still holds the table; a session that holds a table the pool
//! has never seen simply registers it. Sharing never changes a value: a candidate is adopted only after a
//! full equality check against the bucket's live entries, and the fingerprint only selects the bucket.
use super::{BTreeMap, Key};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock, Weak},
};

struct Pool<T> {
    buckets: Mutex<Buckets<T>>,
}
struct Buckets<T> {
    map: HashMap<u64, Vec<Weak<T>>>,
    sweep_at: usize,
}
impl<T: PartialEq> Pool<T> {
    fn new() -> Self {
        Self {
            buckets: Mutex::new(Buckets {
                map: HashMap::new(),
                sweep_at: 64,
            }),
        }
    }
    fn share(&self, fingerprint: u64, value: T) -> Arc<T> {
        let mut buckets = self.buckets.lock().unwrap_or_else(|e| e.into_inner());
        if buckets.map.len() >= buckets.sweep_at {
            buckets.map.retain(|_, bucket| {
                bucket.retain(|entry| entry.strong_count() > 0);
                !bucket.is_empty()
            });
            buckets.sweep_at = (buckets.map.len() * 2).max(64);
        }
        let bucket = buckets.map.entry(fingerprint).or_default();
        bucket.retain(|entry| entry.strong_count() > 0);
        for entry in bucket.iter() {
            if let Some(held) = entry.upgrade() {
                if *held == value {
                    return held;
                }
            }
        }
        let shared = Arc::new(value);
        bucket.push(Arc::downgrade(&shared));
        shared
    }
}
/// Selects a bucket: the table size and its first and last keys. Equality decides sharing, so a weak
/// fingerprint costs only a longer bucket.
pub(super) fn fingerprint<V>(map: &BTreeMap<Key, V>) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    map.len().hash(&mut hasher);
    format!("{:?}", map.keys().next()).hash(&mut hasher);
    format!("{:?}", map.keys().next_back()).hash(&mut hasher);
    hasher.finish()
}
pub(super) fn bindings(
    fingerprint: u64,
    data: super::bindings::BindingData,
) -> Arc<super::bindings::BindingData> {
    static POOL: OnceLock<Pool<super::bindings::BindingData>> = OnceLock::new();
    POOL.get_or_init(Pool::new).share(fingerprint, data)
}
pub(super) fn recipe(
    fingerprint: u64,
    recipe: super::assignment_recipe::AssignmentRecipe,
) -> Arc<super::assignment_recipe::AssignmentRecipe> {
    static POOL: OnceLock<Pool<super::assignment_recipe::AssignmentRecipe>> = OnceLock::new();
    POOL.get_or_init(Pool::new).share(fingerprint, recipe)
}

#[cfg(test)]
mod tests {
    use super::super::BindingTables;
    use super::*;

    fn tables(extra: u32) -> BindingTables {
        let mut indexes = BTreeMap::new();
        indexes.insert(Key::String(dm_ir::SymbolId::of("shared_pool_probe")), 1);
        indexes.insert(Key::Type(dm_ir::SymbolId::of("/datum/probe")), extra);
        BindingTables::validated(indexes, BTreeMap::new(), None)
    }
    #[test]
    fn equal_binding_tables_of_two_sessions_share_one_allocation_until_dropped() {
        let first = tables(2);
        let second = tables(2);
        assert!(first.same_owner(&second));
        let different = tables(3);
        assert!(!first.same_owner(&different));
        assert_eq!(different.assignments().len(), 2);
        drop((first, second));
        // Nothing keeps a dropped table alive: the pool holds weak references only.
        let again = tables(2);
        assert_eq!(again.assignments().len(), 2);
    }
}
