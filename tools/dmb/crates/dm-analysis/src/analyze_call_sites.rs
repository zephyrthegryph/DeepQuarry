//! All-syntax unscoped call-site policy facts, never checker reachability.
//! Reuses the compiler's issued primary body AST and deterministic visitor.
//! Exact legacy target: Analyze sem::procs::call_sites (Term::Call/GlobalCall).
//! Explicit global calls retain their primary scope role, distinct from a
//! global receiver member. New mini-expression targets are not call sites.
use crate::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::Unsupported,
};
use dm_syntax::{Expr, ExprKind, NodeStep, Span, TypedVisitor, VisitDecision};
use std::{collections::BTreeSet, path::Path};
#[derive(Clone, Copy, Default)]
struct Role {
    constructor_operand: bool,
    skip_callee: bool,
}
struct Calls<'a> {
    names: &'a [&'a str],
    spans: Vec<(Span, String)>,
    roles: Vec<Role>,
    error: Option<String>,
}
impl Calls<'_> {
    fn expression_at(
        &mut self,
        node: &Expr,
        path: &[NodeStep],
        projection: Option<dm_syntax::ProjectedExprView<'_>>,
    ) -> VisitDecision {
        let parent = self.roles.last().copied().unwrap_or_default();
        self.roles.push(Role::default());
        let child_zero = matches!(path.last(), Some(NodeStep::Child(0)));
        if parent.skip_callee && child_zero {
            return VisitDecision::Skip;
        }
        if parent.constructor_operand && child_zero {
            // Legacy walk_term(New*) sees ONLY constructor arguments, not a
            // target path/mini-expression, even if that target contains calls.
            return if matches!(&node.kind, ExprKind::Call { .. }) {
                self.roles.last_mut().unwrap().skip_callee = true;
                VisitDecision::Descend
            } else {
                VisitDecision::Skip
            };
        }
        if matches!(&node.kind,ExprKind::Unary{op,..} if op=="new") {
            self.roles.last_mut().unwrap().constructor_operand = true;
        }
        if let ExprKind::Literal(text) = &node.kind {
            match text.parts() {
                Err(error) => {
                    self.error = Some(error.into());
                    return VisitDecision::Stop;
                }
                Ok(Some(parts)) if parts.lexical.is_err() => {
                    self.error = Some("literal interpolation boundary is not certified".into());
                    return VisitDecision::Stop;
                }
                _ => {}
            }
        }
        if let ExprKind::Call { callee, .. } = &node.kind {
            if let dm_syntax::CallTarget::Named(name) | dm_syntax::CallTarget::GlobalNamed(name) =
                dm_syntax::call_target(callee)
            {
                if self.names.contains(&name) {
                    self.spans.push((
                        projection.map_or(callee.span, |v| {
                            v.current_span_of(callee)
                                .expect("original callee in same projected root")
                        }),
                        name.into(),
                    ));
                }
            }
        }
        VisitDecision::Descend
    }
}
impl TypedVisitor for Calls<'_> {
    fn projected_expression(
        &mut self,
        view: dm_syntax::ProjectedExprView<'_>,
        path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        self.expression_at(view.original(), path, Some(view))
    }
    fn leave_projected_expression(
        &mut self,
        _view: dm_syntax::ProjectedExprView<'_>,
        _path: &[NodeStep],
    ) {
        self.roles
            .pop()
            .expect("balanced projected expression walk");
    }

    fn expression(&mut self, node: &Expr, path: &[NodeStep]) -> VisitDecision {
        self.expression_at(node, path, None)
    }
    fn leave_expression(&mut self, _: &Expr, _: &[NodeStep]) {
        self.roles.pop().expect("balanced primary expression walk");
    }
}
/// Compact policy rows only. Raw/source owners and executable AST remain issued
/// native owners. Host encoding acquisition admission must precede this call.
pub fn named(
    inputs: &PolicyInputs,
    root: &Path,
    names: &[&str],
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<(String, u32, String)>, Unsupported> {
    named_with::<crate::policy_body_demand::Compatibility>(inputs, root, names, checkpoint)
}
pub fn named_checked(
    inputs: &PolicyInputs,
    root: &Path,
    names: &[&str],
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<(String, u32, String)>, crate::policy_body_demand::PolicyFailure> {
    named_with::<crate::policy_body_demand::Checked>(inputs, root, names, checkpoint)
}
pub fn named_with<D: crate::policy_body_demand::Demand>(
    inputs: &PolicyInputs,
    root: &Path,
    names: &[&str],
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<(String, u32, String)>, D::Error> {
    let mut sites = BTreeSet::new();
    let archive = inputs.archive();
    for ordinal in 0..archive.len() {
        checkpoint().map_err(Unsupported)?;
        let body = D::parse(archive, ordinal)?;
        let syntax = body.statement_body();
        if !syntax.syntax_complete() {
            return Err(
                Unsupported("call sites need complete native statement syntax".into()).into(),
            );
        }
        let mut visitor = Calls {
            names,
            spans: Vec::new(),
            roles: Vec::new(),
            error: None,
        };
        let report = dm_syntax::visit_statements(&syntax.parsed().statements, &mut visitor);
        if let Some(error) = visitor.error {
            return Err(Unsupported(error).into());
        }
        if report.unsupported_statements != 0 || report.stopped {
            return Err(Unsupported("call-site visit is incomplete".into()).into());
        }
        for (span, name) in visitor.spans {
            checkpoint().map_err(Unsupported)?;
            // A joined logical row does not prove a callee's physical line.
            // This asks for an exact original point first, then ONLY the
            // producer-certified single-physical-line macro line receipt. It
            // never searches text or reuses an unproven coarse row location.
            let location = archive
                .original_policy_line(span.start)
                .map_err(Unsupported)?;
            let source = inputs
                .file(&location.path)
                .ok_or_else(|| Unsupported("call origin has no captured source".into()))?;
            if !source.is_compiled() || source.role() != PolicyRole::DmSource {
                return Err(Unsupported("call origin is not compiled source".into()).into());
            }
            let relative = dm_preprocess::regions::relative_filesystem_path(&location.path, root)
                .as_deref()
                .unwrap_or(location.path.as_path())
                .to_string_lossy()
                .replace('\\', "/");
            let line = u32::try_from(
                source
                    .analyze_display_line(location.line)
                    .map_err(|error| Unsupported(error.to_string()))?,
            )
            .map_err(|_| Unsupported("call line overflow".into()))?;
            sites.insert((relative, line, name));
        }
    }
    Ok(sites.into_iter().collect())
}
#[cfg(test)]
#[path = "analyze_call_sites_tests.rs"]
mod tests;
