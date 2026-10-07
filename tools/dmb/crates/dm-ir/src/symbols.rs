//! Content-derived symbols shared across independent compiler processes.
//!
//! These are semantic names, never BYOND table indexes. The linker assigns wire
//! indexes separately. Hash collisions are errors and leave the table unchanged.

use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize)]
pub struct SymbolId(u64);

impl SymbolId {
    pub fn of(text: &str) -> Self {
        Self::of_bytes(text.as_bytes())
    }

    /// Runtime string payloads can contain non-UTF-8 BYOND formatting bytes.
    /// Their identity uses exact bytes, never a lossy Unicode conversion.
    pub fn of_bytes(bytes: &[u8]) -> Self {
        Self(xxhash_rust::xxh3::xxh3_64(bytes))
    }

    pub const fn bits(self) -> u64 {
        self.0
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SymbolCollision {
    pub id: SymbolId,
    pub existing: Arc<str>,
    pub incoming: Arc<str>,
}

impl fmt::Display for SymbolCollision {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "symbol hash collision {:016x}: {:?} and {:?}",
            self.id.bits(),
            self.existing,
            self.incoming
        )
    }
}

impl std::error::Error for SymbolCollision {}

#[derive(Clone, Debug, Default)]
pub struct SymbolTable {
    texts: HashMap<SymbolId, Arc<str>>,
    parent: Option<Arc<SymbolTable>>,
}

impl SymbolTable {
    /// Immutable spelling backing plus a small collision-checked local delta.
    pub fn overlay(parent: Arc<SymbolTable>) -> Self {
        Self {
            texts: HashMap::new(),
            parent: Some(parent),
        }
    }
    /// Accept only this dictionary or an overlay issued over this exact immutable
    /// backing. Overlay insertion rejects collisions with every ancestor, so
    /// added spellings cannot alter an existing source meaning.
    pub fn is_extension_of(&self, source: &SymbolTable) -> bool {
        std::ptr::eq(self, source)
            || self
                .parent
                .as_ref()
                .is_some_and(|parent| parent.is_extension_of(source))
    }
    pub fn intern(&mut self, text: &str) -> Result<SymbolId, SymbolCollision> {
        self.insert(SymbolId::of(text), text)
    }

    fn insert(&mut self, id: SymbolId, text: &str) -> Result<SymbolId, SymbolCollision> {
        if let Some(existing) = self.parent.as_ref().and_then(|parent| parent.text(id)) {
            if existing != text {
                return Err(SymbolCollision {
                    id,
                    existing: Arc::from(existing),
                    incoming: Arc::from(text),
                });
            }
            return Ok(id);
        }
        match self.texts.entry(id) {
            std::collections::hash_map::Entry::Occupied(entry) => {
                if entry.get().as_ref() != text {
                    return Err(SymbolCollision {
                        id,
                        existing: Arc::clone(entry.get()),
                        incoming: Arc::from(text),
                    });
                }
            }
            std::collections::hash_map::Entry::Vacant(entry) => {
                entry.insert(Arc::from(text));
            }
        }
        Ok(id)
    }

    pub fn text(&self, id: SymbolId) -> Option<&str> {
        self.texts
            .get(&id)
            .map(AsRef::as_ref)
            .or_else(|| self.parent.as_ref().and_then(|parent| parent.text(id)))
    }

    pub fn len(&self) -> usize {
        self.texts.len() + self.parent.as_ref().map_or(0, |parent| parent.len())
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Deterministic traversal for export and self-contained cache segments.
    pub fn ordered(&self) -> Vec<(SymbolId, &str)> {
        let mut symbols: Vec<_> = self
            .texts
            .iter()
            .map(|(&id, text)| (id, text.as_ref()))
            .collect();
        if let Some(parent) = &self.parent {
            symbols.extend(parent.ordered());
        }
        symbols.sort_unstable_by_key(|&(id, _)| id);
        symbols
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlay_shares_backing_and_rejects_parent_collisions() {
        let mut base = SymbolTable::default();
        let a = base.intern("a").unwrap();
        let base = Arc::new(base);
        let mut local = SymbolTable::overlay(Arc::clone(&base));
        assert_eq!(local.intern("a").unwrap(), a);
        local.intern("b").unwrap();
        assert_eq!(base.len(), 1);
        assert_eq!(local.len(), 2);
        assert_eq!(local.text(a), Some("a"));
        assert!(local.is_extension_of(&base));
        assert!(!SymbolTable::default().is_extension_of(&base));
        assert!(local.insert(a, "different").is_err());
        assert_eq!(local.text(a), Some("a"));
        assert!(local.is_extension_of(&base));
        assert!(!SymbolTable::default().is_extension_of(&base));
        assert_eq!(local.ordered().len(), 2);
    }
    #[test]
    fn insertion_order_does_not_change_ids_or_export() {
        let mut first = SymbolTable::default();
        let mut second = SymbolTable::default();
        for text in ["/datum/example", "name", "", "é"] {
            first.intern(text).unwrap();
        }
        for text in ["é", "", "name", "/datum/example"] {
            second.intern(text).unwrap();
        }
        assert_eq!(first.ordered(), second.ordered());
        assert_eq!(first.text(SymbolId::of("é")), Some("é"));
        assert_eq!(first.len(), 4);
        first.intern("name").unwrap();
        assert_eq!(first.len(), 4);
    }

    #[test]
    fn collision_preserves_original_text() {
        let mut table = SymbolTable::default();
        let id = table.intern("original").unwrap();
        let error = table.insert(id, "different").unwrap_err();
        assert_eq!(error.existing.as_ref(), "original");
        assert_eq!(error.incoming.as_ref(), "different");
        assert_eq!(table.text(id), Some("original"));
        assert_eq!(table.len(), 1);
    }
}
