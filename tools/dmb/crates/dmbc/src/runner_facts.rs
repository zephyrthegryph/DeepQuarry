//! Common pinned host preparation for compilation and selected-reference queries.
use crate::{compile_driver, engine::EngineSnapshot, engine_host::*};
use dm_tree::{constant_resolution::ScalarSnapshot, frontend::ColdFrontend};
use std::sync::Arc;

pub(crate) type PreparedHost = (EngineResolverHost<ScalarSnapshot>, Arc<ScalarSnapshot>);
#[cfg(test)]
#[path = "analysis_export_resolved_tests.rs"]
mod resolved_tests;
pub(super) fn prepare(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
) -> Result<PreparedHost, String> {
    let prepared = prepare_components(frontend, engine)?;
    let host = EngineResolverHost::new(
        Arc::clone(&prepared.scalar),
        prepared.constants,
        prepared.runtime,
    )
    .with_pinned_facts(engine, frontend, prepared.pinned)?;
    Ok((host, prepared.scalar))
}
struct Components {
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
    pinned: Arc<PinnedHostFacts>,
    source: EngineResolverHost<dm_tree::SemanticTree>,
    scalar: Arc<ScalarSnapshot>,
}
fn prepare_components(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
) -> Result<Components, String> {
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
    prepare_from_catalogs(frontend, engine, constants, runtime)
}
fn prepare_from_catalogs(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
) -> Result<Components, String> {
    prepare_from_catalogs_with_artifacts(frontend, engine, constants, runtime, None, None)
}
fn prepare_from_catalogs_with_artifacts(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    constants: ConstantCatalog,
    runtime: RuntimeAliasCatalog,
    artifacts: Option<&dyn dm_tree::constant_resolution::ScalarArtifacts>,
    providers: Option<&crate::engine_host::PinnedEngineProviders>,
) -> Result<Components, String> {
    let pinned = if let Some(providers) = providers {
        PinnedHostFacts::capture_with_providers(engine, frontend, &constants, &runtime, providers)?
    } else {
        PinnedHostFacts::capture(engine, frontend, &constants, &runtime)?
    };
    let source = EngineResolverHost::new(
        frontend.snapshot.tree.clone(),
        constants.clone(),
        runtime.clone(),
    )
    .with_pinned_facts(engine, frontend, Arc::clone(&pinned))?;
    let scalar = Arc::new(compile_driver::scalars_with_artifacts(
        frontend,
        engine,
        &source,
        source.configuration_identity(),
        artifacts,
    ));
    Ok(Components {
        constants,
        runtime,
        pinned,
        source,
        scalar,
    })
}

#[path = "runner_facts_retained.rs"]
mod retained;
pub(crate) use retained::RetainedHostFacts;
pub(crate) fn prepare_retained(
    frontend: &ColdFrontend,
    engine: &Arc<crate::runner_host::RetainedEngine>,
    retained: Option<&RetainedHostFacts>,
) -> Result<PreparedHost, String> {
    match retained {
        Some(retained) => retained.prepare(frontend, engine),
        None => prepare(frontend, &engine.snapshot),
    }
}
