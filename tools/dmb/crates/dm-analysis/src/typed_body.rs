//! Analysis over an issued, already parsed body. This module never parses source.
use dm_syntax::{TypedVisitor, VisitReport};
use dm_tree::frontend::{BodyOccurrence, ParsedBody};
use std::fmt;
#[path = "typed_body_queries.rs"]
pub mod queries;
#[cfg(test)]
#[path = "typed_body_tests.rs"]
mod tests;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NoTypedModel;
impl fmt::Display for NoTypedModel {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("issued body has no typed statement model")
    }
}
impl std::error::Error for NoTypedModel {}

/// The occurrence and diagnostics belong to the current issued body. A recovering
/// model may contain unsupported statements; these remain visible to visitors.
pub struct BodyVisit<'a> {
    pub occurrence: &'a BodyOccurrence,
    pub diagnostics: &'a [dm_syntax::Diagnostic],
    pub report: VisitReport,
}

pub fn visit<'a>(
    body: &'a ParsedBody<'_>,
    visitor: &mut impl TypedVisitor,
) -> Result<BodyVisit<'a>, NoTypedModel> {
    let parsed = body.statement_body().ok_or(NoTypedModel)?.parsed();
    Ok(BodyVisit {
        occurrence: body.occurrence(),
        diagnostics: &parsed.diagnostics,
        report: dm_syntax::visit_statements(&parsed.statements, visitor),
    })
}
