//! Structurally shared exact expansion environments. Each binding owns its
//! replacement and definition origin once; snapshots retain only persistent roots.
use super::DefinitionOrigin;
use crate::{Macro, MacroLookup};
use std::sync::Arc;

#[derive(Clone, Debug)]
struct Binding {
    definition: Arc<Macro>,
    origin: Option<DefinitionOrigin>,
}

#[derive(Clone, Debug, Default)]
pub struct MacroEnvironment {
    bindings: im::OrdMap<Arc<str>, Arc<Binding>>,
}
impl MacroEnvironment {
    /// Exact persistent-root sharing, for opt-in diagnostics without cloning maps.
    pub fn shares_storage_with(&self, other: &Self) -> bool {
        self.bindings.ptr_eq(&other.bindings)
    }

    /// Borrow retained payloads; opaque persistent-map node capacity is not exposed.
    /// The binding address and inline size permit deduplication across snapshots.
    pub fn visit_storage(
        &self,
        mut visitor: impl FnMut(&Arc<str>, usize, usize, &Arc<Macro>, Option<&DefinitionOrigin>),
    ) {
        for (name, binding) in &self.bindings {
            visitor(
                name,
                Arc::as_ptr(binding) as usize,
                std::mem::size_of::<Binding>(),
                &binding.definition,
                binding.origin.as_ref(),
            );
        }
    }
    pub(super) fn insert(
        &mut self,
        name: &str,
        definition: Macro,
        origin: Option<DefinitionOrigin>,
    ) {
        self.bindings.insert(
            Arc::from(name),
            Arc::new(Binding {
                definition: Arc::new(definition),
                origin,
            }),
        );
    }
    pub(super) fn remove(&mut self, name: &str) {
        self.bindings.remove(name);
    }
    pub fn definition_origin(&self, name: &str) -> Option<&DefinitionOrigin> {
        self.bindings.get(name)?.origin.as_ref()
    }
    pub fn shared_definition(&self, name: &str) -> Option<Arc<Macro>> {
        self.bindings
            .get(name)
            .map(|binding| Arc::clone(&binding.definition))
    }
    pub fn len(&self) -> usize {
        self.bindings.len()
    }
    pub fn is_empty(&self) -> bool {
        self.bindings.is_empty()
    }
}
impl MacroLookup for MacroEnvironment {
    fn get_key_value(&self, name: &str) -> Option<(&str, &Macro)> {
        self.bindings
            .get_key_value(name)
            .map(|(key, binding)| (key.as_ref(), binding.definition.as_ref()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn snapshots_share_replacement_bodies_and_freeze_definition_epochs() {
        let mut env = MacroEnvironment::default();
        env.insert(
            "LARGE",
            Macro {
                parameters: None,
                variadic: false,
                replacement: "body".repeat(16384),
            },
            None,
        );
        let first = env.clone();
        assert!(first.shares_storage_with(&env));
        env.insert(
            "OTHER",
            Macro {
                parameters: None,
                variadic: false,
                replacement: "2".into(),
            },
            None,
        );
        let second = env.clone();
        assert!(!first.shares_storage_with(&second));
        let retained = |snapshot: &MacroEnvironment| {
            let mut result = None;
            snapshot.visit_storage(|name, binding, _, definition, _| {
                if name.as_ref() == "LARGE" {
                    result = Some((binding, Arc::as_ptr(definition) as usize));
                }
            });
            result.unwrap()
        };
        assert_eq!(retained(&first), retained(&second));
        assert!(std::ptr::eq(
            first.get("LARGE").unwrap(),
            second.get("LARGE").unwrap()
        ));
        env.insert(
            "LARGE",
            Macro {
                parameters: None,
                variadic: false,
                replacement: "new".into(),
            },
            None,
        );
        env.remove("OTHER");
        assert_eq!(first.get("LARGE").unwrap().replacement.len(), 65536);
        assert_eq!(second.get("OTHER").unwrap().replacement, "2");
        assert_eq!(env.get("LARGE").unwrap().replacement, "new");
        assert!(env.get("OTHER").is_none());
    }
}
