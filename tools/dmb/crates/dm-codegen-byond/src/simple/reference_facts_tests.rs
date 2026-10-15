use super::*;
struct NoQueries;
impl dm_ir::Resolver for NoQueries {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        panic!("local/argument capture must not add semantic probes: {query:?}")
    }
}
#[test]
fn selected_coordinates_are_body_relative_and_invalid_context_is_an_explicit_gap() {
    let inputs = crate::ProcedureInputs {
        parameters: vec!["x".into()],
        ..Default::default()
    };
    let symbols = dm_ir::SymbolTable::default();
    let capture = |source: &str| {
        let ast = dm_syntax::parse(source);
        let body = dm_syntax::parse_body_items(&ast.items[0].children);
        let view = dm_syntax::StatementView::all(&body.statements);
        let (_, facts) = compile_statement_view_with_resolver_and_references_at(
            view,
            &inputs,
            &symbols,
            &NoQueries,
            None,
            ast.items[0].span,
        )
        .unwrap();
        assert!(facts
            .references
            .iter()
            .all(|reference| reference.relative_span.is_some()));
        let (_, invalid) = compile_statement_view_with_resolver_and_references_at(
            view,
            &inputs,
            &symbols,
            &NoQueries,
            None,
            dm_syntax::Span {
                start: usize::MAX,
                end: 0,
            },
        )
        .unwrap();
        assert!(invalid
            .references
            .iter()
            .all(|reference| reference.relative_span.is_none()));
        let (_, standalone) = compile_statement_view_with_resolver_and_references(
            view, &inputs, &symbols, &NoQueries, None,
        )
        .unwrap();
        assert!(standalone
            .references
            .iter()
            .all(|reference| reference.relative_span.is_none()));
        facts
    };
    let first = capture("/proc/read(x)\n    return x\n");
    let shifted = capture("// source shifted\n/proc/read(x)\n    return x\n");
    assert!(!first.references.is_empty());
    assert_eq!(
        first, shifted,
        "current absolute offsets must never enter the retained payload"
    );
}
#[test]
fn property_and_call_facts_record_runtime_dispatch_without_receiver_type_guesses() {
    // DreamMaker 516.1687 rejects `holder.method(value)`, `holder:method(value)` and `holder?.method(value)` on an
    // untyped formal when no proc `method` exists ("holder.method: undefined proc"), so the only valid runtime
    // dispatch on an untyped receiver is a property access and `call(holder, "method")`.
    let source = dm_syntax::parse("/proc/read(holder,value)\n    holder.foo = value\n    call(holder,\"method\")(value)\n    return holder.foo\n");
    let body = dm_syntax::parse_body_items(&source.items[0].children);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let inputs = crate::ProcedureInputs {
        parameters: vec!["holder".into(), "value".into()],
        ..Default::default()
    };
    let symbols = dm_ir::SymbolTable::default();
    let view = dm_syntax::StatementView::all(&body.statements);
    let ordinary =
        crate::compile_statement_view_with_resolver(view, &inputs, &symbols, &NoQueries, None)
            .unwrap();
    let (captured, facts) = compile_statement_view_with_resolver_and_references(
        view, &inputs, &symbols, &NoQueries, None,
    )
    .unwrap();
    assert_eq!(ordinary.procedure, captured.procedure);
    assert!(facts.references.iter().any(|reference| matches!(reference.meaning,M::RuntimeProperty{name,static_property:false,safe:false} if name==SymbolId::of("foo"))));
    assert!(facts.references.iter().any(|reference| matches!(reference.meaning,M::DynamicCall{dispatcher,target_count:2} if dispatcher==SymbolId::of("call"))));
    assert!(!facts.complete);
}
#[test]
fn selected_local_and_argument_facts_preserve_emission_and_current_coordinates() {
    let source = dm_syntax::parse(
        "/proc/read(x)\n    var/y = x\n    if(x)\n        var/z = y\n        y = z\n    return x\n",
    );
    let body = dm_syntax::parse_body_items(&source.items[0].children);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let inputs = crate::ProcedureInputs {
        parameters: vec!["x".into()],
        ..Default::default()
    };
    let symbols = dm_ir::SymbolTable::default();
    let view = dm_syntax::StatementView::all(&body.statements);
    let ordinary =
        crate::compile_statement_view_with_resolver(view, &inputs, &symbols, &NoQueries, None)
            .unwrap();
    let (captured, facts) = compile_statement_view_with_resolver_and_references(
        view, &inputs, &symbols, &NoQueries, None,
    )
    .unwrap();
    assert_eq!(ordinary.procedure, captured.procedure);
    assert!(!facts.complete);
    // DreamMaker rejects a nested `var/x` that shadows the formal `x` ("x: duplicate definition"), so the
    // local in this fixture is `y`.
    let x: Vec<_> = facts
        .references
        .iter()
        .filter(|reference| reference.name == SymbolId::of("x") || reference.name == SymbolId::of("y"))
        .collect();
    assert!(
        x.iter()
            .filter(|reference| reference.meaning == M::Argument(0))
            .count()
            >= 3
    );
    assert!(x
        .iter()
        .any(|reference| matches!(reference.meaning, M::Local(_))));
    assert!(x.iter().all(|reference| !reference.path.is_empty()));
    assert!(x.iter().any(|reference| reference
        .path
        .iter()
        .any(|step| matches!(step, dm_syntax::NodeStep::Branch(_)))));
    // Owned facts are independent of the authored AST lifetime.
    drop(body);
    drop(source);
    assert!(!facts.references.is_empty());
}
