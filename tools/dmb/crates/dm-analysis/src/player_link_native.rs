//! Complete player_link match policy over the ORIGINAL issued native body graph.
//! It observes statement-root simple assignments, not nested named arguments;
//! declared type hints, never inferred values, decide whether a receiver is mob.
use crate::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::{self, Unsupported},
};
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{ExprKind, Span};
use std::{collections::BTreeSet, path::Path};
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: usize,
}
fn is_mob_using<E:From<Unsupported>>(tree:&dm_tree::SemanticTree,ty:&str,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    checkpoint()?;
    if ty == "/mob" {
        return Ok(true);
    }
    if ty.is_empty() {
        return Ok(false);
    }
    let profile = tree.checker_builtin_profile().ok_or_else(|| {
        Unsupported("player-link source type roster lacks certified checker hierarchy".into())
    })?;
    checkpoint()?;
    if !tree
        .checker_source_type_presence(profile, ty)
        .map_err(|e| Unsupported(format!("{e:?}")))?
    {
        return Ok(false);
    }
    checkpoint()?;
    match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(ty))) {
        M::Symbols(rows) => Ok(rows.contains(&SymbolId::of("/mob"))),
        M::Missing => Ok(false),
        _ => Err(Unsupported(
            "player-link receiver ancestry is unavailable".into(),
        ).into()),
    }
}
pub fn findings(
    inputs: &PolicyInputs,
    root: &Path,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    findings_with::<crate::policy_body_demand::Compatibility>(inputs,root,exempt,checkpoint)
}
pub fn findings_checked(
    inputs: &PolicyInputs,
    root: &Path,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>,crate::policy_body_demand::PolicyFailure> {
    findings_with::<crate::policy_body_demand::Checked>(inputs,root,exempt,checkpoint)
}
pub fn findings_with<D:crate::policy_body_demand::Demand>(inputs:&PolicyInputs,root:&Path,exempt:impl Fn(&str)->bool,mut checkpoint:impl FnMut()->Result<(),String>)->Result<Vec<Finding>,D::Error>{
 struct Legacy<'a,D:crate::policy_body_demand::Demand>{poll:&'a mut dyn FnMut()->Result<(),String>,kind:std::marker::PhantomData<D>}
 impl<D:crate::policy_body_demand::Demand> crate::policy_body_demand::WorkspaceWork for Legacy<'_,D>{type Error=D::Error;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),D::Error>{(self.poll)().map_err(|message|Unsupported(message).into())}fn retain(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn overflow(&mut self)->D::Error{"legacy player-link geometry".into()}fn allocation_failed(&mut self)->D::Error{"legacy player-link allocation".into()}fn body<'a>(&mut self,archive:&'a dm_tree::frontend::BodyArchive,ordinal:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,D::Error>{D::parse(archive,ordinal)}}
 findings_workspace_using(inputs,root,exempt,&mut Legacy::<D>{poll:&mut checkpoint,kind:std::marker::PhantomData})
}
/// SAME old receiver/type/statement-root policy, controlled by its actual host.
/// Work carries operation funding only; every body must be issued by this archive.
pub fn findings_workspace_using<W:crate::policy_body_demand::WorkspaceWork>(inputs:&PolicyInputs,root:&Path,exempt:impl Fn(&str)->bool,work:&mut W)->Result<Vec<Finding>,W::Error>{
 let archive=inputs.archive();let tree=archive.tree();tree.checker_builtin_profile().ok_or_else(||Unsupported("player-link needs certified native builtin ancestry".into()))?;
 let mut found=BTreeSet::new();let mut hierarchy=0usize;let mut longest=0usize;
 if W::CHECKED{for ty in tree.types(){work.checkpoint()?;longest=longest.max(tree.symbols().text(ty.path).ok_or("player-link type spelling absent")?.len());}hierarchy=tree.types().len().checked_add(tree.members().len()).and_then(|n|n.checked_mul(256)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(hierarchy)?;}
 for ordinal in 0..archive.len(){
  work.checkpoint()?;let occurrence=&archive.occurrences()[ordinal];
  if W::CHECKED{let width=occurrence.source.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(hierarchy)).ok_or_else(||work.overflow())?;work.temporary(width)?;}
  let rel=dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path,root).ok_or_else(||Unsupported("player-link procedure lies outside root".into()))?.to_string_lossy().replace('\\',"/");
  if exempt(&rel){continue}
  let body=work.body(archive,ordinal)?;if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),occurrence){return Err("player-link operation returned a foreign original body loan".into())}
  if W::CHECKED{let local_width=body.source_locals().map_err(Unsupported)?.scope_admission().map_err(Unsupported)?;let span=occurrence.expanded_span;let bytes=span.end.checked_sub(span.start).and_then(|n|n.checked_add(1)).and_then(|n|n.checked_mul(longest.max(128))).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(local_width)).and_then(|n|n.checked_add(hierarchy)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(bytes)?;}
  let scope=untyped::archived_scope(&body,tree,&[])?.with_archive(archive)?;let owner=tree.symbols().text(scope.owner).ok_or_else(||Unsupported("player-link owner spelling unavailable".into()))?;let owner_is_mob=is_mob_using(tree,owner,&mut||work.checkpoint())?;
  let visited=crate::untyped_order::try_statement_assignments_current(body.statement_body().view(),work,&mut|work|work.checkpoint(),&mut|work,target,_,at:Span,_current_target| -> Result<(),W::Error>{
   work.checkpoint()?;let hit=match &target.kind{
    ExprKind::Ident(name)=>owner_is_mob&&matches!(name.as_str(),"key"|"ckey")&&!scope.locals.contains_key(name),
    ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}if matches!(selector.as_str(),"key"|"ckey")=>match scope.player_link_receiver_type_using(object,&mut||work.checkpoint())?{Some(ty)=>is_mob_using(tree,&ty,&mut||work.checkpoint())?,None=>false},_=>false};
   if !hit{return Ok(())}let point=archive.original_policy_line(at.start).map_err(Unsupported)?;if point.path!=occurrence.source.path{return Err(Unsupported("player-link cross-file statement location needs an issued old-policy projection".into()).into())}
   let source=inputs.file(&point.path).ok_or_else(||Unsupported("player-link statement source not captured".into()))?;if !source.is_compiled()||source.role()!=PolicyRole::DmSource{return Err(Unsupported("player-link statement not compiled DM".into()).into())}let line=source.analyze_display_line(point.line).map_err(|e|Unsupported(e.to_string()))?;
   let candidate=(rel.clone(),line);if !found.contains(&candidate){if W::CHECKED{let kept=candidate.0.capacity().checked_add(2048).ok_or_else(||work.overflow())?;work.retain(kept)?;}found.insert(candidate);}work.checkpoint()
  });
  match visited{Ok(())=>(),Err(crate::untyped_order::PolicyVisitFailure::Callback(actual))=>return Err(actual),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(message))=>return Err(Unsupported(message.into()).into())}
 }
 work.checkpoint()?;if W::CHECKED{let count=found.len();let maximum=count.checked_mul(4).ok_or_else(||work.overflow())?;let kept=maximum.checked_mul(std::mem::size_of::<Finding>()).and_then(|n|n.checked_add(256)).ok_or_else(||work.overflow())?;work.retain(kept)?;let mut output=Vec::new();output.try_reserve_exact(count).map_err(|_|work.allocation_failed())?;if output.capacity()>maximum{return Err(work.allocation_failed())}output.extend(found.into_iter().map(|(rel,line)|Finding{rel,line}));Ok(output)}else{Ok(found.into_iter().map(|(rel,line)|Finding{rel,line}).collect())}
}
#[cfg(test)]
#[path = "player_link_native_tests.rs"]
mod tests;
