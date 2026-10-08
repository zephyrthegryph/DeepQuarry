use super::*;
use crate::parse;

#[test]
fn scoped_label_preserves_nested_body_and_targeted_control() {
    let source = "/proc/test(L)\n    if(L)\n        outer_loop:\n            for(var/x in L)\n                break outer_loop\n    if(L)\n        outer_loop:\n            for(var/x in L)\n                continue outer_loop\n";
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let parsed = parse_proc_body(&ast.items[0]);
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    assert_eq!(parsed.statements.len(), 2);
    for (index, control) in parsed.statements.iter().enumerate() {
        let StatementKind::If { then_branch, .. } = &control.kind else {
            panic!("expected if");
        };
        let StatementKind::Label {
            name,
            body: label_body,
        } = &then_branch[0].kind
        else {
            panic!("expected scoped label");
        };
        assert_eq!(name, "outer_loop");
        let StatementKind::For {
            body: loop_body, ..
        } = &label_body[0].kind
        else {
            panic!("expected nested for");
        };
        if index == 0 {
            assert!(
                matches!(&loop_body[0].kind, StatementKind::BreakLabel(label) if label == "outer_loop")
            );
        } else {
            assert!(
                matches!(&loop_body[0].kind, StatementKind::ContinueLabel(label) if label == "outer_loop")
            );
        }
    }
}

#[test]
fn nested_control_and_absolute_spans() {
    let source = "/proc/test(L)\n    var/x = 0\n    for(var/i in L)\n        if(i)\n            x += i\n        else\n            helper()\n    while(x)\n        x = x - 1\n    return x\n";
    let ast = parse(source);
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert_eq!(body.statements.len(), 4);
    let StatementKind::For {
        control: ForControl::Each { binding, iterable },
        body: loop_body,
    } = &body.statements[1].kind
    else {
        panic!("expected foreach")
    };
    assert_eq!(binding, "var/i");
    assert_eq!(&source[iterable.span.range()], "L");
    let StatementKind::If {
        then_branch,
        else_branch,
        ..
    } = &loop_body[0].kind
    else {
        panic!("expected if")
    };
    assert!(matches!(then_branch[0].kind, StatementKind::Assign { .. }));
    assert!(matches!(else_branch[0].kind, StatementKind::Call(_)));
    assert!(matches!(
        body.statements[2].kind,
        StatementKind::While { .. }
    ));
}

#[test]
fn switch_string_labels_do_not_become_numeric_ranges() {
    let ast = parse("/proc/test(choice)\n    switch(choice)\n        if(\"Ready to Hatch\") return 1\n        if(\"Switch to STANDARD\", \"Switch to BROAD\") return 2\n        if(1 to 3) return 3\n");
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let StatementKind::Switch { cases, .. } = &body.statements[0].kind else {
        panic!("switch");
    };
    assert!(matches!(
        cases[0].alternatives[0],
        SwitchAlternative::Exact(_)
    ));
    assert_eq!(cases[1].alternatives.len(), 2);
    assert!(matches!(
        cases[2].alternatives[0],
        SwitchAlternative::Range(_, _)
    ));
}

#[test]
fn parenthesized_return_and_throw_are_control_statements() {
    let ast = parse("/proc/test()\n    return(1 + 2)\n    throw(7)\n");
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert!(matches!(
        body.statements[0].kind,
        StatementKind::Return(Some(_))
    ));
    assert!(matches!(body.statements[1].kind, StatementKind::Throw(_)));
}

#[test]
fn inline_controls_and_native_comma_for() {
    let ast = parse("/proc/test(A)\n    if(!istype(A)) return\n    else return 1\n    for(A, A && !istype(A), A=A.loc);\n    while(A) A = A.loc\n");
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let StatementKind::If {
        then_branch,
        else_branch,
        ..
    } = &body.statements[0].kind
    else {
        panic!("if");
    };
    assert!(matches!(then_branch[0].kind, StatementKind::Return(None)));
    assert!(matches!(
        else_branch[0].kind,
        StatementKind::Return(Some(_))
    ));
    let StatementKind::For {
        control,
        body: loop_body,
    } = &body.statements[1].kind
    else {
        panic!("for");
    };
    assert!(matches!(control, ForControl::CStyle { .. }));
    assert!(loop_body.is_empty());
    let StatementKind::While {
        body: loop_body, ..
    } = &body.statements[2].kind
    else {
        panic!("while");
    };
    assert!(matches!(loop_body[0].kind, StatementKind::Assign { .. }));
}

