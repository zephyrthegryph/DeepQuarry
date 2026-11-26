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
