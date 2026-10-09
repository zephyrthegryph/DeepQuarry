//! One uncached orchestration path over captured semantic inputs.
//! Admission is deliberately bounded by the production composer. A successful
//! return means every declaration was admitted, rather than a partial artifact.
use crate::{
    composition::{validate_global_program, CompositionError},
    lowering::{AbiPolicy, LoweringConfig, LoweringDiagnostic},
    symbolic::{IntegrationError, ReferenceBindings},
};
use dm_ir::Resolver;
use dm_link::LinkInventory;
use dm_tree::frontend::ColdFrontend;
use std::time::{Duration, Instant};
mod initializer_factory;

#[derive(Clone, Copy, Debug)]
pub enum ColdStage {
    StartupCapture,
    AbiPreparation,
    Initializers,
    InitializerClassification,
    InitializerCodegen,
    ProcedureLowering,
    RequiredTypeAdmission,
    SymbolicLinking,
    Composition,
}
pub type ColdMeasurement = crate::stage_measurements::Measurement<ColdStage>;
impl crate::stage_measurements::StageName for ColdStage {
    fn profile_name(self) -> &'static str {
        match self {
            Self::StartupCapture => "cold.startup_capture",
            Self::AbiPreparation => "cold.abi_preparation",
            Self::Initializers => "cold.initializers",
            Self::InitializerClassification => "initializer.classification",
            Self::InitializerCodegen => "initializer.codegen",
            Self::ProcedureLowering => "cold.procedure_lowering",
            Self::RequiredTypeAdmission => "cold.required_type_admission",
            Self::SymbolicLinking => "cold.symbolic_linking",
            Self::Composition => "cold.composition",
        }
    }
}
pub type ColdObserver<'a> = crate::stage_measurements::Observer<'a, ColdStage>;
type StageMeasurement<'a> = crate::stage_measurements::Scope<'a, ColdStage>;

#[derive(Clone, Copy, Debug, Default)]
pub struct ColdTimings {
    pub abi_preparation: Duration,
    pub lowering: Duration,
    pub initializers: Duration,
    pub symbolic_linking: Duration,
    pub composition: Duration,
    pub total: Duration,
}

pub struct ColdOutput {
    pub dmb: byond_dmb::dmb::EncodedDmb,
    pub timings: ColdTimings,
    /// Owned exact startup stage output, available to resident hosts. The global
    /// fixture path has no captured declaration/static startup stage.
    pub startup: Option<std::sync::Arc<crate::startup::StartupFacts>>,
}
#[derive(Debug)]
pub enum ColdError {
    EngineMismatch,
    AbiPreparation(String),
    Lowering(Vec<LoweringDiagnostic>),
    NonAuthoritativeAbi,
    Linking(IntegrationError),
    Composition(CompositionError),
    Initializer(String),
    InitializerInvariant(String),
    Projection(crate::class_projection::ProjectionError),
}
fn initializer_lowering_error(
    error: crate::initializer_diagnostics::InitializerLoweringError,
) -> ColdError {
    use crate::initializer_diagnostics::InitializerLoweringError as E;
    match error {
        E::Diagnostics(diagnostics) => ColdError::Lowering(diagnostics),
        E::Invariant(message) => ColdError::InitializerInvariant(message),
        E::Unsupported(message) => ColdError::Initializer(message),
    }
}
/// Captured declaration/initializer policy for the production class path.
/// Link inventory remains explicit; no observable table order is guessed here.
pub struct CapturedDeclarationInputs<'a> {
    pub initializers: &'a dyn crate::initializer_policy::CapturedInitializerEvaluator,
    pub type_values: &'a dyn crate::class_projection::TypeValuePolicy,
    pub resource_search_context: Option<u128>,
    /// Complete observable order of fresh source types; excludes retained,
    /// root and world entries. Discovery must capture this order explicitly.
    pub source_type_order: &'a [dm_ir::SymbolId],
}
pub struct CapturedLinkInputs<'a> {
    /// Same pinned bytes used to seed the declaration model.
    pub engine_bytes: &'a [u8],
    pub engine: &'a crate::engine::EngineSnapshot,
    pub references: &'a ReferenceBindings,
    pub inventory: LinkInventory,
}
/// The caller captures source/resources and engine facts before this function.
/// No filesystem, durable item store or historical mutable bindings are read.
/// Resource encoding/publication are subsequent stages and excluded from these
/// timings; these are not end-to-end compiler benchmark figures.
pub fn compile_captured_program<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    resolver: &R,
    policy: &P,
    links: CapturedLinkInputs<'_>,
    config: LoweringConfig,
) -> Result<ColdOutput, ColdError> {
    let total = Instant::now();
    let executor = dm_exec::BuildExecutor::new(config.workers)
        .map_err(|error| ColdError::AbiPreparation(error.to_string()))?;
    let captured = frontend.engine.as_ref().ok_or(ColdError::EngineMismatch)?;
    if captured.identity != links.engine.identity() {
        return Err(ColdError::EngineMismatch);
    }
    if !links
        .engine
        .matches_template(links.engine_bytes, links.engine.interpretation_schema())
    {
        return Err(ColdError::EngineMismatch);
    }
    validate_global_program(frontend).map_err(ColdError::Composition)?;
    let stage = Instant::now();
    let batch =
        crate::lowering::lower_frontend_on_executor(frontend, resolver, policy, config, &executor);
    let lowering = stage.elapsed();
    if !batch.diagnostics.is_empty() {
        return Err(ColdError::Lowering(batch.diagnostics));
    }
    if batch.units.iter().any(|unit| unit.abi.is_none()) {
        return Err(ColdError::NonAuthoritativeAbi);
    }
    let stage = Instant::now();
    let frozen = crate::symbolic::freeze_artifact_tables_with_executor(
        batch,
        frontend.snapshot.tree.symbols(),
        links.references,
        links.inventory,
        Vec::new(),
        &executor,
    )
    .map_err(ColdError::Linking)?;
    let symbolic_linking = stage.elapsed();
    let stage = Instant::now();
    let dmb =
        crate::composition::compose_global_program_encoded(links.engine_bytes, &frozen, frontend)
            .map_err(ColdError::Composition)?;
    Ok(ColdOutput {
        dmb,
        startup: None,
        timings: ColdTimings {
            abi_preparation: Duration::ZERO,
            lowering,
            initializers: Duration::ZERO,
            symbolic_linking,
            composition: stage.elapsed(),
            total: total.elapsed(),
        },
    })
}

