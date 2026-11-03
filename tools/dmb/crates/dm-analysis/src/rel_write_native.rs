//! Complete typed rel_write_undeclared observation over the original body graph.
use crate::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::{self, Unsupported},
};
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, Span};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::Path,
};
#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: usize,
    pub var: String,
    pub message: String,
}
fn under<E:From<Unsupported>>(tree: &dm_tree::SemanticTree, child: &str, parent: &str,poll:&mut impl FnMut()->Result<(),E>) -> Result<bool, E> {
    poll()?;
    if child == parent {
        return Ok(true);
    }
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("relation ancestry needs checker profile".into()))?;
    poll()?;
    if !tree
        .checker_source_type_presence(profile, child)
        .map_err(|e| Unsupported(format!("{e:?}")))?
        || !tree
            .checker_source_type_presence(profile, parent)
            .map_err(|e| Unsupported(format!("{e:?}")))?
    {
        return Ok(false);
    }
    poll()?;
    match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(child))) {
        M::Symbols(xs) => Ok(xs.contains(&SymbolId::of(parent))),
        other => Err(Unsupported(format!(
            "relation ancestry unavailable: {other:?}"
        )).into()),
    }
}
pub fn declared(
    tree: &dm_tree::SemanticTree,
    rels: &HashMap<String, Vec<String>>,
    ty: Option<&str>,
    var: &str,
) -> Result<bool, Unsupported> {
    declared_using(tree,rels,ty,var,&mut||Ok::<(),Unsupported>(()))
}
pub fn declared_using<E:From<Unsupported>>(tree:&dm_tree::SemanticTree,rels:&HashMap<String,Vec<String>>,ty:Option<&str>,var:&str,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    let Some(types) = rels.get(var) else {
        return Ok(false);
    };
    let Some(ty) = ty else { return Ok(true) };
    for d in types {
        poll()?;
        if d == ty || under(tree, ty, d,poll)? || under(tree, d, ty,poll)? {
            return Ok(true);
        }
    }
    Ok(false)
}
fn node_using<'a,E>(mut e:&'a Expr,poll:&mut impl FnMut()->Result<(),E>)->Result<&'a Expr,E>{poll()?;while let ExprKind::Group(inner)=&e.kind{poll()?;e=inner}Ok(e)}
fn nameof_using<'a,E>(e:&'a Expr,poll:&mut impl FnMut()->Result<(),E>)->Result<Option<(Option<&'a Expr>,&'a str)>,E>{
 let ExprKind::Call{callee,args}=&node_using(e,poll)?.kind else{return Ok(None)};if !matches!(&callee.kind,ExprKind::Ident(n)if n=="nameof")||args.len()!=1{return Ok(None)}Ok(match &node_using(&args[0],poll)?.kind{ExprKind::Ident(var)=>Some((None,var)),ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>Some((Some(object),selector)),_=>None})
}

