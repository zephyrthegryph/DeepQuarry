//! Source and hash-qualified builtin call facts for pinned checker policies.
//!
//! These queries borrow the one native semantic owner. They do not resolve
//! runtime ABI slots, infer checker types from compiler Values, or guess builtin
//! names. Diagnostic visitors must still reproduce pinned argument visitation.
use dm_ir::{
    DeclarationMeaning, PackedU128, ProcedureIdentity, ResolveQuery as Q, ResolvedMeaning as M,
    Resolver, SymbolId,
};
use dm_tree::SemanticTree;
use std::sync::Arc;
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CallableFact {
    Source {
        identity: ProcedureIdentity,
        metadata: Arc<DeclarationMeaning>,
    },
    CheckerBuiltin {
        declaring_owner: SymbolId,
        name: SymbolId,
        metadata: Arc<DeclarationMeaning>,
    },
    /// Exact absence in both current source and the selected fixed checker DSL.
    Missing,
}
/// The nearest ancestor wins; source beats a fixed builtin only on the same
/// owner. The pinned checker includes root/global ancestors. This kind-qualified
/// prerequisite does not silently merge same-owner proc/verb source occurrences.
/// Effective source declaration wins over a fixed builtin just as pinned
/// get_proc does. A missing source chain does not imply a missing builtin.
/// This helper supports ordinary callable terms only; reserved syntax forms
/// (list, input, call, new, parent/self calls) are primary grammar contexts.
pub fn callable(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    owner: SymbolId,
    name: SymbolId,
    verb: bool,
) -> Result<CallableFact, String> {
    let ancestry = Q::Ancestry(owner);
    let expected_ancestry = Resolver::resolve(tree, ancestry);
    if !matches!(expected_ancestry, M::Symbols(_))
        || resolver.resolve(ancestry) != expected_ancestry
    {
        return Err("checker call facts need issued receiver ancestry".into());
    }
    let M::Symbols(ancestors) = expected_ancestry else {
        unreachable!()
    };
    let source = source_candidate(tree, resolver, owner, name, verb)?;
    // Own authored source overrides the same-owner builtin and every ancestor.
    if matches!(&source,Some(CallableFact::Source {identity,..}) if identity.owner==owner) {
        return Ok(source.unwrap());
    }
    // The pinned checker walks root/global declarations too. The native
    // source query deliberately separates that runtime namespace.
    let source = match source {
        Some(source) => Some(source),
        None if owner != SymbolId::of("/") => {
            source_candidate(tree, resolver, SymbolId::of("/"), name, verb)?
        }
        None => None,
    };
    let builtin = match resolver.resolve(Q::CheckerBuiltinProc {
        profile,
        owner,
        name,
        verb,
    }) {
        M::Member {
            owner: declaring_owner,
            name: resolved_name,
            data,
            ..
        } => {
            if resolved_name != name || data.procedure.is_none() || data.inherited_opaque().is_some()
            {
                return Err("checker builtin callable metadata is opaque or mismatched".into());
            }
            Some(CallableFact::CheckerBuiltin {
                declaring_owner,
                name,
                metadata: data,
            })
        }
        M::Missing => None,
        _ => return Err(
            "checker builtin callable needs attached exact profile and complete fixed DSL facts"
                .into(),
        ),
    };
    match (source, builtin) {
        (Some(source), Some(builtin)) => {
            let CallableFact::Source { identity, .. } = &source else {
                unreachable!()
            };
            let CallableFact::CheckerBuiltin {
                declaring_owner, ..
            } = &builtin
            else {
                unreachable!()
            };
            let source_depth = ancestors
                .iter()
                .position(|&owner| owner == identity.owner)
                .ok_or("source callable is outside issued ancestry")?;
            let builtin_depth = ancestors
                .iter()
                .position(|&owner| owner == *declaring_owner)
                .ok_or("checker builtin is outside issued ancestry")?;
            Ok(if source_depth <= builtin_depth {
                source
            } else {
                builtin
            })
        }
        (Some(fact), None) | (None, Some(fact)) => Ok(fact),
        (None, None) => Ok(CallableFact::Missing),
    }
}
fn source_candidate(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    owner: SymbolId,
    name: SymbolId,
    verb: bool,
) -> Result<Option<CallableFact>, String> {
    let query = Q::SourceDeclarationChain { owner, name, verb };
    let answer = resolver.resolve(query);
    if answer != Resolver::resolve(tree, query) {
        return Err("checker call facts host differs from issued source chain".into());
    }
    match answer {
        M::Members(rows) => {
            let Some(M::Declaration { identity, data, .. }) = rows.first() else {
                return Err("checker call facts need nonempty exact source chain".into());
            };
            if data.procedure.is_none() || data.inherited_opaque().is_some() {
                return Err("checker source callable metadata is opaque".into());
            }
            Ok(Some(CallableFact::Source {
                identity: *identity,
                metadata: Arc::clone(data),
            }))
        }
        M::Missing => Ok(None),
        _ => Err("checker call facts need source declaration presence proof".into()),
    }
}
impl CallableFact {
    pub fn owner(&self) -> Option<SymbolId> {
        match self {
            Self::Source { identity, .. } => Some(identity.owner),
            Self::CheckerBuiltin {
                declaring_owner, ..
            } => Some(*declaring_owner),
            Self::Missing => None,
        }
    }
    pub fn metadata(&self) -> Option<&Arc<DeclarationMeaning>> {
        match self {
            Self::Source { metadata, .. } | Self::CheckerBuiltin { metadata, .. } => Some(metadata),
            Self::Missing => None,
        }
    }
}
/// Pinned get_proc has one proc/verb name map. Native source namespaces remain
/// separate; merge their exact candidates only when ancestry orders them.
/// Same-owner mixed source occurrences need an issued unified chronology.
fn callable_any_native(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    owner: SymbolId,
    name: SymbolId,
) -> Result<CallableFact, String> {
    let proc = callable(tree, resolver, profile, owner, name, false)?;
    let verb = callable(tree, resolver, profile, owner, name, true)?;
    if matches!(proc, CallableFact::Missing) {
        return Ok(verb);
    }
    if matches!(verb, CallableFact::Missing) {
        return Ok(proc);
    }
    let M::Symbols(ancestors) = resolver.resolve(Q::Ancestry(owner)) else {
        return Err("checker callable merge needs exact ancestry".into());
    };
    let p = ancestors
        .iter()
        .position(|&a| Some(a) == proc.owner())
        .ok_or("proc candidate outside ancestry")?;
    let v = ancestors
        .iter()
        .position(|&a| Some(a) == verb.owner())
        .ok_or("verb candidate outside ancestry")?;
    if p < v {
        return Ok(proc);
    }
    if v < p {
        return Ok(verb);
    }
    match (&proc, &verb) {
        (CallableFact::Source { .. }, CallableFact::CheckerBuiltin { .. }) => Ok(proc),
        (CallableFact::CheckerBuiltin { .. }, CallableFact::Source { .. }) => Ok(verb),
        _ => Err(
            "checker callable merge needs unified same-owner proc/verb declaration order".into(),
        ),
    }
}

