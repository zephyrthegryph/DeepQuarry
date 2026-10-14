use super::*;
use std::path::Path;

#[test]
fn folded_nameof_preserves_typed_source_errors_and_opaque_proofs() {
    struct Opaque;
    impl Resolver for Opaque {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Unsupported(query)
        }
    }
    let frontend = frontend("/datum/receiver\n    var/known = 1\n");
    for source in [
        "nameof(/datum/actually_absent)",
        "nameof(/datum/receiver/proc/actually_absent)",
        "nameof(/datum/receiver::missing)",
        "0 && nameof(/datum/actually_absent)",
    ] {
        let mut symbols = frontend.snapshot.tree.symbols().clone();
        let expression = expression(source, &mut symbols);
        let write = dm_ir::InitializerWrite {
            source_site: dm_ir::InitializerSite::Declaration,
            target: dm_ir::InitializerTarget::Shared {
                slot: SymbolId::of("probe"),
                owner: SymbolId::of("/"),
                name: SymbolId::of("probe"),
            },
            lexical_owner: SymbolId::of("/"),
            lexical_procedure: None,
            value: dm_ir::InitializerValue::Expression(expression.clone()),
            declared_array: None,
            declaration_flags: Some(0),
        };
        let recorder = dm_session::RecordingResolver::new(frontend.snapshot.tree.as_ref());
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &recorder,
            symbols: &symbols,
        };
        let (evaluation, _) = evaluator
            .evaluate_prepared_write(&write, &expression)
            .unwrap();
        assert!(
            matches!(evaluation, Evaluation::InvalidNameof(_, _)),
            "{source}"
        );
        assert!(
            !recorder.reads().is_empty(),
            "{source} must retain admission reads"
        );
        let opaque = DriverEvaluator {
            resolver: &Opaque,
            ..evaluator
        };
        assert!(
            opaque.evaluate_prepared_write(&write, &expression).is_err(),
            "{source}"
        );
    }
}

struct Source<'a>(&'a str);
impl dm_preprocess::SourceProvider for Source<'_> {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

fn frontend(source: &str) -> ColdFrontend {
    dm_tree::frontend::build_with_config(
        Path::new("probe.dme"),
        &Source(source),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap()
}

fn expression(source: &str, symbols: &mut dm_ir::SymbolTable) -> SymbolicExpression {
    let lexed = dm_syntax::lex_spans(source);
    assert!(lexed.diagnostics.is_empty());
    SymbolicExpression {
        tokens: lexed
            .tokens
            .iter()
            .filter(|token| {
                !matches!(
                    token.kind,
                    dm_syntax::TokenKind::Whitespace
                        | dm_syntax::TokenKind::Comment
                        | dm_syntax::TokenKind::Newline
                )
            })
            .map(|token| dm_ir::ExpressionToken {
                kind: token.kind,
                text: symbols.intern(token.text(source)).unwrap(),
                relative_span: token.span,
            })
            .collect::<Vec<_>>()
            .into(),
    }
}

#[test]
fn qualified_initial_values_match_captured_byond_and_record_current_dependencies() {
    let source = include_str!("../../../fixtures/native_compiler/qualified_initial/probe.dm");
    let captured = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/qualified_initial/probe.native.bin"
    ))
    .unwrap();
    for (name, text) in [
        ("base_value", "/datum/base::value"),
        ("child_value", "/datum/base/child::value"),
        ("changed_value", "/datum/base/changed::value"),
        ("fixed_value", "/datum/base::fixed"),
    ] {
        let frontend = frontend(source);
        let tree = frontend.snapshot.tree.as_ref();
        let mut symbols = tree.symbols().clone();
        let value = expression(text, &mut symbols);
        let recorder = dm_session::RecordingResolver::new(tree);
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &recorder,
            symbols: &symbols,
        };
        let expected = captured
            .variables
            .iter()
            .find(|row| captured.string(row.name) == Some(name.as_bytes()))
            .unwrap();
        assert_eq!(expected.kind, 42);
        assert_eq!(
            evaluator.scalar(SymbolId::of("/"), &value).unwrap(),
            Some(SemanticValue::NumberBits(expected.value))
        );
        let (path, member) = text.rsplit_once("::").unwrap();
        if member == "value" {
            assert!(recorder.reads().iter().any(|read| read.query
                == ResolveQuery::Var {
                    owner: SymbolId::of(path),
                    name: SymbolId::of(member)
                }));
        }
        let plain = expression("value", &mut symbols);
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: tree,
            symbols: &symbols,
        };
        assert_eq!(
            evaluator
                .scalar(SymbolId::of("/datum/base"), &plain)
                .unwrap(),
            None
        );
    }
    let cyclic = frontend("/datum/cycle\n    var/value = /datum/cycle::value\n");
    let mut symbols = cyclic.snapshot.tree.symbols().clone();
    let value = expression("/datum/cycle::value", &mut symbols);
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: cyclic.snapshot.tree.as_ref(),
        symbols: &symbols,
    };
    assert!(evaluator
        .scalar(SymbolId::of("/"), &value)
        .unwrap_err()
        .contains("cycle"));
}

