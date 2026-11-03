//! Complete weak_raw_read typed rule over the compiler's ORIGINAL BodyArchive.
//! Raw declaration matching stays with Analyze. Receiver classification reuses
//! the existing stored-reference Walker receiver policy and SAME resolver; no copied model or parser.
use crate::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::{self, Unsupported},
};
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, NodeStep, Span, TypedVisitor, VisitDecision};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::Path,
};
#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: usize,
    pub var: String,
    pub holder: String,
}

fn subtype<E:From<Unsupported>>(tree: &dm_tree::SemanticTree, child: &str, parent: &str,poll:&mut impl FnMut()->Result<(),E>) -> Result<bool, E> {
    poll()?;
    if child == parent {
        return Ok(true);
    }
    let profile = tree.checker_builtin_profile().ok_or_else(|| {
        Unsupported("weak-relation source type roster lacks certified checker hierarchy".into())
    })?;
    poll()?;
    if !tree
        .checker_source_type_presence(profile, child)
        .map_err(|e| Unsupported(format!("{e:?}")))?
    {
        return Ok(false);
    }
    poll()?;
    match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(child))) {
        M::Symbols(ancestors) => Ok(ancestors.contains(&SymbolId::of(parent))),
        M::Missing => Ok(false),
        other => Err(Unsupported(format!(
            "weak-relation ancestry is incomplete: {other:?}"
        )).into()),
    }
}
fn compatible<E:From<Unsupported>>(
    tree: &dm_tree::SemanticTree,
    declarers: &[String],
    holder: &str,poll:&mut impl FnMut()->Result<(),E>,
) -> Result<bool, E> {
    for declaration in declarers {
        poll()?;
        if subtype(tree, holder, declaration,poll)? || subtype(tree, declaration, holder,poll)? {
            return Ok(true);
        }
    }
    Ok(false)
}
struct Mark<'a,W:crate::policy_body_demand::WorkspaceWork>{set:&'a mut HashSet<usize>,work:&'a mut W,error:Option<W::Error>}
impl<W:crate::policy_body_demand::WorkspaceWork> TypedVisitor for Mark<'_,W> {
    fn projected_expression(
        &mut self,
        view: dm_syntax::ProjectedExprView<'_>,
        path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        // Explicitly shape/identity-only; no original span is used as current.
        self.expression(view.original(), path)
    }

    fn expression(&mut self, e: &Expr, _: &[NodeStep]) -> VisitDecision {
        if self.error.is_some(){return VisitDecision::Stop}if let Err(actual)=self.work.checkpoint(){self.error=Some(actual);return VisitDecision::Stop}self.set.insert(e as *const Expr as usize);
        VisitDecision::Descend
    }
}
/// Exclude the exact AST callee head, not its receiver: H.target() is an
/// accessor, but a weak raw receiver in target.child() is still a raw read.
fn mark_callee(e: &Expr, out: &mut HashSet<usize>) {
    // Only an ordinary call's own callee node is an accessor token. A grouped
    // expression used as a dynamic callee still evaluates/reads its contents.
    out.insert(e as *const Expr as usize);
}

