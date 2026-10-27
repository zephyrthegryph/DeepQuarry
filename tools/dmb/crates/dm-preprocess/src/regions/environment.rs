//! Structurally shared exact expansion environments. Each binding owns its
//! replacement and definition origin once; snapshots retain only persistent roots.
use super::DefinitionOrigin;
use crate::{Macro, MacroLookup};
use std::sync::Arc;

#[derive(Clone, Debug)]
pub(super) struct Binding {
    definition: Arc<Macro>,
    origin: Option<DefinitionOrigin>,
}
// The diagnostic structural diff observes allocation ownership, not macro meaning.
// Fresh equal-content bindings must be visited because they retain distinct heaps.
impl PartialEq for Binding {
    fn eq(&self, other: &Self) -> bool {
        std::ptr::eq(self, other)
    }
}
impl Eq for Binding {}

#[derive(Clone, Debug, Default)]
pub struct MacroEnvironment {
    bindings: im::OrdMap<Arc<str>, Arc<Binding>>,
    /// Order independent digest of every binding (name, definition, origin), kept up to date by
    /// `insert` and `remove`: two environments with equal length and fingerprint hold the same
    /// bindings, which lets a planner prove an incoming state unchanged without comparing maps.
    fingerprint: u128,
}
/// Digest of one binding: its name, the whole definition and the definition site.
fn binding_digest(name: &str, binding: &Binding) -> u128 {
    use xxhash_rust::xxh3::Xxh3;
    let mut hash = Xxh3::new();
    hash.update(&(name.len() as u64).to_le_bytes());
    hash.update(name.as_bytes());
    let definition = &*binding.definition;
    match &definition.parameters {
        None => hash.update(&[0]),
        Some(parameters) => {
            hash.update(&[1]);
            hash.update(&(parameters.len() as u64).to_le_bytes());
            for parameter in parameters {
                hash.update(&(parameter.len() as u64).to_le_bytes());
                hash.update(parameter.as_bytes());
            }
        }
    }
    hash.update(&[u8::from(definition.variadic)]);
    hash.update(&(definition.replacement.len() as u64).to_le_bytes());
    hash.update(definition.replacement.as_bytes());
    match &binding.origin {
        None => hash.update(&[0]),
        Some(origin) => {
            hash.update(&[1]);
            let path = origin.path.as_os_str().as_encoded_bytes();
            hash.update(&(path.len() as u64).to_le_bytes());
            hash.update(path);
            hash.update(&(origin.source_span.start as u64).to_le_bytes());
            hash.update(&(origin.source_span.end as u64).to_le_bytes());
            hash.update(&(origin.source_line as u64).to_le_bytes());
        }
    }
    hash.digest128()
}
/// The bindings in which one environment differs from another (`MacroEnvironment::delta_from`): each name with the
/// binding it has (`None`: undefined), sorted by name. Applied to the other environment it gives the first.
#[derive(Clone, Debug, Default)]
pub(super) struct EnvDelta(Vec<(Arc<str>, Option<Arc<Binding>>)>);
impl EnvDelta {
    pub(super) fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    pub(super) fn len(&self) -> usize {
        self.0.len()
    }
    pub(super) fn names(&self) -> Arc<[Arc<str>]> {
        self.0.iter().map(|(name, _)| Arc::clone(name)).collect()
    }
    pub(super) fn contains(&self, name: &str) -> bool {
        self.0.binary_search_by(|(entry, _)| entry.as_ref().cmp(name)).is_ok()
    }
}
impl MacroEnvironment {
    /// This environment with `delta`'s bindings set (or removed).
    pub(super) fn apply(&self, delta: &EnvDelta) -> Self {
        let mut out = self.clone();
        for (name, binding) in &delta.0 {
            if let Some(old) = out.bindings.remove(name.as_ref()) {
                out.fingerprint ^= binding_digest(name, &old);
            }
            if let Some(binding) = binding {
                out.fingerprint ^= binding_digest(name, binding);
                out.bindings.insert(Arc::clone(name), Arc::clone(binding));
            }
        }
        out
    }
    /// The bindings (by content: definition and definition site) in which `self` differs from `base`, so that
    /// `base.apply(&delta)` holds the same bindings as `self`; `None` when more than `limit` differ.
    pub(super) fn delta_from(&self, base: &Self, limit: usize) -> Option<EnvDelta> {
        let mut out = Vec::new();
        for difference in base.bindings.diff(&self.bindings) {
            let entry = match difference {
                im::ordmap::DiffItem::Add(name, binding) => (Arc::clone(name), Some(Arc::clone(binding))),
                im::ordmap::DiffItem::Update { old, new } => {
                    if binding_digest(old.0, old.1) == binding_digest(new.0, new.1) {
                        continue;
                    }
                    (Arc::clone(new.0), Some(Arc::clone(new.1)))
                }
                im::ordmap::DiffItem::Remove(name, _) => (Arc::clone(name), None),
            };
            out.push(entry);
            if out.len() > limit {
                return None;
            }
        }
        out.sort_by(|a, b| a.0.cmp(&b.0));
        Some(EnvDelta(out))
    }
    /// Digest of every binding; equal digests and lengths mean equal environments (a 128-bit
    /// collision aside, which `DMB_FRONTEND_VERIFY` would expose by comparing against a full pass).
    pub fn fingerprint(&self) -> u128 {
        self.fingerprint
    }
    /// Whether both environments hold the same bindings, definitions and definition sites.
    pub fn same_bindings(&self, other: &Self) -> bool {
        self.shares_storage_with(other)
            || (self.len() == other.len() && self.fingerprint == other.fingerprint)
    }
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

