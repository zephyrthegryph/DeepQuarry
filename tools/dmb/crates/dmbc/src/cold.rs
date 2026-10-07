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

#[derive(Clone, Copy, Debug, Default)]
pub struct ColdTimings {
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
    Lowering(Vec<LoweringDiagnostic>),
    NonAuthoritativeAbi,
    Linking(IntegrationError),
    Composition(CompositionError),
    Initializer(String),
    Projection(crate::class_projection::ProjectionError),
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
    let total = Instant::now();
    let captured = frontend.engine.as_ref().ok_or(ColdError::EngineMismatch)?;
    if captured.identity != links.engine.identity()
        || !links
            .engine
            .matches_template(links.engine_bytes, links.engine.interpretation_schema())
    {
        return Err(ColdError::EngineMismatch);
    }
    let stage = Instant::now();
    let plan = dm_tree::initializers::plan(&frontend.snapshot, &frontend.emission_order)
        .map_err(|errors| ColdError::Initializer(format!("initializer planning: {errors:?}")))?;
    let evaluator = crate::initializer_policy::EngineCapturedEvaluator {
        engine: links.engine,
        evaluator: declarations.initializers,
    };
    let initialization = crate::initializer_lowering::lower(
        frontend,
        &plan,
        &evaluator,
        resolver,
        declarations.resource_search_context,
    )
    .map_err(ColdError::Initializer)?;
    let projection = crate::class_projection::project_classified(
        &frontend.snapshot,
        &frontend.emission_order,
        &plan,
        &initialization.classified,
        &initialization.units,
    )
    .map_err(ColdError::Projection)?;
    let initializers = stage.elapsed();
    let mut inventory = links.inventory;
    crate::class_inventory::contribute(
        &projection,
        frontend.snapshot.tree.symbols(),
        declarations.source_type_order,
        &mut inventory,
    )
    .map_err(ColdError::Initializer)?;
    let stage = Instant::now();
    let batch = lower_frontend(frontend, resolver, policy, config);
    let lowering = stage.elapsed();
    if !batch.diagnostics.is_empty() {
        return Err(ColdError::Lowering(batch.diagnostics));
    }
    batch
        .require_production_abi()
        .map_err(|_| ColdError::NonAuthoritativeAbi)?;
    let stage = Instant::now();
    let frozen = crate::symbolic::freeze_program_tables(
        batch,
        frontend.snapshot.tree.symbols(),
        links.references,
        inventory,
        initialization.units,
    )
    .map_err(ColdError::Linking)?;
    let symbolic_linking = stage.elapsed();
    let stage = Instant::now();
    let dmb = crate::composition::compose_projected_program(
        links.engine_bytes,
        &frozen,
        frontend,
        &projection,
        declarations.type_values,
    )
    .map_err(ColdError::Composition)?;
    Ok(ColdOutput {
        dmb,
        timings: ColdTimings {
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
