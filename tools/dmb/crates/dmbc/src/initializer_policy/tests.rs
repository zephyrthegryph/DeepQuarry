use super::*;

#[test]
fn folded_nameof_recovery_preserves_order_and_assignment_ordinal() {
    use dm_codegen_byond::NameofDiagnosticRecovery as Recovery;
    let failure = Evaluation::InvalidNameof(
        "/datum/probe::missing: undefined var".into(),
        Recovery::ReferenceRejected,
    )
    .checked()
    .err()
    .unwrap();
    let issues = failure.into_issues(37);
    assert_eq!(
        issues
            .iter()
            .map(|issue| issue.reason.as_str())
            .collect::<Vec<_>>(),
        [
            "/datum/probe::missing: undefined var",
            "nameof: requires a var, proc reference, or type path",
            "=: missing expression",
        ]
    );
    assert!(issues
        .iter()
        .all(|issue| issue.source_ordinal == 37
            && issue.kind == ClassificationIssueKind::SourceError));
    let failure = Evaluation::InvalidNameof(
        "nameof: requires a var, proc reference, or type path".into(),
        Recovery::ReferenceRequired,
    )
    .checked()
    .err()
    .unwrap();
    assert_eq!(failure.into_issues(9).len(), 2);
    let failure = Evaluation::InvalidNameof(
        "nameof: requires a var, proc reference, or type path".into(),
        Recovery::ModifiedReferenceRequired,
    )
    .checked()
    .err()
    .unwrap();
    let issues = failure.into_issues(19);
    assert_eq!(
        issues
            .iter()
            .map(|issue| issue.reason.as_str())
            .collect::<Vec<_>>(),
        [
            "nameof: requires a var, proc reference, or type path",
            ": missing expression",
        ]
    );
    assert!(issues.iter().all(|issue| issue.source_ordinal == 19));
    let failure = ClassificationFailure::from("opaque reference authority");
    let issues = failure.into_issues(11);
    assert_eq!(issues.len(), 1);
    assert_eq!(issues[0].kind, ClassificationIssueKind::Unsupported);
}