    /// Visit current bindings absent by allocation identity from a previously
    /// visited snapshot. The public persistent-map diff skips shared nodes;
    /// removed bindings are already accounted through the previous snapshot.
    pub fn visit_storage_difference(
        &self,
        previous: &Self,
        mut visitor: impl FnMut(&Arc<str>, usize, usize, &Arc<Macro>, Option<&DefinitionOrigin>),
    ) {
        for difference in previous.bindings.diff(&self.bindings) {
            let (name, binding) = match difference {
                im::ordmap::DiffItem::Add(name, binding) => (name, binding),
                im::ordmap::DiffItem::Update { new, .. } => new,
                im::ordmap::DiffItem::Remove(_, _) => continue,
            };
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
        let binding = Arc::new(Binding {
            definition: Arc::new(definition),
            origin,
        });
        self.fingerprint ^= binding_digest(name, &binding);
        if let Some(old) = self.bindings.insert(Arc::from(name), binding) {
            self.fingerprint ^= binding_digest(name, &old);
        }
    }
    pub(super) fn remove(&mut self, name: &str) {
        if let Some(old) = self.bindings.remove(name) {
            self.fingerprint ^= binding_digest(name, &old);
        }
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
    fn storage_diff_visits_new_equal_content_allocations_and_ignores_removed_bindings() {
        let definition = || Macro {
            parameters: None,
            variadic: false,
            replacement: "same".into(),
        };
        let mut environment = MacroEnvironment::default();
        environment.insert("OLD", definition(), None);
        environment.insert("KEEP", definition(), None);
        let previous = environment.clone();
        let mut unchanged = 0;
        environment.visit_storage_difference(&previous, |_, _, _, _, _| unchanged += 1);
        assert_eq!(unchanged, 0);
        environment.insert("KEEP", definition(), None);
        environment.insert("NEW", definition(), None);
        environment.remove("OLD");
        let mut changed = Vec::new();
        environment.visit_storage_difference(&previous, |name, binding, _, definition, _| {
            changed.push((name.to_string(), binding, Arc::as_ptr(definition) as usize));
        });
        assert_eq!(
            changed
                .iter()
                .map(|entry| entry.0.as_str())
                .collect::<Vec<_>>(),
            vec!["KEEP", "NEW"]
        );
        previous.visit_storage(|name, binding, _, definition, _| {
            if name.as_ref() == "KEEP" {
                assert_ne!(changed[0].1, binding);
                assert_ne!(changed[0].2, Arc::as_ptr(definition) as usize);
            }
        });
        assert_eq!(previous.get("KEEP"), environment.get("KEEP"));
    }
    #[test]
    fn fingerprint_follows_bindings_not_history() {
        let definition = |text: &str| Macro {
            parameters: None,
            variadic: false,
            replacement: text.into(),
        };
        let origin = |line| DefinitionOrigin {
            path: Arc::new(std::path::PathBuf::from("a.dm")),
            source_span: dm_syntax::Span::new(0, 4),
            source_line: line,
        };
        let mut left = MacroEnvironment::default();
        let mut right = MacroEnvironment::default();
        left.insert("A", definition("1"), Some(origin(1)));
        left.insert("B", definition("2"), None);
        right.insert("B", definition("2"), None);
        right.insert("A", definition("9"), None);
        right.insert("A", definition("1"), Some(origin(1)));
        assert!(left.same_bindings(&right));
        assert_eq!(left.fingerprint(), right.fingerprint());
        right.insert("A", definition("1"), Some(origin(2)));
        assert!(!left.same_bindings(&right), "a moved definition site differs");
        right.insert("A", definition("1"), Some(origin(1)));
        right.insert("C", definition("3"), None);
        assert!(!left.same_bindings(&right));
        right.remove("C");
        assert!(left.same_bindings(&right));
        left.remove("A");
        left.remove("B");
        assert_eq!(left.fingerprint(), MacroEnvironment::default().fingerprint());
    }
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
