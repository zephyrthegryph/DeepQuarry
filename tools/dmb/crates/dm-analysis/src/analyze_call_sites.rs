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
struct Calls<'a,'work,W:crate::policy_body_demand::WorkspaceWork> {
    work:&'work mut W,
    names: &'a [&'a str],
    spans: Vec<(Span, String)>,
    roles: Vec<Role>,
    error: Option<W::Error>,
    failed_entry:bool,
}
impl<W:crate::policy_body_demand::WorkspaceWork> Calls<'_,'_,W> {
    fn expression_at(
        &mut self,
        node: &Expr,
        path: &[NodeStep],
        projection: Option<dm_syntax::ProjectedExprView<'_>>,
    ) -> VisitDecision {
        if self.error.is_some(){self.failed_entry=true;return VisitDecision::Stop}
        if let Err(actual)=self.work.checkpoint(){self.error=Some(actual);self.failed_entry=true;return VisitDecision::Stop}
        if W::CHECKED&&self.roles.len()==self.roles.capacity(){let wanted=match self.roles.len().checked_add(1).and_then(|n|n.checked_mul(4)){Some(n)=>n,None=>{self.error=Some(self.work.overflow());self.failed_entry=true;return VisitDecision::Stop}};let bytes=match wanted.checked_mul(std::mem::size_of::<Role>()).and_then(|n|n.checked_add(256)){Some(n)=>n,None=>{self.error=Some(self.work.overflow());self.failed_entry=true;return VisitDecision::Stop}};if let Err(actual)=self.work.temporary(bytes){self.error=Some(actual);self.failed_entry=true;return VisitDecision::Stop}if self.roles.try_reserve_exact(1).is_err()||self.roles.capacity()>wanted{self.error=Some(self.work.allocation_failed());self.failed_entry=true;return VisitDecision::Stop}}
        let parent = self.roles.last().copied().unwrap_or_default();
        self.roles.push(Role::default());
        self.failed_entry=false;
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
                    if W::CHECKED{let bytes=match name.len().checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<(Span,String)>()*4+256)){Some(n)=>n,None=>{self.error=Some(self.work.overflow());return VisitDecision::Stop}};if let Err(actual)=self.work.retain(bytes){self.error=Some(actual);return VisitDecision::Stop}if self.spans.len()==self.spans.capacity(){let maximum=match self.spans.len().checked_add(1).and_then(|n|n.checked_mul(4)){Some(n)=>n,None=>{self.error=Some(self.work.overflow());return VisitDecision::Stop}};if self.spans.try_reserve_exact(1).is_err()||self.spans.capacity()>maximum{self.error=Some(self.work.allocation_failed());return VisitDecision::Stop}}}
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
impl<W:crate::policy_body_demand::WorkspaceWork> TypedVisitor for Calls<'_,'_,W> {
    fn statement(&mut self,_:&dm_syntax::Statement,_:&[NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.work.checkpoint(){Ok(())=>VisitDecision::Descend,Err(actual)=>{self.error=Some(actual);VisitDecision::Stop}}}

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
        if self.failed_entry{self.failed_entry=false;return}
        self.roles
            .pop()
            .expect("balanced projected expression walk");
    }

    fn expression(&mut self, node: &Expr, path: &[NodeStep]) -> VisitDecision {
        self.expression_at(node, path, None)
    }
    fn leave_expression(&mut self, _: &Expr, _: &[NodeStep]) {
        if self.failed_entry{self.failed_entry=false;return}
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
    struct Legacy<'a,D:crate::policy_body_demand::Demand>{poll:&'a mut dyn FnMut()->Result<(),String>,kind:std::marker::PhantomData<D>}
    impl<D:crate::policy_body_demand::Demand> crate::policy_body_demand::WorkspaceWork for Legacy<'_,D>{type Error=D::Error;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),D::Error>{(self.poll)().map_err(|message|Unsupported(message).into())}fn retain(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn overflow(&mut self)->D::Error{"legacy call-site geometry".into()}fn allocation_failed(&mut self)->D::Error{"legacy call-site allocation".into()}fn body<'a>(&mut self,archive:&'a dm_tree::frontend::BodyArchive,ordinal:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,D::Error>{D::parse(archive,ordinal)}}
    named_workspace_using(inputs,root,names,&mut Legacy::<D>{poll:&mut checkpoint,kind:std::marker::PhantomData})
}
/// SAME all-syntax visitor under the actual full-workspace operation's control.
pub fn named_workspace_using<W:crate::policy_body_demand::WorkspaceWork>(inputs:&PolicyInputs,root:&Path,names:&[&str],work:&mut W)->Result<Vec<(String,u32,String)>,W::Error>{
    let mut sites = BTreeSet::new();
    let archive = inputs.archive();
    for ordinal in 0..archive.len() {
        work.checkpoint()?;
        let body = work.body(archive, ordinal)?;
        let expected=archive.occurrences().get(ordinal).ok_or("call-site actual body ordinal absent")?;if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),expected){return Err("call-site operation returned a foreign original body loan".into())}
        if W::CHECKED{let span=body.occurrence().expanded_span;let width=span.end.checked_sub(span.start).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(width)?;}
        let syntax = body.statement_body();
        if !syntax.syntax_complete() {
            return Err(
                Unsupported("call sites need complete native statement syntax".into()).into(),
            );
        }
        let mut visitor = Calls {
            names,
            work:&mut *work,
            spans: Vec::new(),
            roles: Vec::new(),
            error: None,
            failed_entry:false,
        };
        let report = dm_syntax::visit_statements(&syntax.parsed().statements, &mut visitor);
        let Calls{spans,error,..}=visitor;
        if let Some(error) = error {
            return Err(error);
        }
        if report.unsupported_statements != 0 || report.stopped {
            return Err(Unsupported("call-site visit is incomplete".into()).into());
        }
        for (span, name) in spans {
            work.checkpoint()?;
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
            if W::CHECKED{let width=location.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(8192)).ok_or_else(||work.overflow())?;work.temporary(width)?;}
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
            if W::CHECKED{let bytes=relative.capacity().checked_add(2048).ok_or_else(||work.overflow())?;work.retain(bytes)?;}
            sites.insert((relative, line, name));
        }
    }
    if W::CHECKED{let count=sites.len();let maximum=count.checked_mul(4).ok_or_else(||work.overflow())?;let bytes=maximum.checked_mul(std::mem::size_of::<(String,u32,String)>()).and_then(|n|n.checked_add(256)).ok_or_else(||work.overflow())?;work.retain(bytes)?;let mut output=Vec::new();output.try_reserve_exact(count).map_err(|_|work.allocation_failed())?;if output.capacity()>maximum{return Err(work.allocation_failed())}output.extend(sites);Ok(output)}else{Ok(sites.into_iter().collect())}
}
#[cfg(test)]
#[path = "analyze_call_sites_tests.rs"]
mod tests;
