//! One uncached orchestration path over captured semantic inputs.
//! Admission is deliberately bounded by the production composer. A successful
//! return means every declaration was admitted, rather than a partial artifact.
use crate::{
    composition::{compose_global_program, validate_global_program, CompositionError},
    lowering::{lower_frontend, AbiPolicy, LoweringConfig, LoweringDiagnostic},
    symbolic::{freeze_and_link_tables, IntegrationError, ReferenceBindings},
};
use dm_ir::Resolver;
use dm_link::LinkInventory;
use dm_tree::frontend::ColdFrontend;
use std::time::{Duration, Instant};

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
    pub dmb: Vec<u8>,
    pub timings: ColdTimings,
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
fn initializer_lowering_error(error: crate::initializer_diagnostics::InitializerLoweringError) -> ColdError {
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
    let batch = lower_frontend(frontend, resolver, policy, config);
    let lowering = stage.elapsed();
    if !batch.diagnostics.is_empty() {
        return Err(ColdError::Lowering(batch.diagnostics));
    }
    if batch.units.iter().any(|unit| unit.abi.is_none()) {
        return Err(ColdError::NonAuthoritativeAbi);
    }
    let stage = Instant::now();
    let frozen = freeze_and_link_tables(
        batch,
        frontend.snapshot.tree.symbols(),
        links.references,
        links.inventory,
    )
    .map_err(ColdError::Linking)?;
    let symbolic_linking = stage.elapsed();
    let stage = Instant::now();
    let dmb = compose_global_program(links.engine_bytes, &frozen, frontend)
        .map_err(ColdError::Composition)?;
    Ok(ColdOutput {
        dmb,
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
        frontend, resolver, links, declarations, config, map_initializers, non_text, None,
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
    let total = Instant::now();
    let measurement = StageMeasurement::new(observer, ColdStage::StartupCapture);
    let startup = crate::startup::capture_with_spellings_and_workers(
        frontend,
        &links.inventory.spellings,
        config.workers,
    )
    .map_err(ColdError::Initializer)?;
    measurement.complete();
    let measurement = StageMeasurement::new(observer, ColdStage::AbiPreparation);
    let prepared = crate::driver_facts::prepare_pinned_source_abi_with_startup(
        frontend,
        links.engine,
        resolver,
        &startup,
        declarations.resource_search_context,
        config.workers,
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
    let startup = crate::startup::capture_with_spellings_and_workers(
        frontend,
        &links.inventory.spellings,
        config.workers,
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
    let initializer_observer = |event: crate::initializer_lowering::InitializerMeasurement| {
        if let Some(observer) = observer {
            observer(ColdMeasurement {
                stage: match event.stage {
                    crate::initializer_lowering::InitializerStage::Classification => ColdStage::InitializerClassification,
                    crate::initializer_lowering::InitializerStage::Codegen => ColdStage::InitializerCodegen,
                },
                elapsed: event.elapsed,
                succeeded: event.succeeded,
            });
        }
    };
    let initialization = crate::initializer_lowering::lower_captured_observed(
        frontend,
        startup,
        &evaluator,
        resolver,
        declarations.resource_search_context,
        observer.map(|_| &initializer_observer as &crate::initializer_lowering::InitializerObserver<'_>),
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
    let batch =
        crate::lowering::lower_frontend_with_statics(frontend, resolver, policy, config, &startup);
    let lowering = stage.elapsed();
    if !batch.diagnostics.is_empty() {
        return Err(ColdError::Lowering(batch.diagnostics));
    }
    batch
        .require_production_abi()
        .map_err(|_| ColdError::NonAuthoritativeAbi)?;
    measurement.complete();
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
            maps: &map_initializers,
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
        .chain(map_initializers)
        .collect();
    let frozen = crate::symbolic::freeze_artifact_tables(
        batch,
        plan.symbols.as_ref(),
        links.references,
        inventory,
        initialization,
    )
    .map_err(ColdError::Linking)?;
    measurement.complete();
    let symbolic_linking = stage.elapsed();
    let stage = Instant::now();
    let measurement = StageMeasurement::new(observer, ColdStage::Composition);
    let dmb = crate::composition::compose_projected_with_symbols(
        links.engine_bytes,
        &frozen,
        frontend,
        &projection,
        declarations.type_values,
        non_text,
        plan.symbols.as_ref(),
    )
    .map_err(ColdError::Composition)?;
    measurement.complete();
    Ok(ColdOutput {
        dmb,
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
mod tests {
    use super::*;
    use crate::{engine::EngineSnapshot, lowering::UnitIdentity};
    use dm_codegen_byond::ProcedureInputs;
    use dm_ir::{ProcedureMetadata, SymbolTable};
    use dm_tree::frontend::{FrontendConfig, SourceLocation};
    use std::path::Path;

    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/var/x = 1\n/proc/p()\n    return 1\n".into())
        }
    }
    #[test]
    fn classified_cold_path_emits_real_class_field_and_procedure() {
        use crate::driver_facts::{self, BoundaryAbi, DriverEvaluator, FrozenPreparedPolicy};
        struct ClassSource;
        impl dm_preprocess::SourceProvider for ClassSource {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok(
                    "/datum/demo\n    var/value = 7\n/datum/demo/proc/read()\n    return value\n"
                        .into(),
                )
            }
        }
        struct NoTypeDefaults;
        impl crate::class_projection::TypeValuePolicy for NoTypeDefaults {
            fn tag(
                &self,
                _: dm_ir::SymbolId,
            ) -> Result<u8, crate::class_projection::ProjectionError> {
                Err(crate::class_projection::ProjectionError::Unsupported(
                    "fixture has no type defaults".into(),
                ))
            }
        }
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = EngineSnapshot::from_bytes(bytes, 1)
            .unwrap()
            .with_bootstrap_catalog()
            .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &ClassSource,
            &Default::default(),
            FrontendConfig {
                workers: 2,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let evaluator = DriverEvaluator {
            resource_search_context: None,
            resolver: frontend.snapshot.tree.as_ref(),
            symbols: frontend.snapshot.tree.symbols(),
        };
        // This finite fixture explicitly certifies read as a new procedure. It
        // does not issue a production certificate for unknown engine names.
        let boundaries = driver_facts::unit_members(&frontend)
            .unwrap()
            .keys()
            .map(|identity| (*identity, BoundaryAbi::Fresh))
            .collect();
        let prepared =
            driver_facts::prepare_source_abi(&frontend, &engine, &evaluator, &boundaries, None, 2)
                .unwrap();
        let policy = FrozenPreparedPolicy::new(&frontend, &prepared).unwrap();
        let links = crate::engine_link::capture(bytes, &engine).unwrap();
        let order = crate::type_creation_order::collect(
            &frontend.allocation_ledger,
            &frontend.expanded.text,
            frontend.snapshot.tree.symbols(),
            &links.inventory,
        )
        .unwrap();
        let output = compile_captured_classified_program(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &policy,
            CapturedLinkInputs {
                engine_bytes: bytes,
                engine: &engine,
                references: &links.references,
                inventory: links.inventory,
            },
            CapturedDeclarationInputs {
                initializers: &evaluator,
                type_values: &NoTypeDefaults,
                resource_search_context: None,
                source_type_order: &order,
            },
            LoweringConfig {
                workers: 2,
                ..Default::default()
            },
        )
        .unwrap_or_else(|error| {
            let captured = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
            let record = captured.procs.get(55);
            let layouts: Vec<_> = engine.procedure_layouts().iter().filter(|layout| layout.wire_proc == 55)
                .map(|layout| (engine.symbols().text(layout.owner), layout.name.and_then(|name| engine.symbols().text(name)), layout.kind)).collect();
            panic!("{error:?}; engine_procs={}; record55={record:?}; strings55={:?}; layouts55={layouts:?}; source_owner={:?}; source_name={:?}",
                captured.procs.len(), record.map(|record| record.strings.map(|id| captured.string(id))),
                dm_ir::SymbolId::of("/datum/demo"), dm_ir::SymbolId::of("read"));
        });
        let image = byond_dmb::dmb::Dmb::from_bytes(&output.dmb).unwrap();
        image.validate_references().unwrap();
        let class = image
            .classes
            .iter()
            .position(|class| {
                image.string(class.path_string_id()) == Some(b"/datum/demo".as_slice())
            })
            .unwrap();
        let declarations = image.class_variable_declarations(class).unwrap();
        assert!(declarations.iter().any(|(id, _)| {
            let record = &image.variables[*id as usize];
            image.string(record.name) == Some(b"value".as_slice())
                && record.kind == 42
                && record.value == 7f32.to_bits()
        }));
        assert!(
            image
                .procs
                .iter()
                .any(|proc| image.string(proc.strings[0])
                    == Some(b"/datum/demo/proc/read".as_slice()))
        );
    }
    #[test]
    fn pinned_cold_startup_interleaves_globals_class_and_distinct_procedure_statics() {
        struct StartupSource;
        impl dm_preprocess::SourceProvider for StartupSource {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("var/global_first = make_value()\n/datum/startup_probe\n    var/static/class_middle = make_value()\n/datum/startup_probe/proc/first()\n    var/static/counter = make_value()\n    return counter\n/datum/startup_probe/proc/second()\n    var/static/counter = make_value()\n    return counter\nvar/global_last = make_value()\n/proc/make_value()\n    return 7\n".into())
            }
        }
        struct NoTypeDefaults;
        impl crate::class_projection::TypeValuePolicy for NoTypeDefaults {
            fn tag(
                &self,
                _: dm_ir::SymbolId,
            ) -> Result<u8, crate::class_projection::ProjectionError> {
                Err(crate::class_projection::ProjectionError::Unsupported(
                    "no type defaults".into(),
                ))
            }
        }
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = EngineSnapshot::from_bytes(bytes, 1)
            .unwrap()
            .with_bootstrap_catalog()
            .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &StartupSource,
            &Default::default(),
            FrontendConfig {
                workers: 2,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let make_query = dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of("make_value"));
        assert!(
            matches!(
                dm_ir::Resolver::resolve(frontend.snapshot.tree.as_ref(), make_query),
                dm_ir::ResolvedMeaning::Member { .. }
            ),
            "query={make_query:?}, answer={:?}",
            dm_ir::Resolver::resolve(frontend.snapshot.tree.as_ref(), make_query)
        );
        let mut host_symbols = frontend.snapshot.tree.symbols().clone();
        let constants =
            crate::engine_host::ConstantCatalog::native_516_1687(&mut host_symbols).unwrap();
        let runtime = crate::engine_host::RuntimeAliasCatalog::new(
            engine.identity(),
            &host_symbols,
            Vec::new(),
            frontend
                .snapshot
                .tree
                .types()
                .iter()
                .map(|node| node.path)
                .collect(),
            crate::engine_host::Completeness::Partial,
        )
        .unwrap();
        let host = crate::engine_host::EngineResolverHost::new(
            frontend.snapshot.tree.clone(),
            constants,
            runtime,
        )
        .with_pinned_callables(&engine, &frontend)
        .unwrap();
        use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver as _};
        let owner = dm_ir::SymbolId::of("/datum/startup_probe");
        assert!(matches!(host.resolve(make_query), M::Member { .. }));
        let first = dm_ir::SymbolId::of("first");
        assert!(matches!(
            host.resolve(Q::Proc {
                owner,
                name: first,
                verb: false
            }),
            M::Member { .. }
        ));
        assert_eq!(
            host.resolve(Q::Proc {
                owner,
                name: first,
                verb: true
            }),
            M::Missing
        );
        assert_eq!(
            host.resolve(Q::HasMemberProc {
                owner,
                name: dm_ir::SymbolId::of("make_value")
            }),
            M::Presence(false)
        );
        // The pinned receiver catalog certifies New as a proc, so its opposite
        // verb namespace is absent. An uncaptured spelling is still unknown.
        assert_eq!(
            host.resolve(Q::Proc {
                owner,
                name: dm_ir::SymbolId::of("New"),
                verb: true,
            }),
            M::Missing
        );
        let query = Q::Proc {
            owner,
            name: dm_ir::SymbolId::of("never_captured_callable"),
            verb: true,
        };
        assert_eq!(host.resolve(query), M::Unsupported(query));

        let evaluator = crate::driver_facts::DriverEvaluator {
            resource_search_context: None,
            resolver: &host,
            symbols: frontend.snapshot.tree.symbols(),
        };
        let links = crate::engine_link::capture(bytes, &engine).unwrap();
        let order = crate::type_creation_order::collect(
            &frontend.allocation_ledger,
            &frontend.expanded.text,
            frontend.snapshot.tree.symbols(),
            &links.inventory,
        )
        .unwrap();
        let output = compile_captured_classified_with_pinned_abi(
            &frontend,
            &host,
            CapturedLinkInputs {
                engine_bytes: bytes,
                engine: &engine,
                references: &links.references,
                inventory: links.inventory,
            },
            CapturedDeclarationInputs {
                initializers: &evaluator,
                type_values: &NoTypeDefaults,
                resource_search_context: None,
                source_type_order: &order,
            },
            LoweringConfig {
                workers: 2,
                max_chunk: 1,
            },
            Vec::new(),
            None,
        )
        .unwrap();
        let image = byond_dmb::dmb::Dmb::from_bytes(&output.dmb).unwrap();
        image.validate_references().unwrap();
        let footer = &image.lists[image.variable_footer as usize];
        let mut selected = Vec::new();
        for (slot, pair) in footer.chunks_exact(2).enumerate() {
            let name = image
                .string(image.variables[pair[0] as usize].name)
                .unwrap();
            if [
                b"global_first".as_slice(),
                b"class_middle",
                b"counter",
                b"global_last",
            ]
            .contains(&name)
            {
                selected.push((slot as u32, name.to_vec(), pair[0]));
            }
        }
        assert_eq!(
            selected
                .iter()
                .map(|(_, name, _)| name.as_slice())
                .collect::<Vec<_>>(),
            vec![
                b"global_first".as_slice(),
                b"class_middle",
                b"counter",
                b"counter",
                b"global_last"
            ]
        );
        assert_ne!(selected[2].0, selected[3].0);
        assert_ne!(selected[2].2, selected[3].2);
        let initializer = image.world.ids[4];
        assert_ne!(initializer, 0xffff);
        let code = &image.lists[image.procs[initializer as usize].code_locals_args[0] as usize];
        let instructions = byond_dmb::bytecode::decode(code).unwrap();
        assert_eq!(
            instructions
                .iter()
                .filter(|instruction| instruction.name == "End")
                .count(),
            1
        );
        let slots = instructions
            .iter()
            .filter(|instruction| instruction.name == "SetVar")
            .flat_map(|instruction| instruction.typed_operands().unwrap())
            .filter_map(|operand| match operand {
                byond_dmb::bytecode::Operand::Variable(byond_dmb::operands::Variable::Global(
                    slot,
                )) => Some(slot),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(
            slots,
            selected
                .iter()
                .map(|(slot, _, _)| *slot)
                .collect::<Vec<_>>()
        );
    }
    struct MustNotLower;
    impl AbiPolicy for MustNotLower {
        fn inputs(
            &self,
            _: UnitIdentity,
            _: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            panic!("unsupported programs must be rejected before body lowering")
        }
    }
    #[test]
    fn pinned_engine_and_full_admission_precede_expensive_lowering() {
        let bytes = include_bytes!("../../../fixtures/native_template.bin");
        let engine = EngineSnapshot::from_bytes(bytes, 1).unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source,
            &Default::default(),
            FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let references = ReferenceBindings::default();
        let result = compile_captured_program(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &MustNotLower,
            CapturedLinkInputs {
                engine_bytes: bytes,
                engine: &engine,
                references: &references,
                inventory: Default::default(),
            },
            Default::default(),
        );
        assert!(matches!(
            result,
            Err(ColdError::Composition(CompositionError::Unsupported(_)))
        ));
        let changed_schema = EngineSnapshot::from_bytes(bytes, 2).unwrap();
        let result = compile_captured_program(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &MustNotLower,
            CapturedLinkInputs {
                engine_bytes: bytes,
                engine: &changed_schema,
                references: &references,
                inventory: Default::default(),
            },
            Default::default(),
        );
        assert!(matches!(result, Err(ColdError::EngineMismatch)));
    }
}
