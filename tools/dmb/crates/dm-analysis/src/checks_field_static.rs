//! Pinned Follow::Field missing-static-type warning + exact call-return hints.
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc, GPL-3.0.
use crate::{
    checker_expression_visit::{Event, Walk},
    checks::{Diagnostic, Severity},
};
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
    let mut rows=Vec::new();visit_events(archive,severity,walk.events,|row|{rows.push(row);Ok::<(),String>(())})?;Ok(rows)
}
pub(crate) fn visit_events<'a,E:From<String>+for<'e>From<&'e str>>(archive:&BodyArchive,severity:Severity,events:impl IntoIterator<Item=Event<'a>>,mut emit:impl FnMut(Diagnostic)->Result<(),E>)->Result<(),E>{
    for event in events {
        let Event::FieldWithoutStaticType {
            expression,
            at,
            name,
            hint,
        } = event
        else {
            continue;
        };
        let notes = crate::checker_static_type_notes::notes(archive, at, hint)?;
        emit(Diagnostic {
            family: "field_access_static_type",
            severity,
            span: at,
            expression_span: expression.span,
            message: format!("field access requires static type: {name:?}"),
            notes,
        })?;
    }
    Ok(())
}
// Source locations are compiler-issued scalar facts, not serialized models.
// Note::legacy_text retains existing string notes for old fixture consumers:
// source.map(|s|format!("{}:{}: {}",s.line,s.byte_column,message)).unwrap_or(message).
