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
    check_prefix(&syntax.parsed().statements, severity)
}
fn check_prefix(
    statements: &[dm_syntax::Statement],
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    let mut diagnostics = Vec::new();
    // The reference checks only the initial contiguous top-level settings,
    // including `set ... in ...`. Later/nested settings belong to other policy.
    for statement in statements {
        let Some(setting) = statement.setting() else {
            break;
        };
        let attribute = setting.attribute;
        let value = setting.value.original();
        let message = match attribute {
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
                expression_span: setting.value.current_span(),
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

#[cfg(test)]
mod projected_tests {
    use super::*;
    use std::sync::{atomic::AtomicUsize, Arc};
    struct Provider {
        root: dm_syntax::SettingExpression,
    }
    impl dm_syntax::SettingSyntaxProvider for Provider {
        fn setting(
            &self,
            _: &dm_syntax::Item,
        ) -> Result<dm_syntax::SettingStatement, dm_syntax::Diagnostic> {
            Ok(dm_syntax::SettingStatement {
                attribute: "waitfor".into(),
                relation: "=".into(),
                value: self.root.clone(),
            })
        }
    }
    #[test]
    fn invalid_setting_diagnostics_keep_current_header_and_expression_spans_after_warm_padding() {
        let rhs = "9";
        let input = dm_syntax::lex_spans(rhs);
        let counter = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&counter, 8 * 1024 * 1024, &checkpoint);
        let original = dm_syntax::prepare_setting_expression(
            rhs,
            &input.tokens,
            dm_syntax::Span::new(0, 1),
            &a,
        )
        .unwrap();
        for padding in ["", "\n\n"] {
            let source = format!("{padding}/proc/p()\n    set waitfor = 9\n    return 1\n");
            let full = dm_syntax::parse(&source);
            let provider = Provider {
                root: original
                    .clone()
                    .project_current(source.find('9').unwrap(), 1)
                    .unwrap(),
            };
            let owned = dm_syntax::parse_body_items(&full.items[0].children);
            let projected = dm_syntax::parse_body_items_with_context_and_settings(
                &full.items[0].children,
                &source,
                &|_| None,
                &provider,
                &a,
            );
            let expected = check_prefix(&owned.statements, Severity::Warning).unwrap();
            let current = check_prefix(&projected.statements, Severity::Warning).unwrap();
            assert_eq!(expected, current);
            assert_eq!(current.len(), 1);
            assert_eq!(&source[current[0].expression_span.range()], rhs);
        }
    }
}
