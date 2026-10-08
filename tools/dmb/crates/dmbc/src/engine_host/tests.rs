use super::*;
struct Missing;
impl Resolver for Missing {
    fn resolve(&self, _: Q) -> M {
        M::Missing
    }
}
#[test]
fn unordered_type_membership_has_canonical_content_and_policy_identity() {
    let mut symbols = SymbolTable::default();
    let first = symbols.intern("/datum/first").unwrap();
    let second = symbols.intern("/datum/second").unwrap();
    let left = RuntimeAliasCatalog::new(
        1,
        &symbols,
        Vec::new(),
        vec![first, second],
        Completeness::Partial,
    )
    .unwrap();
    let right = RuntimeAliasCatalog::new(
        1,
        &symbols,
        Vec::new(),
        vec![second, first, second],
        Completeness::Partial,
    )
    .unwrap();
    assert_eq!(left.identity(), right.identity());
    assert_eq!(left.policy_identity(), right.policy_identity());
    assert!(left.ordinary.contains(&first));
    assert!(right.ordinary.contains(&second));
}
#[test]
fn pinned_receiver_methods_lower_dynamically_without_fabricated_abi() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(
                "/datum/probe\n/proc/copy_probe(list/items)\n    return items.Copy(1, 2)\n/icon/proc/icon_probe()\n    return IconStates()\n"
                    .into(),
            )
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
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
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        Completeness::Partial,
    )
    .unwrap();
    let host = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
        .with_pinned_callables(&engine, &frontend)
        .unwrap();
    let list = SymbolId::of("/list");
    let copy = SymbolId::of("Copy");
    assert_eq!(
        host.resolve(Q::Proc {
            owner: list,
            name: copy,
            verb: false
        }),
        M::IntrinsicProc {
            declaring_owner: list,
            name: copy
        }
    );
    assert_eq!(
        host.resolve(Q::Proc {
            owner: list,
            name: copy,
            verb: true
        }),
        M::Missing
    );
    assert_eq!(
        host.resolve(Q::HasMemberProc {
            owner: list,
            name: copy
        }),
        M::Presence(true)
    );
    let read = SymbolId::of("Read");
    let icon = SymbolId::of("/icon");
    let icon_states = SymbolId::of("IconStates");
    assert_eq!(
        host.resolve(Q::Proc {
            owner: icon,
            name: icon_states,
            verb: false
        }),
        M::RetainedProc {
            declaring_owner: icon,
            name: icon_states,
            verb: false,
            engine_identity: engine.identity(),
            wire_proc: 7
        }
    );
    let physical = engine
        .procedure_layouts()
        .iter()
        .find(|record| {
            record.owner == icon
                && record.name == Some(icon_states)
                && record.kind == dm_tree::MemberKind::Proc
        })
        .unwrap();
    assert_eq!(physical.wire_proc, 7);
    let image =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin"))
            .unwrap();
    assert_eq!(
        image.string(image.procs[7].strings[0]),
        Some(b"/icon/proc/IconStates".as_slice())
    );
    assert!(!image.proc_code_words(7).unwrap().is_empty());
    let ast = dm_syntax::parse("/icon/proc/p()\n    return IconStates()\n");
    let inputs = dm_codegen_byond::ProcedureInputs {
        current_type_path: Some("/icon".into()),
        ..Default::default()
    };
    let lowered = dm_codegen_byond::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &inputs,
        frontend.snapshot.tree.symbols(),
        &host,
    )
    .unwrap();
    assert!(lowered
        .procedure
        .code
        .items
        .iter()
        .any(|item| matches!(item,
        dm_codegen_byond::Item::Instruction(instruction) if instruction.opcode == 0x29)));
    assert_eq!(
        host.resolve(Q::Proc {
            owner: SymbolId::of("/datum/probe"),
            name: read,
            verb: false
        }),
        M::IntrinsicProc {
            declaring_owner: SymbolId::of("/datum"),
            name: read
        }
    );
    for query in [
        Q::GlobalProc(copy),
        Q::Proc {
            owner: SymbolId::of("/never_captured"),
            name: copy,
            verb: false,
        },
        Q::Proc {
            owner: list,
            name: SymbolId::of("never_authored"),
            verb: false,
        },
    ] {
        assert_eq!(host.resolve(query), M::Unsupported(query));
    }
    let body = frontend.body(&frontend.bodies[0]).unwrap();
    let inputs = dm_codegen_byond::ProcedureInputs {
        parameters: vec!["items".into()],
        parameter_types: [("items".into(), "/list".into())].into(),
        ..Default::default()
    };
    let lowered = dm_codegen_byond::compile_simple_proc_with_resolver(
        &body.children,
        &inputs,
        &symbols,
        &host,
    )
    .unwrap();
    let receiver_call = lowered
        .procedure
        .code
        .items
        .iter()
        .find_map(|item| match item {
            dm_codegen_byond::Item::Instruction(instruction)
                if instruction.opcode == byond_dmb::bytecode::opcode::CALL =>
            {
                Some(instruction)
            }
            _ => None,
        })
        .expect("receiver Copy call");
    assert_eq!(
        receiver_call.operands,
        vec![
            dm_codegen_byond::Word::Variable(dm_codegen_byond::VariableWord::SetCache(
                Box::new(dm_codegen_byond::VariableWord::Arg(0)),
                Box::new(dm_codegen_byond::VariableWord::DynamicProc("Copy".into())),
            )),
            dm_codegen_byond::Word::Immediate(2),
        ]
    );
}
#[test]
fn pinned_global_callable_absence_keeps_source_and_intrinsic_domains_distinct() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/probe/proc/member_only()\n    return 1\n/proc/global_only()\n    return 2\n".into())
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
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
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        Completeness::Partial,
    )
    .unwrap();
    let host = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
        .with_pinned_callables(&engine, &frontend)
        .unwrap();
    assert_eq!(
        host.resolve(Q::GlobalProc(SymbolId::of("member_only"))),
        M::Missing
    );
    assert!(
        matches!(host.resolve(Q::GlobalProc(SymbolId::of("global_only"))), M::Member { owner, .. } if owner == SymbolId::of("/"))
    );
    assert!(matches!(
        host.resolve(Q::Proc {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("member_only"),
            verb: false
        }),
        M::Member { .. }
    ));
    for name in ["sin", "never_authored_name"] {
        let query = Q::GlobalProc(SymbolId::of(name));
        assert_eq!(host.resolve(query), M::Unsupported(query));
    }
}
#[test]
fn source_membership_changes_do_not_change_compiler_policy_identity() {
    use std::path::Path;
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let build = |source| {
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source(source),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let mut symbols = frontend.snapshot.tree.symbols().clone();
        let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
        let runtime = RuntimeAliasCatalog::new(
            engine.identity(),
            &symbols,
            Vec::new(),
            frontend
                .snapshot
                .tree
                .types()
                .iter()
                .map(|node| node.path)
                .collect(),
            Completeness::Partial,
        )
        .unwrap();
        EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
            .with_pinned_callables(&engine, &frontend)
            .unwrap()
            .with_pinned_variables(&engine, &frontend)
            .unwrap()
    };
    let before = build("/datum/probe\n");
    let after = build("/datum/probe\n/datum/unrelated\n    var/fresh = 1\n    proc/new_function()\n        return fresh\n");
    assert_eq!(
        before.configuration_identity(),
        after.configuration_identity()
    );
    let type_query = Q::RuntimeType(SymbolId::of("/datum/unrelated"));
    assert_ne!(before.resolve(type_query), after.resolve(type_query));
    let variable_query = Q::Var {
        owner: SymbolId::of("/datum/unrelated"),
        name: SymbolId::of("fresh"),
    };
    assert_ne!(
        before.resolve(variable_query),
        after.resolve(variable_query)
    );
    let proc_query = Q::Proc {
        owner: SymbolId::of("/datum/unrelated"),
        name: SymbolId::of("new_function"),
        verb: false,
    };
    assert_ne!(before.resolve(proc_query), after.resolve(proc_query));
}
#[test]
fn pinned_authored_variable_absence_preserves_global_and_field_shadow_domains() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("var/global_only = 4\nvar/shared_name = 1\n/datum/probe\n    var/shared_name = 2\n    var/static/unique_counter = 0\n    var/static/ambiguous_counter = 0\n/datum/probe/child\n    unique_counter = 2\n/datum/other\n    var/static/ambiguous_counter = 1\n/datum/probe/proc/read()\n    return shared_name + global_only\n/proc/root_read()\n    return shared_name\n#undef FALSE\n/datum/shadow\n    var/FALSE = 5\n".into())
        }
    }
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
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
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        Completeness::Partial,
    )
    .unwrap();
    let base = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime);
    let base_identity = base.configuration_identity();
    let host = base.with_pinned_variables(&engine, &frontend).unwrap();
    assert_ne!(host.configuration_identity(), base_identity);
    let owner = SymbolId::of("/datum/probe");
    let root = SymbolId::of("/");
    let global = SymbolId::of("global_only");
    let shadow = SymbolId::of("shared_name");
    let unique = SymbolId::of("unique_counter");
    assert!(matches!(host.resolve(Q::UniqueStaticVar(unique)),
        M::Slot { owner: actual, name, .. } if actual == owner && name == unique));
    assert!(matches!(host.resolve(Q::UniqueStaticVar(global)),
        M::Slot { owner: actual, name, .. } if actual == root && name == global));
    // Instance fields block fallback to a same-name shared slot. Distinct
    // formal slots also remain ambiguous, while inherited assignments do not.
    for name in [shadow, SymbolId::of("ambiguous_counter")] {
        assert_eq!(host.resolve(Q::UniqueStaticVar(name)), M::Missing);
    }
    let unknown = Q::UniqueStaticVar(SymbolId::of("never_captured_variable"));
    assert_eq!(host.resolve(unknown), M::Unsupported(unknown));
    // The pinned engine positively declares tag as an instance field.
    // This is an authoritative counterexample to shared-slot uniqueness,
    // even though the rest of the intrinsic inventory remains partial.
    assert_eq!(
        host.resolve(Q::UniqueStaticVar(SymbolId::of("tag"))),
        M::Missing
    );
    for (spelling, value) in [("TRUE", 1.0_f32), ("FALSE", 0.0_f32)] {
        let name = SymbolId::of(spelling);
        assert_eq!(
            host.resolve(Q::GlobalVar(name)),
            M::Value(SemanticValue::NumberBits(value.to_bits()))
        );
        assert_eq!(
            host.resolve(Q::Constant { owner, name }),
            M::Value(SemanticValue::NumberBits(value.to_bits()))
        );
    }
    let shadow_query = Q::Constant {
        owner: SymbolId::of("/datum/shadow"),
        name: SymbolId::of("FALSE"),
    };
    assert_eq!(host.resolve(shadow_query), M::Unsupported(shadow_query));
    assert!(
        matches!(host.resolve(Q::GlobalVar(global)),M::Member{owner:actual,..} if actual==root)
    );
    assert_eq!(
        host.resolve(Q::Var {
            owner,
            name: global
        }),
        M::Missing
    );
    assert_eq!(
        host.resolve(Q::VarStorage {
            owner,
            name: global
        }),
        M::Missing
    );
    assert_eq!(
        host.resolve(Q::HasMemberVar {
            owner,
            name: global
        }),
        M::Presence(false)
    );
    assert!(
        matches!(host.resolve(Q::VarStorage{owner,name:shadow}),M::InstanceField{declaring_owner,name} if declaring_owner==owner&&name==shadow)
    );
    assert_eq!(
        host.resolve(Q::Var {
            owner,
            name: SymbolId::of("NORTH")
        }),
        M::Missing
    );
    assert!(matches!(
        host.resolve(Q::PredefinedConstant(SymbolId::of("NORTH"))),
        M::Value(_)
    ));
    let query = Q::Var {
        owner,
        name: SymbolId::of("never_captured_variable"),
    };
    assert_eq!(host.resolve(query), M::Unsupported(query));
    let unknown_owner = Q::Var {
        owner: SymbolId::of("/never_captured_owner"),
        name: global,
    };
    assert_eq!(host.resolve(unknown_owner), M::Unsupported(unknown_owner));
    let intrinsic = Q::DeclaredVarType {
        owner,
        name: SymbolId::of("tag"),
    };
    assert_eq!(host.resolve(intrinsic), M::Unsupported(intrinsic));
    let tree = &frontend.snapshot.tree;
    let instance = tree
        .resolve(
            tree.lookup_type(owner).unwrap(),
            shadow,
            dm_tree::MemberKind::Var,
        )
        .unwrap();
    assert_eq!(tree.override_chain(instance), vec![instance]);
    for body in frontend.bodies.iter() {
        let parsed = frontend.body(body).unwrap();
        let member = tree.member(body.member).unwrap();
        let path = tree.type_node(member.owner).unwrap().path;
        let inputs = dm_codegen_byond::ProcedureInputs {
            current_type_path: (path != root)
                .then(|| tree.symbols().text(path).unwrap().to_owned()),
            ..Default::default()
        };
        let code = dm_codegen_byond::compile_simple_proc_with_resolver(
            &parsed.children,
            &inputs,
            tree.symbols(),
            &host,
        )
        .unwrap();
        let expected = if path == root { shadow } else { global };
        let expected_text = tree.symbols().text(expected).unwrap();
        let globals: Vec<_> = code
            .procedure
            .code
            .items
            .iter()
            .flat_map(|item| match item {
                dm_codegen_byond::Item::Instruction(instruction) => instruction
                    .operands
                    .iter()
                    .filter_map(|word| match word {
                        dm_codegen_byond::Word::Variable(
                            dm_codegen_byond::VariableWord::Global(name),
                        ) => Some(name.as_str()),
                        _ => None,
                    })
                    .collect::<Vec<_>>(),
                _ => Vec::new(),
            })
            .collect();
        // Resolver globals use canonical root-slot symbols, not the
        // source spelling used by the legacy string-only encoder.
        assert_eq!(globals, vec![format!("var/{expected_text}")]);
        assert!(code
            .slots
            .values()
            .any(|slot| slot.owner == root && slot.name == expected));
    }
}
#[test]
fn exact_constant_bits_and_bytes_preserve_partial_negatives() {
    let mut symbols = SymbolTable::default();
    let constants = ConstantCatalog::new(
        1,
        &mut symbols,
        vec![
            ("X".into(), SemanticValue::NumberBits(0x80000000)),
            ("TEXT".into(), SemanticValue::Text(Arc::from([0xff, 0]))),
        ],
        Completeness::Partial,
    )
    .unwrap();
    let runtime =
        RuntimeAliasCatalog::new(1, &symbols, vec![], vec![], Completeness::Partial).unwrap();
    let host = EngineResolverHost::new(Arc::new(Missing), constants, runtime);
    assert_eq!(
        host.resolve(Q::PredefinedConstant(SymbolId::of("X"))),
        M::Value(SemanticValue::NumberBits(0x80000000))
    );
    assert_eq!(
        host.resolve(Q::PredefinedConstant(SymbolId::of("TEXT"))),
        M::Value(SemanticValue::Text(Arc::from([0xff, 0])))
    );
    let absent = Q::PredefinedConstant(SymbolId::of("absent"));
    assert_eq!(host.resolve(absent), M::Unsupported(absent));
}
#[test]
fn captured_aliases_and_ordinary_types_do_not_imply_negative_completeness() {
    let mut symbols = SymbolTable::default();
    let ordinary = symbols.intern("/obj").unwrap();
    let alias = symbols.intern("/obj{a=1}").unwrap();
    let constants = ConstantCatalog::new(1, &mut symbols, vec![], Completeness::Complete).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        1,
        &symbols,
        vec![(alias, ordinary)],
        vec![ordinary],
        Completeness::Partial,
    )
    .unwrap();
    let host = EngineResolverHost::new(Arc::new(Missing), constants, runtime);
    assert_eq!(host.resolve(Q::RuntimeType(alias)), M::Symbol(ordinary));
    assert_eq!(host.resolve(Q::RuntimeType(ordinary)), M::Symbol(ordinary));
    let absent = Q::RuntimeType(SymbolId::of("/unknown"));
    assert_eq!(host.resolve(absent), M::Unsupported(absent));
    assert_eq!(
        host.resolve(Q::PredefinedConstant(SymbolId::of("missing"))),
        M::Missing
    );
}

