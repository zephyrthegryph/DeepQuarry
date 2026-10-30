use super::*;
struct Host;
impl dm_ir::Resolver for Host {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
#[test]
fn preparsed_lossless_fallback_preserves_original_errors() {
    let parsed = dm_syntax::parse("/proc/p()\n    return (1 +)\n");
    let body = &parsed.items[0].children;
    assert!(!dm_syntax::parse_body_items(body).diagnostics.is_empty());
    let inputs = crate::ProcedureInputs::default();
    let symbols = dm_ir::SymbolTable::default();
    let ordinary =
        compile_simple_proc_with_resolver_and_debug(body, &inputs, &symbols, &Host, None)
            .err()
            .unwrap();
    let preparsed = compile_preparsed_lossless_with_resolver(body, &inputs, &symbols, &Host, None)
        .err()
        .unwrap();
    assert_eq!(ordinary, preparsed);
}

#[test]
fn immutable_mask_matches_owned_filter_for_labels_and_empty_else() {
    let source = dm_syntax::parse(
        "/proc/p()\n    outer:\n        set waitfor = 0\n        for(var/x in list(1, 2))\n            continue outer\n    if(1)\n        return 7\n    else\n        set name = \"hidden\"\n",
    );
    let body = dm_syntax::parse_body_items(&source.items[0].children);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let mask = dm_syntax::StatementMask::from_predicate(&body.statements, |statement| {
        matches!(statement.kind, StatementKind::Set { .. })
    });
    let filtered = dm_syntax::filter_statements(body.statements.clone(), &mut |statement| {
        !matches!(statement.kind, StatementKind::Set { .. })
    });
    let inputs = crate::ProcedureInputs::default();
    let symbols = dm_ir::SymbolTable::default();
    let expected =
        compile_typed_statements_with_resolver(&filtered, &inputs, &symbols, &Host, None).unwrap();
    let actual = compile_statement_view_with_resolver(
        dm_syntax::StatementView::masked(&body.statements, &mask),
        &inputs,
        &symbols,
        &Host,
        None,
    )
    .unwrap();
    assert_eq!(expected.procedure, actual.procedure);
    assert!(matches!(
        body.statements[0].kind,
        StatementKind::Label { .. }
    ));
    let StatementKind::Label { body: retained, .. } = &body.statements[0].kind else {
        unreachable!()
    };
    assert!(matches!(retained[0].kind, StatementKind::Set { .. }));
}

#[test]
fn native_array_dimensions_lower_from_same_original_roots_without_text_parse() {
    // This focused lowering fixture supplies ONLY the known symbolic runtime
    // list operand. Existing native executable-word fixtures authenticate the
    // actual builtin payload; no other type/procedure answer is fabricated.
    struct ListOnly;
    impl dm_ir::Resolver for ListOnly {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            match query {
                dm_ir::ResolveQuery::RuntimeType(path) if path == SymbolId::of("/list") => {
                    dm_ir::ResolvedMeaning::Symbol(path)
                }
                _ => dm_ir::ResolvedMeaning::Unsupported(query),
            }
        }
    }
    for denied in [
        dm_ir::ResolveQuery::Type(SymbolId::of("/list")),
        dm_ir::ResolveQuery::RuntimeType(SymbolId::of("/datum")),
    ] {
        assert_eq!(
            dm_ir::Resolver::resolve(&ListOnly, denied),
            dm_ir::ResolvedMeaning::Unsupported(denied)
        );
    }
    for source in [
        "/proc/p()\n    var/x[3]\n    return x\n",
        "/proc/p()\n    var/x[2][3] = list(1)\n    return x\n",
    ] {
        let parsed = dm_syntax::parse(source);
        let body = dm_syntax::parse_body_items(&parsed.items[0].children);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let root = &body.local_variables.entries().unwrap()[0]
            .array_syntax
            .as_ref()
            .unwrap()
            .root
            .dimensions[0];
        let original_ptr = root as *const Expr;
        let inputs = crate::ProcedureInputs::default();
        let symbols = dm_ir::SymbolTable::default();
        let before_legacy = assignments::text_parse_calls();
        let expected = compile_typed_statements_with_resolver(
            &body.statements,
            &inputs,
            &symbols,
            &ListOnly,
            None,
        )
        .unwrap();
        assert!(
            assignments::text_parse_calls() > before_legacy,
            "independent compatibility lowering must exercise its original dimension parser"
        );
        let before_native = assignments::text_parse_calls();
        let actual = compile_statement_view_with_resolver(
            dm_syntax::StatementView::from_parsed(&body),
            &inputs,
            &symbols,
            &ListOnly,
            None,
        )
        .unwrap();
        assert_eq!(
            assignments::text_parse_calls(),
            before_native,
            "native owner path must not parse dimension text again"
        );
        assert_eq!(expected.procedure, actual.procedure);
        assert_eq!(
            original_ptr,
            &body.local_variables.entries().unwrap()[0]
                .array_syntax
                .as_ref()
                .unwrap()
                .root
                .dimensions[0] as *const Expr
        );
    }
}

