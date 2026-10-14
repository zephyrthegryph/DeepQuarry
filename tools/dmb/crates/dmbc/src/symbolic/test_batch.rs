//! Fixture adapter: rich inputs enter the actual current contribution producer.
use super::*;
use crate::lowering::LoweringBatch;

pub(crate) fn link_test_batch(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
) -> Result<FrozenBatch, IntegrationError> {
    link_test_artifacts(batch, symbols, external, inventory, Vec::new())
}

pub(crate) fn link_test_artifacts(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
) -> Result<FrozenBatch, IntegrationError> {
    link_test_artifacts_with_workers(batch, symbols, external, inventory, initialization, 1)
}

pub(crate) fn link_test_artifacts_with_workers(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
    workers: usize,
) -> Result<FrozenBatch, IntegrationError> {
    if !batch.diagnostics.is_empty() {
        return Err(IntegrationError::LoweringFailed(batch.diagnostics.len()));
    }
    batch
        .identity_index()
        .map_err(IntegrationError::DuplicateUnit)?;
    let mut bindings = std::collections::BTreeSet::new();
    for entry in inventory.entry_iter() {
        if let Key::Type(id) = entry.key {
            let path = symbols
                .text(id)
                .ok_or(IntegrationError::MissingSpelling(id))?;
            if SymbolId::of(path) != id {
                return Err(IntegrationError::MissingSpelling(id));
            }
            bindings.insert(SymRef::Type(id));
        }
    }
    for unit in batch.units.iter().filter(|unit| unit.effective) {
        for symbol in [unit.identity.owner, unit.identity.name] {
            symbols
                .text(symbol)
                .ok_or(IntegrationError::MissingSpelling(symbol))?;
        }
        if !bindings.insert(unit_reference(unit.identity)) {
            return Err(IntegrationError::DuplicateUnit(unit.identity));
        }
    }
    let contributions = batch
        .units
        .into_iter()
        .map(|unit| prepare_contribution(unit, symbols, &bindings, external, false))
        .collect::<Result<Vec<_>, _>>()?;
    let executor = dm_exec::BuildExecutor::new(workers)
        .map_err(|error| IntegrationError::InvalidInitializer(format!("executor: {error}")))?;
    link_prepared_artifact_tables_on_executor(
        contributions,
        symbols,
        external,
        inventory,
        initialization,
        &executor,
    )
}
