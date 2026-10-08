//! Uncached production admission and publication adapter.
//! All semantic inputs are captured before this boundary; no fallback compiler
//! is invoked when admission fails.
use crate::{cold, driver_facts, engine::EngineSnapshot, lowering::LoweringConfig};
use dm_ir::Resolver;
use dm_tree::frontend::ColdFrontend;

/// Hold this handle through capture, compilation and installation. Independent
/// worktrees have distinct locks; two processes targeting one manifest serialize.
pub fn acquire_build_lock(project: &std::path::Path) -> std::io::Result<std::fs::File> {
    use fs2::FileExt;
    let directory = project
        .parent()
        .ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, "manifest has no parent")
        })?
        .join(".dmbc");
    std::fs::create_dir_all(&directory)?;
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(directory.join("build.lock"))?;
    file.lock_exclusive()?;
    Ok(file)
}

/// Resolve source scalar constants once, using the same backend spelling rules
/// used by executable lowering. The returned overlay retains dependency edges.
pub fn scalars(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    predefined: &dyn Resolver,
    predefined_identity: u128,
) -> dm_tree::constant_resolution::ScalarSnapshot {
    use dm_tree::constant_resolution::{ScalarBackend, ScalarQuery};
    let tree = &frontend.snapshot.tree;
    let mut requests = tree
        .members()
        .iter()
        .filter(|member| member.kind == dm_tree::MemberKind::Var && member.metadata.flags & 2 != 0)
        .map(|member| ScalarQuery::Const {
            owner: tree
                .type_node(member.owner)
                .expect("member belongs to captured tree")
                .path,
            name: member.name,
        })
        .collect::<Vec<_>>();
    for name in ["turf", "area", "maxx", "maxy", "maxz"] {
        requests.push(ScalarQuery::EffectiveDefault {
            owner: dm_ir::SymbolId::of("/world"),
            name: dm_ir::SymbolId::of(name),
        });
    }
    let decode = |raw: &str| {
        dm_codegen_byond::decode_constant_string_literal(raw)
            .ok()
            .flatten()
    };
    let nameof = |expression: &dm_syntax::Expr| {
        dm_codegen_byond::nameof_reference(expression).map(str::to_owned)
    };
    let mut identity = b"native-scalar-policy-v1:byond-string-decoder:nameof-reference".to_vec();
    identity.extend_from_slice(&engine.identity().to_le_bytes());
    identity.extend_from_slice(&predefined_identity.to_le_bytes());
    let calls = crate::pure_calls::PinnedPureCalls::new(engine).ok();
    dm_tree::constant_resolution::resolve_with_predefined_and_calls(
        &frontend.snapshot,
        &requests,
        &ScalarBackend {
            identity: xxhash_rust::xxh3::xxh3_128(&identity),
            decode_string: &decode,
            nameof: &nameof,
        },
        Some(predefined),
        calls
            .as_ref()
            .map(|calls| calls as &dyn dm_tree::constants::PureCalls),
    )
}

pub fn map_defaults(
    scalars: &dm_tree::constant_resolution::ScalarSnapshot,
) -> Result<Vec<crate::world_projection::Directive>, String> {
    use dm_tree::constant_resolution::{ScalarOutcome, ScalarQuery};
    let tree = &scalars.source.tree;
    let mut values = Vec::new();
    for name in ["turf", "area", "maxx", "maxy", "maxz"] {
        let owner = dm_ir::SymbolId::of("/world");
        let symbol = dm_ir::SymbolId::of(name);
        let member = tree
            .lookup_type(owner)
            .and_then(|owner| tree.resolve(owner, symbol, dm_tree::MemberKind::Var))
            .and_then(|member| tree.member(member));
        // Captured engine defaults are handled by the map driver. Only authored
        // values replace them; unsupported authored expressions must fail.
        let authored = scalars
            .source
            .occurrences
            .source_order()
            .iter()
            .any(|occurrence| {
                let dm_tree::Target::Member(id) = occurrence.target else {
                    return false;
                };
                tree.member(id).is_some_and(|member| {
                    member.name == symbol
                        && tree
                            .type_node(member.owner)
                            .is_some_and(|node| node.path == owner)
                })
            });
        if !authored {
            continue;
        }
        if member.is_none_or(|member| member.metadata.initializer.is_none()) {
            return Err(format!(
                "world.{name} authored default has no certified effective initializer"
            ));
        }
        match scalars.outcome(ScalarQuery::EffectiveDefault {
            owner,
            name: symbol,
        }) {
            Some(ScalarOutcome::Value(value)) => values.push((name, value)),
            other => return Err(format!("world.{name} map default is unresolved: {other:?}")),
        }
    }
    crate::world_projection::project(values).map_err(|error| format!("map defaults: {error:?}"))
}

