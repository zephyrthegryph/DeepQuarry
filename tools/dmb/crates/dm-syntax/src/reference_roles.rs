//! Syntax roles consumed by lowering and analysis. These do not infer types or
//! resolve symbols; dispatch and target meanings remain the resolver's job.
use crate::{Expr, ExprKind};
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum ReferenceAccess {
    #[default]
    Read,
    Write,
    ReadWrite,
}
pub fn assignment_target_access(operator: &str) -> Option<ReferenceAccess> {
    match operator {
        "=" => Some(ReferenceAccess::Write),
        "+=" | "-=" | "*=" | "/=" | "%=" | "|=" | "&=" | "^=" | "<<=" | ">>=" | "||=" | "&&=" => {
            Some(ReferenceAccess::ReadWrite)
        }
        _ => None,
    }
}

#[derive(Clone, Copy, Debug)]
pub enum CallTarget<'a> {
    Named(&'a str),
    GlobalNamed(&'a str),
    Member {
        object: &'a Expr,
        selector: &'a str,
    },
    SafeMember {
        object: &'a Expr,
        selector: &'a str,
        via_colon: bool,
    },
    Dynamic {
        dispatcher: &'a str,
        targets: &'a [Expr],
    },
    Unsupported,
}
pub fn call_target(callee: &Expr) -> CallTarget<'_> {
    match &callee.kind {
        ExprKind::Ident(name) => CallTarget::Named(name),
        ExprKind::Unary { op, value } if op == "::" => match &value.kind {
            ExprKind::Ident(name) => CallTarget::GlobalNamed(name),
            _ => CallTarget::Unsupported,
        },
        ExprKind::Member {
            object, selector, ..
        } => CallTarget::Member { object, selector },
        ExprKind::SafeMember {
            object,
            selector,
            via_colon,
        } => CallTarget::SafeMember {
            object,
            selector,
            via_colon: *via_colon,
        },
        ExprKind::Call { callee, args } => match &callee.kind {
            ExprKind::Ident(name) if name == "call" || name == "call_ext" => CallTarget::Dynamic {
                dispatcher: name,
                targets: args,
            },
            _ => CallTarget::Unsupported,
        },
        _ => CallTarget::Unsupported,
    }
}
/// Lexical spelling of a reference-bearing node, without selecting its meaning.
pub fn reference_node_name(node: &Expr) -> Option<&str> {
    match &node.kind {
        ExprKind::Ident(name) => Some(name),
        ExprKind::Unary { op, value } if op == "::" => match &value.kind {
            ExprKind::Ident(name) => Some(name),
            _ => None,
        },
        ExprKind::Member { selector, .. }
        | ExprKind::SafeMember { selector, .. }
        | ExprKind::StaticMember { selector, .. } => Some(selector),
        ExprKind::Call { .. } => match call_target(node) {
            CallTarget::Dynamic { dispatcher, .. } => Some(dispatcher),
            _ => None,
        },
        _ => None,
    }
}
#[derive(Clone, Copy, Debug)]
pub struct NamedArgument<'a> {
    pub key: &'a Expr,
    pub value: &'a Expr,
}
pub fn named_argument(argument: &Expr) -> Option<NamedArgument<'_>> {
    match &argument.kind {
        ExprKind::Binary { op, lhs, rhs } if op == "=" => Some(NamedArgument {
            key: lhs,
            value: rhs,
        }),
        _ => None,
    }
}
pub fn is_global_receiver(object: &Expr) -> bool {
    matches!(&object.kind,ExprKind::Ident(name) if name=="global")
}
/// A sole arglist wrapper is syntax; its contained expression is the evaluated
/// value. This is the same recognition used by target call lowering.
pub fn arglist_argument(args: &[Expr]) -> Option<&Expr> {
    let [argument] = args else {
        return None;
    };
    let ExprKind::Call { callee, args } = &argument.kind else {
        return None;
    };
    let [value] = args.as_slice() else {
        return None;
    };
    matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist").then_some(value)
}
/// These names are emitted as literal values before lexical lookup in lowering.
pub fn is_literal_identifier(name: &str) -> bool {
    matches!(name, "null" | "FALSE" | "TRUE")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parse_expression;
    #[test]
    fn member_receivers_and_named_labels_are_borrowed_not_guessed_bindings() {
        let parsed = parse_expression("holder.run(key = value)").expr.unwrap();
        let ExprKind::Call { callee, args } = &parsed.kind else {
            panic!("call expected")
        };
        let CallTarget::Member { object, selector } = call_target(callee) else {
            panic!("member expected")
        };
        assert_eq!(selector, "run");
        assert!(matches!(&object.kind,ExprKind::Ident(name) if name=="holder"));
        let named = named_argument(&args[0]).unwrap();
        assert!(matches!(&named.key.kind,ExprKind::Ident(name) if name=="key"));
        assert!(matches!(&named.value.kind,ExprKind::Ident(name) if name=="value"));
        let ExprKind::Binary { lhs, rhs, .. } = &args[0].kind else {
            unreachable!()
        };
        assert!(std::ptr::eq(named.key, &**lhs));
        assert!(std::ptr::eq(named.value, &**rhs));
    }
}