#[test]
fn authored_calls_are_rejected_only_in_instance_defaults_including_nested_arguments() {
    // Domain evidence: user-proc-initializer-domains-20261010-root and
    // user-proc-instance-overrides-20261010-root pinned BYOND 516.1687 receipts.
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("probe.dme"),
        &Source("/proc/receiver_amount()\n    return 7\n/datum/probe\n    var/amount\n"),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let (pinned, _scalar) =
        crate::request_runner::runner_facts::prepare(&frontend, &engine).unwrap();
    let tree = frontend.snapshot.tree.as_ref();
    let owner = SymbolId::of("/datum/probe");
    let mut symbols = tree.symbols().clone();
    for text in [
        "receiver_amount()",
        "list(receiver_amount())",
        "new/datum/probe(receiver_amount())",
    ] {
        let expression = expression(text, &mut symbols);
        for site in [
            dm_ir::InitializerSite::Declaration,
            dm_ir::InitializerSite::Assignment,
        ] {
            let recorder = dm_session::RecordingResolver::new(&pinned);
            let evaluator = DriverEvaluator {
                pure_calls: None,
                resource_search_context: None,
                resolver: &recorder,
                symbols: &symbols,
            };
            let mut write = dm_ir::InitializerWrite {
                source_site: site,
                target: dm_ir::InitializerTarget::Instance {
                    declaring_owner: owner,
                    receiver_owner: owner,
                    name: SymbolId::of("amount"),
                },
                lexical_owner: owner,
                lexical_procedure: None,
                value: dm_ir::InitializerValue::Expression(expression.clone()),
                declared_array: None,
                declaration_flags: Some(0),
            };
            assert!(
                matches!(
                    evaluator.evaluate_write(&write, &expression).unwrap(),
                    Evaluation::SourceError(_)
                ),
                "{text}"
            );
            write.target = dm_ir::InitializerTarget::Shared {
                slot: SymbolId::of("amount"),
                owner,
                name: SymbolId::of("amount"),
            };
            assert!(!matches!(
                evaluator.evaluate_write(&write, &expression).unwrap(),
                Evaluation::SourceError(_)
            ));
        }
    }
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &pinned,
        symbols: &symbols,
    };
    let ast = dm_syntax::parse_expression("list(1)").expr.unwrap();
    let write = dm_ir::InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: dm_ir::InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name: SymbolId::of("amount"),
        },
        lexical_owner: owner,
        lexical_procedure: None,
        value: dm_ir::InitializerValue::NoAuthoredValue,
        declared_array: None,
        declaration_flags: Some(0),
    };
    assert!(evaluator.instance_call_error(&write, &ast).is_none());
}
