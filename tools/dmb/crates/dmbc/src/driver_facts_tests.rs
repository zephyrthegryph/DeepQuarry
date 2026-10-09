#[test]
fn initializer_instance_storage_requires_exact_receiver_and_declaring_tuple() {
    struct Storage {
        answer: ResolvedMeaning,
        reads: std::sync::Mutex<Vec<ResolveQuery>>,
    }
    impl Resolver for Storage {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            self.reads.lock().unwrap().push(query);
            self.answer.clone()
        }
    }
    let owner = SymbolId::of("/atom");
    let receiver = SymbolId::of("/obj/subtype");
    let name = SymbolId::of("density");
    let write = dm_ir::InitializerWrite {
        target: dm_ir::InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: receiver,
            name,
        },
        lexical_owner: receiver,
        lexical_procedure: None,
        value: dm_ir::InitializerValue::NoAuthoredValue,
        declared_array: None,
        declaration_flags: None,
    };
    let query = ResolveQuery::VarStorage {
        owner: receiver,
        name,
    };
    let symbols = dm_ir::SymbolTable::default();
    for (answer, expected) in [
        (
            ResolvedMeaning::InstanceField {
                declaring_owner: owner,
                name,
            },
            Some(Some((owner, name))),
        ),
        (
            ResolvedMeaning::InstanceField {
                declaring_owner: receiver,
                name,
            },
            None,
        ),
        (
            ResolvedMeaning::InstanceField {
                declaring_owner: owner,
                name: SymbolId::of("other"),
            },
            None,
        ),
        (ResolvedMeaning::Missing, Some(None)),
        (
            ResolvedMeaning::Slot {
                symbol: name,
                owner,
                name,
            },
            Some(None),
        ),
        (ResolvedMeaning::Unsupported(query), None),
    ] {
        let host = Storage {
            answer,
            reads: std::sync::Mutex::new(Vec::new()),
        };
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resolver: &host,
            symbols: &symbols,
            resource_search_context: None,
        };
        let result = evaluator.instance_storage(&write);
        match expected {
            Some(value) => assert_eq!(result.as_ref().unwrap(), &value),
            None => assert!(result.is_err()),
        }
        assert_eq!(*host.reads.lock().unwrap(), [query]);
        assert_eq!(write.declaration_flags, None);
        let startup = crate::startup::StartupEvaluator {
            ordinary: &evaluator,
            resolver: &host,
            symbols: &symbols,
            resource_search_context: None,
        };
        assert_eq!(startup.instance_storage(&write), result);
    }
}
use super::*;
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        // Descendant encountered first: scheduling must follow previous,
        // not source order. Public result order remains source order.
        Ok("/child\n    parent_type = /base\n/child/p()\n    return 2\n/base\n/base/proc/p()\n    set name = \"base display\"\n    return 1\n".into())
    }
}
fn frontend() -> ColdFrontend {
    dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap()
}
#[test]
fn lexical_abi_constants_support_long_acyclic_chains_and_reject_exact_cycles() {
    let procedure = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    };
    for cyclic in [false, true] {
        let mut source = "/proc/work()\n".to_owned();
        for index in 0..72 {
            let value = if index == 0 {
                if cyclic {
                    "c71".into()
                } else {
                    "7".into()
                }
            } else {
                format!("c{}", index - 1)
            };
            source.push_str(&format!("    var/static/const/c{index} = {value}\n"));
        }
        source.push_str("    var/static/const/result = c71\n");
        let ast = dm_syntax::parse(&source);
        let captured =
            dm_tree::procedure_statics::capture(procedure, &ast.items[0].children).unwrap();
        let resolver = dm_tree::procedure_statics::StaticResolver::from_plans(
            &MissingHost,
            [(procedure, &captured)],
        )
        .unwrap();
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &resolver,
            symbols: &captured.symbols,
        };
        let declaration = captured
            .declarations
            .iter()
            .find(|declaration| declaration.identity.name == SymbolId::of("result"))
            .unwrap();
        let dm_ir::InitializerValue::Expression(expression) = &declaration.initializer else {
            panic!("expression");
        };
        let frontend = frontend();
        let context = AbiContext {
            identity: UnitIdentity {
                owner: procedure.owner,
                name: procedure.name,
                namespace: Namespace::Proc,
                occurrence: 0,
            },
            symbols: &captured.symbols,
            origin: &frontend.bodies[0].source,
            resolver: &resolver,
        };
        let answer = LexicalAbiEvaluator(&evaluator).evaluate(expression, &context);
        if cyclic {
            assert!(answer.unwrap_err().message.contains("constant cycle"));
        } else {
            assert_eq!(answer.unwrap(), SemanticValue::NumberBits(7f32.to_bits()));
        }
    }
}
#[test]
fn startup_evaluation_respects_procedure_static_shadowing() {
    let procedure = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    };
    let body=dm_syntax::parse("/proc/work()\n    var/static/const/base = 7\n    var/static/value = base + 1\n    return value\n");
    let captured = dm_tree::procedure_statics::capture(procedure, &body.items[0].children).unwrap();
    let resolver = dm_tree::procedure_statics::StaticResolver::from_plans(
        &MissingHost,
        [(procedure, &captured)],
    )
    .unwrap();
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &resolver,
        symbols: &captured.symbols,
    };
    let value = captured
        .declarations
        .iter()
        .find(|value| value.identity.name == SymbolId::of("value"))
        .unwrap();
    let dm_ir::InitializerValue::Expression(expression) = &value.initializer else {
        panic!("expression");
    };
    let write = dm_ir::InitializerWrite {
        target: dm_ir::InitializerTarget::ProcedureStatic(value.identity),
        lexical_owner: procedure.owner,
        lexical_procedure: Some(procedure),
        value: value.initializer.clone(),
        declared_array: None,
        declaration_flags: Some(value.modifiers),
    };
    assert!(
        matches!(evaluator.evaluate_write(&write,expression).unwrap(),Evaluation::Scalar(SemanticValue::NumberBits(bits)) if f32::from_bits(bits)==8.0)
    );
}
#[test]
fn captured_resource_literal_and_static_alias_keep_symbolic_path() {
    struct Assets {
        constant: Option<SymbolicExpression>,
        runtime_field: bool,
    }
    impl Resolver for Assets {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::Var { owner, name } if self.runtime_field => {
                    ResolvedMeaning::Member {
                        owner,
                        name,
                        fingerprint: 4,
                        data: std::sync::Arc::new(dm_ir::DeclarationMeaning::default()),
                    }
                }
                ResolveQuery::Var { .. } => ResolvedMeaning::Missing,
                ResolveQuery::GlobalVar(name)
                    if name == SymbolId::of("asset") && self.constant.is_some() =>
                {
                    ResolvedMeaning::Member {
                        owner: SymbolId::of("/"),
                        name,
                        fingerprint: 3,
                        data: std::sync::Arc::new(dm_ir::DeclarationMeaning {
                            flags: 2,
                            initializer: self.constant.clone(),
                            ..Default::default()
                        }),
                    }
                }
                ResolveQuery::ResourceIn {
                    path,
                    search_context: 17,
                } if path == SymbolId::of("asset.txt") => {
                    ResolvedMeaning::Resource { path, content: 123 }
                }
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    let procedure = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("p"),
        verb: false,
        occurrence: 0,
    };
    let body = dm_syntax::parse(
        "/proc/p()\n    var/static/const/asset = 'asset.txt'\n    var/static/value = asset\n",
    );
    let plan = dm_tree::procedure_statics::capture(procedure, &body.items[0].children).unwrap();
    let resolver = dm_tree::procedure_statics::StaticResolver::from_plans(
        &Assets {
            constant: None,
            runtime_field: false,
        },
        [(procedure, &plan)],
    )
    .unwrap();
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resolver: &resolver,
        symbols: &plan.symbols,
        resource_search_context: Some(17),
    };
    for declaration in &plan.declarations {
        let dm_ir::InitializerValue::Expression(expression) = &declaration.initializer else {
            panic!("expression")
        };
        assert_eq!(
            evaluator
                .scalar_in(
                    procedure.owner,
                    expression,
                    Some(procedure),
                    &RefCell::new(Default::default())
                )
                .unwrap(),
            Some(SemanticValue::Resource(SymbolId::of("asset.txt")))
        );
    }
    let dm_ir::InitializerValue::Expression(literal) = &plan.declarations[0].initializer else {
        panic!("expression")
    };
    let dm_ir::InitializerValue::Expression(alias) = &plan.declarations[1].initializer else {
        panic!("expression")
    };
    let assets = Assets {
        constant: Some(literal.clone()),
        runtime_field: false,
    };
    let ordinary = DriverEvaluator {
        pure_calls: None,
        resolver: &assets,
        symbols: &plan.symbols,
        resource_search_context: Some(17),
    };
    assert_eq!(
        ordinary
            .scalar(SymbolId::of("/datum/probe"), alias)
            .unwrap(),
        Some(SemanticValue::Resource(SymbolId::of("asset.txt")))
    );
    let shadow_assets = Assets {
        constant: Some(literal.clone()),
        runtime_field: true,
    };
    let shadow = DriverEvaluator {
        pure_calls: None,
        resolver: &shadow_assets,
        symbols: &plan.symbols,
        resource_search_context: Some(17),
    };
    assert_eq!(
        shadow.scalar(SymbolId::of("/datum/probe"), alias).unwrap(),
        None
    );
    let no_context = DriverEvaluator {
        resource_search_context: None,
        ..evaluator
    };
    let dm_ir::InitializerValue::Expression(expression) = &plan.declarations[0].initializer else {
        panic!("expression")
    };
    assert!(no_context
        .scalar(procedure.owner, expression)
        .unwrap_err()
        .contains("search context"));
}
struct MissingHost;
impl Resolver for MissingHost {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
#[test]
fn abi_failures_keep_each_captured_source_and_specific_cause() {
    let frontend = frontend();
    let prepared = PreparedSourceAbi {
        units: Vec::new(),
        diagnostics: vec![
            (1, dm_codegen_byond::procedure_abi::AbiError::unsupported("second specific cause")),
            (0, dm_codegen_byond::procedure_abi::AbiError::unsupported("first specific cause")),
        ],
    };
    let diagnostics = abi_diagnostics(&frontend, &prepared).unwrap();
    assert_eq!(diagnostics.len(), 2);
    assert_eq!(diagnostics[0].message, "first specific cause");
    assert_eq!(diagnostics[1].message, "second specific cause");
    for (ordinal, diagnostic) in diagnostics.iter().enumerate() {
        assert_eq!(diagnostic.origin.path, frontend.bodies[ordinal].source.path);
        assert_eq!(diagnostic.origin.line, frontend.bodies[ordinal].source.line);
        assert!(diagnostic.identity.is_some());
    }
}
#[test]
fn pinned_constructor_prepares_source_dependency_without_caller_fresh_map() {
    let engine =
        EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
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
    let prepared =
        prepare_pinned_source_abi(&frontend, &engine, frontend.snapshot.tree.as_ref(), None, 2)
            .unwrap();
    assert!(
        prepared.prepared.diagnostics.is_empty(),
        "{:?}",
        prepared.prepared.diagnostics
    );
    assert_eq!(prepared.prepared.units.len(), frontend.bodies.len());
    assert_ne!(prepared.policy_identity, engine.identity());
    let policy = FrozenPreparedPolicy::new(&frontend, &prepared.prepared).unwrap();
    let mut overlay = dm_ir::SymbolTable::overlay(frontend.snapshot.tree.shared_symbols());
    overlay.intern("body-only-static-name").unwrap();
    let body = &frontend.bodies[0];
    let identity = *unit_members(&frontend)
        .unwrap()
        .iter()
        .find(|(_, member)| **member == body.member)
        .unwrap()
        .0;
    let metadata = frontend
        .snapshot
        .tree
        .member(body.member)
        .unwrap()
        .metadata
        .procedure
        .as_ref()
        .unwrap();
    assert!(policy
        .validate(identity, metadata, &overlay, &body.source)
        .is_ok());
    assert!(policy
        .validate(
            identity,
            metadata,
            &dm_ir::SymbolTable::default(),
            &body.source
        )
        .is_err());
    let lowered = crate::lowering::lower_frontend(
        &frontend,
        frontend.snapshot.tree.as_ref(),
        &policy,
        crate::lowering::LoweringConfig {
            workers: 2,
            ..Default::default()
        },
    );
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    assert!(lowered.units.iter().all(|unit| unit.abi.is_some()));
}
#[test]
fn predecessor_abi_waves_preserve_encounter_order_and_inherited_layout() {
    let frontend = frontend();
    let engine =
        EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
            .unwrap();
    let index = unit_members(&frontend).unwrap();
    let base = *index
        .keys()
        .find(|identity| identity.owner == SymbolId::of("/base"))
        .unwrap();
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: frontend.snapshot.tree.as_ref(),
        symbols: frontend.snapshot.tree.symbols(),
    };
    // Fixture explicitly declares its base fresh; production must capture
    // the corresponding complete engine absence fact before issuing Fresh.
    let boundaries = BTreeMap::from([(base, BoundaryAbi::Fresh)]);
    let batch = prepare_source_abi(&frontend, &engine, &evaluator, &boundaries, None, 2).unwrap();
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    assert_eq!(
        batch.units.iter().map(|(id, _)| *id).collect::<Vec<_>>(),
        frontend
            .bodies
            .iter()
            .map(|body| body.member)
            .collect::<Vec<_>>()
    );
    for (_, unit) in &batch.units {
        assert_eq!(
            unit.require_production_abi()
                .unwrap()
                .layout
                .display_name
                .as_deref(),
            Some(b"base display".as_slice())
        );
    }
    let policy = FrozenPreparedPolicy::new(&frontend, &batch).unwrap();
    let lowered = crate::lowering::lower_frontend(
        &frontend,
        frontend.snapshot.tree.as_ref(),
        &policy,
        Default::default(),
    );
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    lowered.require_production_abi().unwrap();
}
#[test]
fn unknown_root_abi_is_not_fresh_and_blocks_descendants() {
    let frontend = frontend();
    let engine =
        EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
            .unwrap();
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: frontend.snapshot.tree.as_ref(),
        symbols: frontend.snapshot.tree.symbols(),
    };
    let batch =
        prepare_source_abi(&frontend, &engine, &evaluator, &BTreeMap::new(), None, 8).unwrap();
    assert!(batch.units.is_empty());
    assert_eq!(batch.diagnostics.len(), frontend.bodies.len());
    assert!(batch
        .diagnostics
        .windows(2)
        .all(|pair| pair[0].0 < pair[1].0));
    assert!(FrozenPreparedPolicy::new(&frontend, &batch).is_err());
}
#[test]
fn procedure_scalar_literals_preserve_exact_identity_and_constant_aliases() {
    struct Host {
        identity: dm_ir::ProcedureIdentity,
    }
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::ProcedureValue {
                    owner,
                    name,
                    verb: false,
                    formal: true,
                } if owner == self.identity.owner && name == self.identity.name => {
                    ResolvedMeaning::Value(SemanticValue::Procedure(self.identity))
                }
                ResolveQuery::Constant { name, .. } if name == SymbolId::of("alias") => {
                    ResolvedMeaning::Value(SemanticValue::Procedure(self.identity))
                }
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    let host = Host {
        identity: dm_ir::ProcedureIdentity {
            owner: SymbolId::of("/"),
            name: SymbolId::of("callback"),
            verb: false,
            occurrence: 2,
        },
    };
    let mut symbols = dm_ir::SymbolTable::default();
    for source in ["/proc/callback", "alias", "/proc/unknown"] {
        let lexed = dm_syntax::lex_spans(source);
        assert!(lexed.diagnostics.is_empty());
        let expression = dm_ir::SymbolicExpression {
            tokens: lexed
                .tokens
                .iter()
                .map(|token| dm_ir::ExpressionToken {
                    kind: token.kind,
                    text: symbols.intern(token.text(source)).unwrap(),
                    relative_span: token.span,
                })
                .collect::<Vec<_>>()
                .into(),
        };
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resolver: &host,
            symbols: &symbols,
            resource_search_context: None,
        };
        let result = evaluator.scalar_in(
            SymbolId::of("/"),
            &expression,
            None,
            &RefCell::new(std::collections::HashSet::new()),
        );
        if source == "/proc/unknown" {
            assert!(result.is_err());
        } else {
            assert_eq!(
                result.unwrap(),
                Some(SemanticValue::Procedure(host.identity))
            );
        }
    }
}

