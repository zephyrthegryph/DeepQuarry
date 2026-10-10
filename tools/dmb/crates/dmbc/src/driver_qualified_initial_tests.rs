use super::*;
use std::path::Path;

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