pub fn findings(
    inputs: &PolicyInputs,
    root: &Path,
    weak: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    findings_with::<crate::policy_body_demand::Compatibility>(
        inputs, root, weak, exempt, checkpoint,
    )
}
pub fn findings_checked(
    inputs: &PolicyInputs,
    root: &Path,
    weak: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, crate::policy_body_demand::PolicyFailure> {
    findings_with::<crate::policy_body_demand::Checked>(inputs, root, weak, exempt, checkpoint)
}
pub fn findings_with<D: crate::policy_body_demand::Demand>(
    inputs: &PolicyInputs,
    root: &Path,
    weak: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, D::Error> {
    struct Legacy<'a,D:crate::policy_body_demand::Demand>{poll:&'a mut dyn FnMut()->Result<(),String>,kind:std::marker::PhantomData<D>}
    impl<D:crate::policy_body_demand::Demand> crate::policy_body_demand::WorkspaceWork for Legacy<'_,D>{type Error=D::Error;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),D::Error>{(self.poll)().map_err(|m|Unsupported(m).into())}fn retain(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn overflow(&mut self)->D::Error{"legacy weak geometry".into()}fn allocation_failed(&mut self)->D::Error{"legacy weak allocation".into()}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,D::Error>{D::parse(a,n)}}
    findings_workspace_using(inputs,root,weak,exempt,&mut Legacy::<D>{poll:&mut checkpoint,kind:std::marker::PhantomData})
}
/// SAME original marker, declaration receiver, ordered-body and first-hit policy.
pub fn findings_workspace_using<W:crate::policy_body_demand::WorkspaceWork>(inputs:&PolicyInputs,root:&Path,weak:&HashMap<String,Vec<String>>,exempt:impl Fn(&str)->bool,work:&mut W)->Result<Vec<Finding>,W::Error>{
 work.checkpoint()?;if weak.is_empty(){return Ok(Vec::new())}let archive=inputs.archive();let tree=archive.tree();let profile=tree.checker_builtin_profile().ok_or_else(||Unsupported("weak-relation typing needs certified native hierarchy".into()))?;tree.validate_checker_builtin_profile(profile).map_err(|e|Unsupported(format!("{e:?}")))?;
 let mut geometry=0usize;let mut longest=128usize;if W::CHECKED{for t in tree.types(){work.checkpoint()?;longest=longest.max(tree.symbols().text(t.path).ok_or("weak type spelling absent")?.len());}geometry=tree.types().len().checked_add(tree.members().len()).and_then(|n|n.checked_add(archive.len())).and_then(|n|n.checked_mul(longest.checked_add(2048)?)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(geometry)?;}
 let mut rows=BTreeMap::new();for(ordinal,occurrence)in crate::untyped_native::ordered_bodies_using(tree,archive.occurrences(),&mut||work.checkpoint())?{work.checkpoint()?;if W::CHECKED{let width=occurrence.source.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(geometry)).ok_or_else(||work.overflow())?;work.temporary(width)?;}let rel=dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path,root).ok_or_else(||Unsupported("weak-relation procedure is outside captured root".into()))?.to_string_lossy().replace('\\',"/");if exempt(&rel){continue}
 let body=work.body(archive,ordinal)?;if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),occurrence){return Err("weak host returned foreign original body loan".into())}if W::CHECKED{let local=body.source_locals().map_err(Unsupported)?.scope_admission().map_err(Unsupported)?;let span=occurrence.expanded_span;let bytes=span.end.checked_sub(span.start).and_then(|n|n.checked_add(1)).and_then(|n|n.checked_mul(longest)).and_then(|n|n.checked_mul(32)).and_then(|n|n.checked_add(local)).and_then(|n|n.checked_add(geometry)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(bytes)?;}
 let scope=untyped::archived_scope(&body,tree,&[])?.with_archive(archive)?;let owner=tree.symbols().text(scope.owner).ok_or_else(||Unsupported("weak-relation owner spelling unavailable".into()))?;let mut named=HashSet::new();let mut callees=HashSet::new();let control=std::cell::RefCell::new(&mut *work);
 let visited=crate::untyped_order::try_policy_expressions(body.statement_body().view(),&mut||control.borrow_mut().checkpoint(),&mut|observed,at|->Result<(),W::Error>{let work=&mut **control.borrow_mut();let e=observed.original();if let ExprKind::Literal(text)=&e.kind{if let Some(parts)=text.parts().map_err(|e|Unsupported(e.into()))?{parts.lexical.map_err(|e|Unsupported(format!("{e:?}")))?;}}
 if let ExprKind::Call{callee,args}=&e.kind{mark_callee(callee,&mut callees);if matches!(&callee.kind,ExprKind::Ident(n)if n=="nameof"){for argument in args{let mut marker=Mark{set:&mut named,work,error:None};dm_syntax::visit_expression(argument,&mut marker);if let Some(actual)=marker.error{return Err(actual)}}}}
 let address=e as *const Expr as usize;if named.contains(&address)||callees.contains(&address){return Ok(())}let hit=match &e.kind{ExprKind::Ident(name)if weak.contains_key(name)&&!scope.locals.contains_key(name)=>Some((name.as_str(),Some(owner.to_owned()))),ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}if weak.contains_key(selector)=>Some((selector.as_str(),scope.player_link_receiver_type_using(object,&mut||work.checkpoint())?)),_=>None};let Some((var,Some(holder)))=hit else{return Ok(())};if holder.is_empty()||holder=="/"||!compatible(tree,&weak[var],&holder,&mut||work.checkpoint())?{return Ok(())}
 let origin=archive.original_policy_line(at.start).map_err(Unsupported)?;if origin.path!=occurrence.source.path{return Err("weak-relation cross-file statement requires issued old-policy origin projection".into())}let source=inputs.file(&origin.path).ok_or_else(||Unsupported("weak-relation statement source missing".into()))?;if !source.is_compiled()||source.role()!=PolicyRole::DmSource{return Err("weak-relation statement is not compiled original DM".into())}let line=source.analyze_display_line(origin.line).map_err(|e|Unsupported(e.to_string()))?;
 if W::CHECKED{let bytes=rel.len().checked_mul(2).and_then(|n|n.checked_add(var.len().checked_mul(2)?)).and_then(|n|n.checked_add(holder.len())).and_then(|n|n.checked_add(4096)).ok_or_else(||work.overflow())?;work.retain(bytes)?;}rows.entry((rel.clone(),line,var.to_owned())).or_insert_with(||Finding{rel:rel.clone(),line,var:var.to_owned(),holder});work.checkpoint()});
 match visited{Ok(())=>(),Err(crate::untyped_order::PolicyVisitFailure::Callback(actual))=>return Err(actual),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(message))=>return Err(Unsupported(message.into()).into())}
 }work.checkpoint()?;let mut out=if W::CHECKED{let count=rows.len();let max=count.checked_mul(4).ok_or_else(||work.overflow())?;let width=max.checked_mul(std::mem::size_of::<Finding>()).and_then(|n|n.checked_add(256)).ok_or_else(||work.overflow())?;work.retain(width)?;let mut out=Vec::new();out.try_reserve_exact(count).map_err(|_|work.allocation_failed())?;if out.capacity()>max{return Err(work.allocation_failed())}out.extend(rows.into_values());out}else{rows.into_values().collect::<Vec<_>>()};crate::checker_order::sort_source_order(&mut out,&mut|a,b|->Result<std::cmp::Ordering,W::Error>{work.checkpoint()?;Ok(a.rel.cmp(&b.rel).then_with(||a.line.cmp(&b.line)).then_with(||message_bytes(a).cmp(message_bytes(b))))})?;work.checkpoint()?;Ok(out)
}
fn message_bytes(row:&Finding)->impl Iterator<Item=u8>+'_ {std::iter::once(b'`').chain(row.var.bytes()).chain(b"` of ".iter().copied()).chain(row.holder.bytes()).chain(b" is a weak relation read raw; use ".iter().copied()).chain(row.var.bytes()).chain(b"()".iter().copied())}

#[cfg(test)]
#[path = "weak_raw_read_native_tests.rs"]
mod tests;