#[test]
fn lexical_type_intrinsic_keeps_declaring_context_and_records_type_dependency() {
    struct Types {
        reads: std::sync::Mutex<Vec<ResolveQuery>>,
    }
    impl Resolver for Types {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            self.reads.lock().unwrap().push(query);
            match query {
                ResolveQuery::Type(id)
                    if ["/obj/base", "/obj/child"]
                        .iter()
                        .any(|path| id == SymbolId::of(path)) =>
                {
                    ResolvedMeaning::Symbol(id)
                }
                ResolveQuery::Constant { .. }
                | ResolveQuery::Var { .. }
                | ResolveQuery::GlobalVar(_)
                | ResolveQuery::ProcedureStatic { .. } => ResolvedMeaning::Missing,
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    let mut symbols = dm_ir::SymbolTable::default();
    for name in [
        "/",
        "/obj/base",
        "/obj/child",
        "/obj/missing",
        "__TYPE__",
        "value",
        "work",
    ] {
        symbols.intern(name).unwrap();
    }
    let expression = SymbolicExpression {
        tokens: vec![dm_ir::ExpressionToken {
            kind: dm_syntax::TokenKind::Ident,
            text: SymbolId::of("__TYPE__"),
            relative_span: dm_syntax::Span::new(0, 8),
        }]
        .into(),
    };
    let host = Types {
        reads: Default::default(),
    };
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &host,
        symbols: &symbols,
    };
    assert_eq!(
        evaluator.scalar(SymbolId::of("/"), &expression).unwrap(),
        Some(SemanticValue::Null)
    );
    let intrinsic = SymbolId::of("__TYPE__");
    let root = SymbolId::of("/");
    assert_eq!(
        *host.reads.lock().unwrap(),
        vec![
            ResolveQuery::Constant {
                owner: root,
                name: intrinsic
            },
            ResolveQuery::Var {
                owner: root,
                name: intrinsic
            },
            ResolveQuery::GlobalVar(intrinsic),
        ]
    );
    host.reads.lock().unwrap().clear();
    let owner = SymbolId::of("/obj/base");
    let procedure = dm_ir::ProcedureIdentity {
        owner,
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    };
    for target in [
        dm_ir::InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: SymbolId::of("/obj/child"),
            name: SymbolId::of("value"),
        },
        dm_ir::InitializerTarget::ProcedureStatic(dm_ir::ProcedureStaticIdentity {
            procedure,
            name: SymbolId::of("value"),
        }),
    ] {
        let write = dm_ir::InitializerWrite {
            target,
            lexical_owner: owner,
            lexical_procedure: Some(procedure),
            value: dm_ir::InitializerValue::Expression(expression.clone()),
            declared_array: None,
            declaration_flags: Some(0),
        };
        assert!(
            matches!(evaluator.evaluate_write(&write, &expression).unwrap(), Evaluation::Scalar(SemanticValue::Type(id)) if id == owner)
        );
        let ast = dm_syntax::parse_expression("__TYPE__").expr.unwrap();
        assert!(
            matches!(evaluator.evaluate_ast_write(&write, &ast, "__TYPE__", &symbols).unwrap(), Evaluation::Scalar(SemanticValue::Type(id)) if id == owner)
        );
    }
    let one = [
        ResolveQuery::ProcedureStatic {
            procedure,
            name: intrinsic,
        },
        ResolveQuery::Constant {
            owner,
            name: intrinsic,
        },
        ResolveQuery::Var {
            owner,
            name: intrinsic,
        },
        ResolveQuery::GlobalVar(intrinsic),
        ResolveQuery::Type(owner),
    ];
    assert_eq!(*host.reads.lock().unwrap(), one.repeat(4));
    assert!(evaluator
        .scalar(SymbolId::of("/obj/missing"), &expression)
        .is_err());
    assert_eq!(
        host.reads.lock().unwrap().last(),
        Some(&ResolveQuery::Type(SymbolId::of("/obj/missing")))
    );
}

