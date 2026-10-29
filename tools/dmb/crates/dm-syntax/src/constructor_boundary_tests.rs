use super::*;
fn expression(source: &str) -> Expr {
    let parsed = parse_expression(source);
    assert!(
        parsed.diagnostics.is_empty(),
        "{source}: {:?}",
        parsed.diagnostics
    );
    parsed.expr.unwrap()
}
fn constructor(value: &Expr) -> &Expr {
    let ExprKind::Unary { op, value } = &value.kind else {
        panic!("expected constructor: {value:?}")
    };
    assert_eq!(op, "new");
    value
}

#[test]
fn member_call_follows_the_new_object_after_its_first_argument_list() {
    let source = "new /datum/probe(1).read(2)";
    let value = expression(source);
    let ExprKind::Call { callee, args } = &value.kind else {
        panic!()
    };
    assert_eq!(args.len(), 1);
    let ExprKind::Member {
        object, selector, ..
    } = &callee.kind
    else {
        panic!()
    };
    assert_eq!(selector, "read");
    assert_eq!(object.span.end, source.find(".read").unwrap());
    let ExprKind::Call { callee, args } = &constructor(object).kind else {
        panic!()
    };
    assert!(matches!(&callee.kind,ExprKind::TypePath(path) if path=="/datum/probe"));
    assert_eq!(args.len(), 1);
}

#[test]
fn index_and_second_call_are_follows_not_absorbed_constructor_targets() {
    let value = expression("new /list(2)[1]");
    let ExprKind::Index { object, .. } = &value.kind else {
        panic!()
    };
    assert!(matches!(constructor(object).kind, ExprKind::Call { .. }));
    let value = expression("new /datum()()");
    let ExprKind::Call { callee, args } = &value.kind else {
        panic!()
    };
    assert!(args.is_empty());
    assert!(matches!(constructor(callee).kind, ExprKind::Call { .. }));
}

#[test]
fn dynamic_target_fields_precede_ctor_arguments_but_later_fields_do_not() {
    let value = expression("new types.selected(3).value");
    let ExprKind::Member {
        object, selector, ..
    } = &value.kind
    else {
        panic!()
    };
    assert_eq!(selector, "value");
    let ExprKind::Call { callee, .. } = &constructor(object).kind else {
        panic!()
    };
    assert!(matches!(&callee.kind,ExprKind::Member {selector,..} if selector=="selected"));
    let value = expression("new /datum.value");
    let ExprKind::Member {
        object, selector, ..
    } = &value.kind
    else {
        panic!()
    };
    assert_eq!(selector, "value");
    assert!(matches!(constructor(object).kind, ExprKind::TypePath(_)));
}

#[test]
fn prefab_modified_fields_stay_inside_target_before_ctor_arguments() {
    let value = expression("new /datum{value=1}(2).value");
    let ExprKind::Member { object, .. } = &value.kind else {
        panic!()
    };
    let ExprKind::Call { callee, args } = &constructor(object).kind else {
        panic!()
    };
    assert_eq!(args.len(), 1);
    assert!(matches!(&callee.kind,ExprKind::ObjectInitializer {fields,..} if fields.len()==1));
}

#[test]
fn bare_contextual_new_can_precede_delimiters_and_postfix_unary_is_outside_it() {
    let value = expression("list(new, new /datum)");
    let ExprKind::Call { args, .. } = &value.kind else {
        panic!()
    };
    assert_eq!(args.len(), 2);
    assert!(
        matches!(&args[0].kind,ExprKind::Call {callee,args} if matches!(&callee.kind,ExprKind::Ident(name) if name=="new") && args.is_empty())
    );
    assert!(matches!(constructor(&args[1]).kind, ExprKind::TypePath(_)));
    let value = expression("new typevar++");
    let ExprKind::Unary { op, value } = &value.kind else {
        panic!()
    };
    assert_eq!(op, "post++");
    assert!(matches!(constructor(value).kind, ExprKind::Ident(_)));
}