#[test]
fn lexical_type_namespace_exclusion_preserves_authored_shadows_and_real_lowering() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/probe\n/datum/probe/proc/read()\n    return __TYPE__\n/datum/shadow\n    var/__TYPE__ = 7\n".into())
        }
    }
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
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
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        Completeness::Partial,
    )
    .unwrap();
    let base = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime);
    let base_identity = base.configuration_identity();
    let host = base.with_pinned_variables(&engine, &frontend).unwrap();
    assert_ne!(host.configuration_identity(), base_identity);

    let name = SymbolId::of("__TYPE__");
    let owner = SymbolId::of("/datum/probe");
    assert_eq!(host.resolve(Q::VarStorage { owner, name }), M::Missing);
    assert_eq!(host.resolve(Q::GlobalVar(name)), M::Missing);
    assert_eq!(
        host.resolve(Q::HasMemberVar { owner, name }),
        M::Presence(false)
    );
    let shadow_owner = SymbolId::of("/datum/shadow");
    assert!(matches!(
        host.resolve(Q::VarStorage {
            owner: shadow_owner,
            name
        }),
        M::InstanceField { .. }
    ));
    let unknown = Q::VarStorage {
        owner: SymbolId::of("/datum/uncaptured"),
        name,
    };
    assert_eq!(host.resolve(unknown), M::Unsupported(unknown));
    let body = frontend.bodies.iter().next().unwrap();
    let parsed = frontend.body(body).unwrap();
    let inputs = dm_codegen_byond::ProcedureInputs {
        current_type_path: Some("/datum/probe".into()),
        ..Default::default()
    };
    // The real lowering path performs its field/storage query before recognizing
    // __TYPE__; this must no longer fail on Unsupported VarStorage.
    dm_codegen_byond::compile_simple_proc_with_resolver(
        &parsed.children,
        &inputs,
        frontend.snapshot.tree.symbols(),
        &host,
    )
    .unwrap();
}

#[test]
fn lexical_type_exclusion_checks_root_globals_and_generated_fields() {
    let catalog = serde_json::json!({"Types": [{"Path": "/", "GlobalVariables": {"__TYPE__": 0}}]});
    assert!(verify_lexical_type_namespace(&catalog, &BTreeSet::new()).is_err());
    let catalog = serde_json::json!({"Types": []});
    assert!(
        verify_lexical_type_namespace(&catalog, &BTreeSet::from([SymbolId::of("__TYPE__")]))
            .is_err()
    );
    assert!(verify_lexical_type_namespace(&catalog, &BTreeSet::new()).is_ok());
}