#[test]
fn authored_static_lexical_and_global_type_names_shadow_intrinsic() {
    struct Shadow {
        global: bool,
        unknown: bool,
        reads: std::sync::Mutex<Vec<ResolveQuery>>,
    }
    impl Resolver for Shadow {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            self.reads.lock().unwrap().push(query);
            match query {
                ResolveQuery::Constant { .. } if !self.global && !self.unknown => {
                    ResolvedMeaning::Value(SemanticValue::NumberBits(7f32.to_bits()))
                }
                ResolveQuery::GlobalVar(_) if self.global => {
                    ResolvedMeaning::Value(SemanticValue::NumberBits(9f32.to_bits()))
                }
                ResolveQuery::Var { .. } if self.unknown => ResolvedMeaning::Unsupported(query),
                ResolveQuery::Constant { .. }
                | ResolveQuery::Var { .. }
                | ResolveQuery::GlobalVar(_)
                | ResolveQuery::ProcedureStatic { .. } => ResolvedMeaning::Missing,
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    let procedure = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/obj/base"),
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    };
    let body = dm_syntax::parse("/obj/base/proc/work()\n    var/static/const/__TYPE__ = 17\n    var/static/value = __TYPE__\n    return value\n");
    let captured = dm_tree::procedure_statics::capture(procedure, &body.items[0].children).unwrap();
    let value = captured
        .declarations
        .iter()
        .find(|value| value.identity.name == SymbolId::of("value"))
        .unwrap();
    let dm_ir::InitializerValue::Expression(expression) = &value.initializer else {
        panic!("expression")
    };
    let write = dm_ir::InitializerWrite {
        target: dm_ir::InitializerTarget::ProcedureStatic(value.identity),
        lexical_owner: procedure.owner,
        lexical_procedure: Some(procedure),
        value: value.initializer.clone(),
        declared_array: None,
        declaration_flags: Some(value.modifiers),
    };
    for (global, unknown, number) in [
        (false, false, Some(7f32)),
        (true, false, Some(9f32)),
        (false, true, None),
    ] {
        let host = Shadow {
            global,
            unknown,
            reads: Default::default(),
        };
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &host,
            symbols: &captured.symbols,
        };
        let answer = evaluator.scalar(procedure.owner, expression);
        match number {
            Some(number) => assert_eq!(
                answer.unwrap(),
                Some(SemanticValue::NumberBits(number.to_bits()))
            ),
            None => assert!(answer.is_err()),
        }
        assert!(!host
            .reads
            .lock()
            .unwrap()
            .iter()
            .any(|query| matches!(query, ResolveQuery::Type(_))));
        let resolver =
            dm_tree::procedure_statics::StaticResolver::from_plans(&host, [(procedure, &captured)])
                .unwrap();
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &resolver,
            symbols: &captured.symbols,
        };
        assert!(
            matches!(evaluator.evaluate_write(&write, expression).unwrap(), Evaluation::Scalar(SemanticValue::NumberBits(bits)) if f32::from_bits(bits) == 17.0)
        );
    }
}

