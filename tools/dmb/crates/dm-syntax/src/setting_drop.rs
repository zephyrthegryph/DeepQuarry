//! Stack-safe destruction of original setting/interpolation AST ownership.
//! Nodes move out of their original buffers; no Expr clones/model copies.
use crate::literal::LiteralParts;
use crate::{Expr, ExprKind, SharedSettingRetention};

pub(crate) fn drop_expression(expression: Expr, anchor: Option<SharedSettingRetention>) {
    let mut pending = Vec::new();
    pending.push(expression);
    release(pending, anchor);
}
pub(crate) fn drop_literal_parts(parts: LiteralParts, anchor: Option<SharedSettingRetention>) {
    let LiteralParts {
        template,
        expressions,
        lexical: _,
    } = parts;
    drop(template);
    release(expressions, anchor);
}
fn release(mut pending: Vec<Expr>, anchor: Option<SharedSettingRetention>) {
    // Native root/last-literal callers retain their primary anchor until BOTH
    // worklist and auxiliary anchor buffers are physically freed. Native root
    // admission includes this cleanup coordination headroom.
    let mut retained = Vec::new();
    while let Some(expression) = pending.pop() {
        match expression.kind {
            ExprKind::Literal(literal) => {
                let (parts, retention) = literal.into_drop_parts();
                if let Some(retention) = retention {
                    retained.push(retention);
                }
                if let Some(mut parts) = parts {
                    drop(parts.template);
                    pending.append(&mut parts.expressions);
                    drop(parts.expressions);
                }
            }
            ExprKind::Unary { value, .. }
            | ExprKind::Group(value)
            | ExprKind::TypeFilter { value, .. } => pending.push(*value),
            ExprKind::Binary { lhs, rhs, .. } => {
                pending.push(*lhs);
                pending.push(*rhs);
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                pending.push(*condition);
                pending.push(*then_value);
                pending.push(*else_value);
            }
            ExprKind::Call { callee, mut args } => {
                pending.push(*callee);
                pending.append(&mut args);
                drop(args);
            }
            ExprKind::Member { object, .. }
            | ExprKind::StaticMember { object, .. }
            | ExprKind::SafeMember { object, .. } => pending.push(*object),
            ExprKind::ObjectInitializer { object, fields } => {
                pending.push(*object);
                for (_, value) in fields {
                    pending.push(value);
                }
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                pending.push(*object);
                pending.push(*index);
            }
            ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
        }
    }
    drop(pending);
    drop(retained);
    drop(anchor);
}
