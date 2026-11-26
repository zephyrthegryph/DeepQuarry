//! Reference-only mode for subtrees the scalar evaluator does not evaluate.
//! These nodes have not been value-visited: ordinary name/resource/call adapters
//! are never invoked, and the caller keeps its original short-circuit result.
use dm_syntax::{Expr, ExprKind};
pub(super) fn observe_unevaluated(expression: &Expr, observer: Option<&dyn Fn(&Expr)>) {
    let Some(observer) = observer else {
        return;
    };
    if let ExprKind::Call { callee, args } = &expression.kind {
        if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof") {
            if let [argument] = args.as_slice() {
                observer(argument);
            }
        }
    }
    dm_syntax::for_each_expression_child(expression, |_, child| {
        observe_unevaluated(child, Some(observer));
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::*;
    use std::cell::RefCell;
    #[test]
    fn skipped_nameof_is_observed_without_resolving_or_evaluating_ordinary_operands() {
        for source in [
            "0 && (missing + nameof(world.cpu))",
            "1 || nameof(world.cpu)",
            "1 ? 9 : (missing + nameof(/obj::icon))",
        ] {
            let parsed = dm_syntax::parse_expression(source);
            let observed = RefCell::new(Vec::new());
            let values = RefCell::new(0);
            let observer = |expression: &Expr| observed.borrow_mut().push(expression.span);
            let result = evaluate_expr_with_resources_and_calls_and_nameof_observer(
                parsed.expr.as_ref().unwrap(),
                |_| panic!("skipped ordinary identifier resolved"),
                |_| panic!("skipped string decoded"),
                |_| {
                    *values.borrow_mut() += 1;
                    None
                },
                |_| panic!("skipped resource resolved"),
                None,
                Some(&observer),
            )
            .unwrap();
            assert!(matches!(result, Some(Constant::Number(_))), "{source}");
            assert_eq!(observed.borrow().len(), 1, "{source}");
            assert_eq!(*values.borrow(), 0, "{source}");
            let unchanged = evaluate_expr_with_resources_and_calls(
                parsed.expr.as_ref().unwrap(),
                |_| panic!("ordinary identifier"),
                |_| None,
                |_| panic!("old API must not observe skipped nameof"),
                |_| None,
                None,
            )
            .unwrap();
            assert_eq!(result, unchanged);
        }
    }
}
