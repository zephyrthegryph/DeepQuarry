//! Compiler behavior regressions for shared native literal syntax.
use super::*;

fn bindings(names: &[&str]) -> LowerBindings {
    LowerBindings {
        global_procs: names
            .iter()
            .map(|name| {
                (
                    (*name).to_owned(),
                    reference(Table::Proc, format!("/proc/{name}")),
                )
            })
            .collect(),
        ..Default::default()
    }
}
fn calls(compiled: &SimpleProc) -> usize {
    compiled
        .code
        .items
        .iter()
        .filter(|item| {
            matches!(item,
                CodeItem::Instruction(instruction) if instruction.opcode == opcode::CALL_GLOB
            )
        })
        .count()
}
fn typed_return_literal(body: &dm_syntax::ParsedBody) -> &dm_syntax::LiteralText {
    let dm_syntax::StatementKind::Return(Some(expression)) = &body.statements[0].kind else {
        panic!("expected return literal");
    };
    let ExprKind::Literal(text) = &expression.kind else {
        panic!("expected literal");
    };
    text
}

#[test]
fn unified_literals_nested_quoted_interpolations_emit_both_calls() {
    let source = r#"/proc/probe()
    return "[outer("a\"b]", "[inner()]")]"
"#;
    let ast = dm_syntax::parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let typed = dm_syntax::parse_proc_body(&ast.items[0]);
    assert!(typed.diagnostics.is_empty(), "{:?}", typed.diagnostics);
    let literal = typed_return_literal(&typed);
    let original = literal.parts().unwrap().unwrap();
    let expressions = original.expressions.as_ptr();
    let compiled = compile_with_lookup(
        &[],
        Some(TypedInput::Statements(dm_syntax::StatementView::all(
            &typed.statements,
        ))),
        &bindings(&["outer", "inner"]),
        None,
        None,
    )
    .unwrap();
    assert_eq!(
        calls(&compiled),
        2,
        "both nested calls execute exactly once"
    );
    assert!(compiled
        .strings
        .iter()
        .any(|text| text.bytes.as_ref() == b"a\"b]"));
    assert_eq!(
        literal.parts().unwrap().unwrap().expressions.as_ptr(),
        expressions,
        "emission must preserve the issuing literal's retained expression owner"
    );
}

#[test]
fn unified_literals_registration_and_emission_agree_on_cooked_leaves() {
    let source = r#"/proc/probe()
    return "[echo("\x74ype_value", @"[raw]", "also")]"
"#;
    let ast = dm_syntax::parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let typed = dm_syntax::parse_proc_body(&ast.items[0]);
    assert!(typed.diagnostics.is_empty(), "{:?}", typed.diagnostics);
    let literal = typed_return_literal(&typed);
    let mut registered = Vec::new();
    visit_native_constant_string_literals(literal, |bytes| registered.push(bytes.to_vec()))
        .unwrap();
    assert_eq!(
        registered,
        [b"type_value".to_vec(), b"[raw]".to_vec(), b"also".to_vec()]
    );
    let compiled = compile_with_lookup(
        &[],
        Some(TypedInput::Statements(dm_syntax::StatementView::all(
            &typed.statements,
        ))),
        &bindings(&["echo"]),
        None,
        None,
    )
    .unwrap();
    assert_eq!(calls(&compiled), 1);
    for leaf in registered {
        assert_eq!(
            compiled
                .strings
                .iter()
                .filter(|text| text.bytes.as_ref() == leaf.as_slice())
                .count(),
            1,
            "each registered constant leaf must have its cooked emitted payload"
        );
    }
}

#[test]
fn unified_literals_discarded_interpolation_preserves_call_effects() {
    let ast = dm_syntax::parse("/proc/probe()\n    \"[side_effect()]\"\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_fixture_proc_with_bindings(&ast.items[0].children, &bindings(&["side_effect"]))
            .unwrap();
    assert_eq!(
        calls(&compiled),
        1,
        "discarding the resulting string must not discard its call"
    );
}

#[test]
fn unified_literals_malformed_interpolation_cannot_emit_as_a_constant() {
    let ast = dm_syntax::parse("/proc/probe()\n    return \"[broken(]\"\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let typed = dm_syntax::parse_proc_body(&ast.items[0]);
    assert!(typed.diagnostics.is_empty(), "{:?}", typed.diagnostics);
    let literal = typed_return_literal(&typed);
    assert!(literal.parts().is_err());
    let errors = compile_with_lookup(
        &[],
        Some(TypedInput::Statements(dm_syntax::StatementView::all(
            &typed.statements,
        ))),
        &bindings(&["broken"]),
        None,
        None,
    )
    .unwrap_err();
    assert!(
        errors
            .iter()
            .any(|error| error.reason.contains("invalid string interpolation")),
        "{errors:?}"
    );
}