#[test]
fn prepared_runtime_syntax_matches_compatibility_classification_and_diagnostics() {
    use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
    struct Empty;
    impl Resolver for Empty {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Missing
        }
    }
    struct Legacy<'a>(&'a dyn CapturedInitializerEvaluator);
    impl CapturedInitializerEvaluator for Legacy<'_> {
        fn evaluate(
            &self,
            owner: SymbolId,
            value: &SymbolicExpression,
        ) -> Result<Evaluation, String> {
            self.0.evaluate(owner, value)
        }
        fn evaluate_write(
            &self,
            write: &InitializerWrite,
            value: &SymbolicExpression,
        ) -> Result<Evaluation, String> {
            self.0.evaluate_write(write, value)
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("prepared_fixture").unwrap();
    for source in ["17", "list(1,2)", "rand(1,2)", "\"[rand(1,2)]\"", "1 +"] {
        let value = expression(source, &mut symbols).unwrap();
        let captured = write(owner, name, InitializerValue::Expression(value.clone()));
        let production = crate::driver_facts::DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &Empty,
            symbols: &symbols,
        };
        let wrapped = EngineCapturedEvaluator {
            engine: &engine,
            evaluator: &production,
        };
        let prepared = classify(std::slice::from_ref(&captured), &symbols, &wrapped);
        let compatibility = classify(std::slice::from_ref(&captured), &symbols, &Legacy(&wrapped));
        match (prepared, compatibility) {
            (Ok(prepared), Ok(compatibility)) => {
                assert_eq!(prepared.writes.len(), compatibility.writes.len());
                for (a, b) in prepared.writes.iter().zip(&compatibility.writes) {
                    assert_eq!(a.default, b.default);
                    assert_eq!(a.phase, b.phase);
                    assert_eq!(a.runtime_value, b.runtime_value);
                }
                assert_eq!(
                    prepared
                        .groups
                        .iter()
                        .map(|group| (&group.receiver, &group.writes))
                        .collect::<Vec<_>>(),
                    compatibility
                        .groups
                        .iter()
                        .map(|group| (&group.receiver, &group.writes))
                        .collect::<Vec<_>>()
                );
            }
            (Err(prepared), Err(compatibility)) => assert_eq!(prepared, compatibility),
            _ => panic!("prepared and compatibility classification differ: {source}"),
        }
        if source == "1 +" {
            assert_eq!(
                production
                    .evaluate_prepared_write(&captured, &value)
                    .err()
                    .unwrap(),
                "captured scalar expression failed parsing"
            );
        } else {
            let (_, prepared) = wrapped.evaluate_prepared_write(&captured, &value).unwrap();
            let prepared = prepared.expect("engine wrapper forwards prepared syntax");
            assert_eq!(prepared.source(), value.source_text(&symbols).unwrap());
            assert_eq!(
                *prepared.ast(),
                dm_syntax::parse_expression(prepared.source()).expr.unwrap()
            );
        }
    }
    struct Runtime;
    impl CapturedInitializerEvaluator for Runtime {
        fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
            Ok(Evaluation::Runtime)
        }
    }
    let malformed = expression("1 +", &mut symbols).unwrap();
    let mut captured = write(owner, name, InitializerValue::Expression(malformed));
    assert_eq!(
        classify(std::slice::from_ref(&captured), &symbols, &Runtime).unwrap_err(),
        "invalid initializer expression"
    );
    captured.declaration_flags = Some(2);
    assert_eq!(
        classify(&[captured], &symbols, &Runtime).unwrap_err(),
        "const initializer is not scalar"
    );
}
#[test]
fn nested_pure_calls_keep_literal_allocation_and_reject_unavailable_components() {
    use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
    struct Empty;
    impl Resolver for Empty {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Missing
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let calls = crate::pure_calls::PinnedPureCalls::new(&engine).unwrap();
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let name = symbols.intern("colors").unwrap();
    let value = expression("list(rgb(255,201,49), list(rgb(1,2,3,128)))", &mut symbols).unwrap();
    let captured = write(root, name, InitializerValue::Expression(value));
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: Some(&calls),
        resource_search_context: None,
        resolver: &Empty,
        symbols: &symbols,
    };
    let result = classify(&[captured], &symbols, &evaluator).unwrap();
    assert_eq!(result.writes[0].phase, Some(Phase::LiteralAllocation));
    let invalid = expression("list(rgb(rand(0,255),2,3))", &mut symbols).unwrap();
    let invalid = write(root, name, InitializerValue::Expression(invalid));
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: Some(&calls),
        resource_search_context: None,
        resolver: &Empty,
        symbols: &symbols,
    };
    assert!(classify(&[invalid], &symbols, &evaluator)
        .unwrap_err()
        .to_string()
        .contains("rgb components must be captured constant numbers"));
}
#[test]
fn mutable_instance_knowledge_retains_opaque_modifiers() {
    struct Mutable;
    impl CapturedInitializerEvaluator for Mutable {
        fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
            Ok(Evaluation::Runtime)
        }
        fn binding_knowledge(
            &self,
            write: &InitializerWrite,
        ) -> Result<Option<BindingKnowledge>, String> {
            let InitializerTarget::Instance {
                declaring_owner,
                name,
                ..
            } = write.target
            else {
                return Ok(None);
            };
            Ok(Some(BindingKnowledge::MutableInstance {
                owner: declaring_owner,
                name,
                receipt: 1,
            }))
        }
    }
    let mut symbols = SymbolTable::default();
    let atom = symbols.intern("/atom").unwrap();
    let child = symbols.intern("/obj/example").unwrap();
    let name = symbols.intern("name").unwrap();
    let write = InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: InitializerTarget::Instance {
            declaring_owner: atom,
            receiver_owner: child,
            name,
        },
        lexical_owner: child,
        lexical_procedure: None,
        value: InitializerValue::Expression(expression("run()", &mut symbols).unwrap()),
        declared_array: None,
        declaration_flags: None,
    };
    let classified = classify(std::slice::from_ref(&write), &symbols, &Mutable).unwrap();
    assert_eq!(classified.writes[0].write, write);
    assert_eq!(classified.writes[0].write.declaration_flags, None);
    assert_eq!(classified.groups[0].receiver, Some(child));
    let mut known_const = write;
    known_const.declaration_flags = Some(2);
    assert!(classify(&[known_const], &symbols, &Mutable).is_err());
}
struct Evaluator;
impl CapturedInitializerEvaluator for Evaluator {
    fn evaluate(&self, _: SymbolId, value: &SymbolicExpression) -> Result<Evaluation, String> {
        if value.tokens.len() == 1 && value.tokens[0].text == SymbolId::of("2") {
            Ok(Evaluation::Scalar(SemanticValue::NumberBits(
                2f32.to_bits(),
            )))
        } else {
            Ok(Evaluation::Runtime)
        }
    }
}
fn write(owner: SymbolId, name: SymbolId, value: InitializerValue) -> InitializerWrite {
    InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: InitializerTarget::Shared {
            slot: SymbolId::of("slot"),
            owner,
            name,
        },
        lexical_owner: owner,
        lexical_procedure: None,
        value,
        declared_array: None,
        declaration_flags: Some(8),
    }
}
#[test]
fn indexed_receiver_groups_preserve_interleaved_owner_and_global_order() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let first = symbols.intern("/datum/first").unwrap();
    let second = symbols.intern("/datum/second").unwrap();
    let name = symbols.intern("value").unwrap();
    let runtime = InitializerValue::Expression(expression("run()", &mut symbols).unwrap());
    let literal = InitializerValue::Expression(expression("list(2)", &mut symbols).unwrap());
    let instance = |owner, value| InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name,
        },
        lexical_owner: owner,
        lexical_procedure: None,
        value,
        declared_array: None,
        declaration_flags: Some(0),
    };
    let writes = [
        instance(first, runtime.clone()),
        write(root, name, runtime.clone()),
        instance(second, runtime.clone()),
        instance(first, literal.clone()),
        write(root, name, literal),
        instance(second, runtime.clone()),
        write(root, name, runtime),
    ];
    let classified = classify(&writes, &symbols, &Evaluator).unwrap();
    assert_eq!(
        classified
            .groups
            .iter()
            .map(|group| group.receiver)
            .collect::<Vec<_>>(),
        [Some(first), None, Some(second)]
    );
    let ordinals = classified
        .groups
        .iter()
        .map(|group| {
            group
                .writes
                .iter()
                .map(|&index| classified.writes[index].source_ordinal)
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    assert_eq!(ordinals, [vec![0, 3], vec![4, 1, 6], vec![2, 5]]);
    assert_eq!(
        classified
            .writes
            .iter()
            .map(|write| write.source_ordinal)
            .collect::<Vec<_>>(),
        (0..writes.len()).collect::<Vec<_>>()
    );
}

#[test]
fn client_header_assignment_preserves_unknown_modifiers_without_runtime_code() {
    let mut symbols = SymbolTable::default();
    let client = symbols.intern("/client").unwrap();
    let name = symbols.intern("preload_rsc").unwrap();
    let mut header = write(
        client,
        name,
        InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
    );
    header.target = InitializerTarget::Instance {
        declaring_owner: client,
        receiver_owner: client,
        name,
    };
    header.declaration_flags = None;
    let result = classify(&[header.clone()], &symbols, &Evaluator).unwrap();
    assert!(result.groups.is_empty());
    assert_eq!(result.writes[0].write, header);
    assert!(
        matches!(result.writes[0].default,DefaultValue::Scalar(SemanticValue::NumberBits(bits)) if bits==2f32.to_bits())
    );
    header.target = InitializerTarget::Instance {
        declaring_owner: client,
        receiver_owner: SymbolId::of("/client/subtype"),
        name,
    };
    header.lexical_owner = SymbolId::of("/client/subtype");
    assert!(classify(&[header], &symbols, &Evaluator).is_ok());
}
#[test]
fn global_literal_phase_is_stable_and_instances_keep_encounter_order() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let name = symbols.intern("x").unwrap();
    let runtime = write(
        root,
        name,
        InitializerValue::Expression(expression("run()", &mut symbols).unwrap()),
    );
    let literal = write(
        root,
        name,
        InitializerValue::Expression(expression("list(2)", &mut symbols).unwrap()),
    );
    let result = classify(
        &[runtime.clone(), literal.clone(), runtime],
        &symbols,
        &Evaluator,
    )
    .unwrap();
    assert_eq!(
        result.groups[0]
            .writes
            .iter()
            .map(|&index| result.writes[index].source_ordinal)
            .collect::<Vec<_>>(),
        [1, 0, 2]
    );
    let owner = symbols.intern("/datum/x").unwrap();
    let instance = |mut write: InitializerWrite| {
        write.target = InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name,
        };
        write.lexical_owner = owner;
        write.declaration_flags = Some(0);
        write
    };
    let result = classify(
        &[instance(result.writes[0].write.clone()), instance(literal)],
        &symbols,
        &Evaluator,
    )
    .unwrap();
    assert_eq!(
        result.groups[0]
            .writes
            .iter()
            .map(|&index| result.writes[index].source_ordinal)
            .collect::<Vec<_>>(),
        [0, 1]
    );
}
#[test]
fn sized_array_uses_captured_integer_dimensions_and_const_runtime_rejects() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let name = symbols.intern("x").unwrap();
    let array = Arc::new(dm_ir::ArrayDeclaration {
        dimensions: Arc::from([Some(expression("2", &mut symbols).unwrap())]),
        element_type: None,
    });
    let mut item = write(
        root,
        name,
        InitializerValue::ArrayAllocation(Arc::clone(&array)),
    );
    item.declared_array = Some(array);
    let result = classify(&[item], &symbols, &Evaluator).unwrap();
    assert_eq!(result.writes[0].phase, Some(Phase::LiteralAllocation));
    assert_eq!(
        result.writes[0].default,
        DefaultValue::Scalar(SemanticValue::Null)
    );
    assert_eq!(
        result.writes[0].runtime_value,
        Some(RuntimeValue::SizedArray(Arc::from([2u16])))
    );
    let mut item = write(
        root,
        name,
        InitializerValue::Expression(expression("run()", &mut symbols).unwrap()),
    );
    item.declaration_flags = Some(2);
    assert!(classify(&[item], &symbols, &Evaluator)
        .unwrap_err()
        .contains("const"));
}
#[test]
fn missing_modifier_preflight_reports_all_ordinals_and_queries_once() {
    struct Counting {
        queries: std::sync::Mutex<Vec<SymbolId>>,
        evaluations: std::sync::atomic::AtomicUsize,
    }
    impl CapturedInitializerEvaluator for Counting {
        fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
            self.evaluations
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            Ok(Evaluation::Scalar(SemanticValue::NumberBits(
                2f32.to_bits(),
            )))
        }
        fn declaration_modifiers(&self, write: &InitializerWrite) -> Result<Option<u32>, String> {
            let name = match write.target {
                InitializerTarget::Shared { name, .. } => name,
                _ => panic!("fixture target"),
            };
            self.queries.lock().unwrap().push(name);
            Ok(write.declaration_flags)
        }
    }
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/probe").unwrap();
    let value = InitializerValue::Expression(expression("2", &mut symbols).unwrap());
    let mut writes = ["zeta", "alpha", "middle"]
        .into_iter()
        .map(|name| write(owner, symbols.intern(name).unwrap(), value.clone()))
        .collect::<Vec<_>>();
    writes[0].declaration_flags = None;
    writes[2].declaration_flags = None;
    let evaluator = Counting {
        queries: std::sync::Mutex::new(Vec::new()),
        evaluations: std::sync::atomic::AtomicUsize::new(0),
    };
    let error = classify_with_diagnostics(&writes, &symbols, &evaluator).unwrap_err();
    assert_eq!(
        error
            .issues
            .iter()
            .map(|issue| issue.source_ordinal)
            .collect::<Vec<_>>(),
        [0, 2]
    );
    assert!(error.issues[0]
        .reason
        .contains("/datum/probe::zeta (write 0)"));
    assert!(error.issues[1]
        .reason
        .contains("/datum/probe::middle (write 2)"));
    assert_eq!(
        *evaluator.queries.lock().unwrap(),
        [
            SymbolId::of("zeta"),
            SymbolId::of("alpha"),
            SymbolId::of("middle")
        ]
    );
    assert_eq!(
        evaluator
            .evaluations
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    evaluator.queries.lock().unwrap().clear();
    for write in &mut writes {
        write.declaration_flags = Some(8);
    }
    let result = classify_with_diagnostics(&writes, &symbols, &evaluator).unwrap();
    assert_eq!(result.writes.len(), 3);
    assert_eq!(evaluator.queries.lock().unwrap().len(), 3);
    assert_eq!(
        evaluator
            .evaluations
            .load(std::sync::atomic::Ordering::Relaxed),
        3
    );
}
#[test]
fn nonmodifier_failure_keeps_failing_write_ordinal() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("value").unwrap();
    let first = write(
        owner,
        name,
        InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
    );
    let mut second = write(
        owner,
        name,
        InitializerValue::Expression(expression("run()", &mut symbols).unwrap()),
    );
    second.declaration_flags = Some(2);
    let error = classify_with_diagnostics(&[first, second], &symbols, &Evaluator).unwrap_err();
    assert_eq!(error.issues.len(), 1);
    assert_eq!(error.issues[0].source_ordinal, 1);
    assert!(error.issues[0].reason.contains("const initializer"));
}
#[test]
fn savefile_header_scalar_keeps_unknown_flags_and_no_runtime_group() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/savefile").unwrap();
    let name = symbols.intern("byond_version").unwrap();
    let mut header = write(
        owner,
        name,
        InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
    );
    header.target = InitializerTarget::Instance {
        declaring_owner: owner,
        receiver_owner: owner,
        name,
    };
    header.declaration_flags = None;
    let result = classify_with_diagnostics(&[header.clone()], &symbols, &Evaluator).unwrap();
    assert_eq!(result.writes[0].write.declaration_flags, None);
    assert_eq!(result.writes[0].phase, None);
    assert!(result.groups.is_empty());
    header.value = InitializerValue::Expression(expression("run()", &mut symbols).unwrap());
    let error = classify_with_diagnostics(&[header], &symbols, &Evaluator).unwrap_err();
    assert_eq!(error.issues[0].source_ordinal, 0);
    assert!(error.issues[0]
        .reason
        .contains("savefile header property requires a captured scalar"));
}
#[test]
fn world_header_exception_is_exact_and_does_not_cover_runtime_fields() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/world").unwrap();
    let name = symbols.intern("fps").unwrap();
    let mut header = write(
        owner,
        name,
        InitializerValue::Expression(expression("2", &mut symbols).unwrap()),
    );
    header.target = InitializerTarget::Instance {
        declaring_owner: owner,
        receiver_owner: owner,
        name,
    };
    header.declaration_flags = None;
    let result = classify_with_diagnostics(&[header.clone()], &symbols, &Evaluator).unwrap();
    assert_eq!(result.writes[0].write.declaration_flags, None);
    assert_eq!(result.writes[0].phase, None);
    assert!(result.groups.is_empty());
    let runtime_name = symbols.intern("time").unwrap();
    header.target = InitializerTarget::Instance {
        declaring_owner: owner,
        receiver_owner: owner,
        name: runtime_name,
    };
    let error = classify_with_diagnostics(&[header.clone()], &symbols, &Evaluator).unwrap_err();
    assert!(error.issues[0]
        .reason
        .contains("opaque initializer declaration modifiers"));
    let child = symbols.intern("/world/child").unwrap();
    header.lexical_owner = child;
    header.target = InitializerTarget::Instance {
        declaring_owner: owner,
        receiver_owner: child,
        name,
    };
    assert!(classify_with_diagnostics(&[header], &symbols, &Evaluator)
        .unwrap_err()
        .issues[0]
        .reason
        .contains("opaque initializer declaration modifiers"));
}

