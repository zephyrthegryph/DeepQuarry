//! Pinned Follow::Call missing-static-type Warning and exact fix hints.
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc lib.rs2222-2227,
//! GPL-3.0. Arguments are suppressed by the original shared evaluated visitor.
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
fn rows(
    archive: &BodyArchive,
    walk: Walk<'_>,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    let mut out = Vec::new();
    for event in walk.events {
        let Event::UnknownReceiverCall {
            expression,
            at,
            name,
            hint,
        } = event
        else {
            continue;
        };
        let hint = hint.map_err(str::to_owned)?;
        let notes = crate::checker_static_type_notes::notes(archive, at, hint)?;
        out.push(Diagnostic {
            family: "proc_call_static_type",
            severity,
            span: at,
            expression_span: expression.span,
            message: format!("proc call requires static type: {name:?}"),
            notes,
        });
    }
    Ok(out)
}
