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

#[test]
fn admitted_original_body_literals_share_children_with_registration_decoder_and_emission(){
    use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
    let source="/proc/probe()\n    return \"value [outer(1)]\"\n";
    let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());
    let admission=dm_syntax::SettingAdmission::with_stack_allowance(&counter,32*1024*1024,1024*1024,&healthy);
    let cleanup=admission.reserve(source.len()*512+8192).unwrap();
    let ast=dm_syntax::parse(source);assert!(ast.diagnostics.is_empty());
    let parsed=dm_syntax::parse_body_items_with_context(&ast.items[0].children,source,&|_|None);
    assert!(typed_return_literal(&parsed).retained_parts().is_none());
    let prepared=dm_syntax::prepare_body_literal_syntax(parsed,cleanup,&admission).unwrap();
    let(parsed,storage)=prepared.into_parts();
    let literal=typed_return_literal(&parsed);let children=literal.parts().unwrap().unwrap().expressions.as_ptr();
    assert_eq!(decode_native_constant_string_literal(literal).unwrap(),None);
    visit_native_constant_string_literals(literal,|_|{}).unwrap();
    let current=compile_with_lookup(&[],Some(TypedInput::Statements(dm_syntax::StatementView::from_parsed(&parsed))),&bindings(&["outer"]),None,None).unwrap();
    let old=dm_syntax::parse_proc_body(&ast.items[0]);
    let expected=compile_with_lookup(&[],Some(TypedInput::Statements(dm_syntax::StatementView::from_parsed(&old))),&bindings(&["outer"]),None,None).unwrap();
    assert_eq!(current,expected,"whole emitted artifact and ordered payloads match owned source parser");
    assert_eq!(literal.parts().unwrap().unwrap().expressions.as_ptr(),children,"all real compiler consumers retain the original syntax");
    drop(old);dm_syntax::drop_body_literal_syntax(parsed,Some(storage));assert_eq!(counter.load(Ordering::Acquire),0);
}
#[test]
fn admitted_body_literal_child_error_is_deferred_to_same_emission_diagnostic(){
    use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
    let source="/proc/probe()\n    return \"bad [1 +]\"\n";
    let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());
    let admission=dm_syntax::SettingAdmission::new(&counter,16*1024*1024,&healthy);
    let cleanup=admission.reserve(source.len()*512+8192).unwrap();
    let ast=dm_syntax::parse(source);let parsed=dm_syntax::parse_body_items_with_context(&ast.items[0].children,source,&|_|None);
    let prepared=dm_syntax::prepare_body_literal_syntax(parsed,cleanup,&admission).unwrap();let(parsed,storage)=prepared.into_parts();assert!(parsed.diagnostics.is_empty());
    let old=dm_syntax::parse_proc_body(&ast.items[0]);
    let current=compile_with_lookup(&[],Some(TypedInput::Statements(dm_syntax::StatementView::from_parsed(&parsed))),&bindings(&[]),None,None).unwrap_err();
    let expected=compile_with_lookup(&[],Some(TypedInput::Statements(dm_syntax::StatementView::from_parsed(&old))),&bindings(&[]),None,None).unwrap_err();
    assert_eq!(format!("{current:?}"),format!("{expected:?}"),"complete actual compiler error is unchanged; no eager source diagnostic");
    drop(old);dm_syntax::drop_body_literal_syntax(parsed,Some(storage));assert_eq!(counter.load(Ordering::Acquire),0);
}