#[cfg(test)]
#[path = "checker_call_facts_tests.rs"]
mod tests;

/// Authenticate a selected original value coordinate. Ordinary lookup chooses
/// the group winner; exact/self/parent calls may deliberately name earlier values.
pub(crate) fn require_original_group_chronology_using<E:From<String>+From<&'static str>>(tree:&SemanticTree,profile:PackedU128,fact:&CallableFact,name:&str,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<(),E>{checkpoint()?;let target=crate::checker_effects::callable_target(tree,profile,fact)?;let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|e|format!("original call catalog: {e:?}"))?;if catalog.profile!=profile{return Err("original call catalog profile differs".into())}let actual_name=match fact{CallableFact::Source{identity,..}=>identity.name,CallableFact::CheckerBuiltin{name,..}=>*name,CallableFact::Missing=>return Err("original call target is missing".into())};if actual_name!=SymbolId::of(name){return Err("original call name differs from actual target".into())}let spelling=if matches!(target,crate::checker_effects::EffectTarget::Builtin(_)){catalog.spelling(actual_name)}else{tree.symbols().text(actual_name)}.ok_or("original call spelling absent")?;if spelling!=name{return Err("original call spelling differs".into())}if let Some(group)=crate::checker_original_group::Group::for_target_using(tree,profile,target,checkpoint)?{let expected=group.fact_using(target,checkpoint)?;match(fact.metadata(),expected.metadata()){(Some(actual),Some(original))if Arc::ptr_eq(actual,original)=>(),_=>return Err("original call group metadata owner differs".into())}}Ok(())}

