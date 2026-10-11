use super::*;
use crate::engine::EngineSnapshot;
use dm_tree::frontend::FrontendConfig;
use std::{path::Path, sync::Arc};

#[test]
fn prepared_seal_releases_source_before_byte_identical_composition() {
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let (baseline, sealed, source_tree) = {
        use crate::driver_facts::{self, BoundaryAbi, DriverEvaluator, FrozenPreparedPolicy};
        struct ClassSource;
        impl dm_preprocess::SourceProvider for ClassSource {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok(
                "/datum/demo\n    var/value = 7\n    var/preset = /datum/demo{value=3}\n/datum/demo/proc/read()\n    return value\n"
                    .into(),
            )
            }
        }
        struct NoTypeDefaults;
        impl crate::class_projection::TypeValuePolicy for NoTypeDefaults {
            fn tag(
                &self,
                path: dm_ir::SymbolId,
            ) -> Result<u8, crate::class_projection::ProjectionError> {
                if path == dm_ir::SymbolId::of("/datum/demo") {
                    return Ok(32);
                }
                Err(crate::class_projection::ProjectionError::Unsupported(
                    "fixture has no type defaults".into(),
                ))
            }
        }
        let bytes = include_bytes!("../../../../fixtures/native_template.bin");
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
        // Runtime type interpretation is a captured host policy, not a tree
        // declaration query. Use the same host boundary as production.
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
        );
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &host,
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

        let source_tree = Arc::downgrade(&frontend.snapshot.tree);
        let links = crate::engine_link::capture(bytes, &engine).unwrap();
        let order = crate::type_creation_order::collect(
            &frontend.allocation_ledger,
            &frontend.expanded.text,
            frontend.snapshot.tree.symbols(),
            &links.inventory,
        )
        .unwrap();
        let config = LoweringConfig {
            workers: 2,
            ..Default::default()
        };
        let declarations = || CapturedDeclarationInputs {
            initializers: &evaluator,
            type_values: &NoTypeDefaults,
            resource_search_context: None,
            source_type_order: &order,
            source_allocation_roster: None,
        };
        let baseline = compile_captured_classified_program(
            &frontend,
            &host,
            &policy,
            CapturedLinkInputs {
                engine_bytes: bytes,
                engine: &engine,
                references: &links.references,
                inventory: links.inventory,
            },
            declarations(),
            config,
        )
        .unwrap();
        assert!(baseline.startup.is_some());
        let links = crate::engine_link::capture(bytes, &engine).unwrap();
        let bodies = dm_tree::frontend::BodyArena::new(&frontend);
        let startup = crate::startup::capture_with_executor_and_bodies(
            &frontend,
            &links.inventory.spellings,
            &executor,
            &bodies,
        )
        .unwrap();
        let mut memo = crate::lowering_memo::ProcedureMemo::new(17);
        memo.symbolic = Some(Arc::new(Default::default()));
        let prepared = prepare_with_startup(
            &frontend,
            &host,
            &policy,
            CapturedLinkInputs {
                engine_bytes: bytes,
                engine: &engine,
                references: &links.references,
                inventory: links.inventory,
            },
            declarations(),
            config,
            Vec::new(),
            None,
            &startup,
            None,
            Some(&memo),
            &executor,
            bodies,
            None,
            None,
        )
        .unwrap();
        assert!(memo.symbolic.as_ref().unwrap().retention_stats().records > 0);
        assert_eq!(
            memo.values.admitted_bytes(),
            0,
            "compact symbolic completion must not also retain a rich IR graph"
        );
        let domains = prepared.domains();
        let values = Arc::new(crate::resource_values::PreparedResourceValues::capture(
            &NoTypeDefaults,
            &domains,
        ));
        let sealed = prepared
            .seal(&frontend, Arc::from(bytes.as_slice()), values, None)
            .unwrap();
        (baseline.dmb, sealed, source_tree)
    };
    assert!(
        source_tree.upgrade().is_none(),
        "sealed composition must not retain source tree"
    );
    let owned = sealed.compose(&executor, None).unwrap();
    assert!(owned.startup.is_none());
    assert_eq!(owned.dmb.bytes(), baseline.bytes());
    assert_eq!(owned.dmb.content_hash(), baseline.content_hash());
}
