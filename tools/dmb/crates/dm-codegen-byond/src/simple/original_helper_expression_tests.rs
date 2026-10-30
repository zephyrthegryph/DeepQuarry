//! No synthetic syntax on the borrowed expression path.
use super::*;
struct NoQueries;
impl dm_ir::Resolver for NoQueries {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        panic!("local/formal-only helper unexpectedly queried {query:?}")
    }
}
#[test]
fn original_input_source_roots_emit_same_words_and_exact_relative_formal_reads() {
    for expression in ["x+y", "(x+y)*2", "x?y:3"] {
        let source = format!("/proc/p(x,y in {expression})\n    return 1\n");
        let cold = dm_syntax::parse_declaration_skeleton(&source);
        let issued = dm_syntax::parse_proc_with_origins_from_spans(
            &source,
            cold.items[0].span,
            &cold.tokens,
            0,
        )
        .unwrap();
        let root = issued.parameters.entries().unwrap()[1]
            .expressions()
            .unwrap()
            .unwrap()
            .source()
            .unwrap();
        let legacy = dm_syntax::parse(&format!("/proc/helper(x,y)\n    return {expression}\n"));
        let body = dm_syntax::parse_body_items(&legacy.items[0].children);
        let inputs = crate::ProcedureInputs {
            parameters: vec!["x".into(), "y".into()],
            ..Default::default()
        };
        let symbols = dm_ir::SymbolTable::default();
        let expected = match compile_statement_view_with_resolver(
            dm_syntax::StatementView::all(&body.statements),
            &inputs,
            &symbols,
            &NoQueries,
            None,
        ) {
            Ok(v) => v,
            Err(e) => panic!("legacy helper {e:?}"),
        };
        let before = assignments::text_parse_calls();
        let (actual, refs) = match compile_return_expression_with_resolver_and_references(
            root,
            &format!("return {expression}"),
            &inputs,
            &symbols,
            &NoQueries,
            None,
        ) {
            Ok(v) => v,
            Err(e) => panic!("borrowed helper {e:?}"),
        };
        assert_eq!(actual.procedure, expected.procedure);
        assert_eq!(assignments::text_parse_calls(), before);
        assert_eq!(refs.unbound_selections, 0);
        assert!(refs
            .references
            .iter()
            .any(|r| matches!(r.meaning, dm_ir::SelectedMeaning::Argument(1))));
        for reference in refs.references {
            let (start, end) = reference
                .relative_span
                .expect("same root coordinate issuance");
            assert_eq!(
                source.get(root.span.start + start..root.span.start + end),
                symbols
                    .text(reference.name)
                    .or_else(|| match reference.name {
                        n if n == SymbolId::of("x") => Some("x"),
                        n if n == SymbolId::of("y") => Some("y"),
                        _ => None,
                    })
            );
        }
    }
}