#[test]
fn inherited_source_layout_retains_exact_prepared_owner_without_copying_payloads() {
    let frontend = frontend();
    let engine =
        EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
            .unwrap();
    let units = unit_members(&frontend).unwrap();
    let (base, base_member) = units
        .iter()
        .find(|(unit, _)| unit.owner == SymbolId::of("/base"))
        .unwrap();
    let child = *units
        .keys()
        .find(|unit| unit.owner == SymbolId::of("/child"))
        .unwrap();
    let layout = dm_codegen_byond::procedure_abi::ProcLayout {
        display_name: Some(b"shared display".to_vec()),
        description: Some(b"shared description".to_vec()),
        category: dm_codegen_byond::procedure_abi::Category::Text(b"shared category".to_vec()),
        flags: 0x101,
        invisibility: Some(0),
        ..Default::default()
    };
    let owner = Arc::new(crate::procedure_policy::PreparedAbi {
        layout: layout.clone(),
        argument_sources: Vec::new(),
        source_helpers: Vec::new(),
    });
    let weak = Arc::downgrade(&owner);
    let layouts = HashMap::from([(*base_member, Arc::clone(&owner))]);
    assert!(Arc::ptr_eq(&owner, &layouts[base_member]));
    assert_eq!(
        owner.layout.description.as_ref().unwrap().as_ptr(),
        layouts[base_member]
            .layout
            .description
            .as_ref()
            .unwrap()
            .as_ptr()
    );
    drop(owner);
    assert!(weak.upgrade().is_some());
    let boundaries = BTreeMap::from([(*base, BoundaryAbi::Fresh)]);
    let facts = DriverInheritedFacts {
        frontend: &frontend,
        engine: &engine,
        source_layouts: &layouts,
        boundaries: &boundaries,
        unit_members: &units,
    };
    let origin = &frontend
        .bodies
        .iter()
        .find(|body| body.member == units[&child])
        .unwrap()
        .source;
    let inherited = facts
        .inherited(&AbiContext {
            identity: child,
            symbols: frontend.snapshot.tree.symbols(),
            origin,
            resolver: frontend.snapshot.tree.as_ref(),
        })
        .unwrap();
    match inherited {
        InheritedLayout::Known(actual) => assert_eq!(actual, layout),
        _ => panic!("expected exact inherited layout"),
    }
    drop(layouts);
    assert!(weak.upgrade().is_none());
}