#[test]
fn pair_iteration_preserves_both_bindings_and_iterable() {
    let ast = parse("/proc/test(L)\n    for(var/I, V in L)\n        output(I, V)\n    for(var/key, value in alist(\"x\" = L))\n        output(key, value)\n    for(var/I, V in L) qdel(V)\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert!(
        matches!(&body.statements[0].kind, StatementKind::For { control: ForControl::Pair { key_binding, value_binding, .. }, .. } if key_binding == "var/I" && value_binding == "V")
    );
    assert!(
        matches!(&body.statements[1].kind, StatementKind::For { control: ForControl::Pair { key_binding, value_binding, .. }, .. } if key_binding == "var/key" && value_binding == "value")
    );
    assert!(
        matches!(&body.statements[2].kind, StatementKind::For { control: ForControl::Pair { .. }, body } if body.len() == 1)
    );
}

#[test]
fn inline_return_if_conditions_from_game_parse_cleanly() {
    let ast = parse("/proc/test(user)\n    if (GLOB.prison_shuttle_moving_to_station || GLOB.prison_shuttle_moving_to_prison) return\n    if (istype(user, /mob/observer)) return\n    if(user.stat || !Adjacent(user)) return\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert!(body.statements.iter().all(|statement| matches!(&statement.kind, StatementKind::If { then_branch, .. } if matches!(&then_branch[0].kind, StatementKind::Return(None)))));
}

#[test]
fn bare_var_declarations_retain_spelling_and_values() {
    let ast = parse(
        "/proc/test()\n    var amount = 1\n    var\tname = \"Ada\"\n    var/typed/item = null\n",
    );
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let declarations = body
        .statements
        .iter()
        .map(|statement| match &statement.kind {
            StatementKind::Var { declaration, value } => {
                assert!(value.is_some());
                declaration.as_str()
            }
            other => panic!("expected var declaration, got {other:?}"),
        })
        .collect::<Vec<_>>();
    assert_eq!(declarations, ["var amount", "var\tname", "var/typed/item"]);
}

#[test]
fn spawn_blocks_and_inline_body_are_structured() {
    let source = "/proc/test()\n    spawn(5)\n        tick()\n    spawn() tick()\n    spawn\n        tick()\n";
    let ast = parse(source);
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert_eq!(body.statements.len(), 3);
    let StatementKind::Spawn {
        delay: Some(delay),
        body: first_body,
    } = &body.statements[0].kind
    else {
        panic!("expected timed spawn")
    };
    assert_eq!(&source[delay.span.range()], "5");
    assert!(matches!(first_body[0].kind, StatementKind::Call(_)));
    for statement in &body.statements[1..] {
        let StatementKind::Spawn { delay, body } = &statement.kind else {
            panic!("expected spawn")
        };
        assert!(delay.is_none());
        assert_eq!(body.len(), 1);
        assert!(matches!(body[0].kind, StatementKind::Call(_)));
    }
}

#[test]
fn do_while_pairs_following_condition() {
    let source = "/proc/test()\n    do\n        tick()\n    while(ready())\n    return 1\n";
    let ast = parse(source);
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert_eq!(body.statements.len(), 2);
    let StatementKind::DoWhile {
        body: loop_body,
        condition,
    } = &body.statements[0].kind
    else {
        panic!("expected do-while")
    };
    assert!(matches!(loop_body[0].kind, StatementKind::Call(_)));
    assert_eq!(&source[condition.span.range()], "ready()");
}

#[test]
fn proc_set_attributes_and_src_in_are_typed() {
    let source = "/obj/proc/test()\n    set waitfor = FALSE\n    set name = \"Look in bag\"\n    set src in view(1)\n    return\n";
    let ast = parse(source);
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert_eq!(body.statements.len(), 4);
    let attributes = body.statements[..3]
        .iter()
        .map(|statement| match &statement.kind {
            StatementKind::Set {
                attribute,
                relation,
                value,
            } => {
                assert!(!source[value.span.range()].is_empty());
                (attribute.as_str(), relation.as_str())
            }
            other => panic!("expected set declaration, got {other:?}"),
        })
        .collect::<Vec<_>>();
    assert_eq!(attributes, [("waitfor", "="), ("name", "="), ("src", "in")]);
}

#[test]
fn switch_and_ternary_return_are_structured() {
    let ast = parse(
        "/proc/test()\n    switch(x)\n        if(1)\n            return 1\n    return x ? 1 : 2\n",
    );
    let body = parse_proc_body(&ast.items[0]);
    assert_eq!(body.statements.len(), 2);
    assert!(matches!(
        body.statements[0].kind,
        StatementKind::Switch { .. }
    ));
    assert!(matches!(
        body.statements[1].kind,
        StatementKind::Return(Some(_))
    ));
    assert!(body.diagnostics.is_empty());
}

#[test]
fn else_if_chain_is_nested_without_orphans() {
    let ast = parse("/proc/test(x)\n    if(x == 1)\n        return 1\n    else if(x == 2)\n        return 2\n    else\n        return 3\n");
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert_eq!(body.statements.len(), 1);
    let StatementKind::If { else_branch, .. } = &body.statements[0].kind else {
        panic!("expected if")
    };
    let StatementKind::If { else_branch, .. } = &else_branch[0].kind else {
        panic!("expected else if")
    };
    assert!(matches!(else_branch[0].kind, StatementKind::Return(_)));
}

#[test]
fn native_common_operations_fixture_has_structured_bodies() {
    let source = include_str!("../../../fixtures/lowering/common_ops.dm");
    let ast = parse(source);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 5);
    for proc in &ast.items {
        let body = parse_proc_body(proc);
        assert!(
            body.diagnostics.is_empty(),
            "{}: {:?}",
            proc.header,
            body.diagnostics
        );
        assert_eq!(body.statements.len(), 1);
        assert!(!matches!(
            body.statements[0].kind,
            StatementKind::Unsupported
        ));
    }
}

