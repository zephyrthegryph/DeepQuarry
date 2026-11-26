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