/// The driver always prepares ABI facts through the pinned coverage policy.
/// A failed preparation never publishes a partial executable.
#[allow(clippy::too_many_arguments)]
pub fn compile<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    engine: &EngineSnapshot,
    engine_bytes: &[u8],
    links: crate::engine_link::EngineLinkFacts,
    values: &dyn crate::class_projection::TypeValuePolicy,
    resource_context: Option<u128>,
    maps: Vec<crate::initialization_artifact::InitializationArtifact>,
    stage: Option<&dyn crate::composition::NonTextOutputStage>,
    workers: usize,
) -> Result<cold::ColdOutput, cold::ColdError> {
    compile_observed(
        frontend,
        resolver,
        engine,
        engine_bytes,
        links,
        values,
        resource_context,
        maps,
        stage,
        workers,
        None,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn compile_observed<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    engine: &EngineSnapshot,
    engine_bytes: &[u8],
    links: crate::engine_link::EngineLinkFacts,
    values: &dyn crate::class_projection::TypeValuePolicy,
    resource_context: Option<u128>,
    maps: Vec<crate::initialization_artifact::InitializationArtifact>,
    stage: Option<&dyn crate::composition::NonTextOutputStage>,
    workers: usize,
    observer: Option<&cold::ColdObserver<'_>>,
) -> Result<cold::ColdOutput, cold::ColdError> {
    compile_observed_with_memo(
        frontend,
        resolver,
        engine,
        engine_bytes,
        links,
        values,
        resource_context,
        maps,
        stage,
        workers,
        observer,
        None,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn compile_observed_with_memo<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    engine: &EngineSnapshot,
    engine_bytes: &[u8],
    links: crate::engine_link::EngineLinkFacts,
    values: &dyn crate::class_projection::TypeValuePolicy,
    resource_context: Option<u128>,
    maps: Vec<crate::initialization_artifact::InitializationArtifact>,
    stage: Option<&dyn crate::composition::NonTextOutputStage>,
    workers: usize,
    observer: Option<&cold::ColdObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> Result<cold::ColdOutput, cold::ColdError> {
    compile_observed_input(
        frontend,
        resolver,
        engine,
        engine_bytes,
        links,
        values,
        resource_context,
        maps,
        stage,
        workers,
        observer,
        memo,
        None,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn compile_revision_observed_with_memo<R: Resolver>(
    frontend: &dm_tree::frontend::FrontendRevision,
    resolver: &R,
    engine: &EngineSnapshot,
    engine_bytes: &[u8],
    links: crate::engine_link::EngineLinkFacts,
    values: &dyn crate::class_projection::TypeValuePolicy,
    resource_context: Option<u128>,
    maps: Vec<crate::initialization_artifact::InitializationArtifact>,
    stage: Option<&dyn crate::composition::NonTextOutputStage>,
    workers: usize,
    observer: Option<&cold::ColdObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> Result<cold::ColdOutput, cold::ColdError> {
    compile_observed_input(
        frontend,
        resolver,
        engine,
        engine_bytes,
        links,
        values,
        resource_context,
        maps,
        stage,
        workers,
        observer,
        memo,
        Some(frontend),
    )
}

#[allow(clippy::too_many_arguments)]
fn compile_observed_input<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    engine: &EngineSnapshot,
    engine_bytes: &[u8],
    links: crate::engine_link::EngineLinkFacts,
    values: &dyn crate::class_projection::TypeValuePolicy,
    resource_context: Option<u128>,
    maps: Vec<crate::initialization_artifact::InitializationArtifact>,
    stage: Option<&dyn crate::composition::NonTextOutputStage>,
    workers: usize,
    observer: Option<&cold::ColdObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    revision: Option<&dm_tree::frontend::FrontendRevision>,
) -> Result<cold::ColdOutput, cold::ColdError> {
    let order = crate::type_creation_order::collect(
        &frontend.allocation_ledger,
        &frontend.expanded.text,
        frontend.snapshot.tree.symbols(),
        &links.inventory,
    )
    .map_err(cold::ColdError::Initializer)?;
    let calls =
        crate::pure_calls::PinnedPureCalls::new(engine).map_err(cold::ColdError::Initializer)?;
    let evaluator = driver_facts::DriverEvaluator {
        pure_calls: Some(&calls),
        resolver,
        symbols: frontend.snapshot.tree.symbols(),
        resource_search_context: resource_context,
    };
    cold::compile_captured_classified_with_pinned_abi_memo_revision(
        frontend,
        resolver,
        cold::CapturedLinkInputs {
            engine_bytes,
            engine,
            references: &links.references,
            inventory: links.inventory,
        },
        cold::CapturedDeclarationInputs {
            initializers: &evaluator,
            type_values: values,
            resource_search_context: resource_context,
            source_type_order: &order,
        },
        LoweringConfig {
            workers,
            ..Default::default()
        },
        maps,
        stage,
        observer,
        memo,
        revision,
    )
}