#[test]
fn range_for_with_step_is_structured() {
    let source = "/proc/count()\n    for(var/i = 1 to 10 step 2)\n        output(i)\n";
    let ast = parse(source);
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let StatementKind::For {
        control:
            ForControl::Range {
                binding,
                start,
                end,
                step,
            },
        body: loop_body,
    } = &body.statements[0].kind
    else {
        panic!("expected range for")
    };
    assert_eq!(binding, "var/i");
    assert_eq!(&source[start.span.range()], "1");
    assert_eq!(&source[end.span.range()], "10");
    assert_eq!(&source[step.as_ref().unwrap().span.range()], "2");
    assert!(matches!(loop_body[0].kind, StatementKind::Call(_)));
}

#[test]
fn c_style_for_is_structured() {
    let ast = parse("/proc/count(n)\n    for(var/i = 0; i < n; i = i + 1)\n        return i\n");
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert!(matches!(
        body.statements[0].kind,
        StatementKind::For {
            control: ForControl::CStyle { .. },
            ..
        }
    ));
}

#[test]
fn in_range_for_used_by_game_code_is_structured() {
    let ast = parse("/proc/count(n)\n    for(var/i in 1 to n)\n        return i\n");
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    assert!(matches!(
        body.statements[0].kind,
        StatementKind::For {
            control: ForControl::Range { .. },
            ..
        }
    ));
}

#[test]
fn try_catch_and_throw_are_structured() {
    let ast = parse("/proc/guard()\n    try\n        throw \"bad\"\n    catch(var/exception/E)\n        return E\n");
    let body = parse_proc_body(&ast.items[0]);
    assert!(body.diagnostics.is_empty());
    let StatementKind::Try {
        body: protected,
        catch_binding,
        catch_body,
    } = &body.statements[0].kind
    else {
        panic!("expected try")
    };
    assert_eq!(catch_binding.as_deref(), Some("var/exception/E"));
    assert!(matches!(protected[0].kind, StatementKind::Throw(_)));
    assert!(matches!(catch_body[0].kind, StatementKind::Return(Some(_))));
}
