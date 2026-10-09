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
    Member {
        object: &'a Expr,
        selector: &'a str,
    },
    SafeMember {
        object: &'a Expr,
        selector: &'a str,
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
        ExprKind::Member {
            object, selector, ..
        } => CallTarget::Member { object, selector },
        ExprKind::SafeMember { object, selector } => CallTarget::SafeMember { object, selector },
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
