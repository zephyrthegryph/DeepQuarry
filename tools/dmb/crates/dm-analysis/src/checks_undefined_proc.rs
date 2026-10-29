//! Untagged pinned undefined-proc errors over evaluated-call events.
//!
//! Pinned reference errors have no errortype string. `undefined_proc` below is
//! an oracle routing key, NOT a new legacy TOML diagnostic-override setting.
//! Default Error severity and exact wording are preserved. This bounded cohort
//! does not certify all checker diagnostics or unsupported call/type contexts.
use crate::{
    checker_expression_visit::{self, Event},
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
    let walk = checker_expression_visit::linear(frontend, body, resolver, profile)?;
    diagnostics(&frontend.snapshot.tree, walk)
}
/// Expanded cohort uses the SAME pinned reachable-block observer, not an AST
/// prewalk that would incorrectly inspect skipped arguments or dead siblings.
pub fn check_evaluated(
    frontend: &ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    enabled: bool,
) -> Result<Vec<Diagnostic>, String> {
    if !enabled {
        return Ok(Vec::new());
    }
    diagnostics(
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
    diagnostics(
        archive.tree(),
        checker_expression_visit::archived(archive, body, resolver, profile)?,
    )
}
fn diagnostics(
    tree: &SemanticTree,
    walk: checker_expression_visit::Walk<'_>,
) -> Result<Vec<Diagnostic>, String> {
    let mut out = Vec::new();
    for event in walk.events {
        let Event::MissingCall {
            expression,
            at,
            name,
            receiver,
        } = event
        else {
            continue;
        };
        let owner = if receiver == SymbolId::of("/") {
            "(global)"
        } else {
            tree.symbols()
                .text(receiver)
                .ok_or("missing receiver source spelling")?
        };
        out.push(Diagnostic {
            family: "undefined_proc",
            severity: Severity::Error,
            span: at,
            expression_span: expression.span,
            message: format!("undefined proc: {name:?} on {owner}"),
            notes: Vec::new(),
        });
    }
    Ok(out)
}
#[cfg(test)]
#[path = "checks_undefined_proc_tests.rs"]
mod tests;
