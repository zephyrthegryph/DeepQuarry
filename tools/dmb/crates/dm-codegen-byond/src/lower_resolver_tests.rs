use super::*;
use std::sync::Mutex;
#[test]
fn missing_nested_modified_type_requires_current_semantic_absence() {
    let mut symbols = SymbolTable::default();
    for name in ["/obj/outer", "/obj/missing", "child", "value"] {
        symbols.intern(name).unwrap();
    }
    for (answer, kind) in [
        (
            (|query| match query {
                Q::RuntimeType(path) if path == SymbolId::of("/obj/missing") => {
                    M::Unsupported(query)
                }
                Q::RuntimeType(path) => M::Symbol(path),
                Q::Type(path) if path == SymbolId::of("/obj/missing") => M::Missing,
                Q::HasMemberVar { .. } => M::Presence(true),
                _ => M::Unsupported(query),
            }) as fn(Q) -> M,
            crate::LowerErrorKind::SourceError,
        ),
        (
            (|query| match query {
                Q::RuntimeType(path) if path != SymbolId::of("/obj/missing") => M::Symbol(path),
                Q::HasMemberVar { .. } => M::Presence(true),
                _ => M::Unsupported(query),
            }) as fn(Q) -> M,
            crate::LowerErrorKind::UnsupportedModel,
        ),
    ] {
        // Lower the current nested descriptor field, where the missing inner
        // runtime type is actually demanded, through the common initializer.
        let ast = dm_syntax::parse_expression("/obj/missing{value=1}")
            .expr
            .unwrap();
        let host = Host {
            reads: Default::default(),
            answer,
        };
        let error = crate::initializer::lower_modified_assignments(
            &[("child".into(), ast)],
            SymbolId::of("/obj/outer"),
            crate::initializer::InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug: None,
            },
            &host,
        )
        .err()
        .unwrap();
        let crate::initializer::InitializerError::Lowering(errors) = error else {
            panic!("typed lowering failure")
        };
        assert_eq!(errors[0].kind, kind);
        assert!(host
            .reads
            .lock()
            .unwrap()
            .contains(&Q::Type(SymbolId::of("/obj/missing"))));
    }
}
pub(super) struct Host {
    pub(super) reads: Mutex<Vec<Q>>,
    pub(super) answer: fn(Q) -> M,
}
impl Resolver for Host {
    fn resolve(&self, query: Q) -> M {
        self.reads.lock().unwrap().push(query);
        (self.answer)(query)
    }
}
pub(super) fn lower(
    source: &str,
    inputs: ProcedureInputs,
    symbols: &SymbolTable,
    host: &Host,
) -> Result<ResolverProc, Vec<LowerError>> {
    let ast = dm_syntax::parse(source);
    crate::compile_simple_proc_with_resolver(&ast.items[0].children, &inputs, symbols, host)
}
#[test]
fn method_native_dispatch_requires_exact_certified_name_and_namespace() {
    struct NativeHost(u8);
    impl Resolver for NativeHost {
        fn resolve(&self, query: Q) -> M {
            let owner = SymbolId::of("/datum/probe");
            let name = SymbolId::of("callback");
            match query {
                Q::HasMemberProc {
                    owner: found,
                    name: selector,
                } if found == owner && selector == name => M::Presence(true),
                Q::Proc {
                    owner: found,
                    name: selector,
                    verb: false,
                } if found == owner && selector == name => M::Member {
                    owner,
                    name,
                    fingerprint: 1,
                    data: Arc::new(Default::default()),
                },
                Q::MethodProcedureValue {
                    owner: found,
                    name: selector,
                    verb: false,
                } if found == owner && selector == name => match self.0 {
                    0 => M::IntrinsicProc {
                        declaring_owner: owner,
                        name,
                    },
                    1 => M::RetainedProc {
                        declaring_owner: owner,
                        name,
                        verb: false,
                        engine_identity: 1,
                        wire_proc: 3,
                    },
                    2 => M::IntrinsicProc {
                        declaring_owner: owner,
                        name: SymbolId::of("wrong"),
                    },
                    3 => M::RetainedProc {
                        declaring_owner: owner,
                        name,
                        verb: true,
                        engine_identity: 1,
                        wire_proc: 3,
                    },
                    _ => M::Unsupported(query),
                },
                _ => M::Unsupported(query),
            }
        }
    }
    let mut symbols = SymbolTable::default();
    symbols.intern("/datum/probe").unwrap();
    symbols.intern("callback").unwrap();
    let ast = dm_syntax::parse("/proc/probe()\n    callback()\n");
    for mode in 0..5 {
        let result = crate::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &ProcedureInputs {
                current_type_path: Some("/datum/probe".into()),
                ..Default::default()
            },
            &symbols,
            &NativeHost(mode),
        );
        if mode < 2 {
            assert!(result.unwrap().procedure_values.is_empty());
        } else {
            assert!(result.is_err(), "uncertified method answer mode {mode}");
        }
    }
}
#[test]
fn typed_list_contexts_query_container_runtime_type() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/list").unwrap();
    let host = Host {
        reads: Mutex::new(Vec::new()),
        answer: |query| match query {
            Q::RuntimeType(id) if id == SymbolId::of("/list") => M::Symbol(id),
            Q::Ancestry(id) if id == SymbolId::of("/list") => M::Symbols(vec![id].into()),
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
                    lexical_locals: std::sync::Arc::from([]),
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
            Q::Ancestry(id) if id == SymbolId::of("/datum") => M::Symbols(vec![id].into()),
            Q::Ancestry(id) if id == SymbolId::of("/datum/ordinary") => {
                M::Symbols(vec![id, SymbolId::of("/datum")].into())
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
                M::Symbols(vec![id, SymbolId::of("/obj")].into())
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
    let site = captured
        .source_span
        .expect("ordinary lowering captures an expression recipe");
    assert!(site.start < site.end);
    assert!(captured
        .descriptor
        .fields()
        .iter()
        .all(|(_, value)| value.span.start >= site.start && value.span.end <= site.end));
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