#[path = "parallel_tests.rs"]
mod parallel_tests;

#[test]
fn sparse_runtime_model_has_compact_slots_and_releases_evaluated_list_before_codegen() {
    use std::sync::{Mutex, Weak};
    type Entries = [(Option<SemanticValue>, SemanticValue)];
    struct ListOwner {
        last_list: Mutex<Option<Weak<Entries>>>,
        argument_calls: std::sync::atomic::AtomicUsize,
    }
    impl CapturedInitializerEvaluator for ListOwner {
        fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
            let entries: Arc<Entries> =
                Arc::from([(None, SemanticValue::NumberBits(2f32.to_bits()))]);
            *self.last_list.lock().unwrap() = Some(Arc::downgrade(&entries));
            Ok(Evaluation::Scalar(SemanticValue::List(entries)))
        }
        fn evaluate_ast_write(
            &self,
            _: &InitializerWrite,
            ast: &dm_syntax::Expr,
            _: &str,
            _: &SymbolTable,
        ) -> Result<Evaluation, String> {
            assert!(
                self.last_list
                    .lock()
                    .unwrap()
                    .as_ref()
                    .unwrap()
                    .upgrade()
                    .is_none(),
                "discarded evaluated list must not overlap runtime construction preparation"
            );
            self.argument_calls
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            assert_eq!(ast.kind, dm_syntax::ExprKind::Literal("2".into()));
            Ok(Evaluation::Scalar(SemanticValue::NumberBits(
                2f32.to_bits(),
            )))
        }
    }
    // A sparse ledger must not embed the full AST into every scalar write's slot.
    assert!(std::mem::size_of::<RuntimeValue>() <= 3 * std::mem::size_of::<usize>());
    assert!(std::mem::size_of::<Option<RuntimeValue>>() <= 3 * std::mem::size_of::<usize>());
    let evaluator = ListOwner {
        last_list: Mutex::new(None),
        argument_calls: std::sync::atomic::AtomicUsize::new(0),
    };
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("owned_list").unwrap();
    let source = expression("list(2)", &mut symbols).unwrap();
    let mut captured = write(owner, name, InitializerValue::Expression(source));
    let classified = classify(std::slice::from_ref(&captured), &symbols, &evaluator).unwrap();
    assert_eq!(classified.writes[0].phase, Some(Phase::LiteralAllocation));
    assert!(matches!(
        classified.writes[0].default,
        DefaultValue::InitializerExpression { token: 0, .. }
    ));
    let Some(RuntimeValue::Expression(ast)) = &classified.writes[0].runtime_value else {
        panic!("literal list must retain its one runtime AST");
    };
    assert_eq!(
        ast.as_ref(),
        &dm_syntax::parse_expression("list(2)").expr.unwrap()
    );
    assert_eq!(classified.groups[0].writes, [0]);
    assert_eq!(
        evaluator
            .argument_calls
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
    captured.declaration_flags = Some(2);
    let error = classify(&[captured], &symbols, &evaluator).unwrap_err();
    assert!(error.contains("const initializer is not scalar"));
    assert_eq!(
        evaluator
            .argument_calls
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
    assert!(evaluator
        .last_list
        .lock()
        .unwrap()
        .as_ref()
        .unwrap()
        .upgrade()
        .is_none());
}

#[path = "classification/sized_array_tests.rs"]
mod sized_array_tests;
