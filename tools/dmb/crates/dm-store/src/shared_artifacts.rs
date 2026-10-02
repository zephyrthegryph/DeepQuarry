//! Weak interning of immutable, content-addressed stage results. Mutable query
//! state stays with its session; live owners share allocations across worktrees.
use std::{
    collections::BTreeMap,
    sync::{Arc, Weak},
};

pub struct SharedArtifacts<T> {
    entries: BTreeMap<String, Weak<T>>,
    max_entries: usize,
}
impl<T> SharedArtifacts<T> {
    pub fn new(max_entries: usize) -> Self {
        Self {
            entries: BTreeMap::new(),
            max_entries,
        }
    }
    pub fn get(&self, identity: &str) -> Option<Arc<T>> {
        self.entries.get(identity)?.upgrade()
    }
    /// The caller establishes that equal identities describe equal stage data.
    /// This index retains no payload and cannot prevent owner-budget eviction.
    pub fn intern(&mut self, identity: String, value: T) -> Arc<T> {
        if let Some(existing) = self.get(&identity) {
            return existing;
        }
        let value = Arc::new(value);
        if self.max_entries == 0 {
            return value;
        }
        if self.entries.len() >= self.max_entries {
            self.entries.retain(|_, value| value.strong_count() != 0);
            while self.entries.len() >= self.max_entries {
                self.entries.pop_first();
            }
        }
        self.entries.insert(identity, Arc::downgrade(&value));
        value
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn immutable_owners_share_and_weak_index_does_not_pin_data() {
        let mut pool = SharedArtifacts::new(2);
        let first = pool.intern("content".into(), vec![1, 2]);
        let second = pool.intern("content".into(), vec![1, 2]);
        assert!(Arc::ptr_eq(&first, &second));
        drop(first);
        drop(second);
        assert!(pool.get("content").is_none());
        let _live = pool.intern("other".into(), vec![3]);
        pool.intern("third".into(), vec![4]);
        assert!(pool.entries.len() <= 2);
    }
}
