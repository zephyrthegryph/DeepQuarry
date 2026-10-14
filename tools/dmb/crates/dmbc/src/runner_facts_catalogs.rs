//! Stage-local catalog production on the host's shared observation store.
use super::*;
pub(super) const CONSTANTS_KEY: &[u8] = b"dmbc-native-host-constants-v1";
pub(super) const RUNTIME_KEY: &[u8] = b"dmbc-native-host-runtime-types-v1";
pub(super) struct Constants {
    pub catalog: ConstantCatalog,
    pub spellings: dm_ir::SymbolTable,
}
impl RetainedHostFacts {
    pub(super) fn catalogs(
        &self,
        current: &Current<'_>,
    ) -> Result<(ConstantCatalog, RuntimeAliasCatalog), String> {
        let constants = self.constants(current)?;
        self.runtime_after_constants(current, &constants)
    }
    pub(super) fn constants(&self, current: &Current<'_>) -> Result<Arc<Constants>, String> {
        let previous = self.values.lookup(CONSTANTS_KEY, current);
        let constants = match previous.as_deref() {
            Some(Artifact::Constants(constants)) => {
                self.constant_hits.fetch_add(1, Ordering::Relaxed);
                Arc::clone(constants)
            }
            _ => {
                let mut spellings = dm_ir::SymbolTable::default();
                let catalog = ConstantCatalog::native_516_1687(&mut spellings)
                    .map_err(|error| format!("engine constants: {error:?}"))?;
                let constants = Arc::new(Constants { catalog, spellings });
                self.insert_stage(
                    CONSTANTS_KEY,
                    current,
                    &[Query::Engine],
                    Artifact::Constants(Arc::clone(&constants)),
                );
                constants
            }
        };
        Ok(constants)
    }
    fn runtime_after_constants(
        &self,
        current: &Current<'_>,
        constants: &Constants,
    ) -> Result<(ConstantCatalog, RuntimeAliasCatalog), String> {
        let symbols = merge_current(current, constants)?;
        let previous = self.values.lookup(RUNTIME_KEY, current);
        if let Some(Artifact::Runtime(runtime)) = previous.as_deref() {
            self.runtime_hits.fetch_add(1, Ordering::Relaxed);
            return Ok((constants.catalog.clone(), runtime.clone()));
        }
        let runtime = RuntimeAliasCatalog::new(
            current.engine.snapshot.identity(),
            &symbols,
            Vec::new(),
            current.type_paths().as_ref().clone(),
            Completeness::Partial,
        )
        .map_err(|error| format!("runtime type catalog: {error:?}"))?;
        self.insert_stage(
            RUNTIME_KEY,
            current,
            &[Query::Engine, Query::TypePaths],
            Artifact::Runtime(runtime.clone()),
        );
        Ok((constants.catalog.clone(), runtime))
    }
    pub(super) fn admit_constant_spellings(&self, current: &Current<'_>) -> Result<(), String> {
        let constants = self.constants(current)?;
        merge_current(current, &constants)?;
        Ok(())
    }
    pub(super) fn retain_catalog_stages(&self) {
        let mut keys = Vec::new();
        self.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { key, .. } = view {
                if key.as_ref() != KEY {
                    keys.push(Arc::clone(key));
                }
            }
        });
        self.values
            .retain_current_keys(keys.iter().map(|key| key.as_ref()));
    }
}

fn merge_current(
    current: &Current<'_>,
    constants: &Constants,
) -> Result<dm_ir::SymbolTable, String> {
    // Every current symbol namespace still performs complete collision admission.
    let mut symbols = dm_ir::SymbolTable::overlay(current.frontend.snapshot.tree.shared_symbols());
    symbols
        .merge_from(&constants.spellings)
        .map_err(|error| format!("engine constants: {:?}", HostError::Symbol(error)))?;
    Ok(symbols)
}
