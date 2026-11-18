//! Stack-safe destruction of original setting/interpolation AST ownership.
//! Nodes move out of their original buffers; no Expr clones/model copies.
use crate::literal::LiteralParts;
use crate::{Expr, ExprKind, SharedSettingRetention};

/// Identifiers/type paths and literals with no owned template syntax have no
/// recursive child AST. Drop their real payload immediately, before anchors;
/// they never enter the heap worklist, including below a compound node.
pub(crate) fn needs_drop_coordination(expression: &Expr) -> bool {
    match &expression.kind {
        ExprKind::Ident(_) | ExprKind::TypePath(_) => false,
        ExprKind::Literal(text) => text.owns_template_syntax(),
        _ => true,
    }
}
fn schedule(pending: &mut Vec<Expr>, expression: Expr) {
    if needs_drop_coordination(&expression) {
        pending.push(expression);
    } else {
        // Caller retains its primary/auxiliary anchors through this actual drop.
        drop(expression);
    }
}
pub(crate) fn drop_expression(expression: Expr, anchor: Option<SharedSettingRetention>) {
    // Acquire BEFORE even the first worklist slot. Escaped literals belonging
    // to different roots of one body share its maximum-root cleanup envelope.
    let cleanup=anchor.as_ref().map(SharedSettingRetention::cleanup_guard);
    let mut pending = Vec::new();
    schedule(&mut pending, expression);
    release(pending);
    drop(cleanup);
    drop(anchor);
}
pub(crate) fn drop_literal_parts(parts: LiteralParts, anchor: Option<SharedSettingRetention>) {
    // The donor Vec is already payload-funded. Filtering/extension happens
    // only after entering this SAME actual cleanup domain.
    let cleanup=anchor.as_ref().map(SharedSettingRetention::cleanup_guard);
    let LiteralParts {
        native_parser_facts: _,
        template,
        fragments,
        expressions,
        lexical: _,
        runtime_error,
    } = parts;
    drop(template);
    drop(fragments);
    drop(runtime_error);
    release(expressions);
    drop(cleanup);
    drop(anchor);
}
fn release(mut pending: Vec<Expr>) {
    // Native root/last-literal callers retain their primary anchor until BOTH
    // worklist and auxiliary anchor buffers are physically freed. Native root
    // admission includes this cleanup coordination headroom.
    // LiteralParts already owns this Vec as payload. Remove only scalar leaves
    // in place, before it becomes the cleanup worklist; do not clone/reparse.
    pending.retain(needs_drop_coordination);
    let mut retained = Vec::new();
    while let Some(expression) = pending.pop() {
        #[cfg(test)]
        if !needs_drop_coordination(&expression) { LEAF_WORKLIST_ENTRIES.with(|count|count.set(count.get()+1)); }
        match expression.kind {
            ExprKind::Literal(literal) => {
                let (parts, retention) = literal.into_drop_parts();
                if let Some(retention) = retention {
                    retained.push(retention);
                }
                if let Some(parts) = parts {
                    drop(parts.template);
                    drop(parts.fragments);
                    drop(parts.runtime_error);
                    for expression in parts.expressions { schedule(&mut pending, expression); }
                }
            }
            kind => release_child_roots(kind, |child| schedule(&mut pending, child)),
        }
    }
    drop(pending);
    // Auxiliary anchors contain quota/atomic Counter DATA only, never Source,
    // AST/model or callbacks. Free this Vec under lock; the caller's PRIMARY
    // anchor keeps the mutex/counter alive and drops only AFTER unlock.
    drop(retained);
}

/// Move direct child roots without allocation, parsing, or recursion. Literal
/// owners remain atomic here and keep their own existing paid cleanup policy.
/// The caller controls storage/funding of the destination frontier.
pub(crate) fn release_child_roots(kind: ExprKind, mut visit: impl FnMut(Expr)) {
    match kind {
        ExprKind::Literal(literal) => drop(literal),
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => visit(*value),
        ExprKind::Binary { lhs, rhs, .. } => {
            visit(*lhs);
            visit(*rhs);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            visit(*condition);
            visit(*then_value);
            visit(*else_value);
        }
        ExprKind::Call { callee, args } => {
            visit(*callee);
            for expression in args { visit( expression); }
        }
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => visit(*object),
        ExprKind::ObjectInitializer { object, fields } => {
            visit(*object);
            for (_, value) in fields {
                visit( value);
            }
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            visit(*object);
            visit(*index);
        }
        ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
    }
}

#[cfg(test)]
thread_local! { static LEAF_WORKLIST_ENTRIES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) }; }
#[cfg(test)]
#[path="setting_drop_leaf_tests.rs"]mod leaf_tests;
