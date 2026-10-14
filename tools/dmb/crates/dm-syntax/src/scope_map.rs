//! Visibility rollback shared by semantic scope analysis and target lowering.
use std::collections::HashMap;

#[derive(Clone, Copy, Debug)]
pub struct ScopeCheckpoint(usize);

/// A declaration journal replaces whole-environment clones. Checkpoints belong
/// to this map; restore an outer checkpoint to unwind nested failed traversal.
pub struct ScopeMap<T> {
    values: HashMap<String, T>,
    undo: Vec<(String, Option<T>)>,
}
impl<T> Default for ScopeMap<T> {
    fn default() -> Self {
        Self {
            values: HashMap::new(),
            undo: Vec::new(),
        }
    }
}
impl<T: Clone> ScopeMap<T> {
    pub fn checkpoint(&self) -> ScopeCheckpoint {
        ScopeCheckpoint(self.undo.len())
    }
    pub fn restore(&mut self, checkpoint: ScopeCheckpoint) {
        assert!(
            checkpoint.0 <= self.undo.len(),
            "scope checkpoint is no longer live"
        );
        while self.undo.len() > checkpoint.0 {
            let (name, previous) = self.undo.pop().expect("undo exceeds checkpoint");
            match previous {
                Some(previous) => {
                    self.values.insert(name, previous);
                }
                None => {
                    self.values.remove(&name);
                }
            }
        }
    }
    pub fn insert(&mut self, name: String, value: T) -> Option<T> {
        let previous = self.values.insert(name.clone(), value);
        self.undo.push((name, previous.clone()));
        previous
    }
    pub fn get(&self, name: &str) -> Option<&T> {
        self.values.get(name)
    }
    pub fn contains_key(&self, name: &str) -> bool {
        self.values.contains_key(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn outer_restore_unwinds_nested_failure_and_restores_overwritten_type() {
        let mut slots = ScopeMap::default();
        slots.insert("arg".into(), 2);
        let outer = slots.checkpoint();
        slots.insert("arg".into(), 3);
        let inner = slots.checkpoint();
        slots.insert("temporary".into(), 4);
        slots.restore(outer);
        assert_eq!(slots.get("arg"), Some(&2));
        assert!(!slots.contains_key("temporary"));
        // The failed inner scope is gone, rather than leaking hidden locals.
        assert!(inner.0 > outer.0);
    }
    #[test]
    fn sibling_scopes_can_redeclare_without_cloning_unrelated_bindings() {
        struct Value(std::rc::Rc<std::cell::Cell<usize>>);
        impl Clone for Value {
            fn clone(&self) -> Self {
                self.0.set(self.0.get() + 1);
                Self(self.0.clone())
            }
        }
        let clones = std::rc::Rc::new(std::cell::Cell::new(0));
        let mut slots = ScopeMap::default();
        slots.insert("outer".into(), Value(clones.clone()));
        for _ in 0..3 {
            let checkpoint = slots.checkpoint();
            slots.insert("local".into(), Value(clones.clone()));
            slots.restore(checkpoint);
        }
        assert_eq!(clones.get(), 0);
        assert!(slots.contains_key("outer"));
    }
}
