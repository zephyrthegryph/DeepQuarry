use super::*;
use std::sync::Mutex;
struct Host {
    reads: Mutex<Vec<Q>>,
    answer: fn(Q) -> M,
}
impl Resolver for Host {
    fn resolve(&self, query: Q) -> M {
        self.reads.lock().unwrap().push(query);
        (self.answer)(query)
    }
}
fn lower(
    source: &str,
    inputs: ProcedureInputs,
    symbols: &SymbolTable,
    host: &Host,
) -> Result<ResolverProc, Vec<LowerError>> {
    let ast = dm_syntax::parse(source);
    crate::compile_simple_proc_with_resolver(&ast.items[0].children, &inputs, symbols, host)
}
#[test]
fn typed_list_contexts_query_container_runtime_type() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/list").unwrap();
    let host = Host {
        reads: Mutex::new(Vec::new()),
        answer: |query| match query {
            Q::RuntimeType(id) if id == SymbolId::of("/list") => M::Symbol(id),
            Q::Ancestry(id) if id == SymbolId::of("/list") => M::Symbols(vec![id]),
            other => M::Unsupported(other),
        },
    };
    for source in [
        "/proc/p()\n    var/list/datum/item/values = new()\n    return values\n",
        "/proc/p()\n    var/list/datum/item/values = locate()\n    return values\n",
        "/proc/p(values)\n    values = new()\n    return values\n",
    ] {
        let parameters = source.contains("p(values)");
        let result = lower(
            source,
            ProcedureInputs {
                parameters: if parameters {
                    vec!["values".into()]
                } else {
                    vec![]
                },
                parameter_types: if parameters {
                    std::collections::HashMap::from([("values".into(), "/list/datum/item".into())])
                } else {
                    Default::default()
                },
                ..Default::default()
            },
            &symbols,
            &host,
        );
        assert!(result.is_ok(), "{source}: {:?}", result.err());
    }
    assert!(host
        .reads
        .lock()
        .unwrap()
        .iter()
        .any(|query| matches!(query, Q::RuntimeType(id) if *id == SymbolId::of("/list"))));
}
#[test]
fn known_untyped_field_shadows_global_type_demand() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum/item").unwrap();
    symbols.intern("field").unwrap();
    let host = Host {
        reads: Mutex::new(Vec::new()),
        answer: |query| match query {
            Q::HasMemberVar { name, .. } if name == SymbolId::of("field") => M::Presence(true),
            Q::DeclaredVarType { name, .. } if name == SymbolId::of("field") => {
                M::DeclaredType(None)
            }
            Q::VarStorage { owner, name } if name == SymbolId::of("field") => M::InstanceField {
                declaring_owner: owner,
                name,
            },
            other => M::Unsupported(other),
        },
    };
    let code = lower(
        "/datum/item/proc/p()\n    return new field()\n",
        ProcedureInputs {
            current_type_path: Some("/datum/item".into()),
            ..Default::default()
        },
        &symbols,
        &host,
    );
    assert!(code.is_ok(), "{:?}", code.as_ref().err());
    assert!(!host
        .reads
        .lock()
        .unwrap()
        .iter()
        .any(|query| matches!(query,Q::GlobalVar(name) if *name==SymbolId::of("field"))));
}
#[test]
fn procedure_static_uses_exact_slot_tuple_and_parameter_shadowing() {
    let procedure = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/datum/demo"),
        name: SymbolId::of("read"),
        verb: false,
        occurrence: 1,
    };
    let host = Host {
        reads: Mutex::new(Vec::new()),
        answer: |query| match query {
            Q::ProcedureStatic { procedure, name } if name == SymbolId::of("counter") => {
                M::ProcedureStatic(Arc::new(dm_ir::ProcedureStaticDeclaration {
                    identity: dm_ir::ProcedureStaticIdentity { procedure, name },
                    declared_type: None,
                    modifiers: 1,
                    declared_array: None,
                    initializer: dm_ir::InitializerValue::NoAuthoredValue,
                }))
            }
            Q::ProcedureStatic { .. } => M::Missing,
            other => M::Unsupported(other),
        },
    };
    let code = lower(
        "/proc/read()\n    counter += 1\n    return counter\n",
        ProcedureInputs {
            procedure_identity: Some(procedure),
            ..Default::default()
        },
        &SymbolTable::default(),
        &host,
    )
    .unwrap();
    assert_eq!(code.procedure_statics.len(), 1);
    assert_eq!(
        code.procedure_statics.values().next(),
        Some(&dm_ir::ProcedureStaticIdentity {
            procedure,
            name: SymbolId::of("counter")
        })
    );
    let shadowed = lower(
        "/proc/read(counter)\n    return counter\n",
        ProcedureInputs {
            procedure_identity: Some(procedure),
            parameters: vec!["counter".into()],
            ..Default::default()
        },
        &SymbolTable::default(),
        &host,
    )
    .unwrap();
    assert!(shadowed.procedure_statics.is_empty());
}
#[test]
fn locals_need_no_project_snapshot_and_globals_query_host() {
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::GlobalVar(id) if id == SymbolId::of("counter") => M::Presence(true),
            Q::VarStorage { owner, name }
                if owner == SymbolId::of("/") && name == SymbolId::of("counter") =>
            {
                M::Slot {
                    symbol: SymbolId::of("var/counter"),
                    owner,
                    name,
                }
            }
            _ => M::Unsupported(query),
        },
    };
    let mut symbols = SymbolTable::default();
    symbols.intern("/").unwrap();
    symbols.intern("counter").unwrap();
    assert!(lower(
        "/proc/p(value)\n    return value\n",
        ProcedureInputs {
            parameters: vec!["value".into()],
            ..Default::default()
        },
        &symbols,
        &host
    )
    .is_ok());
    assert!(host.reads.lock().unwrap().is_empty());
    assert!(lower(
        "/proc/p()\n    return counter\n",
        Default::default(),
        &symbols,
        &host
    )
    .is_ok());
    assert!(host
        .reads
        .lock()
        .unwrap()
        .contains(&Q::GlobalVar(SymbolId::of("counter"))));
    assert!(host.reads.lock().unwrap().contains(&Q::VarStorage {
        owner: SymbolId::of("/"),
        name: SymbolId::of("counter"),
    }));
}
#[test]
fn unsupported_queries_cannot_become_dynamic_fallback_success() {
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: M::Unsupported,
    };
    let errors = lower(
        "/proc/p()\n    return missing.value\n",
        Default::default(),
        &SymbolTable::default(),
        &host,
    )
    .err()
    .unwrap();
    assert!(errors
        .iter()
        .any(|error| error.reason.contains("unsupported semantic query")));
}
#[test]
fn captured_resource_context_is_demanded_without_filesystem_reads() {
    let mut symbols = SymbolTable::default();
    symbols.intern("assets/icon.dmi").unwrap();
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::ResourceIn {
                path,
                search_context: 77,
            } if path == SymbolId::of("icon.dmi") => M::Resource {
                path: SymbolId::of("assets/icon.dmi"),
                content: 123,
            },
            _ => M::Unsupported(query),
        },
    };
    let result = lower(
        "/proc/p()\n    return 'icon.dmi'\n",
        ProcedureInputs {
            resource_search_context: Some(77),
            ..Default::default()
        },
        &symbols,
        &host,
    )
    .unwrap();
    assert_eq!(
        result.resources.get(&SymbolId::of("assets/icon.dmi")),
        Some(&123)
    );
    assert_eq!(result.procedure.resources, [123]);
}
#[test]
fn modified_alias_is_issued_as_instance_and_ordinary_type_stays_class() {
    let mut symbols = SymbolTable::default();
    for path in ["/datum/modified", "/datum/ordinary", "/datum"] {
        symbols.intern(path).unwrap();
    }
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::RuntimeType(id) if id == SymbolId::of("/datum/modified") => {
                M::Symbol(SymbolId::of("/datum"))
            }
            Q::RuntimeType(id) if id == SymbolId::of("/datum/ordinary") => M::Symbol(id),
            Q::Ancestry(id) if id == SymbolId::of("/datum") => M::Symbols(vec![id]),
            Q::Ancestry(id) if id == SymbolId::of("/datum/ordinary") => {
                M::Symbols(vec![id, SymbolId::of("/datum")])
            }
            _ => M::Unsupported(query),
        },
    };
    let result = lower(
        "/proc/p()\n    return list(/datum/modified,/datum/ordinary)\n",
        Default::default(),
        &symbols,
        &host,
    )
    .unwrap();
    assert_eq!(
        result.instances.get(&SymbolId::of("/datum/modified")),
        Some(&ResolvedInstance {
            alias: SymbolId::of("/datum/modified"),
            runtime_type: SymbolId::of("/datum")
        })
    );
    assert_eq!(
        result.procedure.instance_paths,
        [SymbolId::of("/datum/modified")]
    );
    assert_eq!(
        result.procedure.class_paths,
        [SymbolId::of("/datum/ordinary")]
    );
    assert!(result.procedure.code.items.iter().any(|item|matches!(item,crate::Item::Instruction(instruction) if instruction.operands.iter().any(|word|matches!(word,crate::Word::Value(crate::ValueWord::Instance(path)) if *path==SymbolId::of("/datum/modified"))))));
}
#[test]
fn type_presence_cannot_substitute_for_unknown_runtime_alias_coverage() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum/alias").unwrap();
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::Type(id) => M::Symbol(id),
            _ => M::Unsupported(query),
        },
    };
    let errors = lower(
        "/proc/p()\n    return /datum/alias\n",
        Default::default(),
        &symbols,
        &host,
    )
    .err()
    .unwrap();
    assert!(errors
        .iter()
        .any(|error| error.reason.contains("RuntimeType")));
}
#[test]
fn builtin_world_binding_bypasses_constant_preflight_and_keeps_lexical_shadows() {
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: M::Unsupported,
    };
    for (source, inputs, expected) in [
        (
            "/world/proc/p()\n    return world\n",
            ProcedureInputs {
                current_type_path: Some("/world".into()),
                ..Default::default()
            },
            crate::VariableWord::World,
        ),
        (
            "/proc/p(world)\n    return world\n",
            ProcedureInputs {
                parameters: vec!["world".into()],
                ..Default::default()
            },
            crate::VariableWord::Arg(0),
        ),
        (
            "/proc/p()\n    var/world = null\n    return world\n",
            ProcedureInputs::default(),
            crate::VariableWord::Local(0),
        ),
    ] {
        let code = lower(source, inputs, &SymbolTable::default(), &host).unwrap();
        assert!(code.procedure.code.items.iter().any(|item| matches!(item,
            crate::Item::Instruction(instruction) if instruction.operands.contains(&crate::Word::Variable(expected.clone())))));
    }
    assert!(host.reads.lock().unwrap().is_empty());
}
#[test]
fn world_receiver_call_uses_builtin_type_without_outer_field_queries() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/world").unwrap();
    symbols.intern("Genesis").unwrap();
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::RuntimeType(owner) if owner == SymbolId::of("/world") => M::Symbol(owner),
            Q::HasMemberProc { owner, name }
                if owner == SymbolId::of("/world") && name == SymbolId::of("Genesis") =>
            {
                M::Presence(true)
            }
            Q::Proc {
                owner,
                name,
                verb: false,
            } if owner == SymbolId::of("/world") && name == SymbolId::of("Genesis") => {
                M::IntrinsicProc {
                    declaring_owner: owner,
                    name,
                }
            }
            Q::Proc { verb: true, .. } => M::Missing,
            other => M::Unsupported(other),
        },
    };
    let result = lower(
        "/world/proc/p()\n    return world.Genesis()\n",
        ProcedureInputs {
            current_type_path: Some("/world".into()),
            ..Default::default()
        },
        &symbols,
        &host,
    );
    assert!(result.is_ok(), "{:?}", result.err());
    assert!(!host.reads.lock().unwrap().iter().any(|query| matches!(
        query,
        Q::HasMemberVar { .. } | Q::VarStorage { .. } | Q::GlobalVar(_)
    )));
}
#[test]
fn args_receiver_type_preserves_lexical_shadows_without_outer_variable_queries() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/list").unwrap();
    symbols.intern("Copy").unwrap();
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::RuntimeType(owner) if owner == SymbolId::of("/list") => M::Symbol(owner),
            Q::HasMemberProc { owner, name }
                if owner == SymbolId::of("/list") && name == SymbolId::of("Copy") =>
            {
                M::Presence(true)
            }
            Q::Proc {
                owner,
                name,
                verb: false,
            } if owner == SymbolId::of("/list") && name == SymbolId::of("Copy") => {
                M::IntrinsicProc {
                    declaring_owner: owner,
                    name,
                }
            }
            Q::Proc { verb: true, .. } => M::Missing,
            other => M::Unsupported(other),
        },
    };
    for (source, inputs, variable) in [
        (
            "/datum/demo/proc/p()\n    return args.Copy(3)\n",
            ProcedureInputs {
                current_type_path: Some("/datum/demo".into()),
                ..Default::default()
            },
            crate::VariableWord::Args,
        ),
        (
            "/proc/p(args)\n    return args.Copy(3)\n",
            ProcedureInputs {
                parameters: vec!["args".into()],
                ..Default::default()
            },
            crate::VariableWord::Arg(0),
        ),
        (
            "/proc/p()\n    var/args = null\n    return args.Copy(3)\n",
            ProcedureInputs::default(),
            crate::VariableWord::Local(0),
        ),
    ] {
        let code = lower(source, inputs, &symbols, &host).unwrap();
        assert!(code.procedure.code.items.iter().any(|item| matches!(item,
            crate::Item::Instruction(instruction) if instruction.operands.iter().any(|word| matches!(word,
                crate::Word::Variable(crate::VariableWord::SetCache(owner, _)) if owner.as_ref() == &variable)))));
    }
    assert!(!host.reads.lock().unwrap().iter().any(|query| matches!(
        query,
        Q::HasMemberVar { .. } | Q::VarStorage { .. } | Q::GlobalVar(_) | Q::DeclaredVarType { .. }
    )));
}
#[test]
fn positive_member_call_does_not_require_unrelated_global_proc_absence() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/icon").unwrap();
    symbols.intern("Turn").unwrap();
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::HasMemberProc { owner, name }
                if owner == SymbolId::of("/icon") && name == SymbolId::of("Turn") =>
            {
                M::Presence(true)
            }
            Q::Proc {
                owner,
                name,
                verb: false,
            } if owner == SymbolId::of("/icon") && name == SymbolId::of("Turn") => {
                M::IntrinsicProc {
                    declaring_owner: owner,
                    name,
                }
            }
            Q::Proc { verb: true, .. } => M::Missing,
            other => M::Unsupported(other),
        },
    };
    let code = lower(
        "/icon/proc/p()\n    Turn(90)\n",
        ProcedureInputs {
            current_type_path: Some("/icon".into()),
            ..Default::default()
        },
        &symbols,
        &host,
    );
    assert!(code.is_ok(), "{:?}", code.err());
    assert!(!host
        .reads
        .lock()
        .unwrap()
        .iter()
        .any(|query| matches!(query, Q::GlobalProc(_))));
}
#[test]
fn modified_resource_aliases_share_descriptor_content_after_recorded_queries() {
    let owner = SymbolId::of("/obj/base");
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::RuntimeType(id) if id == SymbolId::of("/obj/base") => M::Symbol(id),
            Q::ResourceIn {
                path,
                search_context: 7,
            } if path == SymbolId::of("one.txt") || path == SymbolId::of("two.txt") => {
                M::Resource { path, content: 99 }
            }
            other => M::Unsupported(other),
        },
    };
    let mut symbols = SymbolTable::default();
    for spelling in ["/obj/base", "one.txt", "two.txt"] {
        symbols.intern(spelling).unwrap();
    }
    let code = lower(
        "/proc/p()\n    . = /obj/base{asset='one.txt'}\n    return (/obj/base{asset='two.txt'})\n",
        ProcedureInputs {
            resource_search_context: Some(7),
            ..Default::default()
        },
        &symbols,
        &host,
    )
    .unwrap();
    assert_eq!(code.modified_instances.len(), 1);
    let descriptor = &code.modified_instances.values().next().unwrap().descriptor;
    assert_eq!(descriptor.runtime_type(), owner);
    assert_eq!(descriptor.resources().values().next().unwrap().content, 99);
    let reads = host.reads.lock().unwrap();
    for path in [SymbolId::of("one.txt"), SymbolId::of("two.txt")] {
        assert!(reads.contains(&Q::ResourceIn {
            path,
            search_context: 7
        }));
    }
}
#[test]
fn modified_literal_captures_ordered_assignments_and_emits_instance_reference() {
    let owner = SymbolId::of("/obj/base");
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::RuntimeType(id) if id == SymbolId::of("/obj/base") => M::Symbol(id),
            Q::Ancestry(id) if id == SymbolId::of("/obj/base") => {
                M::Symbols(vec![id, SymbolId::of("/obj")])
            }
            other => M::Unsupported(other),
        },
    };
    let mut symbols = SymbolTable::default();
    symbols.intern("/obj/base").unwrap();
    symbols.intern("/obj").unwrap();
    let code = lower(
        "/proc/p()\n    return (/obj/base{a=1;a=2;b=list(/obj/base)})\n",
        ProcedureInputs::default(),
        &symbols,
        &host,
    )
    .unwrap();
    let (symbol, captured) = code.modified_instances.iter().next().unwrap();
    assert_eq!(code.modified_instances.len(), 1);
    assert_eq!(captured.descriptor.runtime_type(), owner);
    assert_eq!(
        captured
            .descriptor
            .fields()
            .iter()
            .map(|(name, _)| name.as_str())
            .collect::<Vec<_>>(),
        ["a", "a", "b"]
    );
    let dm_ir::SymRef::Instance(_) = symbol else {
        panic!("wrong identity domain")
    };
    assert!(code.procedure.code.items.iter().any(|item| matches!(item,
        crate::Item::Instruction(instruction) if instruction.operands.iter().any(|word| matches!(word,
            crate::Word::Value(crate::ValueWord::Instance(alias)) if *alias == SymbolId::of(&captured.descriptor.alias()))))));
}
#[test]
fn opaque_intrinsic_field_read_uses_presence_and_storage_only() {
    let mut symbols = SymbolTable::default();
    for text in ["/atom", "name"] {
        symbols.intern(text).unwrap();
    }
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::HasMemberVar { owner, name }
                if owner == SymbolId::of("/atom") && name == SymbolId::of("name") =>
            {
                M::Presence(true)
            }
            Q::VarStorage { owner, name }
                if owner == SymbolId::of("/atom") && name == SymbolId::of("name") =>
            {
                M::InstanceField {
                    declaring_owner: owner,
                    name,
                }
            }
            Q::GlobalVar(_) => M::Missing,
            Q::PredefinedConstant(_) => M::Missing,
            _ => M::Unsupported(query),
        },
    };
    let result = lower(
        "/atom/proc/p()\n    return name\n",
        ProcedureInputs {
            current_type_path: Some("/atom".into()),
            ..Default::default()
        },
        &symbols,
        &host,
    );
    assert!(result.is_ok());
    let reads = host.reads.lock().unwrap();
    assert!(reads
        .iter()
        .any(|query| matches!(query, Q::HasMemberVar { .. })));
    assert!(reads
        .iter()
        .any(|query| matches!(query, Q::VarStorage { .. })));
    assert!(!reads.iter().any(|query| matches!(
        query,
        Q::Var { .. } | Q::StaticVar { .. } | Q::DeclaredVarType { .. }
    )));
}
#[test]
fn assignment_type_is_demanded_only_by_contextual_constructors() {
    let mut symbols = SymbolTable::default();
    for text in ["/atom", "name"] {
        symbols.intern(text).unwrap();
    }
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::HasMemberVar { owner, name }
                if owner == SymbolId::of("/atom") && name == SymbolId::of("name") =>
            {
                M::Presence(true)
            }
            Q::VarStorage { owner, name }
                if owner == SymbolId::of("/atom") && name == SymbolId::of("name") =>
            {
                M::InstanceField {
                    declaring_owner: owner,
                    name,
                }
            }
            _ => M::Unsupported(query),
        },
    };
    for value in ["3", "TRUE ? 3 : 4", "null || 3"] {
        host.reads.lock().unwrap().clear();
        let result = lower(
            &format!("/atom/proc/p()\n    name = {value}\n"),
            ProcedureInputs {
                current_type_path: Some("/atom".into()),
                ..Default::default()
            },
            &symbols,
            &host,
        );
        assert!(result.is_ok(), "{value}: {:?}", result.err());
        assert!(
            !host
                .reads
                .lock()
                .unwrap()
                .iter()
                .any(|q| matches!(q, Q::DeclaredVarType { .. })),
            "{value}"
        );
    }
    for value in [
        "new()",
        "TRUE ? new() : null",
        "null || new()",
        "locate() in list()",
    ] {
        let errors = lower(
            &format!("/atom/proc/p()\n    name = {value}\n"),
            ProcedureInputs {
                current_type_path: Some("/atom".into()),
                ..Default::default()
            },
            &symbols,
            &host,
        )
        .err()
        .unwrap();
        assert!(
            errors
                .iter()
                .any(|error| error.reason.contains("DeclaredVarType")),
            "{value}: {errors:?}"
        );
    }
}
#[test]
fn known_untyped_is_distinct_from_unknown_type_or_storage() {
    let symbols = SymbolTable::default();
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::DeclaredVarType { name, .. } if name == SymbolId::of("known") => {
                M::DeclaredType(None)
            }
            _ => M::Unsupported(query),
        },
    };
    let lookup = ProjectResolver {
        modified_instances: RefCell::new(Default::default()),
        procedure_values: RefCell::new(Default::default()),
        procedure_statics: RefCell::new(Default::default()),
        resolver: &host,
        symbols: &symbols,
        slots: RefCell::new(BTreeMap::new()),
        resources: RefCell::new(BTreeMap::new()),
        instances: RefCell::new(BTreeMap::new()),
        runtime_types: RefCell::new(BTreeMap::new()),
        resource_search_context: None,
    };
    let owner = SymbolId::of("/datum");
    assert_eq!(
        lookup
            .declared_type(Q::DeclaredVarType {
                owner,
                name: SymbolId::of("known")
            })
            .unwrap(),
        None
    );
    assert!(lookup
        .declared_type(Q::DeclaredVarType {
            owner,
            name: SymbolId::of("unknown")
        })
        .is_err());
    assert!(lookup
        .slot(Q::VarStorage {
            owner,
            name: SymbolId::of("unknown")
        })
        .is_err());
}
#[test]
fn positive_member_proc_does_not_require_opposite_namespace_absence() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum/probe").unwrap();
    for name in ["authored", "intrinsic", "verb_only", "unknown"] {
        symbols.intern(name).unwrap();
    }
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::Proc {
                owner,
                name,
                verb: false,
            } if name == SymbolId::of("authored") => M::Member {
                owner,
                name,
                fingerprint: 1,
                data: std::sync::Arc::new(Default::default()),
            },
            Q::Proc {
                owner,
                name,
                verb: false,
            } if name == SymbolId::of("intrinsic") => M::IntrinsicProc {
                declaring_owner: owner,
                name,
            },
            Q::Proc {
                name, verb: false, ..
            } if name == SymbolId::of("verb_only") => M::Missing,
            Q::Proc {
                owner,
                name,
                verb: true,
            } if name == SymbolId::of("verb_only") => M::Member {
                owner,
                name,
                fingerprint: 2,
                data: std::sync::Arc::new(Default::default()),
            },
            Q::ProcedureValue {
                owner,
                name,
                verb,
                formal: true,
            } if name == SymbolId::of("authored") || name == SymbolId::of("verb_only") => {
                M::Value(dm_ir::SemanticValue::Procedure(dm_ir::ProcedureIdentity {
                    owner,
                    name,
                    verb,
                    occurrence: 7,
                }))
            }
            _ => M::Unsupported(query),
        },
    };
    let lookup = ProjectResolver {
        modified_instances: RefCell::new(Default::default()),
        procedure_values: RefCell::new(Default::default()),
        procedure_statics: RefCell::new(Default::default()),
        resolver: &host,
        symbols: &symbols,
        slots: RefCell::new(Default::default()),
        resources: RefCell::new(Default::default()),
        instances: RefCell::new(Default::default()),
        runtime_types: RefCell::new(Default::default()),
        resource_search_context: None,
    };
    assert_eq!(
        lookup.member_proc("/datum/probe", "authored").unwrap(),
        Some(dm_ir::SymRef::Proc {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("authored"),
            occurrence: 7
        })
    );
    assert_eq!(
        lookup.member_proc("/datum/probe", "intrinsic").unwrap(),
        None
    );
    assert_eq!(host.reads.lock().unwrap().len(), 3);
    assert!(host.reads.lock().unwrap().iter().all(|query| matches!(
        query,
        Q::Proc { verb: false, .. }
            | Q::ProcedureValue {
                verb: false,
                formal: true,
                ..
            }
    )));
    assert_eq!(
        lookup.member_proc("/datum/probe", "verb_only").unwrap(),
        Some(dm_ir::SymRef::Verb {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("verb_only"),
            occurrence: 7
        })
    );
    assert!(lookup.member_proc("/datum/probe", "unknown").is_err());
}
#[test]
fn procedure_literal_lowering_keeps_exact_formal_identity_sidecar() {
    let owner = SymbolId::of("/datum/base");
    let name = SymbolId::of("callback");
    let identity = dm_ir::ProcedureIdentity {
        owner,
        name,
        verb: false,
        occurrence: 0,
    };
    let host = Host {
        reads: Mutex::new(vec![]),
        answer: |query| match query {
            Q::ProcedureValue {
                owner: found,
                name: found_name,
                verb: false,
                formal: true,
            } if found == SymbolId::of("/datum/base") && found_name == SymbolId::of("callback") => {
                M::Value(SemanticValue::Procedure(dm_ir::ProcedureIdentity {
                    owner: found,
                    name: found_name,
                    verb: false,
                    occurrence: 0,
                }))
            }
            _ => M::Unsupported(query),
        },
    };
    let parsed = dm_syntax::parse("/proc/p()\n    return list(/datum/base/proc/callback)\n");
    let code = crate::compile_simple_proc_with_resolver(
        &parsed.items[0].children,
        &ProcedureInputs::default(),
        &SymbolTable::default(),
        &host,
    )
    .unwrap();
    assert_eq!(code.procedure_values.len(), 1);
    assert_eq!(code.procedure_values.values().next(), Some(&identity));
    assert_eq!(
        host.reads.lock().unwrap().as_slice(),
        &[Q::ProcedureValue {
            owner,
            name,
            verb: false,
            formal: true
        }]
    );
}