#[test]
fn native_mixed_empty_suffix_uses_original_nonempty_dimension_allocation() {
    let parse = |source: &str| {
        let syntax = dm_syntax::parse(source);
        let body = dm_syntax::parse_proc_body(&syntax.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        body
    };
    let mixed = parse("/proc/p()\n    var/x[2][]\n    return x\n");
    let flat = parse("/proc/p()\n    var/x[2]\n    return x\n");
    let inputs = crate::ProcedureInputs::default();
    let symbols = dm_ir::SymbolTable::default();
    let expected =
        compile_typed_statements_with_resolver(&flat.statements, &inputs, &symbols, &Host, None)
            .unwrap();
    let before = assignments::text_parse_calls();
    let actual = compile_statement_view_with_resolver(
        dm_syntax::StatementView::from_parsed(&mixed),
        &inputs,
        &symbols,
        &Host,
        None,
    )
    .unwrap();
    assert_eq!(assignments::text_parse_calls(), before);
    assert_eq!(actual.procedure.code, expected.procedure.code);
    assert_eq!(actual.procedure.local_names, ["x"]);
}

#[test]
fn original_cstyle_array_and_division_dimension_reuse_the_issued_roots() {
    for source in [
        "/proc/p()\n    for(var/x[2];0;)\n        break\n",
        "/proc/p()\n    var/x[6 / 2]\n    return x\n",
    ] {
        let syntax = dm_syntax::parse(source);
        let body = dm_syntax::parse_proc_body(&syntax.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        let before = assignments::text_parse_calls();
        let actual = compile_statement_view_with_resolver(
            dm_syntax::StatementView::from_parsed(&body),
            &crate::ProcedureInputs::default(),
            &dm_ir::SymbolTable::default(),
            &Host,
            None,
        )
        .unwrap();
        assert_eq!(assignments::text_parse_calls(), before);
        assert_eq!(actual.procedure.local_names, ["x"]);
        assert!(actual.procedure.code.items.iter().any(|item|matches!(item,CodeItem::Instruction(instruction) if instruction.opcode==opcode::EMPTY_LIST)),"sized array allocation cannot disappear");
    }
}

#[test]
fn original_cstyle_dimension_name_still_rejects_parameter_collisions() {
    let source = "/proc/p(x)\n    for(var/x[6 / 2];0;)\n        break\n";
    let syntax = dm_syntax::parse(source);
    let body = dm_syntax::parse_proc_body(&syntax.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let inputs = crate::ProcedureInputs {
        parameters: vec!["x".into()],
        ..Default::default()
    };
    let error = compile_statement_view_with_resolver(
        dm_syntax::StatementView::from_parsed(&body),
        &inputs,
        &dm_ir::SymbolTable::default(),
        &Host,
        None,
    )
    .err()
    .expect("the original local name must collide with its parameter");
    assert_eq!(error.len(), 1);
    assert_eq!(error[0].kind, LowerErrorKind::SourceError);
    assert!(
        format!("{error:?}").contains("x: duplicate definition"),
        "{error:?}"
    );
}

#[test]
fn original_explicit_list_fixture_keeps_an_unsupported_host_fail_closed() {
    // Retain the exact original test source. This Host intentionally supplies
    // no runtime type answers, so it cannot authorize list(1). Actual list
    // executable words remain covered by local_sized_arrays_native fixtures.
    let syntax = dm_syntax::parse("/proc/p()\n    var/x[2][3] = list(1)\n    return x\n");
    let body = dm_syntax::parse_proc_body(&syntax.items[0]);
    let errors = compile_statement_view_with_resolver(
        dm_syntax::StatementView::from_parsed(&body),
        &crate::ProcedureInputs::default(),
        &dm_ir::SymbolTable::default(),
        &Host,
        None,
    )
    .err()
    .expect("unsupported test host cannot invent runtime /list");
    assert_eq!(errors.len(), 1);
    assert_eq!(errors[0].kind, LowerErrorKind::UnsupportedModel);
    assert!(errors[0].reason.contains("runtime type"), "{:?}", errors[0]);
}
#[test]
fn original_array_receipt_alone_extends_native_view_eligibility() {
    let syntax = dm_syntax::parse("/proc/p()\n    var/x[6 / 2]\n    return x\n");
    let body = dm_syntax::parse_proc_body(&syntax.items[0]);
    assert!(!typed_statements_supported(&body.statements));
    assert!(typed_statement_view_supported(
        dm_syntax::StatementView::from_parsed(&body)
    ));
}
