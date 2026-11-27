//! Exact current symbol catalog authority, separate from source/body issuance.
use dm_ir::SymbolTable;
use std::sync::Arc;
#[derive(Debug)]
pub(crate) struct SymbolCatalog {
    pub(crate) symbols: Arc<SymbolTable>,
    source: Arc<SymbolTable>,
    pub(super) engine: Option<SymbolTable>,
}
impl SymbolCatalog {
    pub(super) fn capture(
        previous: Option<&Arc<Self>>,
        source: Arc<SymbolTable>,
        engine: Option<&SymbolTable>,
    ) -> Result<Arc<Self>, dm_ir::SymbolCollision> {
        if let Some(previous) = previous {
            let same_engine = match (&previous.engine, engine) {
                (None, None) => true,
                (Some(old), Some(current)) => old.ordered() == current.ordered(),
                _ => false,
            };
            if Arc::ptr_eq(&previous.source, &source) && same_engine {
                return Ok(Arc::clone(previous));
            }
        }
        let mut symbols = engine.cloned().unwrap_or_default();
        symbols.merge_from(&source)?;
        Ok(Arc::new(Self {
            symbols: Arc::new(symbols),
            source,
            engine: engine.cloned(),
        }))
    }
    /// `capture` after a known change of the source table: `previous` was captured from `before`, and `source` is `before`
    /// with the spellings `gone` removed and `new` added. The catalog is the previous one with those applied (no merge of
    /// every spelling again); the same table `capture` builds. `None` when the change does not apply (another source, another
    /// engine, a collision): the caller captures in full, which reports a collision exactly.
    pub(super) fn capture_changed(
        previous: &Arc<Self>,
        before: &Arc<SymbolTable>,
        source: Arc<SymbolTable>,
        engine: Option<&SymbolTable>,
        gone: &[dm_ir::SymbolId],
        new: &[dm_ir::SymbolId],
    ) -> Option<Arc<Self>> {
        if !Arc::ptr_eq(&previous.source, before) {
            return None;
        }
        let same_engine = match (&previous.engine, engine) {
            (None, None) => true,
            (Some(old), Some(current)) => old.ordered() == current.ordered(),
            _ => false,
        };
        if !same_engine {
            return None;
        }
        // Only added spellings: a layer over the previous catalog (no copy of every spelling); a removal needs one flat table.
        let mut symbols = if gone.is_empty()
            && previous.symbols.overlay_depth() < super::declaration_state::MAX_SPELLING_LAYERS
        {
            SymbolTable::overlay(Arc::clone(&previous.symbols))
        } else {
            previous.symbols.flattened()
        };
        for &id in gone {
            // A spelling the engine also has stays (the catalog is the engine's spellings and the source's).
            if engine.is_none_or(|engine| engine.text(id).is_none()) {
                symbols.remove_local(id);
            }
        }
        for &id in new {
            symbols.insert_shared(id, source.shared_text(id)?).ok()?;
        }
        Some(Arc::new(Self {
            symbols: Arc::new(symbols),
            source,
            engine: previous.engine.clone(),
        }))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_source_owner_reuses_catalog_but_changed_engine_spelling_falls_back() {
        let mut source = SymbolTable::default();
        source.intern("source").unwrap();
        let source = Arc::new(source);
        let first = SymbolCatalog::capture(None, source.clone(), None).unwrap();
        let same = SymbolCatalog::capture(Some(&first), source.clone(), None).unwrap();
        assert!(Arc::ptr_eq(&first, &same));
        let mut engine = SymbolTable::default();
        engine.intern("engine").unwrap();
        let changed = SymbolCatalog::capture(Some(&first), source, Some(&engine)).unwrap();
        assert!(!Arc::ptr_eq(&first, &changed));
        assert!(changed
            .symbols
            .text(dm_ir::SymbolId::of("engine"))
            .is_some());
        assert!(changed
            .symbols
            .text(dm_ir::SymbolId::of("source"))
            .is_some());
    }
}