/// One captured cold path for declarations, ordinary/helper procedures and
/// classified initializer artifacts. The same shared freezer/writer publishes
/// their exact table assignment together; unsupported facts fail the whole run.
pub fn compile_captured_classified_program<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    resolver: &R,
    policy: &P,
    links: CapturedLinkInputs<'_>,
    declarations: CapturedDeclarationInputs<'_>,
    config: LoweringConfig,
) -> Result<ColdOutput, ColdError> {
    compile_captured_classified_with_stage(
        frontend,
        resolver,
        policy,
        links,
        declarations,
        config,
        Vec::new(),
        None,
    )
}

/// Production pinned ABI preparation and cold output in one coherent path.
/// Policy preparation consumes the captured resolver; no project maps or
/// mutable output tables are fabricated to decide inherited procedure ABI.
pub fn compile_captured_classified_with_pinned_abi<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    links: CapturedLinkInputs<'_>,
    declarations: CapturedDeclarationInputs<'_>,
    config: LoweringConfig,
    map_initializers: Vec<crate::initialization_artifact::InitializationArtifact>,
    non_text: Option<&dyn crate::composition::NonTextOutputStage>,
) -> Result<ColdOutput, ColdError> {
    compile_captured_classified_with_pinned_abi_observed(
        frontend,
        resolver,
        links,
        declarations,
        config,
        map_initializers,
        non_text,
        None,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn compile_captured_classified_with_pinned_abi_observed<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    links: CapturedLinkInputs<'_>,
    declarations: CapturedDeclarationInputs<'_>,
    config: LoweringConfig,
    map_initializers: Vec<crate::initialization_artifact::InitializationArtifact>,
    non_text: Option<&dyn crate::composition::NonTextOutputStage>,
    observer: Option<&ColdObserver<'_>>,
) -> Result<ColdOutput, ColdError> {
    compile_captured_classified_with_pinned_abi_memo(
        frontend,
        resolver,
        links,
        declarations,
        config,
        map_initializers,
        non_text,
        observer,
        None,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn compile_captured_classified_with_pinned_abi_memo<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    links: CapturedLinkInputs<'_>,
    declarations: CapturedDeclarationInputs<'_>,
    config: LoweringConfig,
    map_initializers: Vec<crate::initialization_artifact::InitializationArtifact>,
    non_text: Option<&dyn crate::composition::NonTextOutputStage>,
    observer: Option<&ColdObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> Result<ColdOutput, ColdError> {
    let executor = dm_exec::BuildExecutor::new(config.workers)
        .map_err(|error| ColdError::AbiPreparation(error.to_string()))?;
    compile_captured_classified_with_pinned_abi_memo_revision(
        frontend,
        resolver,
        links,
        declarations,
        config,
        map_initializers,
        non_text,
        observer,
        memo,
        None,
        &executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn compile_captured_classified_with_pinned_abi_memo_revision<R: Resolver>(
    frontend: &ColdFrontend,
    resolver: &R,
    links: CapturedLinkInputs<'_>,
    declarations: CapturedDeclarationInputs<'_>,
    config: LoweringConfig,
    map_initializers: Vec<crate::initialization_artifact::InitializationArtifact>,
    non_text: Option<&dyn crate::composition::NonTextOutputStage>,
    observer: Option<&ColdObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    revision: Option<&dm_tree::frontend::FrontendRevision>,
    executor: &dm_exec::BuildExecutor,
) -> Result<ColdOutput, ColdError> {
    let total = Instant::now();
    let measurement = StageMeasurement::new(observer, ColdStage::StartupCapture);
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    let startup = match revision {
        Some(revision) => crate::startup::capture_revision_facts_with_executor_and_bodies(
            revision,
            &links.inventory.spellings,
            executor,
            &bodies,
        )
        .and_then(|facts| facts.view_revision(revision)),
        None => crate::startup::capture_with_executor_and_bodies(
            frontend,
            &links.inventory.spellings,
            executor,
            &bodies,
        ),
    }
    .map_err(ColdError::Initializer)?;
    measurement.complete();
    let measurement = StageMeasurement::new(observer, ColdStage::AbiPreparation);
    let prepared = crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor(
        frontend,
        links.engine,
        resolver,
        &startup,
        declarations.resource_search_context,
        executor,
    )
    .map_err(|error| ColdError::AbiPreparation(error.to_string()))?;
    if !prepared.prepared.diagnostics.is_empty() {
        return Err(ColdError::Lowering(
            crate::driver_facts::abi_diagnostics(frontend, &prepared.prepared)
                .map_err(|error| ColdError::AbiPreparation(error.to_string()))?,
        ));
    }
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(frontend, &prepared.prepared)
        .map_err(|error| ColdError::AbiPreparation(error.to_string()))?;
    measurement.complete();
    let abi_preparation = total.elapsed();
    let mut output = compile_with_startup(
        frontend,
        resolver,
        &policy,
        links,
        declarations,
        config,
        map_initializers,
        non_text,
        &startup,
        observer,
        memo,
        executor,
        bodies,
    )?;
    output.timings.abi_preparation = abi_preparation;
    output.timings.total = total.elapsed();
    Ok(output)
}

/// Captured map initialization and non-text output share the declaration/body
/// freezer and final writer. Their semantic capture remains a prior stage.
#[allow(clippy::too_many_arguments)] // Explicit captured boundaries; no project snapshot bundle.
pub fn compile_captured_classified_with_stage<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    resolver: &R,
    policy: &P,
    links: CapturedLinkInputs<'_>,
    declarations: CapturedDeclarationInputs<'_>,
    config: LoweringConfig,
    map_initializers: Vec<crate::initialization_artifact::InitializationArtifact>,
    non_text: Option<&dyn crate::composition::NonTextOutputStage>,
) -> Result<ColdOutput, ColdError> {
    let executor = dm_exec::BuildExecutor::new(config.workers)
        .map_err(|error| ColdError::AbiPreparation(error.to_string()))?;
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    let startup = crate::startup::capture_with_executor_and_bodies(
        frontend,
        &links.inventory.spellings,
        &executor,
        &bodies,
    )
    .map_err(ColdError::Initializer)?;
    compile_with_startup(
        frontend,
        resolver,
        policy,
        links,
        declarations,
        config,
        map_initializers,
        non_text,
        &startup,
        None,
        None,
        &executor,
        bodies,
    )
}

#[allow(clippy::too_many_arguments)]
fn compile_with_startup<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    resolver: &R,
    policy: &P,
    links: CapturedLinkInputs<'_>,
    declarations: CapturedDeclarationInputs<'_>,
    config: LoweringConfig,
    map_initializers: Vec<crate::initialization_artifact::InitializationArtifact>,
    non_text: Option<&dyn crate::composition::NonTextOutputStage>,
    startup: &crate::startup::CapturedStartup<'_>,
    observer: Option<&ColdObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    executor: &dm_exec::BuildExecutor,
    bodies: dm_tree::frontend::BodyArena<'_>,
) -> Result<ColdOutput, ColdError> {
    startup
        .validate_for(frontend)
        .map_err(ColdError::Initializer)?;
    let total = Instant::now();
    for artifact in &map_initializers {
        if !matches!(artifact.identity, dm_link::InitializerIdentity::Map { .. }) {
            return Err(ColdError::Initializer(
                "captured map artifacts cannot replace declaration initializers".into(),
            ));
        }
        artifact.validate().map_err(ColdError::Initializer)?;
    }
    let captured = frontend.engine.as_ref().ok_or(ColdError::EngineMismatch)?;
    if captured.identity != links.engine.identity()
        || !links
            .engine
            .matches_template(links.engine_bytes, links.engine.interpretation_schema())
    {
        return Err(ColdError::EngineMismatch);
    }
    let stage = Instant::now();
    let measurement = StageMeasurement::new(observer, ColdStage::Initializers);
    let static_resolver = startup
        .resolver(frontend, resolver)
        .map_err(ColdError::Initializer)?;
    let resolver = &static_resolver;
    let plan = startup.plan();
    crate::heap_census::emit_if_enabled("startup.ready", |census| {
        census.frontend(frontend);
        census.startup(startup);
        census.body_arena(&bodies);
    })
    .map_err(|error| ColdError::InitializerInvariant(format!("heap census: {error}")))?;
    let startup_evaluator = crate::startup::StartupEvaluator {
        resource_search_context: declarations.resource_search_context,
        ordinary: declarations.initializers,
        resolver,
        symbols: plan.symbols.as_ref(),
    };
    let evaluator = crate::initializer_policy::EngineCapturedEvaluator {
        engine: links.engine,
        evaluator: &startup_evaluator,
    };
    let parallel_factory = declarations
        .initializers
        .parallel_evaluator()
        .map(|ordinary| initializer_factory::StartupParallelFactory {
            ordinary,
            resolver,
            symbols: plan.symbols.as_ref(),
            resource_search_context: declarations.resource_search_context,
        });
    let initializer_observer = |event: crate::initializer_lowering::InitializerMeasurement| {
        if let Some(observer) = observer {
            observer(ColdMeasurement {
                stage: match event.stage {
                    crate::initializer_lowering::InitializerStage::Classification => {
                        ColdStage::InitializerClassification
                    }
                    crate::initializer_lowering::InitializerStage::Codegen => {
                        ColdStage::InitializerCodegen
                    }
                },
                elapsed: event.elapsed,
                succeeded: event.succeeded,
            });
        }
    };
    let initialization = crate::initializer_lowering::lower_captured_observed_memo_on_executor(
        frontend,
        startup,
        &evaluator,
        resolver,
        declarations.resource_search_context,
        crate::initializer_lowering::InitializerExecution {
            executor,
            evaluator: parallel_factory.as_ref().map(|factory| {
                crate::initializer_policy::ParallelEvaluator {
                    factory,
                    engine: Some(links.engine),
                }
            }),
            observer: observer.map(|_| {
                &initializer_observer as &crate::initializer_lowering::InitializerObserver<'_>
            }),
            memo,
        },
    )
    .map_err(initializer_lowering_error)?;
    let projection = crate::class_projection::project_classified(
        &frontend.snapshot,
        &frontend.emission_order,
        plan,
        &initialization.classified,
        &initialization.units,
    )
    .map_err(ColdError::Projection)?;
    measurement.complete();
    let initializers = stage.elapsed();
    let mut inventory = links.inventory;
    let stage = Instant::now();
    let measurement = StageMeasurement::new(observer, ColdStage::ProcedureLowering);
    let batch = match memo {
        Some(memo) => crate::lowering::lower_frontend_with_memo_on_executor_and_bodies(
            frontend,
            resolver,
            policy,
            config,
            startup,
            memo,
            crate::lowering::LoweringExecution::new(executor, &bodies),
        ),
        None => crate::lowering::lower_frontend_with_statics_on_executor_and_bodies(
            frontend,
            resolver,
            policy,
            config,
            startup,
            crate::lowering::LoweringExecution::new(executor, &bodies),
        ),
    };
    let lowering = stage.elapsed();
    if !batch.diagnostics.is_empty() {
        return Err(ColdError::Lowering(batch.diagnostics));
    }
    crate::heap_census::emit_if_enabled("lowering.ready", |census| {
        census.frontend(frontend);
        census.startup(startup);
        census.lowered(&batch);
    })
    .map_err(|error| ColdError::InitializerInvariant(format!("heap census: {error}")))?;
    batch
        .require_production_abi()
        .map_err(|_| ColdError::NonAuthoritativeAbi)?;
    // Consume the request-local parse owner before linking/composition.
    // Reusable startup facts never retain executable syntax.
    drop(bodies);
    measurement.complete();
    // Discover anonymous descriptors only from actual emitted operand sites.
    // Recursive descriptor initializers append to one request-local graph.
    let seeds = batch
        .units
        .iter()
        .flat_map(|unit| {
            std::iter::once((&unit.code, &unit.debug_origins)).chain(
                unit.source_helpers
                    .iter()
                    .map(|helper| (&helper.code, &helper.debug_origins)),
            )
        })
        .chain(
            initialization
                .units
                .iter()
                .map(|unit| (&unit.code, &unit.debug_origins)),
        )
        .chain(
            map_initializers
                .iter()
                .map(|unit| (&unit.code, &unit.debug_origins)),
        );
    let modified_defaults =
        crate::modified_initializers::default_seeds(frontend, plan, &initialization.classified)
            .map_err(ColdError::Initializer)?;
    // Projection/default capture own their results; release the runtime AST ledger.
    drop(initialization.classified);
    let modified = crate::modified_initializers::collect_with_defaults(
        seeds,
        &modified_defaults,
        plan.symbols.as_ref(),
        resolver,
        declarations.initializers.pure_calls(),
    )
    .map_err(ColdError::Initializer)?;
    // Descriptor/debug facts are owned by modified; release their seed copies.
    drop(modified_defaults);
    crate::modified_output::contribute(&modified.descriptors, &mut inventory)
        .map_err(ColdError::Initializer)?;
    let modified_stage = crate::modified_initializers::Stage {
        descriptors: &modified.descriptors,
        types: declarations.type_values,
        next: non_text,
    };
    let non_text = Some(&modified_stage as &dyn crate::composition::NonTextOutputStage);
    // Every anonymous initializer uses the same operand reachability pass and
    // freezer, including type operands used only inside descriptor field values.
    let initialization_artifacts: Vec<_> = map_initializers
        .into_iter()
        .chain(modified.artifacts)
        .collect();
    let measurement = StageMeasurement::new(observer, ColdStage::RequiredTypeAdmission);
    let non_text_types = non_text
        .map(|stage| stage.required_types())
        .unwrap_or_default();
    let (projection, source_type_order) = crate::required_types::admit(
        projection,
        crate::required_types::Inputs {
            source_order: declarations.source_type_order,
            bodies: &batch,
            initializers: &initialization.units,
            maps: &initialization_artifacts,
            inventory: &inventory,
            symbols: plan.symbols.as_ref(),
            non_text_types: &non_text_types,
        },
    )
    .map_err(ColdError::Initializer)?;
    crate::class_inventory::contribute(
        &projection,
        plan.symbols.as_ref(),
        &source_type_order,
        &mut inventory,
    )
    .map_err(ColdError::Initializer)?;
    measurement.complete();
    let stage = Instant::now();
    let measurement = StageMeasurement::new(observer, ColdStage::SymbolicLinking);
    let initialization = initialization
        .units
        .into_iter()
        .map(Into::into)
        .chain(initialization_artifacts)
        .collect();
    let frozen = crate::symbolic::freeze_artifact_tables_with_executor(
        batch,
        plan.symbols.as_ref(),
        links.references,
        inventory,
        initialization,
        executor,
    )
    .map_err(ColdError::Linking)?;
    measurement.complete();
    let symbolic_linking = stage.elapsed();
    let stage = Instant::now();
    let measurement = StageMeasurement::new(observer, ColdStage::Composition);
    crate::heap_census::emit_if_enabled("linking.ready", |census| {
        census.frontend(frontend);
        census.startup(startup);
        census.frozen(&frozen);
    })
    .map_err(|error| ColdError::InitializerInvariant(format!("heap census: {error}")))?;
    let dmb = crate::composition::compose_projected_owned_with_symbols_on_executor(
        links.engine_bytes,
        frozen,
        frontend,
        &projection,
        declarations.type_values,
        non_text,
        plan.symbols.as_ref(),
        executor,
    )
    .map_err(ColdError::Composition)?;
    measurement.complete();
    Ok(ColdOutput {
        dmb,
        startup: Some(startup.facts()),
        timings: ColdTimings {
            abi_preparation: Duration::ZERO,
            lowering,
            initializers,
            symbolic_linking,
            composition: stage.elapsed(),
            total: total.elapsed(),
        },
    })
}

#[cfg(test)]
#[path = "cold/tests.rs"]
mod tests;
