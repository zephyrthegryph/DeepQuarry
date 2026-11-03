//! Syntactic constant-shape facts for future checker control-flow policies.
//!
//! Adapted from pinned SpacemanDMM dreammaker ast.rs Expression::is_const_eval,
//! Expression::as_term and Term::is_static, commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0). This is deliberately NOT
//! general constant evaluation, truthiness, reachability, or a diagnostic walk.
//! Callers must authenticate compiler-issued syntax/configuration first.

use dm_syntax::{numeric_form::numeric_form, Expr, ExprKind};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ControlConstant {
    StaticTerm,
    ConstantEvaluation,
}

/// Exact structural predicate behind pinned visit_control_condition. Parentheses
/// are Term::Expr boundaries, not transparent simplifications; arithmetic is
/// intentionally not folded. A caller still needs the pinned reachable-block
/// protocol before emitting a finding for an eligible control statement.
pub fn classify(expression: &Expr) -> Result<Option<ControlConstant>, String> {
    if let ExprKind::Binary { op, lhs, rhs } = &expression.kind {
        if matches!(
            op.as_str(),
            "==" | "!=" | "<>" | "<" | ">" | "<=" | ">=" | "&&" | "||"
        ) && static_term(lhs)?
            && static_term(rhs)?
        {
            return Ok(Some(ControlConstant::ConstantEvaluation));
        }
    }
    Ok(static_term(expression)?.then_some(ControlConstant::StaticTerm))
}

fn static_term(expression: &Expr) -> Result<bool, String> {
    match &expression.kind {
        ExprKind::TypePath(_) => Ok(true),
        ExprKind::ObjectInitializer { object, .. } => {
            // The reference's prefab term ignores its modified-field values.
            if matches!(object.kind, ExprKind::TypePath(_)) {
                Ok(true)
            } else {
                Err("constant-shape policy lacks a native prefab-term origin".into())
            }
        }
        ExprKind::Literal(text) => {
            // The actual lexer/macro VALUE is independent of its grammar spelling.
            if let Some(value)=text.original_value(){return Ok(matches!(value,dm_syntax::OriginalTokenValue::Int(_)|dm_syntax::OriginalTokenValue::Float(_)|dm_syntax::OriginalTokenValue::String(_)))}
            let raw = text.as_str();
            if raw == "null" {
                return Ok(true);
            }
            if raw
                .as_bytes()
                .first()
                .is_some_and(|c| c.is_ascii_digit() || *c == b'.')
            {
                numeric_form(raw)?;
                return Ok(true);
            }
            if let Some(parts) = text.parts().map_err(str::to_owned)? {
                let lexical = parts.lexical.map_err(|e| format!("constant-shape lexical facts unavailable: {e:?}"))?;
                return Ok(!lexical.interpolated);
            }
            if raw.starts_with('\'') && raw.ends_with('\'') {
                return Ok(false);
            }
            Err("constant-shape policy has an unsupported native literal kind".into())
        }
        // Even a group containing a literal is Term::Expr, which is not one
        // of pinned is_static's terms. Unary/follow operations also prevent
        // Expression::as_term from returning a bare static term.
        _ => Ok(false),
    }
}

#[cfg(test)]
#[path = "checker_constant_shape_tests.rs"]
mod tests;
