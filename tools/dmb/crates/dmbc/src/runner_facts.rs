//! Common pinned host preparation for compilation and selected-reference queries.
use crate::{compile_driver, engine::EngineSnapshot, engine_host::*};
use dm_tree::{constant_resolution::ScalarSnapshot, frontend::ColdFrontend};
use std::sync::Arc;

type PreparedHost = (EngineResolverHost<ScalarSnapshot>, Arc<ScalarSnapshot>);
#[cfg(test)]
#[path = "analysis_export_resolved_tests.rs"]
mod resolved_tests;
pub(super) fn prepare(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
) -> Result<PreparedHost, String> {
    let mut symbols = dm_ir::SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
    let constants = ConstantCatalog::native_516_1687(&mut symbols)
        .map_err(|error| format!("engine constants: {error:?}"))?;
    let ordinary = frontend
        .snapshot
        .tree
        .types()
        .iter()
        .map(|node| node.path)
        .collect();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        ordinary,
        Completeness::Partial,
    )
    .map_err(|error| format!("runtime type catalog: {error:?}"))?;
    let pinned = PinnedHostFacts::capture(engine, frontend, &constants, &runtime)?;
    let source = EngineResolverHost::new(
        frontend.snapshot.tree.clone(),
        constants.clone(),
        runtime.clone(),
    )
    .with_pinned_facts(engine, frontend, Arc::clone(&pinned))?;
    let scalar = Arc::new(compile_driver::scalars(
        frontend,
        engine,
        &source,
        source.configuration_identity(),
    ));
    let host = EngineResolverHost::new(Arc::clone(&scalar), constants, runtime)
        .with_pinned_facts(engine, frontend, pinned)?;
    Ok((host, scalar))
}
