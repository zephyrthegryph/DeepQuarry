//! Content-derived symbols shared across independent compiler processes.
//!
//! These are semantic names, never BYOND table indexes. The linker assigns wire
//! indexes separately. Hash collisions are errors and leave the table unchanged.

use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
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
}

impl SymbolTable {
    pub fn intern(&mut self, text: &str) -> Result<SymbolId, SymbolCollision> {
        self.insert(SymbolId::of(text), text)
    }

    fn insert(&mut self, id: SymbolId, text: &str) -> Result<SymbolId, SymbolCollision> {
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
        self.texts.get(&id).map(AsRef::as_ref)
    }

    pub fn len(&self) -> usize {
        self.texts.len()
    }

    pub fn is_empty(&self) -> bool {
        self.texts.is_empty()
    }

    /// Deterministic traversal for export and self-contained cache segments.
    pub fn ordered(&self) -> Vec<(SymbolId, &str)> {
        let mut symbols: Vec<_> = self
            .texts
            .iter()
            .map(|(&id, text)| (id, text.as_ref()))
            .collect();
        symbols.sort_unstable_by_key(|&(id, _)| id);
        symbols
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
