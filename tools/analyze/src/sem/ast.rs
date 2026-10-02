//! Small AST helpers over the dreammaker tree: sub-expression iteration, a statement's direct
//! expressions and blocks, and the shapes the semantic checks recognize (`foo(args)`, `a.b(args)`).

use dreammaker::ast::{Block, Case, Expression, Follow, Statement, Term};

/// Calls `f` on `e` and every expression nested in it (terms, call arguments, index operands),
/// pre-order.
pub fn walk_expr<'a>(e: &'a Expression, f: &mut dyn FnMut(&'a Expression)) {
    f(e);
    match e {
        Expression::Base { term, follow } => {
            walk_term(&term.elem, f);
            for fo in follow.iter() {
                match &fo.elem {
                    Follow::Index(_, ix) => walk_expr(ix, f),
                    Follow::Call(_, _, args) => {
                        for a in args.iter() {
                            walk_expr(a, f);
                        }
                    }
                    _ => {}
                }
            }
        }
        Expression::BinaryOp { lhs, rhs, .. } => {
            walk_expr(lhs, f);
            walk_expr(rhs, f);
        }
        Expression::AssignOp { lhs, rhs, .. } => {
            walk_expr(lhs, f);
            walk_expr(rhs, f);
        }
        Expression::TernaryOp { cond, if_, else_ } => {
            walk_expr(cond, f);
            walk_expr(if_, f);
            walk_expr(else_, f);
        }
    }
}

fn walk_term<'a>(t: &'a Term, f: &mut dyn FnMut(&'a Expression)) {
    let each = |es: &'a [Expression], f: &mut dyn FnMut(&'a Expression)| {
        for a in es {
            walk_expr(a, f);
        }
    };
    match t {
        Term::Expr(e) => walk_expr(e, f),
        Term::InterpString(_, parts) => {
            for (e, _) in parts.iter() {
                if let Some(e) = e {
                    walk_expr(e, f);
                }
            }
        }
        Term::Call(_, args) | Term::SelfCall(args) | Term::ParentCall(args) | Term::List(args) | Term::GlobalCall(_, args) => each(args, f),
        Term::NewImplicit { args } | Term::NewPrefab { args, .. } | Term::NewMiniExpr { args, .. } => {
            if let Some(a) = args {
                each(a, f);
            }
        }
        Term::Input { args, in_list, .. } | Term::Locate { args, in_list } => {
            each(args, f);
            if let Some(l) = in_list {
                walk_expr(l, f);
            }
        }
        Term::DynamicCall(a, b) => {
            each(a, f);
            each(b, f);
        }
        Term::ExternalCall { library, function, args } => {
            if let Some(l) = library {
                walk_expr(l, f);
            }
            walk_expr(function, f);
            each(args, f);
        }
        Term::Pick(p) => {
            for (w, e) in p.iter() {
                if let Some(w) = w {
                    walk_expr(w, f);
                }
                walk_expr(e, f);
            }
        }
        Term::Prefab(p) => {
            for (_, e) in p.vars.iter() {
                walk_expr(e, f);
            }
        }
        _ => {}
    }
}

/// The expressions a statement holds directly (conditions, values, loop headers), not those inside
/// its nested blocks.
pub fn stmt_exprs(s: &Statement) -> Vec<&Expression> {
    let mut v: Vec<&Expression> = Vec::new();
    match s {
        Statement::Expr(e) | Statement::Throw(e) | Statement::Del(e) => v.push(e),
        Statement::Return(e) | Statement::Crash(e) => {
            if let Some(e) = e {
                v.push(e);
            }
        }
        Statement::While { condition, .. } => v.push(condition),
        Statement::DoWhile { condition, .. } => v.push(&condition.elem),
        Statement::If { arms, .. } => {
            for (c, _) in arms {
                v.push(&c.elem);
            }
        }
        Statement::ForLoop { test, .. } => {
            if let Some(t) = test {
                v.push(t);
            }
        }
        Statement::ForList(fl) => {
            if let Some(l) = &fl.in_list {
                v.push(l);
            }
        }
        Statement::ForKeyValue(fk) => {
            if let Some(l) = &fk.in_list {
                v.push(l);
            }
        }
        Statement::ForRange(fr) => {
            v.push(&fr.start);
            v.push(&fr.end);
            if let Some(s) = &fr.step {
                v.push(s);
            }
        }
        Statement::Var(vs) => {
            if let Some(e) = &vs.value {
                v.push(e);
            }
        }
        Statement::Vars(vs) => {
            for x in vs {
                if let Some(e) = &x.value {
                    v.push(e);
                }
            }
        }
        Statement::Setting { value, .. } => v.push(value),
        Statement::Spawn { delay, .. } => {
            if let Some(d) = delay {
                v.push(d);
            }
        }
        Statement::Switch { input, cases, .. } => {
            v.push(input);
            for (conds, _) in cases.iter() {
                for c in conds.elem.iter() {
                    match c {
                        Case::Exact(e) => v.push(e),
                        Case::Range(a, b) => {
                            v.push(a);
                            v.push(b);
                        }
                    }
                }
            }
        }
        _ => {}
    }
    v
}

