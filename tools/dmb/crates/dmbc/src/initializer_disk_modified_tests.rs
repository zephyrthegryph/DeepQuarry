//! Modified-only continuation transport uses the ordinary typed codec/core.
use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymRef, SymbolId};

#[test]
fn modified_only_disk_requires_exact_policy_runtime_and_complete_current_roots() {
    let root = Temp::new();
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("modified.dme"),
        &Source("/datum/example\n    var/value = 0\n"),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let (host, _) = crate::request_runner::runner_facts::prepare(&frontend, &engine).unwrap();
    let symbols = frontend.snapshot.tree.shared_symbols();
    let owner = SymbolId::of("/datum/example");
    let lexical = SymbolId::of("/");
    let fields = vec![(
        "value".into(),
        dm_syntax::parse_expression("7").expr.unwrap(),
    )];
    let descriptor =
        dm_ir::ModifiedInstance::capture_with_policy(owner, lexical, None, &fields, |_| None, None)
            .unwrap();
    let key = receipts::Binding::modified(
        SymRef::Instance(SymbolId::of(&descriptor.alias())),
        &descriptor,
        None,
    );
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    let disk = Arc::new(LazyDisk::new(root.0.clone()));
    let writer = Transport::new(Arc::clone(&disk), None, 37, true);
    writer.configure(Some(crate::initializer_policy::ParallelEvaluator {
        factory: &evaluator,
        engine: None,
    }));
    let recorder = crate::lowering_memo::RecordingResolver::new(&host);
    assert!(matches!(
        recorder.resolve(Q::Ancestry(lexical)),
        M::Symbols(_)
    ));
    assert_eq!(recorder.resolve(Q::RuntimeType(owner)), M::Symbol(owner));
    struct Debug;
    impl dm_codegen_byond::DebugSourceProvider for Debug {
        fn entry_ordinal(&self) -> Result<u32, String> {
            Ok(0)
        }
        fn ordinal(&self, index: usize) -> Result<u32, String> {
            u32::try_from(index + 1).map_err(|e| e.to_string())
        }
    }
    let code = dm_codegen_byond::initializer::lower_modified_assignments(
        &fields,
        owner,
        dm_codegen_byond::initializer::InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: Some(&Debug),
        },
        &recorder,
    )
    .unwrap();
    let refs = vec![&fields[0].1];
    let proof = b"modified-no-pure-calls-v1";
    writer.stage_with_modified_policy(&key, &refs, &recorder.reads(), &code, Some(proof));
    assert_eq!(disk.finish_batch().unwrap().records, 1);
    let reader = Transport::new(Arc::new(LazyDisk::new(root.0.clone())), None, 37, false);
    reader.configure(Some(crate::initializer_policy::ParallelEvaluator {
        factory: &evaluator,
        engine: None,
    }));
    let (warm, reads, recipes) = reader
        .lookup_with_modified_policy(&key, &refs, &host, &symbols, Some(proof))
        .expect("exact modified-only recipe must replay");
    assert!(recipes.is_empty());
    assert!(crate::lowering_memo_wire::verification_code_equal(
        &code, &warm
    ));
    assert!(reads.iter().any(|r| r.query == Q::RuntimeType(owner)));
    assert!(reader
        .lookup_with_modified_policy(&key, &refs, &host, &symbols, None)
        .is_none());
    assert!(reader
        .lookup_with_modified_policy(&key, &refs, &host, &symbols, Some(b"different provider"))
        .is_none());
    assert!(reader
        .lookup_with_modified_policy(&key, &[], &host, &symbols, Some(proof))
        .is_none());
    let changed = dm_syntax::parse_expression("9").expr.unwrap();
    assert!(reader
        .lookup_with_modified_policy(&key, &[&changed], &host, &symbols, Some(proof))
        .is_none());
    let wrong_runtime = receipts::Binding {
        key: Arc::clone(&key.key),
        inputs: Arc::new(receipts::Inputs::Modified {
            canonical: Arc::from(descriptor.canonical_bytes()),
            policy: None,
            lexical_owner: lexical,
            runtime_type: SymbolId::of("/datum/other"),
            field_count: fields.len(),
            resource_context: None,
        }),
    };
    assert!(reader
        .lookup_with_modified_policy(&wrong_runtime, &refs, &host, &symbols, Some(proof))
        .is_none());
    let captured = dm_codegen_byond::lower_resolver::CapturedModifiedInstance {
        descriptor: descriptor.clone(),
        field_origins: vec![Some(0)],
        origin: Some(0),
        source_span: None,
    };
    let reference = SymRef::Instance(SymbolId::of(&descriptor.alias()));
    let old_origins = crate::debug_sources::DebugOrigins {
        entries: vec![crate::debug_sources::DebugOrigin {
            semantic_path: "old.dm".into(),
            line: 3,
        }],
    };
    let current_origins = crate::debug_sources::DebugOrigins {
        entries: vec![crate::debug_sources::DebugOrigin {
            semantic_path: "moved.dm".into(),
            line: 19,
        }],
    };
    let store = crate::initializer_lowering::InitializerFragments::default()
        .with_disk_transport(Arc::clone(&reader));
    let current = [(reference, captured.clone(), current_origins)];
    let warm_collection = crate::modified_initializers::collect_owned_prepared_retained(
        std::iter::empty(),
        std::iter::empty(),
        &current,
        &symbols,
        &host,
        None,
        Some(&store),
    )
    .unwrap();
    let fresh_collection = crate::modified_initializers::collect_with_defaults(
        std::iter::empty(),
        &current,
        &symbols,
        &host,
        None,
    )
    .unwrap();
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    assert_eq!(
        warm_collection.artifacts[0].debug_origins,
        fresh_collection.artifacts[0].debug_origins
    );
    assert!(crate::lowering_memo_wire::verification_code_equal(
        &warm_collection.artifacts[0].code,
        &fresh_collection.artifacts[0].code
    ));
    assert_ne!(warm_collection.artifacts[0].debug_origins.as_ref(), &old_origins);
    let nested = dm_syntax::parse_expression("/datum/example{value=11}")
        .expr
        .unwrap();
    let nested_fields = vec![("value".into(), nested)];
    let nested_descriptor = dm_ir::ModifiedInstance::capture_with_policy(
        owner,
        lexical,
        None,
        &nested_fields,
        |_| None,
        None,
    )
    .unwrap();
    let nested_key = receipts::Binding::modified(
        SymRef::Instance(SymbolId::of(&nested_descriptor.alias())),
        &nested_descriptor,
        None,
    );
    let nested_recorder = crate::lowering_memo::RecordingResolver::new(&host);
    nested_recorder.resolve(Q::Ancestry(lexical));
    nested_recorder.resolve(Q::RuntimeType(owner));
    let mut nested_code = dm_codegen_byond::initializer::lower_modified_assignments(
        &nested_fields,
        owner,
        dm_codegen_byond::initializer::InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: Some(&Debug),
        },
        &nested_recorder,
    )
    .unwrap();
    assert_eq!(nested_code.modified_instances.len(), 1);
    let modified = nested_code
        .modified_instances
        .iter()
        .map(|(reference, capture)| {
            let evidence = crate::modified_initializers::ExpressionRecipe::from_capture(
                *reference,
                capture,
                &nested_fields[0].1,
            )
            .unwrap()
            .disk_evidence()
            .unwrap();
            (0, evidence)
        })
        .collect::<Vec<_>>();
    nested_code.modified_instances.clear();
    let nested_recipe = writer
        .recipe(&nested_key, &[&nested_fields[0].1], Some(proof))
        .unwrap();
    let payload = crate::lowering_memo_wire::initializer::encode_current_program(
        nested_recipe.bytes.clone(),
        true,
        1,
        nested_recipe.mandatory.clone(),
        &nested_recorder.reads(),
        &nested_code,
        modified,
        true,
    )
    .expect("modified-only nested ref uses field ordinal one");
    let decoded = crate::lowering_memo_wire::initializer::decode_bucket(&payload).unwrap();
    assert!(decoded[0].modified_only);
    assert_eq!(decoded[0].modified.len(), 1);
    for duplicate in [false, true] {
        let bad =
            crate::lowering_memo_wire::initializer::corrupt_modified_roster(&payload, duplicate);
        assert!(Transport::current_candidates(&bad, &nested_recipe).is_err());
    }
    // A corrupt mandatory answer is rejected structurally, before any host replay.
    let mut missing_runtime = recorder.reads();
    for read in &mut missing_runtime {
        if read.query == Q::RuntimeType(owner) {
            read.answer = M::Missing;
        }
    }
    let recipe = writer.recipe(&key, &refs, Some(proof)).unwrap();
    assert!(
        crate::lowering_memo_wire::initializer::encode_current_program(
            recipe.bytes,
            true,
            1,
            recipe.mandatory,
            &missing_runtime,
            &code,
            Vec::new(),
            true,
        )
        .is_none()
    );
}
