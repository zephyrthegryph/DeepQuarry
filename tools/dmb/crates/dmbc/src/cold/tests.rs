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
        &host,
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
        .position(|class| image.string(class.path_string_id()) == Some(b"/datum/demo".as_slice()))
        .unwrap();
    let declarations = image.class_variable_declarations(class).unwrap();
    assert!(declarations.iter().any(|(id, _)| {
        let record = &image.variables[*id as usize];
        image.string(record.name) == Some(b"value".as_slice())
            && record.kind == 42
            && record.value == 7f32.to_bits()
    }));
    let preset = declarations
        .iter()
        .find_map(|(id, _)| {
            let record = &image.variables[*id as usize];
            (image.string(record.name) == Some(b"preset".as_slice())).then_some(record)
        })
        .unwrap();
    assert_eq!(
        preset.kind, 41,
        "modified default must remain a stored descriptor"
    );
    assert!((preset.value as usize) < image.instances.len());
    assert_eq!(
        image.classes[class].lists_and_procs[2],
        u32::from(u16::MAX),
        "stored modified defaults must not add a class runtime assignment"
    );
    assert!(
        image
            .procs
            .iter()
            .any(|proc| image.string(proc.strings[0]) == Some(b"/datum/demo/proc/read".as_slice()))
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
        fn tag(&self, _: dm_ir::SymbolId) -> Result<u8, crate::class_projection::ProjectionError> {
            Err(crate::class_projection::ProjectionError::Unsupported(
                "no type defaults".into(),
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
        pure_calls: None,
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
            byond_dmb::bytecode::Operand::Variable(byond_dmb::operands::Variable::Global(slot)) => {
                Some(slot)
            }
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
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
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
