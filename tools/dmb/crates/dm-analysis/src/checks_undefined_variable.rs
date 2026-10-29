//! Bounded pinned untagged variable/typed-field errors, GPL-3.0 provenance as
//! checker_expression_visit. `undefined_variable` is a route, not a TOML tag.
use crate::{
    checker_expression_visit::{self, Event, Walk},
    checks::{Diagnostic, Severity},
};
use dm_ir::{PackedU128, Resolver, SymbolId};
use dm_tree::{
    frontend::{ArchivedBody, BodyArchive, ColdFrontend, ParsedBody},
    SemanticTree,
};
pub fn check(
    frontend: &ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    enabled: bool,
) -> Result<Vec<Diagnostic>, String> {
    if !enabled {
        return Ok(Vec::new());
    }
    rows(
        &frontend.snapshot.tree,
        checker_expression_visit::evaluated(frontend, body, resolver, profile)?,
    )
}
pub fn archived(
    archive: &BodyArchive,
    body: &ArchivedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    enabled: bool,
) -> Result<Vec<Diagnostic>, String> {
    if !enabled {
        return Ok(Vec::new());
    }
    rows(
        archive.tree(),
        checker_expression_visit::archived(archive, body, resolver, profile)?,
    )
}
fn rows(tree: &SemanticTree, walk: Walk<'_>) -> Result<Vec<Diagnostic>, String> {
    let mut out = Vec::new();
    for event in walk.events {
        let (expression, at, message) = match event {
            Event::MissingVariable {
                expression,
                at,
                name,
            } => (expression, at, format!("undefined var: {name:?}")),
            Event::MissingField {
                expression,
                at,
                name,
                receiver,
            } => {
                let owner = if receiver == SymbolId::of("/") {
                    "(global)"
                } else {
                    tree.symbols()
                        .text(receiver)
                        .ok_or("missing field receiver spelling")?
                };
                (
                    expression,
                    at,
                    format!("undefined field: {name:?} on {owner}"),
                )
            }
            _ => continue,
        };
        out.push(Diagnostic {
            family: "undefined_variable",
            severity: Severity::Error,
            span: at,
            expression_span: expression.span,
            message,
            notes: Vec::new(),
        });
    }
    Ok(out)
}

#[cfg(test)]
#[path = "checks_undefined_variable_tests.rs"]
mod tests;
