//! Pinned Follow::Field missing-static-type warning + exact call-return hints.
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc, GPL-3.0.
use crate::{
    checker_expression_visit::{Event, Walk},
    checks::{Diagnostic, Severity},
};
use dm_syntax::Span;
use dm_tree::frontend::{ArchivedBody, BodyArchive};
pub fn archived(
    archive: &BodyArchive,
    body: &ArchivedBody<'_>,
    resolver: &(impl dm_ir::Resolver + ?Sized),
    profile: dm_ir::PackedU128,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    rows(
        archive,
        crate::checker_expression_visit::archived(archive, body, resolver, profile)?,
        severity,
    )
}
pub fn rows(
    archive: &BodyArchive,
    walk: Walk<'_>,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    let mut rows = Vec::new();
    for event in walk.events {
        if let Some(row) = diagnostic(archive, severity, event, |_| Ok::<(), String>(()))? {
            rows.push(row);
        }
    }
    Ok(rows)
}

pub(crate) fn diagnostic<E: From<String> + for<'a> From<&'a str>>(
    archive: &BodyArchive,
    severity: Severity,
    event: Event<'_>,
    fund_note: impl FnOnce(usize) -> Result<(), E>,
) -> Result<Option<Diagnostic>, E> {
    diagnostic_using(archive, severity, event, Ok, fund_note)
}

pub(crate) fn diagnostic_using<E: From<String> + for<'a> From<&'a str>>(
    archive: &BodyArchive,
    severity: Severity,
    event: Event<'_>,
    project: impl Fn(Span) -> Result<Span, String>,
    fund_note: impl FnOnce(usize) -> Result<(), E>,
) -> Result<Option<Diagnostic>, E> {
    let Event::FieldWithoutStaticType { expression, at, name, hint } = event else {
        return Ok(None);
    };
    let at = project(at)?;
    let notes = crate::checker_static_type_notes::notes_using(archive, at, hint, &project, fund_note)?;
    Ok(Some(Diagnostic {
        family: "field_access_static_type",
        severity,
        span: at,
        expression_span: project(expression.span)?,
        message: format!("field access requires static type: {name:?}"),
        notes,
    }))
}
// Source locations are compiler-issued scalar facts, not serialized models.
// Note::legacy_text retains existing string notes for old fixture consumers:
// source.map(|s|format!("{}:{}: {}",s.line,s.byte_column,message)).unwrap_or(message).
