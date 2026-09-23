//! A small string/key interner (`rust_core.md` §4–5): registries hand out
//! numeric IDs once at boot so no strings cross on hot paths.

use std::collections::HashMap;
use std::sync::Arc;

/// An interned key. IDs are dense, starting at 0, in first-seen order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Symbol(u32);

impl Symbol {
    #[must_use]
    pub const fn id(self) -> u32 {
        self.0
    }
}

#[derive(Clone, Debug, Default)]
pub struct Interner {
    ids: HashMap<Arc<str>, Symbol>,
    names: Vec<Arc<str>>,
}

impl Interner {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// The symbol for `key`, assigning the next ID if it is new.
    ///
    /// # Panics
    /// If more than `u32::MAX` keys are interned.
    pub fn intern(&mut self, key: &str) -> Symbol {
        if let Some(&symbol) = self.ids.get(key) {
            return symbol;
        }
        let symbol = Symbol(u32::try_from(self.names.len()).expect("interner overflow"));
        let name: Arc<str> = Arc::from(key);
        self.names.push(Arc::clone(&name));
        self.ids.insert(name, symbol);
        symbol
    }

    /// The symbol for `key` without inserting.
    #[must_use]
    pub fn get(&self, key: &str) -> Option<Symbol> {
        self.ids.get(key).copied()
    }

    /// The key for a symbol issued by this interner.
    #[must_use]
    pub fn resolve(&self, symbol: Symbol) -> Option<&str> {
        self.names.get(symbol.0 as usize).map(AsRef::as_ref)
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.names.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.names.is_empty()
    }

    /// All keys in ID order.
    pub fn iter(&self) -> impl Iterator<Item = (Symbol, &str)> {
        self.names.iter().enumerate().map(|(i, name)| {
            (
                Symbol(u32::try_from(i).expect("checked on intern")),
                &**name,
            )
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn round_trips_and_dedupes(keys in prop::collection::vec("[a-z_/]{0,12}", 0..200)) {
            let mut interner = Interner::new();
            let symbols: Vec<_> = keys.iter().map(|k| interner.intern(k)).collect();
            for (key, symbol) in keys.iter().zip(&symbols) {
                prop_assert_eq!(interner.resolve(*symbol), Some(key.as_str()));
                prop_assert_eq!(interner.get(key), Some(*symbol));
                prop_assert_eq!(interner.intern(key), *symbol);
            }
            let distinct: std::collections::HashSet<_> = keys.iter().collect();
            prop_assert_eq!(interner.len(), distinct.len());
            for (i, (symbol, _)) in interner.iter().enumerate() {
                prop_assert_eq!(symbol.id() as usize, i);
            }
        }
    }
}
