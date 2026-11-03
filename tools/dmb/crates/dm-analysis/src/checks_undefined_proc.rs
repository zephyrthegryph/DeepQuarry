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
    let mut out=Vec::new();visit_events(tree,walk.events,|row|{out.push(row);Ok::<(),String>(())})?;Ok(out)
}
pub(crate) fn visit_events<'a,E:From<String>+for<'e>From<&'e str>>(tree:&SemanticTree,events:impl IntoIterator<Item=Event<'a>>,mut emit:impl FnMut(Diagnostic)->Result<(),E>)->Result<(),E>{
    for event in events {
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
        emit(Diagnostic {
            family: "undefined_proc",
            severity: Severity::Error,
            span: at,
            expression_span: expression.span,
            message: if matches!(&expression.kind, dm_syntax::ExprKind::Call { callee, .. }
                if matches!(dm_syntax::call_target(callee), dm_syntax::CallTarget::GlobalNamed(_)))
            {
                format!("undefined global proc: {name:?}")
            } else {
                format!("undefined proc: {name:?} on {owner}")
            },
            notes: Vec::new(),
        })?;
    }
    Ok(())
}
#[cfg(test)]
#[path = "checks_undefined_proc_tests.rs"]
mod tests;
