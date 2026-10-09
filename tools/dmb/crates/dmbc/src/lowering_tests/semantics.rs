use super::*;

#[test]
fn actual_lazy_frontend_units_are_equal_with_one_or_two_workers() {
    let frontend = frontend("/proc/first()\n    return 1\n/proc/second()\n    return 2\n");
    let one = lower_frontend(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
    );
    let two = lower_frontend(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
    );
    assert!(one.diagnostics.is_empty(), "{:?}", one.diagnostics);
    assert!(two.diagnostics.is_empty(), "{:?}", two.diagnostics);
    assert_eq!(one.units.len(), 2);
    assert_eq!(one.identity_index(), two.identity_index());
    for (a, b) in one.units.iter().zip(&two.units) {
        assert_eq!(a.identity, b.identity);
        assert_eq!(a.origin.source.span, b.origin.source.span);
        assert_eq!(a.code.procedure, b.code.procedure);
    }
}
#[test]
fn startup_admission_filters_declarations_and_preserves_distinct_static_slots() {
    let frontend = frontend("/proc/first()\n    var/static/counter = 1\n    return counter\n/proc/second()\n    var/static/counter = 2\n    return counter\n");
    let ordinary = lower_frontend(&frontend, &Host, &NoParameters, LoweringConfig::default());
    assert!(ordinary.units.is_empty());
    assert_eq!(ordinary.diagnostics.len(), 2);
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup.resolver(&frontend, &Host).unwrap();
    let one = lower_frontend_with_statics(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            max_chunk: 1,
        },
        &startup,
    );
    let two = lower_frontend_with_statics(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        &startup,
    );
    assert!(one.diagnostics.is_empty(), "{:?}", one.diagnostics);
    assert!(two.diagnostics.is_empty(), "{:?}", two.diagnostics);
    assert_eq!(one.units.len(), 2);
    for (a, b) in one.units.iter().zip(&two.units) {
        assert_eq!(a.code.procedure, b.code.procedure);
        assert_eq!(a.code.procedure_statics, b.code.procedure_statics);
        assert_eq!(a.code.procedure_statics.len(), 1);
    }
    assert_ne!(
        one.units[0].code.procedure_statics,
        one.units[1].code.procedure_statics
    );
}
#[test]
fn global_units_use_global_storage_against_the_real_tree() {
    let frontend = frontend("var/counter = 1\n/proc/read()\n    return counter\n");
    // The real pipeline overlays the complete captured procedure-static roster
    // even when this source has no statics. The bare tree deliberately cannot
    // certify absence in the ProcedureStatic query domain.
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let batch = lower_frontend_with_statics(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
    );
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    let body = frontend.body(&frontend.bodies[0]).unwrap();
    let mut bindings = dm_codegen_byond::LowerBindings {
        current_proc_path: Some("/proc/read".into()),
        ..Default::default()
    };
    bindings.globals.insert("counter".into());
    let slot = batch.units[0].code.slots.iter().next().unwrap().1;
    bindings
        .global_variables
        .insert("counter".into(), dm_ir::SymRef::VariableSlot(slot.symbol));
    let reference =
        dm_codegen_byond::compile_simple_proc_with_bindings(&body.children, &bindings).unwrap();
    assert!(batch.units[0]
        .code
        .slots
        .iter()
        .any(
            |(symbol, slot)| *symbol == dm_ir::SymRef::VariableSlot(slot.symbol)
                && slot.owner == dm_ir::SymbolId::of("/")
                && slot.name == dm_ir::SymbolId::of("counter")
        ));
    let mut without_debug = batch.units[0].code.procedure.clone();
    without_debug.code.items.retain(|item| !matches!(item, dm_codegen_byond::Item::Instruction(instruction) if matches!(instruction.opcode,0x84|0x85)));
    assert_eq!(without_debug, reference);
    assert!(!batch.units[0].debug_origins.entries.is_empty());
}
#[test]
fn unsupported_parameter_policy_reports_ordered_source_diagnostics() {
    let frontend=frontend("/proc/first(value as num)\n    return value\n/proc/second(value as text)\n    return value\n");
    let batch = lower_frontend(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
    );
    assert!(batch.units.is_empty());
    assert_eq!(batch.diagnostics.len(), 2);
    assert!(batch.diagnostics[0].origin.line < batch.diagnostics[1].origin.line);
    assert!(batch
        .diagnostics
        .iter()
        .all(|error| error.message.contains("parameter ABI")));
    assert!(batch
        .diagnostics
        .iter()
        .all(|error| error.kind == DiagnosticKind::UnsupportedModel));
}
#[test]
fn included_macro_failures_report_statement_lines_in_worker_order() {
    struct Included;
    impl dm_preprocess::SourceProvider for Included {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name| name.to_str()) {
                Some("project.dme") => Ok("#include \"body.dm\"\n".into()),
                Some("body.dm") => Ok("#define BAD missing_call()\n/proc/first()\n    if(1)\n        return BAD\n/proc/second()\n    return BAD\n".into()),
                _ => Err("unexpected source".into()),
            }
        }
    }
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Included, &BTreeMap::new(), 1).unwrap();
    let one = lower_frontend(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 1,
            ..Default::default()
        },
    );
    let two = lower_frontend(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
    );
    assert!(one.units.is_empty());
    assert_eq!(one.diagnostics.len(), 2);
    assert_eq!(
        one.diagnostics
            .iter()
            .map(|diagnostic| diagnostic.origin.line)
            .collect::<Vec<_>>(),
        vec![4, 6]
    );
    for (left, right) in one.diagnostics.iter().zip(&two.diagnostics) {
        assert!(left.origin.semantic_path.ends_with("body.dm"));
        assert_eq!(left.kind, DiagnosticKind::UnsupportedModel);
        assert_eq!(left.kind, right.kind);
        assert_eq!(left.origin.span, right.origin.span);
        assert_eq!(left.origin.semantic_path, right.origin.semantic_path);
        assert_eq!(left.origin.line, right.origin.line);
        assert_eq!(
            left.origin.encounter_ordinal,
            right.origin.encounter_ordinal
        );
        assert_eq!(left.origin.include_chain, right.origin.include_chain);
        assert_eq!(left.message, right.message);
    }
}
#[test]
fn included_macro_and_loop_bodies_keep_actual_source_debug_origins() {
    struct Included;
    impl dm_preprocess::SourceProvider for Included {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name|name.to_str()) {
                Some("project.dme") => Ok("#include \"body.dm\"\n".into()),
                Some("body.dm") => Ok("#define VALUE 7\n/proc/p()\n    var/x = 0\n    while(x < 1)\n        x++\n    return VALUE\n".into()),
                _ => Err("unexpected source".into()),
            }
        }
    }
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Included, &BTreeMap::new(), 1).unwrap();
    let batch = lower_frontend(&frontend, &Host, &NoParameters, LoweringConfig::default());
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    assert_eq!(batch.units.len(), 1);
    let entries = &batch.units[0].debug_origins.entries;
    assert!(entries
        .iter()
        .any(|origin| origin.semantic_path.ends_with("body.dm") && origin.line == 5));
    assert!(entries
        .iter()
        .any(|origin| origin.semantic_path.ends_with("body.dm") && origin.line == 6));
    assert!(batch.require_production_abi().is_err());
}
#[test]
fn captured_policy_prepares_guarded_settings_and_authoritative_layout() {
    use crate::procedure_policy::{
        CapturedConstantEvaluator, CapturedInheritedFacts, CapturedProcedurePolicy, InheritedLayout,
    };
    use dm_codegen_byond::procedure_abi::{AbiError, Category};
    struct Facts;
    impl CapturedInheritedFacts for Facts {
        fn inherited(&self, _: &AbiContext<'_>) -> Result<InheritedLayout, AbiError> {
            Ok(InheritedLayout::Fresh)
        }
    }
    impl CapturedConstantEvaluator for Facts {
        fn evaluate(
            &self,
            expression: &dm_ir::SymbolicExpression,
            context: &AbiContext<'_>,
        ) -> Result<dm_ir::SemanticValue, AbiError> {
            match expression.source_text(context.symbols).as_deref() {
                Some("0") => Ok(dm_ir::SemanticValue::NumberBits(0f32.to_bits())),
                Some("1") => Ok(dm_ir::SemanticValue::NumberBits(1f32.to_bits())),
                Some("null") => Ok(dm_ir::SemanticValue::Null),
                _ => Err(AbiError("uncaptured constant".into())),
            }
        }
    }
    let frontend=frontend("/proc/p(value as num | null)\n    if(0)\n        set hidden = 1\n    else\n        set category = null\n    return value\n");
    let facts = Facts;
    let policy = CapturedProcedurePolicy {
        evaluator: &facts,
        inherited: &facts,
        resource_search_context: None,
    };
    let batch = lower_frontend(&frontend, &Host, &policy, LoweringConfig::default());
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    batch.require_production_abi().unwrap();
    let abi = batch.units[0].abi.as_ref().unwrap();
    assert_eq!(abi.layout.category, Category::Null);
    // DM set declarations apply lexically even inside an untaken if branch.
    assert_eq!(abi.layout.flags, 0x25);
    assert_eq!(batch.units[0].code.procedure.argument_type_flags, [136]);
    let helper_frontend = self::frontend("/proc/source(value in list(value))\n    return value\n");
    let helpers = lower_frontend(&helper_frontend, &Host, &policy, LoweringConfig::default());
    assert!(helpers.diagnostics.is_empty(), "{:?}", helpers.diagnostics);
    helpers.require_production_abi().unwrap();
    assert_eq!(helpers.units[0].source_helpers.len(), 1);
    let helper = &helpers.units[0].source_helpers[0];
    assert_eq!(helper.owner, helpers.units[0].identity);
    assert_eq!(helper.argument, 0);
    assert!(helper.code.procedure.argument_names.is_empty());
    assert_eq!(helper.debug_origins.entries[0].line, 1);
    // The wire retains executable helpers but obtains today's header/frame and origin.
    let startup = crate::startup::capture(&helper_frontend).unwrap();
    let host = startup.resolver(&helper_frontend, &Host).unwrap();
    let root = std::env::temp_dir().join(format!(
        "dmbc-private-helper-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::with_disk(11, cache.snapshot().unwrap());
    let cold = lower_frontend_with_memo(
        &helper_frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
    assert_eq!(
        memo.counts
            .unsupported_disk
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    cache.publish(&memo.take_pending()).unwrap();
    let moved = self::frontend("\n/proc/source(value in list(value))\n    return value\n");
    let moved_startup = crate::startup::capture(&moved).unwrap();
    let moved_host = moved_startup.resolver(&moved, &Host).unwrap();
    let disk = crate::lowering_memo::ProcedureMemo::with_disk(11, cache.snapshot().unwrap());
    let warm = lower_frontend_with_memo(
        &moved,
        &moved_host,
        &policy,
        LoweringConfig::default(),
        &moved_startup,
        &disk,
    );
    assert!(warm.diagnostics.is_empty(), "{:?}", warm.diagnostics);
    assert_eq!(
        disk.counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
    assert_eq!(
        warm.units[0].source_helpers[0].code.procedure,
        cold.units[0].source_helpers[0].code.procedure
    );
    assert_eq!(
        warm.units[0].source_helpers[0].debug_origins.entries[0].line,
        2
    );
    drop(disk);
    drop(memo);
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();

    assert!(helper.code.procedure.code.items.iter().any(|item| matches!(item,dm_codegen_byond::Item::Instruction(instruction) if instruction.operands.iter().any(|word|matches!(word,dm_codegen_byond::Word::Variable(dm_codegen_byond::VariableWord::Arg(0)))))));
}
#[test]
fn empty_static_inventory_skips_only_actual_body_without_stored_qualifiers() {
    let frontend = frontend(
        "/proc/p()\n    var/local = 1\n    if(local)\n        local++\n    return local\n",
    );
    let startup = crate::startup::capture(&frontend).unwrap();
    assert!(startup.procedures()[0].1.declarations.is_empty());
    let ordinary = lower_frontend(&frontend, &Host, &NoParameters, LoweringConfig::default());
    let captured = lower_frontend_with_statics(
        &frontend,
        &Host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
    );
    assert!(ordinary.diagnostics.is_empty());
    assert!(captured.diagnostics.is_empty());
    assert_eq!(
        ordinary.units[0].code.procedure,
        captured.units[0].code.procedure
    );
    struct Injected;
    impl AbiPolicy for Injected {
        fn inputs(
            &self,
            _: UnitIdentity,
            _: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            Ok(ProcedureInputs::default())
        }
        fn prepare(
            &self,
            _: &ProcedureMetadata,
            parsed: &dm_syntax::Item,
            _: &AbiContext<'_>,
        ) -> Result<PreparedUnit, String> {
            let mut prepared = PreparedUnit::local_only(ProcedureInputs::default(), parsed);
            let injected =
                dm_syntax::parse("/proc/injected()\n    if(1)\n        var/static/cache = 1\n");
            prepared
                .executable_body
                .insert(0, injected.items[0].children[0].clone());
            Ok(prepared)
        }
    }
    let injected = lower_frontend_with_statics(
        &frontend,
        &Host,
        &Injected,
        LoweringConfig::default(),
        &startup,
    );
    assert!(injected.units.is_empty());
    assert_eq!(injected.diagnostics.len(), 1);
    assert!(injected.diagnostics[0]
        .message
        .contains("startup inventory differs"));
}
#[test]
fn procedure_memo_publisher_flushes_small_bounded_batches_without_dropping_population() {
    struct Many(String);
    impl dm_preprocess::SourceProvider for Many {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    let source = (0..64)
        .map(|index| format!("/proc/p{index}()\n    return {index}\n"))
        .collect::<String>();
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Many(source), &BTreeMap::new(), 1)
            .unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let root = std::env::temp_dir().join(format!(
        "dmbc-publisher-memo-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let cache = Arc::new(dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap());
    let publisher = Arc::clone(&cache);
    let memo = crate::lowering_memo::ProcedureMemo::with_disk_limits(
        71,
        cache.snapshot().unwrap(),
        crate::lowering_memo::MemoLimits {
            pending_bytes: 2048,
            resident_bytes: 1,
        },
    )
    .with_publisher(Arc::new(move |records| {
        publisher
            .publish(&records)
            .map(|_| ())
            .map_err(|error| error.to_string())
    }));
    let cold = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        &startup,
        &memo,
    );
    assert_eq!(cold.units.len(), 64);
    assert!(cold.diagnostics.is_empty());
    let pending = memo.take_pending();
    if !pending.is_empty() {
        cache.publish(&pending).unwrap();
    }
    assert_eq!(
        memo.counts
            .pending_dropped
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    assert_eq!(
        memo.counts
            .publication_failed
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    assert!(
        memo.counts
            .published_records
            .load(std::sync::atomic::Ordering::Relaxed)
            > 0
    );
    let restarted = crate::lowering_memo::ProcedureMemo::with_disk(71, cache.snapshot().unwrap());
    let disk = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &restarted,
    );
    assert_eq!(
        restarted
            .counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        64
    );
    for (cold, disk) in cold.units.iter().zip(&disk.units) {
        assert_eq!(cold.code.procedure, disk.code.procedure);
    }
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn procedure_memo_frozen_preparation_hits_without_prelookup_body_parse() {
    use crate::driver_facts::{prepare_pinned_source_abi, FrozenPreparedPolicy};
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source("/proc/p()\n    set name = \"Display\"\n    var/local = 7\n    return local\n"),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let abi = prepare_pinned_source_abi(&frontend, &engine, &host, None, 1).unwrap();
    assert!(
        abi.prepared.diagnostics.is_empty(),
        "{:?}",
        abi.prepared.diagnostics
    );
    let policy = FrozenPreparedPolicy::new(&frontend, &abi.prepared).unwrap();
    // Production preparation moves the issued body while preserving exact
    // settings/ABI and the original authenticated helper/debug header.
    let body = &frontend.bodies[0];
    let identity = crate::lowering::source_unit_identity(&frontend, body)
        .unwrap()
        .identity;
    let metadata = frontend
        .snapshot
        .tree
        .member(body.member)
        .unwrap()
        .metadata
        .procedure
        .as_ref()
        .unwrap();
    let context = AbiContext {
        identity,
        symbols: startup.plan().symbols.as_ref(),
        origin: &body.source,
        resolver: &host,
    };
    let parsed = frontend.parse_body(body).unwrap();
    let header_ptr = parsed.item().header.as_ptr();
    let local_ptr = parsed.item().children[1].header.as_ptr();
    let borrowed = policy
        .prepare_captured(metadata, &parsed, &context)
        .unwrap();
    let (owned, header) = policy
        .prepare_owned_captured(metadata, parsed, &context)
        .unwrap();
    assert_eq!(owned.executable_body, borrowed.executable_body);
    assert_eq!(owned.executable_body[0].header.as_ptr(), local_ptr);
    assert_eq!(header.header.as_ptr(), header_ptr);
    assert!(header.children.is_empty());
    assert!(std::sync::Arc::ptr_eq(
        owned.abi.as_ref().unwrap(),
        borrowed.abi.as_ref().unwrap(),
    ));

    let root = std::env::temp_dir().join(format!(
        "dmbc-issued-preparation-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::with_disk(
        abi.policy_identity,
        cache.snapshot().unwrap(),
    );
    let cold = lower_frontend_with_memo(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
    let warm = lower_frontend_with_memo(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert!(warm.diagnostics.is_empty(), "{:?}", warm.diagnostics);
    assert_eq!(cold.units[0].code.procedure, warm.units[0].code.procedure);
    assert_eq!(cold.units[0].debug_origins, warm.units[0].debug_origins);
    assert_eq!(
        memo.counts
            .issued_preparations
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert_eq!(
        memo.counts
            .parsed_preparations
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    assert_eq!(
        memo.counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
    cache.publish(&memo.take_pending()).unwrap();
    let disk = crate::lowering_memo::ProcedureMemo::with_disk(
        abi.policy_identity,
        cache.snapshot().unwrap(),
    );
    let disk_warm = lower_frontend_with_memo(
        &frontend,
        &host,
        &policy,
        LoweringConfig::default(),
        &startup,
        &disk,
    );
    assert!(
        disk_warm.diagnostics.is_empty(),
        "{:?}",
        disk_warm.diagnostics
    );
    assert_eq!(
        disk_warm.units[0].code.procedure,
        cold.units[0].code.procedure
    );
    assert_eq!(
        disk.counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
    assert_eq!(
        disk.counts
            .parsed_preparations
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    drop(disk);
    drop(memo);
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
    let custom_frontend = self::frontend("/proc/custom()\n    return 7\n");
    let custom_startup = crate::startup::capture(&custom_frontend).unwrap();
    let custom_host = custom_startup
        .resolver(&custom_frontend, custom_frontend.snapshot.tree.as_ref())
        .unwrap();
    let custom = crate::lowering_memo::ProcedureMemo::new(abi.policy_identity);
    let custom_cold = lower_frontend_with_memo(
        &custom_frontend,
        &custom_host,
        &NoParameters,
        LoweringConfig::default(),
        &custom_startup,
        &custom,
    );
    assert!(custom_cold.diagnostics.is_empty());
    assert_eq!(
        custom
            .counts
            .issued_preparations
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    assert_eq!(
        custom
            .counts
            .parsed_preparations
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
}