/// Original get_proc selection over the same issued native source and fixed
/// checker declarations. The kind-qualified compatibility query above remains
/// useful independently of a complete checker profile.
/// DATA-only checked form of the existing public lookup. The callback is
/// operation control, never a source/profile or model authority.
pub fn callable_any_using<E:From<String>+From<&'static str>>(tree:&SemanticTree,resolver:&(impl Resolver+?Sized),profile:PackedU128,owner:SymbolId,name:SymbolId,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<CallableFact,E>{checkpoint()?;let selected=callable_any_native(tree,resolver,profile,owner,name)?;let selected_owner=match &selected{CallableFact::Source{identity,..}=>identity.owner,CallableFact::CheckerBuiltin{declaring_owner,..}=>*declaring_owner,CallableFact::Missing=>return Ok(selected)};let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|e|format!("original winner catalog: {e:?}"))?;let builtin=catalog.own_callable(selected_owner,name,false).is_some()||catalog.own_callable(selected_owner,name,true).is_some();if !builtin{return Ok(selected)}let ty=tree.lookup_type(selected_owner).ok_or("original winner owner absent")?;let source=[dm_tree::MemberKind::Proc,dm_tree::MemberKind::Verb].into_iter().any(|kind|tree.resolve(ty,name,kind).and_then(|id|tree.member(id)).is_some_and(|row|row.owner==ty));if !source{return Ok(selected)}if catalog.profile!=profile{return Err("original winner profile differs".into())}let group=crate::checker_original_group::Group::issue_using(tree,profile,selected_owner,name,checkpoint)?;group.observe_using(resolver,checkpoint)?;group.winner_using(checkpoint)?.ok_or_else(||E::from("original selected group is empty"))}

pub fn callable_any(tree:&SemanticTree,resolver:&(impl Resolver+?Sized),profile:PackedU128,owner:SymbolId,name:SymbolId)->Result<CallableFact,String>{callable_any_using(tree,resolver,profile,owner,name,&mut||Ok(()))}
pub(crate) fn require_original_group_chronology(tree:&SemanticTree,profile:PackedU128,fact:&CallableFact,name:&str)->Result<(),String>{require_original_group_chronology_using(tree,profile,fact,name,&mut||Ok(()))}

/// Exact current/parent source call, selected by the actual archived occurrence
/// rather than the receiver's virtual winner. Visibility and the evaluator use
/// this same issuer; the returned aliases belong to the existing model/catalog.
pub(crate) fn explicit_fact_using<E:From<String>+From<&'static str>>(archive:&dm_tree::frontend::BodyArchive,caller:ProcedureIdentity,parent:bool,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Option<CallableFact>,E>{
 checkpoint()?;if resolver.source_owner()!=Resolver::source_owner(archive.tree()){return Err("explicit call resolver belongs to another actual source owner".into())}archive.callables().ordinal_for_identity_using(caller,checkpoint)?.ok_or("explicit caller is not in the actual source archive")?;
 let current=crate::checker_effects::EffectTarget::Source(caller);let target=if parent{crate::checker_effects::original_target_parent_using(archive,profile,resolver,current,checkpoint)?}else{Some(current)};
 target.map(|target|match target{
  crate::checker_effects::EffectTarget::Source(identity)=>{let query=Q::SourceDeclarationChain{owner:identity.owner,name:identity.name,verb:identity.verb};let expected=Resolver::resolve(archive.tree(),query);checkpoint()?;if resolver.resolve(query)!=expected{return Err("explicit call chain differs from actual original source".into())}let M::Members(rows)=expected else{return Err("explicit call source chain absent".into())};let metadata=rows.iter().find_map(|row|match row{M::Declaration{identity:actual,data,..}if *actual==identity=>Some(data.clone()),_=>None}).ok_or("explicit call source occurrence absent")?;Ok(CallableFact::Source{identity,metadata})},
  crate::checker_effects::EffectTarget::Builtin(id)=>archive.tree().with_checker_builtin_procedure(id,|row|CallableFact::CheckerBuiltin{declaring_owner:row.owner,name:row.name,metadata:row.metadata.clone()}).map_err(|e|format!("explicit builtin call: {e:?}").into())
 }).transpose()
}
