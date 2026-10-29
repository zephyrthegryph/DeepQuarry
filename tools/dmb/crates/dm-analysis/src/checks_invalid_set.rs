//! Pinned `invalid_set_value` policy over authenticated compiler syntax.
//! Adapted from SpacemanDMM dreamchecker lib.rs, commit
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0).
//! This is one diagnostic family, not a certificate of full checker parity.

use crate::checks::{BodyView, Diagnostic, Severity};
use dm_syntax::{
    numeric_form::{numeric_form, NumericForm},
    Expr, ExprKind, StatementKind,
};
use dm_tree::frontend::{ArchivedBody, StatementBody};

pub fn check(view: &BodyView<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    check_syntax(view.syntax(), severity)
}

pub fn archived(body: &ArchivedBody<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    check_syntax(body.statement_body(), severity)
}

fn check_syntax(syntax: &StatementBody, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    if !syntax.syntax_complete() {
        return Err("body has unsupported or malformed native syntax".into());
    }
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    let mut diagnostics = Vec::new();
    // The reference checks only the initial contiguous top-level settings,
    // including `set ... in ...`. Later/nested settings belong to other policy.
    for statement in &syntax.parsed().statements {
        let StatementKind::Set {
            attribute, value, ..
        } = &statement.kind
        else {
            break;
        };
        let message = match attribute.as_str() {
            "background" | "waitfor" | "hidden" | "instant" | "popup_menu" => {
                let allowed = match &value.kind {
                    ExprKind::Ident(name) => matches!(name.as_str(), "TRUE" | "FALSE"),
                    ExprKind::Literal(text) if starts_number(text.as_str()) => {
                        matches!(numeric_form(text.as_str())?, NumericForm::Integer(0 | 1))
                    }
                    _ => false,
                };
                (!allowed).then(|| format!("set {attribute} must be 0/1/TRUE/FALSE"))
            }
            "name" | "category" | "desc" => {
                let allowed = match &value.kind {
                    ExprKind::Literal(text) => {
                        is_text(text.as_str())
                            || (attribute == "category" && text.as_str() == "null")
                    }
                    ExprKind::Ident(name) => attribute == "category" && name == "null",
                    _ => false,
                };
                (is_reference_term(value)? && !allowed)
                    .then(|| format!("set {attribute} must have a string value"))
            }
            "invisibility" => {
                let allowed = match &value.kind {
                    ExprKind::Literal(text) if starts_number(text.as_str()) => {
                        matches!(numeric_form(text.as_str())?, NumericForm::Integer(0..=100))
                    }
                    _ => false,
                };
                (!allowed).then(|| "set invisibility must be 0-100".into())
            }
            _ => None,
        };
        if let Some(message) = message {
            diagnostics.push(Diagnostic {
                family: "invalid_set_value",
                severity,
                span: statement.header_span,
                expression_span: value.span,
                message,
                notes: Vec::new(),
            });
        }
    }
    Ok(diagnostics)
}

fn starts_number(raw: &str) -> bool {
    raw.as_bytes()
        .first()
        .is_some_and(|c| c.is_ascii_digit() || *c == b'.')
}

fn is_text(raw: &str) -> bool {
    raw.starts_with('"')
        || raw.starts_with("{\"")
        || raw.starts_with("@\"")
        || raw.starts_with("@'")
        || raw.starts_with("@{\"")
}

// Reference Expression::as_term rejects unary/follow/binary operations; a
// parenthesized expression is itself a Term::Expr, not transparently unwrapped.
fn is_reference_term(value: &Expr) -> Result<bool, String> {
    match &value.kind {
        ExprKind::Ident(_)
        | ExprKind::Literal(_)
        | ExprKind::TypePath(_)
        | ExprKind::Group(_)
        | ExprKind::ObjectInitializer { .. } => Ok(true),
        ExprKind::Unary { op, .. } if op == "new" => Ok(true),
        ExprKind::Call { callee, .. } => match &callee.kind {
            ExprKind::Ident(_) | ExprKind::TypePath(_) => Ok(true),
            ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if matches!(name.as_str(), "call" | "call_ext")) => {
                Ok(true)
            }
            ExprKind::Member { .. } | ExprKind::SafeMember { .. } => Ok(false),
            ExprKind::Unary { op, .. } if op == "new" || op == "new()" => Ok(false),
            _ => Err(
                "invalid_set_value needs a compiler-issued term/follow origin for this call".into(),
            ),
        },
        ExprKind::StaticMember { .. } | ExprKind::TypeFilter { .. } => Err(
            "invalid_set_value needs a compiler-issued term/follow origin for this expression"
                .into(),
        ),
        _ => Ok(false),
    }
}

#[cfg(test)]
#[path = "checks_invalid_set_tests.rs"]
mod tests;