/// The nested blocks of a statement, in source order.
pub fn stmt_blocks(s: &Statement) -> Vec<&Block> {
    let mut v: Vec<&Block> = Vec::new();
    match s {
        Statement::While { block, .. } | Statement::DoWhile { block, .. } | Statement::ForInfinite { block } | Statement::ForLoop { block, .. } => v.push(block),
        Statement::ForList(fl) => v.push(&fl.block),
        Statement::ForKeyValue(fk) => v.push(&fk.block),
        Statement::ForRange(fr) => v.push(&fr.block),
        Statement::If { arms, else_arm } => {
            for (_, b) in arms {
                v.push(b);
            }
            if let Some(b) = else_arm {
                v.push(b);
            }
        }
        Statement::Spawn { block, .. } | Statement::Label { block, .. } => v.push(block),
        Statement::Switch { cases, default, .. } => {
            for (_, b) in cases.iter() {
                v.push(b);
            }
            if let Some(b) = default {
                v.push(b);
            }
        }
        Statement::TryCatch { try_block, catch_block, .. } => {
            v.push(try_block);
            v.push(catch_block);
        }
        _ => {}
    }
    v
}

/// Every expression in a block, recursively (statement expressions and what they nest), with the
/// line of the statement that holds it.
pub fn walk_block<'a>(b: &'a Block, f: &mut dyn FnMut(&'a Expression, u32)) {
    for st in b.iter() {
        let line = st.location.line;
        for e in stmt_exprs(&st.elem) {
            walk_expr(e, &mut |x| f(x, line));
        }
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                for e in stmt_exprs(s) {
                    walk_expr(e, &mut |x| f(x, line));
                }
            }
        }
        for nb in stmt_blocks(&st.elem) {
            walk_block(nb, f);
        }
    }
}

/// `foo(args)` as a whole expression: the unscoped call's name and arguments.
pub fn as_call(e: &Expression) -> Option<(&str, &[Expression])> {
    match e {
        Expression::Base { term, follow } if follow.is_empty() => match &term.elem {
            Term::Call(n, args) => Some((n.as_str(), args)),
            _ => None,
        },
        _ => None,
    }
}

/// A bare identifier expression (`A`, `cell`).
pub fn as_ident(e: &Expression) -> Option<&str> {
    match e {
        Expression::Base { term, follow } if follow.is_empty() => match &term.elem {
            Term::Ident(n) => Some(n.as_str()),
            _ => None,
        },
        Expression::Base { term, follow } if follow.len() == 1 => match (&term.elem, &follow[0].elem) {
            // `(A)` parenthesized is a Term::Expr; unary/! is a follow, so this arm is only for `A` itself.
            (Term::Expr(inner), Follow::Unary(_)) => as_ident(inner).filter(|_| false),
            _ => None,
        },
        _ => None,
    }
}

/// `ident` possibly wrapped in parentheses.
pub fn strip_parens(e: &Expression) -> &Expression {
    if let Expression::Base { term, follow } = e {
        if follow.is_empty() {
            if let Term::Expr(inner) = &term.elem {
                return strip_parens(inner);
            }
        }
    }
    e
}

/// Every call in the expression tree: the unscoped `foo(...)`, and methods `x.foo(...)` (name only).
pub fn calls_in<'a>(e: &'a Expression, f: &mut dyn FnMut(&'a str, &'a [Expression])) {
    walk_expr(e, &mut |x| {
        if let Expression::Base { term, follow } = x {
            if let Term::Call(n, args) = &term.elem {
                f(n.as_str(), args);
            }
            for fo in follow.iter() {
                if let Follow::Call(_, n, args) = &fo.elem {
                    f(n.as_str(), args);
                }
            }
        }
    });
}