#[cfg(test)]
mod explicit_global_call_tests {
    use super::*;
    #[test]
    fn scope_call_retains_explicit_global_role_distinct_from_bare_and_member() {
        for (text, global) in [
            ("::req_bool(1)", true),
            ("req_bool(1)", false),
            ("global.req_bool(1)", false),
        ] {
            let parsed = crate::parse_expression(text);
            assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
            let expr = parsed.expr.unwrap();
            let ExprKind::Call { callee, .. } = &expr.kind else {
                panic!()
            };
            assert_eq!(
                matches!(call_target(callee), CallTarget::GlobalNamed("req_bool")),
                global
            );
        }
    }
    #[test]
    fn malformed_or_noncall_scope_refs_remain_explicit_errors() {
        for text in [
            "::",
            "::1()",
            "::name",
            ": :name()",
            ":/*not scope*/:name()",
        ] {
            assert!(
                !crate::parse_expression(text).diagnostics.is_empty(),
                "{text}"
            );
        }
    }
    #[test]
    fn scope_maximal_munch_precedes_ternary_and_member_consumption() {
        for text in [
            "1:::chosen()",
            "a?1:::chosen()",
            "a?1::::chosen()",
            "a : :chosen()",
            "a:/*gap*/:chosen()",
        ] {
            assert!(
                !crate::parse_expression(text).diagnostics.is_empty(),
                "{text}"
            );
        }
        for text in [
            "a ? ::foo() : ::bar()",
            "a?1: ::bar()",
            "a?1:/*gap*/::bar()",
            "a?1: : :bar()",
        ] {
            let parsed = crate::parse_expression(text);
            if text == "a?1: : :bar()" {
                assert!(!parsed.diagnostics.is_empty(), "{text}");
            } else {
                assert!(parsed.diagnostics.is_empty(), "{text}: {parsed:?}");
                let expression = parsed.expr.unwrap();
                let ExprKind::Conditional { else_value, .. } = &expression.kind else {
                    panic!("{text}")
                };
                let ExprKind::Call { callee, .. } = &else_value.kind else {
                    panic!("{text}")
                };
                assert!(
                    matches!(call_target(callee), CallTarget::GlobalNamed("bar")),
                    "{text}"
                );
            }
        }
        let parsed = crate::parse_expression("a::chosen()");
        assert!(parsed.diagnostics.is_empty(), "{parsed:?}");
        let expression = parsed.expr.unwrap();
        let ExprKind::Call { callee, .. } = &expression.kind else {
            panic!()
        };
        assert!(matches!(callee.kind, ExprKind::StaticMember { .. }));
    }
}
