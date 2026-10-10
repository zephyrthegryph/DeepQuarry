use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/var/value = 1\n/proc/p()\n    return 1\n".into())
    }
}
struct RejectBody;
impl AbiPolicy for RejectBody {
    fn inputs(
        &self,
        _: crate::lowering::UnitIdentity,
        _: &dm_ir::ProcedureMetadata,
        _: &dm_ir::SymbolTable,
        _: &dm_tree::frontend::SourceLocation,
    ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
        Err("body rejection must precede deferred default provenance failure".into())
    }
}
struct Types;
impl crate::class_projection::TypeValuePolicy for Types {
    fn tag(&self, _: dm_ir::SymbolId) -> Result<u8, crate::class_projection::ProjectionError> {
        Ok(32)
    }
}
#[test]
fn deferred_default_provenance_failure_does_not_preempt_body_diagnostic() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let seed = engine.frontend_seed();
    let mut frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    // Declaration/occurrence meanings still match; stored-default provenance
    // cannot be licensed by a file whose captured-source status was withdrawn.
    for file in std::sync::Arc::make_mut(&mut frontend.files) {
        file.captured = false;
    }
    let startup = crate::startup::capture(&frontend).unwrap();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: frontend.snapshot.tree.as_ref(),
        symbols: startup.plan().symbols.as_ref(),
    };
    let initialization = crate::initializer_lowering::lower_captured(
        &frontend,
        &startup,
        &evaluator,
        frontend.snapshot.tree.as_ref(),
        None,
    )
    .unwrap();
    assert!(
        matches!(crate::modified_initializers::default_seeds(&frontend, startup.plan(), &initialization.classified), Err(error) if error == "modified default source provenance mismatch")
    );
    drop(initialization);
    let links = crate::engine_link::capture(bytes, &engine).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let result = prepare_with_startup(
        &frontend,
        frontend.snapshot.tree.as_ref(),
        &RejectBody,
        CapturedLinkInputs {
            engine_bytes: bytes,
            engine: &engine,
            references: &links.references,
            inventory: links.inventory,
        },
        CapturedDeclarationInputs {
            initializers: &evaluator,
            type_values: &Types,
            resource_search_context: None,
            source_type_order: &[],
            source_allocation_roster: None,
        },
        LoweringConfig::default(),
        Vec::new(),
        None,
        &startup,
        None,
        None,
        &executor,
        dm_tree::frontend::BodyArena::new(&frontend),
    );
    match result {
        Err(ColdError::Lowering(errors)) => assert!(errors
            .iter()
            .any(|error| error.message.contains("body rejection must precede"))),
        _ => panic!("deferred seed failure preempted authored body lowering"),
    }
}
