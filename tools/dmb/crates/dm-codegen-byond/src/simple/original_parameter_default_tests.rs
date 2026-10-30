//! Borrowing proof only: production caller selection remains unchanged.
use super::*;
struct NoAnswers;
impl dm_ir::Resolver for NoAnswers {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
#[test]
fn original_defaults_emit_identical_words_without_any_default_text_parse() {
    for (header, defaults) in [
        ("x=1+2,y=4", vec![Some("1+2".into()), Some("4".into())]),
        (
            "x=(1+2),y=x+4",
            vec![Some("(1+2)".into()), Some("x+4".into())],
        ),
        (
            "x=\"é漢\",y=null",
            vec![Some("\"é漢\"".into()), Some("null".into())],
        ),
        ("x,y=4", vec![None, Some("4".into())]),
    ] {
        let source = format!("/proc/p({header})\n    return y\n");
        let cold = dm_syntax::parse_declaration_skeleton(&source);
        assert!(cold.diagnostics.is_empty());
        let issued = dm_syntax::parse_proc_with_origins_from_spans(
            &source,
            cold.items[0].span,
            &cold.tokens,
            0,
        )
        .unwrap();
        let body = dm_syntax::parse_body_items(&issued.item.children);
        let view = dm_syntax::StatementView::from_parsed(&body);
        let inputs = crate::ProcedureInputs {
            parameters: vec!["x".into(), "y".into()],
            parameter_defaults: defaults,
            ..Default::default()
        };
        let symbols = dm_ir::SymbolTable::default();
        let expected =
            match compile_statement_view_with_resolver(view, &inputs, &symbols, &NoAnswers, None) {
                Ok(value) => value,
                Err(errors) => panic!("ordinary default fixture must lower: {errors:?}"),
            };
        let before = emission::default_text_parses();
        let text_before = assignments::text_parse_calls();
        let actual = match compile_statement_view_with_original_defaults(
            view,
            &issued.parameters,
            &source,
            &inputs,
            &symbols,
            &NoAnswers,
            None,
        ) {
            Ok(value) => value,
            Err(errors) => panic!("borrowed default fixture must lower: {errors:?}"),
        };
        assert_eq!(actual.procedure, expected.procedure);
        assert_eq!(emission::default_text_parses(), before);
        assert_eq!(assignments::text_parse_calls(), text_before);
    }
}
#[test]
fn original_default_roster_and_optional_refusal_fail_before_emission() {
    let source = "/proc/p(x=1)\n    return x\n";
    let cold = dm_syntax::parse_declaration_skeleton(source);
    let issued =
        dm_syntax::parse_proc_with_origins_from_spans(source, cold.items[0].span, &cold.tokens, 0)
            .unwrap();
    let body = dm_syntax::parse_body_items(&issued.item.children);
    let view = dm_syntax::StatementView::from_parsed(&body);
    let symbols = dm_ir::SymbolTable::default();
    let inputs = crate::ProcedureInputs {
        parameters: vec!["wrong".into()],
        parameter_defaults: vec![Some("1".into())],
        ..Default::default()
    };
    assert!(compile_statement_view_with_original_defaults(
        view,
        &issued.parameters,
        source,
        &inputs,
        &symbols,
        &NoAnswers,
        None
    )
    .is_err());
    let inputs = crate::ProcedureInputs {
        parameters: vec!["x".into()],
        ..Default::default()
    };
    assert!(compile_statement_view_with_original_defaults(
        view,
        &issued.parameters,
        source,
        &inputs,
        &symbols,
        &NoAnswers,
        None
    )
    .is_err());
    let mut refused = issued.parameters;
    refused.admit_optional_expressions(0);
    let inputs = crate::ProcedureInputs {
        parameters: vec!["x".into()],
        parameter_defaults: vec![Some("1".into())],
        ..Default::default()
    };
    assert!(compile_statement_view_with_original_defaults(
        view, &refused, source, &inputs, &symbols, &NoAnswers, None
    )
    .is_err());
}

#[test]
fn lossless_and_automatic_body_modes_never_reparse_original_defaults() {
    let source = "/proc/p(x=1+2)\n    return x\n";
    let cold = dm_syntax::parse_declaration_skeleton(source);
    let issued =
        dm_syntax::parse_proc_with_origins_from_spans(source, cold.items[0].span, &cold.tokens, 0)
            .unwrap();
    let inputs = crate::ProcedureInputs {
        parameters: vec!["x".into()],
        parameter_defaults: vec![Some("1+2".into())],
        ..Default::default()
    };
    let symbols = dm_ir::SymbolTable::default();
    for already_typed in [true, false] {
        let expected = if already_typed {
            compile_preparsed_lossless_with_resolver(
                &issued.item.children,
                &inputs,
                &symbols,
                &NoAnswers,
                None,
            )
        } else {
            compile_simple_proc_with_resolver_and_debug(
                &issued.item.children,
                &inputs,
                &symbols,
                &NoAnswers,
                None,
            )
        };
        let expected = match expected {
            Ok(value) => value,
            Err(errors) => panic!("compatibility {errors:?}"),
        };
        let before = emission::default_text_parses();
        let actual = if already_typed {
            compile_preparsed_lossless_with_original_defaults(
                &issued.item.children,
                &issued.parameters,
                source,
                &inputs,
                &symbols,
                &NoAnswers,
                None,
            )
        } else {
            compile_simple_proc_with_original_defaults(
                &issued.item.children,
                &issued.parameters,
                source,
                &inputs,
                &symbols,
                &NoAnswers,
                None,
            )
        };
        let actual = match actual {
            Ok(value) => value,
            Err(errors) => panic!("original {errors:?}"),
        };
        assert_eq!(actual.procedure, expected.procedure);
        assert_eq!(emission::default_text_parses(), before);
    }
}
