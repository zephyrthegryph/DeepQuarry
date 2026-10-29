//! Exact tagged implicit-new missing-hint diagnostic over compiler-issued
//! evaluated-expression events. The branch and wording are adapted from
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc, dreamchecker/lib.rs:1906-1915,
//! GPL-3.0. This is one family, not a complete checker or expression evaluator.
use crate::{
    checker_expression_visit::{self, Event, Walk},
    checks::{Diagnostic, Severity},
};
use dm_ir::{PackedU128, Resolver};
use dm_tree::frontend::{ArchivedBody, BodyArchive, ColdFrontend, ParsedBody};
pub const FAMILY: &str = "no_typehint_implicit_new";
pub fn check(
    frontend: &ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    diagnostics(
        checker_expression_visit::evaluated(frontend, body, resolver, profile)?,
        severity,
    )
}
pub fn archived(
    archive: &BodyArchive,
    body: &ArchivedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    diagnostics(
        checker_expression_visit::archived(archive, body, resolver, profile)?,
        severity,
    )
}
fn diagnostics(walk: Walk<'_>, severity: Severity) -> Result<Vec<Diagnostic>, String> {
    Ok(walk
        .events
        .into_iter()
        .filter_map(|event| {
            let Event::MissingImplicitNewHint { expression } = event else {
                return None;
            };
            Some(Diagnostic {
                family: FAMILY,
                severity,
                span: expression.span,
                expression_span: expression.span,
                message: "no type hint available on implicit new()".into(),
                notes: Vec::new(),
            })
        })
        .collect())
}
#[cfg(test)]
#[path = "checks_implicit_new_tests.rs"]
mod tests;
