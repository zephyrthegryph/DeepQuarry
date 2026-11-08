//! Full static-member receiver policy, borrowing original native declarations
//! and primary AST. Return-type/value inference intentionally never participates.
use crate::{
    checker_variable_facts,
    policy_inputs::PolicyInputs,
    untyped::{self, Unsupported},
};
use dm_ir::{PackedU128, SymbolId};
use dm_syntax::{Expr, ExprKind};
use dm_tree::{DefinitionMode, MemberKind, SemanticTree};
use std::collections::{BTreeMap, BTreeSet};
#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: u32,
    pub name: String,
}
fn spelling<'a>(
    tree: &'a SemanticTree,
    profile: PackedU128,
    symbol: SymbolId,
) -> Result<&'a str, Unsupported> {
    tree.symbols()
        .text(symbol)
        .or_else(|| tree.checker_builtin_spelling(profile, symbol))
        .ok_or_else(|| Unsupported("static-member declaration spelling unavailable".into()))
}
fn static_names(tree:&SemanticTree,profile:PackedU128)->Result<BTreeSet<String>,Unsupported>{static_names_using(tree,profile,&mut||Ok::<(),Unsupported>(()))}
fn static_names_using<E:From<Unsupported>>(tree: &SemanticTree, profile: PackedU128,checkpoint:&mut impl FnMut()->Result<(),E>) -> Result<BTreeSet<String>, E> {
    checkpoint()?;
    let catalog =
        dm_tree::checker_builtins::pinned_catalog().map_err(|e| Unsupported(format!("{e:?}")))?;
    checkpoint()?;
    tree.validate_checker_builtin_profile(profile)
        .map_err(|e| Unsupported(format!("{e:?}")))?;
    let mut declared = BTreeMap::new();
    for row in catalog
        .declarations
        .iter()
        .filter(|r| r.kind == MemberKind::Var && r.definition == DefinitionMode::Declare)
    {
        checkpoint()?;
        declared.insert((row.owner, row.name), row.metadata.flags & (1 | 8) != 0);
    }
    for member in tree
        .members()
        .iter()
        .filter(|m| m.kind == MemberKind::Var && m.definition == DefinitionMode::Declare)
    {
        checkpoint()?;
        if member.metadata.inherited_opaque.is_some() {
            return Err(Unsupported("static-name flags are incomplete".into()).into());
        }
        let owner = tree
            .type_node(member.owner)
            .ok_or_else(|| Unsupported("static-name owner missing".into()))?
            .path;
        // Same-owner authored declaration replaces its builtin declaration;
        // subtype overrides do not manufacture declarations or erase a base.
        declared.insert((owner, member.name), member.metadata.flags & (1 | 8) != 0);
    }
    declared
        .into_iter()
        .filter(|(_, yes)| *yes)
        .map(|((_, name), _)| {checkpoint()?;spelling(tree, profile, name).map(str::to_owned).map_err(E::from)})
        .collect()
}
struct Receiver<'a> {
    archive: &'a dm_tree::frontend::BodyArchive,
    tree: &'a SemanticTree,
    profile: PackedU128,
    owner: SymbolId,
    locals: &'a std::collections::HashMap<String, String>,
}
impl Receiver<'_> {
    fn declared<E:From<Unsupported>+From<String>>(&self, owner: SymbolId, name: &str,checkpoint:&mut impl FnMut()->Result<(),E>) -> Result<Option<Option<String>>, E> {
        checkpoint()?;
        let fact = checker_variable_facts::variable_using(
            self.tree,
            self.tree,
            self.profile,
            owner,
            SymbolId::of(name),checkpoint,
        )?;
        let Some(fact) = fact else { return Ok(None) };
        if let Some(formal) = fact.formal {
            let qualified = fact
                .metadata
                .declared_type
                .into_iter()
                .chain(fact.metadata.list_element_type)
                .any(|symbol| {
                    spelling(self.tree, self.profile, symbol)
                        .is_ok_and(dm_syntax::has_checker_qualifiers)
                });
            if qualified {
                checkpoint()?;
                let properties = self
                    .archive
                    .checker_variable_properties(formal, self.profile)
                    .map_err(Unsupported)?;
                return Ok(Some(properties.declared_hint().map(str::to_owned)));
            }
        }
        let Some(ty) = fact.metadata.declared_type else {
            return Ok(Some(None));
        };
        checkpoint()?;
        let mut ty = spelling(self.tree, self.profile, ty)?.to_owned();
        if ty == "/list" {
            if let Some(element) = fact.metadata.list_element_type {
                ty.push_str(spelling(self.tree, self.profile, element)?);
            }
        }
        if dm_syntax::has_checker_qualifiers(&ty) {
            return Err(Unsupported(
                "receiver declaration needs native checker qualifier facts".into(),
            ).into());
        }
        Ok(Some(Some(ty)))
    }
    fn of<E:From<Unsupported>+From<String>>(&self, node: &Expr,checkpoint:&mut impl FnMut()->Result<(),E>) -> Result<Option<String>, E> {
        checkpoint()?;
        Ok(match &node.kind {
            ExprKind::Ident(name) => match name.as_str() {
                "src" => (self.owner != SymbolId::of("/"))
                    .then(|| spelling(self.tree, self.profile, self.owner).map(str::to_owned))
                    .transpose().map_err(E::from)?,
                "usr" => Some("/mob".into()),
                "world" => Some("/world".into()),
                "global" => Some("/".into()),
                _ => {
                    if let Some(local) = self.locals.get(name) {
                        if dm_syntax::has_checker_qualifiers(local) {
                            return Err(Unsupported(
                                "local receiver needs native checker qualifier facts".into(),
                            ).into());
                        }
                        (!local.is_empty()).then(|| local.clone())
                    } else if self.owner != SymbolId::of("/") {
                        match self.declared(self.owner, name,checkpoint)? {
                            Some(found) => found,
                            None => self.declared(SymbolId::of("/"), name,checkpoint)?.flatten(),
                        }
                    } else {
                        self.declared(SymbolId::of("/"), name,checkpoint)?.flatten()
                    }
                }
            },
            ExprKind::Group(inner) => self.of(inner,checkpoint)?,
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => match self.of(object,checkpoint)? {
                Some(owner) => self.declared(SymbolId::of(&owner), selector,checkpoint)?.flatten(),
                None => None,
            },
            ExprKind::Unary { op, .. } if op == "new" => {
                match dm_syntax::native_special_forms::constructor(node)
                    .map_err(|e| Unsupported(e.into()))?
                {
                    Some(dm_syntax::native_special_forms::Constructor::Static { path, .. }) => {
                        Some(path.into())
                    }
                    _ => None,
                }
            }
            // Pinned Follow::StaticField/ProcReference erase the receiver
            // declaration type; the value is not typed from its target.
            ExprKind::StaticMember { .. } => None,
            // A call result, index or value expression is NEVER typed from
            // RETURN_TYPE, an assignment, a constant, or a value proof here.
            _ => None,
        })
    }
}
pub fn findings(
    inputs: &PolicyInputs,
    root: &std::path::Path,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    findings_with::<crate::policy_body_demand::Compatibility>(inputs, root, exempt, checkpoint)
}
pub fn findings_checked(
    inputs: &PolicyInputs,
    root: &std::path::Path,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, crate::policy_body_demand::PolicyFailure> {
    findings_with::<crate::policy_body_demand::Checked>(inputs, root, exempt, checkpoint)
}
pub fn findings_with<D: crate::policy_body_demand::Demand>(
    inputs: &PolicyInputs,
    root: &std::path::Path,
    exempt: impl Fn(&str) -> bool,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, D::Error> {
    struct Legacy<'a,D:crate::policy_body_demand::Demand>{poll:&'a mut dyn FnMut()->Result<(),String>,kind:std::marker::PhantomData<D>}
    impl<D:crate::policy_body_demand::Demand> crate::policy_body_demand::WorkspaceWork for Legacy<'_,D>{type Error=D::Error;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),D::Error>{(self.poll)().map_err(|m|Unsupported(m).into())}fn retain(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn overflow(&mut self)->D::Error{"legacy member geometry".into()}fn allocation_failed(&mut self)->D::Error{"legacy member allocation".into()}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,D::Error>{D::parse(a,n)}}
    findings_workspace_using(inputs,root,exempt,&mut Legacy::<D>{poll:&mut checkpoint,kind:std::marker::PhantomData})
}
/// Complete SAME old declared-only receiver policy under typed host work.
pub fn findings_workspace_using<W:crate::policy_body_demand::WorkspaceWork>(inputs:&PolicyInputs,root:&std::path::Path,exempt:impl Fn(&str)->bool,work:&mut W)->Result<Vec<Finding>,W::Error>{
 let archive=inputs.archive();let tree=archive.tree();let profile=tree.checker_builtin_profile().ok_or_else(||Unsupported("static-member name universe needs fixed builtin hierarchy/profile".into()))?;
 let mut longest=128usize;let mut geometry=0usize;if W::CHECKED{let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|e|Unsupported(format!("{e:?}")))?;for ty in tree.types(){work.checkpoint()?;longest=longest.max(tree.symbols().text(ty.path).ok_or("member type spelling unavailable")?.len());}for member in tree.members(){work.checkpoint()?;longest=longest.max(spelling(tree,profile,member.name)?.len());}geometry=tree.members().len().checked_add(tree.types().len()).and_then(|n|n.checked_add(catalog.declarations.len())).and_then(|n|n.checked_mul(longest.checked_add(1024)?)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(geometry)?;}
 let statics=static_names_using(tree,profile,&mut||work.checkpoint())?;let mut rows=BTreeSet::new();
 for ordinal in 0..archive.len(){work.checkpoint()?;let occurrence=&archive.occurrences()[ordinal];if W::CHECKED{let bytes=occurrence.source.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(geometry)).ok_or_else(||work.overflow())?;work.temporary(bytes)?;}
 let rel=dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path,root).as_deref().unwrap_or(occurrence.source.path.as_path()).to_string_lossy().replace('\\',"/");if !rel.starts_with("code/")||exempt(&rel){continue}
 let body=work.body(archive,ordinal)?;if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),occurrence){return Err("member host returned foreign original body loan".into())}
 if W::CHECKED{let locals=body.source_locals().map_err(Unsupported)?.scope_admission().map_err(Unsupported)?;let span=occurrence.expanded_span;let bytes=span.end.checked_sub(span.start).and_then(|n|n.checked_add(1)).and_then(|n|n.checked_mul(longest)).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(locals)).and_then(|n|n.checked_add(geometry)).and_then(|n|n.checked_add(16384)).ok_or_else(||work.overflow())?;work.temporary(bytes)?;}
 let scope=untyped::archived_scope(&body,tree,&[])?;let receiver=Receiver{archive,tree,profile,owner:scope.owner,locals:&scope.locals};let control=std::cell::RefCell::new(&mut *work);
 let visited=crate::untyped_order::try_policy_expressions(body.statement_body().view(),&mut||control.borrow_mut().checkpoint(),&mut|observed,at|->Result<(),W::Error>{let work=&mut **control.borrow_mut();let expr=observed.original();if let ExprKind::Literal(text)=&expr.kind{crate::untyped::require_policy_literal_shape(text,archive.source_mapping().initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290)?;}
 let(ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..})=&expr.kind else{return Ok(())};if statics.contains(selector)&&receiver.of(object,&mut||work.checkpoint())?.is_none(){let source=archive.original_policy_line(at.start).map_err(Unsupported)?;let captured=inputs.file(&source.path).ok_or_else(||Unsupported("member origin is not captured".into()))?;if !captured.is_compiled()||captured.role()!=crate::policy_inputs::PolicyRole::DmSource{return Err("member origin is not compiled DM source".into())}let line=captured.analyze_display_line(source.line).map_err(|e|Unsupported(e.to_string()))?;
 if W::CHECKED{let bytes=source.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(selector.len())).and_then(|n|n.checked_add(2048)).ok_or_else(||work.overflow())?;work.retain(bytes)?;}let relative=dm_preprocess::regions::relative_filesystem_path(&source.path,root).as_deref().unwrap_or(source.path.as_path()).to_string_lossy().replace('\\',"/");rows.insert((relative,u32::try_from(line).map_err(|_|Unsupported("member line overflow".into()))?,selector.clone()));}work.checkpoint()});
 match visited{Ok(())=>(),Err(crate::untyped_order::PolicyVisitFailure::Callback(actual))=>return Err(actual),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(message))=>return Err(Unsupported(message.into()).into())}
 }
 work.checkpoint()?;if W::CHECKED{let count=rows.len();let max=count.checked_mul(4).ok_or_else(||work.overflow())?;let retained=max.checked_mul(std::mem::size_of::<Finding>()).and_then(|n|n.checked_add(256)).ok_or_else(||work.overflow())?;work.retain(retained)?;let mut out=Vec::new();out.try_reserve_exact(count).map_err(|_|work.allocation_failed())?;if out.capacity()>max{return Err(work.allocation_failed())}out.extend(rows.into_iter().map(|(rel,line,name)|Finding{rel,line,name}));Ok(out)}else{Ok(rows.into_iter().map(|(rel,line,name)|Finding{rel,line,name}).collect())}
}

#[cfg(test)]
#[path = "untyped_member_native_tests.rs"]
mod tests;
