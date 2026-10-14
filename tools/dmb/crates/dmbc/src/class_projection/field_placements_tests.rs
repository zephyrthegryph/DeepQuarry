use super::*;
use crate::class_projection::*;
use dm_ir::{SemanticValue, SymbolId, SymbolicExpression};

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct Evaluator<'a>(&'a dm_tree::SemanticTree);
impl crate::initializer_policy::CapturedInitializerEvaluator for Evaluator<'_> {
    fn evaluate(
        &self,
        _: SymbolId,
        _: &SymbolicExpression,
    ) -> Result<crate::initializer_policy::Evaluation, String> {
        Ok(crate::initializer_policy::Evaluation::Scalar(
            SemanticValue::Text(Arc::from(b"custom".as_slice())),
        ))
    }
    fn instance_storage(
        &self,
        write: &dm_ir::InitializerWrite,
    ) -> Result<Option<(SymbolId, SymbolId)>, String> {
        let dm_ir::InitializerTarget::Instance {
            declaring_owner,
            receiver_owner,
            name,
        } = write.target
        else {
            return Ok(None);
        };
        Ok(
            match dm_ir::Resolver::resolve(
                self.0,
                dm_ir::ResolveQuery::VarStorage {
                    owner: receiver_owner,
                    name,
                },
            ) {
                dm_ir::ResolvedMeaning::InstanceField {
                    declaring_owner: actual,
                    name: actual_name,
                } if actual == declaring_owner && actual_name == name => {
                    Some((actual, actual_name))
                }
                _ => None,
            },
        )
    }
}
struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported("no type values".into()))
    }
}
#[derive(Clone)]
struct IssuedProjection {
    projection: ClassProjection,
    symbols: dm_ir::SymbolTable,
    source_order: Vec<SymbolId>,
}
impl std::ops::Deref for IssuedProjection {
    type Target = ClassProjection;
    fn deref(&self) -> &ClassProjection {
        &self.projection
    }
}
impl std::ops::DerefMut for IssuedProjection {
    fn deref_mut(&mut self) -> &mut ClassProjection {
        &mut self.projection
    }
}
fn projection(store: &ClassProjections, text: &'static str) -> IssuedProjection {
    projection_with_origins(store, text, true)
}
fn projection_with_origins(
    store: &ClassProjections,
    text: &'static str,
    retain_origins: bool,
) -> IssuedProjection {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        std::path::Path::new("project.dme"),
        &Source(text),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let mut plan =
        dm_tree::initializers::plan(&frontend.snapshot, &frontend.emission_order).unwrap();
    let evaluator = Evaluator(&frontend.snapshot.tree);
    let captured = crate::initializer_policy::EngineCapturedEvaluator {
        engine: &engine,
        evaluator: &evaluator,
    };
    let classified =
        crate::initializer_policy::classify(&plan.writes, &plan.symbols, &captured).unwrap();
    let mut projection = project_classified_with_artifacts(
        &frontend.snapshot,
        &frontend.emission_order,
        &plan,
        &classified,
        &[],
        Some(store),
    )
    .unwrap();
    if !retain_origins {
        plan.origins = Arc::from([]);
    }
    projection.bind_field_sources(&frontend, &plan).unwrap();
    let engine_inventory = crate::engine_link::capture(bytes, &engine)
        .unwrap()
        .inventory;
    let source_order = crate::type_creation_order::collect(
        &frontend.allocation_ledger,
        &frontend.expanded.text,
        &plan.symbols,
        &engine_inventory,
    )
    .unwrap();
    IssuedProjection {
        projection,
        symbols: frontend.snapshot.tree.symbols().clone(),
        source_order,
    }
}
fn failure(projection: &IssuedProjection) -> ProjectionError {
    let mut image =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin"))
            .unwrap();
    let symbols = &projection.symbols;
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let mut inventory = crate::engine_link::capture(
        include_bytes!("../../../../fixtures/native_template.bin"),
        &engine,
    )
    .unwrap()
    .inventory;
    let (admitted, order) = crate::required_types::admit_prepared(
        projection.projection.clone(),
        crate::required_types::PreparedInputs {
            source_allocation_roster: None,
            source_order: &projection.source_order,
            body_type_requests: &[],
            initializers: &[],
            maps: &[],
            inventory: &inventory,
            symbols,
            non_text_types: &[],
        },
    )
    .unwrap();
    crate::class_inventory::contribute(&admitted, symbols, &order, &mut inventory).unwrap();
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    materialize_types(&mut image, &admitted, &tables, symbols).unwrap();
    materialize_members(&mut image, &admitted, &tables, symbols, &NoTypes).unwrap_err()
}
#[test]
fn retained_invalid_gender_binds_current_shifted_origin_and_source_status() {
    let store = ClassProjections::default();
    let first = projection(
        &store,
        "/obj/bad_gender
    gender = \"custom\"
",
    );
    let shifted = projection(
        &store,
        "// shifted

/obj/bad_gender
    gender = \"custom\"
",
    );
    let fresh = projection(
        &ClassProjections::default(),
        "// shifted

/obj/bad_gender
    gender = \"custom\"
",
    );
    assert!(Arc::ptr_eq(&first.fields[0], &shifted.fields[0]));
    let source = |projection: &IssuedProjection| {
        let ProjectionError::SourceError { field, message } = failure(projection) else {
            panic!("expected current source error")
        };
        projection.source_diagnostic(field, message).unwrap()
    };
    let original = source(&first);
    let current = source(&shifted);
    let independent = source(&fresh);
    assert_eq!(original.origin.line, 2);
    assert_eq!(current.origin.line, 4);
    assert_eq!(current.origin.span, independent.origin.span);
    assert_eq!(
        current.origin.semantic_path,
        independent.origin.semantic_path
    );
    assert_eq!(current.message, "invalid gender");
    let rejected = crate::diagnostics::report_source_error(current).unwrap();
    assert_eq!(rejected.kind.exit_code(), 2);
    let mut unbound = shifted.clone();
    unbound.field_placements = Default::default();
    assert!(matches!(failure(&unbound), ProjectionError::Unsupported(_)));
}

#[test]
fn ordinary_uninitialized_and_opaque_fields_do_not_require_source_placements() {
    let projection = projection_with_origins(
        &ClassProjections::default(),
        "/obj/bad_gender\n    var/uninitialized\n    var/opaque = opaque_call()\n",
        false,
    );
    assert!(!projection.fields.is_empty());
    assert!(projection.field_placements.candidates.is_empty());
    assert!(projection.field_placements.locations.is_empty());
}