fn pairs(name: &str) -> &'static [(usize, usize)] {
    match name {
        "rel_set" | "rel_add" | "rel_remove" | "rel_clear" | "rel_take" | "rel_take_all"
        | "rel_private" | "rel_is_private" => &[(0, 1)],
        "rel_move" => &[(0, 1), (2, 3)],
        _ => &[],
    }
}
/// Formal metadata comes from the original source/checker owner, not a copied
/// variable table or inferred values. Unknown authored types remain unknown.
pub fn detail(
    inputs: &PolicyInputs,
    root: &Path,
    holder: Option<&str>,
    var: &str,
    verb: &str,
    keyed: bool,
    remaining: &mut usize,
) -> Result<String, Unsupported> {
    detail_using(inputs,root,holder,var,verb,keyed,remaining,false,&mut||Ok::<(),Unsupported>(()),&mut|_|Ok::<(),Unsupported>(()))
}
/// Same exact formal-owner/file/list debug message; operation control only.
pub fn detail_using<E:From<Unsupported>+From<String>>(inputs:&PolicyInputs,root:&Path,holder:Option<&str>,var:&str,verb:&str,keyed:bool,remaining:&mut usize,checked:bool,poll:&mut impl FnMut()->Result<(),E>,reserve:&mut impl FnMut(usize)->Result<(),E>)->Result<String,E>{
    poll()?;
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("relation variable lookup needs checker profile".into()))?;
    let mut owner = String::new();
    let mut file = String::new();
    let mut list = false;
    if let Some(holder) = holder {
        poll()?;
        if tree
            .checker_source_type_presence(profile, holder)
            .map_err(|e| Unsupported(format!("{e:?}")))?
        {
            if let Some(fact) = crate::checker_variable_facts::variable_using(
                tree,
                tree,
                profile,
                SymbolId::of(holder),
                SymbolId::of(var),poll,
            )?
            {
                owner = tree
                    .symbols()
                    .text(fact.owner)
                    .ok_or_else(|| {
                        Unsupported("relation declaration owner spelling unavailable".into())
                    })?
                    .to_owned();
                if let Some(formal) = fact.formal {
                    poll()?;
                    let property = archive
                        .checker_variable_properties(formal, profile)
                        .map_err(Unsupported)?;
                    list = property
                        .declared_hint()
                        .is_some_and(|p| p == "/list" || p.starts_with("/list/"));
                    poll()?;
                    let point = archive
                        .checker_variable_definition_point(formal, profile)
                        .map_err(Unsupported)?;
                    file = dm_preprocess::regions::relative_filesystem_path(&point.path, root)
                        .ok_or_else(|| {
                            Unsupported(
                                "relation formal declaration lies outside captured root".into(),
                            )
                        })?
                        .to_string_lossy()
                        .replace('\\', "/");
                } else {
                    list = fact.metadata.declared_type == Some(SymbolId::of("/list"));
                }
            }
        }
    }
    list |= matches!(verb, "rel_add" | "rel_remove" | "rel_take_all");
    let bound = verb
        .len()
        .checked_add(var.len().saturating_mul(2))
        .and_then(|n| n.checked_add(holder.unwrap_or("an untyped holder").len()))
        .and_then(|n| n.checked_add(owner.len()))
        .and_then(|n| n.checked_add(file.len()))
        .and_then(|n| n.checked_add(512))
        .and_then(|n| n.checked_mul(2))
        .ok_or_else(|| Unsupported("relation finding size overflow".into()))?;
    reserve(bound)?;
    if !checked{*remaining=remaining.checked_sub(bound).ok_or_else(||Unsupported("relation finding budget exceeded before message retention".into()))?;}
    poll()?;
    Ok(format!(
        "{} writes `{}` of {}, which no relation declares [decl {}::{} many={} keyed={} at={}]",
        verb,
        var,
        holder.unwrap_or("an untyped holder"),
        owner,
        var,
        list as u8,
        keyed as u8,
        file
    ))
}
pub fn findings(
    inputs: &PolicyInputs,
    root: &Path,
    rels: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    remaining: &mut usize,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    findings_with::<crate::policy_body_demand::Compatibility>(
        inputs, root, rels, exempt, remaining, checkpoint,
    )
}
pub fn findings_checked(
    inputs: &PolicyInputs,
    root: &Path,
    rels: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    remaining: &mut usize,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, crate::policy_body_demand::PolicyFailure> {
    findings_with::<crate::policy_body_demand::Checked>(
        inputs, root, rels, exempt, remaining, checkpoint,
    )
}
pub fn findings_with<D: crate::policy_body_demand::Demand>(
    inputs: &PolicyInputs,
    root: &Path,
    rels: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    remaining: &mut usize,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, D::Error> {
    struct Legacy<'a,D:crate::policy_body_demand::Demand>{poll:&'a mut dyn FnMut()->Result<(),String>,kind:std::marker::PhantomData<D>}
    impl<D:crate::policy_body_demand::Demand> crate::policy_body_demand::WorkspaceWork for Legacy<'_,D>{type Error=D::Error;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),D::Error>{(self.poll)().map_err(|m|Unsupported(m).into())}fn retain(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn overflow(&mut self)->D::Error{"legacy relation geometry".into()}fn allocation_failed(&mut self)->D::Error{"legacy relation allocation".into()}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,D::Error>{D::parse(a,n)}}
    findings_workspace_using(inputs,root,rels,exempt,remaining,&mut Legacy::<D>{poll:&mut checkpoint,kind:std::marker::PhantomData})
}
/// SAME original prefix/nameof/receiver policy over actual issued body loans.
pub fn findings_workspace_using<W:crate::policy_body_demand::WorkspaceWork>(inputs:&PolicyInputs,root:&Path,rels:&HashMap<String,Vec<String>>,exempt:impl Fn(&str)->bool,remaining:&mut usize,work:&mut W)->Result<Vec<Finding>,W::Error>{
 work.checkpoint()?;let archive=inputs.archive();let tree=archive.tree();tree.checker_builtin_profile().ok_or_else(||Unsupported("relation typing needs certified native hierarchy".into()))?;
 let mut longest=128usize;let mut geometry=0usize;if W::CHECKED{let mut longest_path=root.as_os_str().len();for file in inputs.files(){work.checkpoint()?;longest_path=longest_path.max(file.path().as_os_str().len());}for ty in tree.types(){work.checkpoint()?;longest=longest.max(tree.symbols().text(ty.path).ok_or("relation type spelling unavailable")?.len());}geometry=tree.members().len().checked_add(tree.types().len()).and_then(|n|n.checked_add(archive.len())).and_then(|n|n.checked_mul(longest.checked_add(2048)?)).and_then(|n|n.checked_add(longest_path.checked_mul(128)?)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(geometry)?;}
 let mut found=BTreeMap::new();for(ordinal,occurrence)in crate::untyped_native::ordered_bodies_using(tree,archive.occurrences(),&mut||work.checkpoint())?{work.checkpoint()?;if W::CHECKED{let bytes=occurrence.source.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(geometry)).ok_or_else(||work.overflow())?;work.temporary(bytes)?;}let rel=dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path,root).ok_or_else(||Unsupported("relation procedure outside root".into()))?.to_string_lossy().replace('\\',"/");if exempt(&rel){continue}
 let body=work.body(archive,ordinal)?;if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),occurrence){return Err("relation host returned foreign original body loan".into())}if W::CHECKED{let locals=body.source_locals().map_err(Unsupported)?.scope_admission().map_err(Unsupported)?;let span=occurrence.expanded_span;let bytes=span.end.checked_sub(span.start).and_then(|n|n.checked_add(1)).and_then(|n|n.checked_mul(longest)).and_then(|n|n.checked_mul(32)).and_then(|n|n.checked_add(locals)).and_then(|n|n.checked_add(geometry)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(bytes)?;}
 let scope=untyped::archived_scope(&body,tree,&[])?.with_archive(archive)?;let mut prefixes=HashSet::new();let control=std::cell::RefCell::new(&mut *work);
 let visited=crate::untyped_order::try_policy_expressions(body.statement_body().view(),&mut||control.borrow_mut().checkpoint(),&mut|observed,at|->Result<(),W::Error>{let work=&mut **control.borrow_mut();let e=observed.original();if let ExprKind::Literal(text)=&e.kind{if let Some(parts)=text.parts().map_err(|e|Unsupported(e.into()))?{parts.lexical.map_err(|e|Unsupported(format!("{e:?}")))?;}}
 let prefix=match &e.kind{ExprKind::Member{object,..}|ExprKind::StaticMember{object,..}|ExprKind::SafeMember{object,..}|ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>Some(object.as_ref()as *const Expr as usize),ExprKind::Call{callee,..}=>Some(callee.as_ref()as *const Expr as usize),_=>None};if let Some(pointer)=prefix{if !prefixes.contains(&pointer){if !W::CHECKED{*remaining=remaining.checked_sub(64).ok_or_else(||Unsupported("relation prefix-coordinate budget exceeded".into()))?;}prefixes.insert(pointer);}}if prefixes.contains(&(e as *const Expr as usize)){return Ok(())}
 let ExprKind::Call{callee,args}=&e.kind else{return Ok(())};let ExprKind::Ident(verb)=&callee.kind else{return Ok(())};for &(hi,vi)in pairs(verb){work.checkpoint()?;let(Some(holder),Some(var))=(args.get(hi),args.get(vi))else{continue};let Some((receiver,var))=nameof_using(var,&mut||work.checkpoint())?else{continue};let receiver_ty=match receiver{Some(r)=>scope.player_link_receiver_type_using(r,&mut||work.checkpoint())?,None=>None};let ty=match receiver_ty{some@Some(_)=>some,None=>scope.player_link_receiver_type_using(holder,&mut||work.checkpoint())?}.filter(|t|!t.is_empty()&&t!="/");if declared_using(tree,rels,ty.as_deref(),var,&mut||work.checkpoint())?{continue}
 let origin=archive.original_policy_line(at.start).map_err(Unsupported)?;if origin.path!=occurrence.source.path{return Err("relation cross-file statement requires original old-policy projection".into())}let source=inputs.file(&origin.path).ok_or_else(||Unsupported("relation statement source not captured".into()))?;if !source.is_compiled()||source.role()!=PolicyRole::DmSource{return Err("relation statement not compiled DM".into())}let line=source.analyze_display_line(origin.line).map_err(|e|Unsupported(e.to_string()))?;let coordinate=rel.len().checked_add(var.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(256)).ok_or_else(||work.overflow())?;if !W::CHECKED{*remaining=remaining.checked_sub(coordinate).ok_or_else(||Unsupported("relation finding coordinate budget exceeded before retention".into()))?;}else{let retained=coordinate.checked_add(2048).ok_or_else(||work.overflow())?;work.retain(retained)?;}
 let key=(rel.clone(),line,var.to_owned());if !found.contains_key(&key){if !W::CHECKED&&found.len()>=10000{return Err("relation finding admission exceeded".into())}let shared=std::cell::RefCell::new(&mut *work);let message=detail_using(inputs,root,ty.as_deref(),var,verb,verb=="rel_add"&&args.len()>3,remaining,W::CHECKED,&mut||shared.borrow_mut().checkpoint(),&mut|bytes|shared.borrow_mut().retain(bytes))?;found.insert(key,message);}}
 work.checkpoint()});match visited{Ok(())=>(),Err(crate::untyped_order::PolicyVisitFailure::Callback(actual))=>return Err(actual),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(message))=>return Err(Unsupported(message.into()).into())}
 }work.checkpoint()?;let count=found.len();let mut rows=Vec::new();if W::CHECKED{let max=count.checked_mul(4).ok_or_else(||work.overflow())?;let bytes=max.checked_mul(std::mem::size_of::<Finding>()).and_then(|n|n.checked_add(256)).ok_or_else(||work.overflow())?;work.retain(bytes)?;rows.try_reserve_exact(count).map_err(|_|work.allocation_failed())?;if rows.capacity()>max{return Err(work.allocation_failed())}}rows.extend(found.into_iter().map(|((rel,line,var),message)|Finding{rel,line,var,message}));crate::checker_order::sort_source_order(&mut rows,&mut|a,b|->Result<std::cmp::Ordering,W::Error>{work.checkpoint()?;Ok((&a.rel,a.line,&a.message).cmp(&(&b.rel,b.line,&b.message)))})?;work.checkpoint()?;Ok(rows)
}

#[cfg(test)]
#[path = "rel_write_native_tests.rs"]
mod tests;
