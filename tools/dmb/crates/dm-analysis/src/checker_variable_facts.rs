//! Pinned declared-variable lookup on the SAME compiler tree and resolver.
//! No scalar/default value is mistaken for a declaration or static type.
use dm_ir::{
    DeclarationMeaning, PackedU128, ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId,
};
use dm_tree::SemanticTree;
use std::sync::Arc;
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct VariableFact {
    /// Exact source formal selected by the ORIGINAL owner, never a name guess.
    pub formal: Option<dm_tree::MemberId>,
    pub owner: SymbolId,
    pub name: SymbolId,
    pub metadata: Arc<DeclarationMeaning>,
}
pub fn variable(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    owner: SymbolId,
    name: SymbolId,
) -> Result<Option<VariableFact>, String> {
    variable_using(tree,resolver,profile,owner,name,&mut||Ok::<(),String>(()))
}
/// SAME selector and exact query order with operation-local typed control.
pub fn variable_using<E:From<String>>(tree:&SemanticTree,resolver:&(impl Resolver+?Sized),profile:PackedU128,owner:SymbolId,name:SymbolId,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Option<VariableFact>,E>{
    checkpoint()?;
    let ancestry = Q::Ancestry(owner);
    checkpoint()?;
    let expected = Resolver::resolve(tree, ancestry);
    checkpoint()?;
    if resolver.source_owner() != Resolver::source_owner(tree)
        || resolver.resolve(ancestry) != expected
    {
        return Err(E::from("checker variable host lacks issued receiver/source provenance".to_owned()));
    }
    let M::Symbols(ancestors) = expected else {
        return Err(E::from("checker variable ancestry unavailable".to_owned()));
    };
    let control=std::cell::RefCell::new(checkpoint);
    let source_candidate = |receiver| -> Result<Option<VariableFact>, E> {
        (control.borrow_mut())()?;
        let query = Q::SourceVarDeclaration {
            owner: receiver,
            name,
        };
        let answer = resolver.resolve(query);
        (control.borrow_mut())()?;
        if answer != Resolver::resolve(tree, query) {
            return Err(E::from("checker source-variable query differs from issued declaration".to_owned()));
        }
        match answer {
            M::Member {
                owner,
                name: actual,
                data,
                ..
            } if actual == name && data.inherited_opaque.is_none() && data.procedure.is_none() => {
                (control.borrow_mut())()?;
                let formal = tree
                    .source_formal_variable_member(owner, name)
                    .map_err(str::to_owned)?
                    .ok_or_else(||E::from("issued source formal unavailable".to_owned()))?;
                if !Arc::ptr_eq(
                    &tree
                        .member(formal)
                        .ok_or_else(||E::from("issued source formal disappeared".to_owned()))?
                        .metadata,
                    &data,
                ) {
                    return Err(E::from("source formal does not borrow selected original metadata".to_owned()));
                }
                Ok(Some(VariableFact {
                    formal: Some(formal),
                    owner,
                    name,
                    metadata: data,
                }))
            }
            M::Missing => Ok(None),
            _ => Err(E::from("checker source-variable declaration is unavailable or opaque".to_owned())),
        }
    };
    select_using(owner,|target|{(control.borrow_mut())()?;Ok(ancestors.iter().position(|&p|p==target))},source_candidate,||{
    (control.borrow_mut())()?;
    let builtin = match resolver.resolve(Q::CheckerBuiltinVar {
        profile,
        owner,
        name,
    }) {
        M::Member {
            owner,
            name: actual,
            data,
            ..
        } if actual == name && data.inherited_opaque.is_none() && data.procedure.is_none() => {
            Some(VariableFact {
                formal: None,
                owner,
                name,
                metadata: data,
            })
        }
        M::Missing => None,
        _ => return Err(E::from("checker variable needs exact hash-qualified builtin facts".to_owned())),
    };
    Ok(builtin)
    })
}
fn select(
    owner:SymbolId,mut rank:impl FnMut(SymbolId)->Result<Option<usize>,String>,
    mut source_candidate:impl FnMut(SymbolId)->Result<Option<VariableFact>,String>,
    mut builtin_candidate:impl FnMut()->Result<Option<VariableFact>,String>,
)->Result<Option<VariableFact>,String>{
    select_using(owner,&mut rank,&mut source_candidate,&mut builtin_candidate)
}
fn select_using<E:From<String>>(owner:SymbolId,mut rank:impl FnMut(SymbolId)->Result<Option<usize>,E>,mut source_candidate:impl FnMut(SymbolId)->Result<Option<VariableFact>,E>,mut builtin_candidate:impl FnMut()->Result<Option<VariableFact>,E>)->Result<Option<VariableFact>,E>{
    let mut source = source_candidate(owner)?;
    if source.as_ref().is_some_and(|fact| fact.owner == owner) {
        return Ok(source);
    }
    if source.is_none() && owner != SymbolId::of("/") {
        source = source_candidate(SymbolId::of("/"))?;
    }
    let builtin=builtin_candidate()?;
    match (source, builtin) {
        (Some(source), Some(builtin)) => {
            let a = rank(source.owner)?
                .ok_or_else(||E::from("source variable outside issued ancestry".to_owned()))?;
            let b = rank(builtin.owner)?
                .ok_or_else(||E::from("builtin variable outside issued ancestry".to_owned()))?;
            Ok(Some(if a <= b { source } else { builtin }))
        }
        (Some(fact), None) | (None, Some(fact)) => Ok(Some(fact)),
        (None, None) => Ok(None),
    }
}

/// Borrowed ORIGINAL-only entry for consumers already guarded by their current
/// capture. It shares selection precedence with the recording-resolver entry,
/// but does not serialize unused initializer values merely to hash an answer.
/// This is not a replacement for resolver dependency recording in other jobs.
pub fn variable_original(tree:&SemanticTree,profile:PackedU128,owner:SymbolId,name:SymbolId)
    ->Result<Option<VariableFact>,String>{
    variable_original_using(tree,profile,owner,name,||tree.validate_checker_builtin_profile(profile).map_err(|e|format!("checker variable profile: {e:?}")))
}
/// SAME original selector with the actual immutable tree/profile proof.
pub fn variable_original_validated(tree:&SemanticTree,proof:&dm_tree::checker_builtins::ValidatedCheckerProfile<'_>,profile:PackedU128,owner:SymbolId,name:SymbolId)->Result<Option<VariableFact>,String>{variable_original_using(tree,profile,owner,name,||proof.require(tree,profile).map_err(|e|format!("checker variable profile: {e:?}")))}
fn variable_original_using(tree:&SemanticTree,_profile:PackedU128,owner:SymbolId,name:SymbolId,validate:impl FnOnce()->Result<(),String>)->Result<Option<VariableFact>,String>{
    validate()?;
    tree.lookup_type(owner).ok_or("checker variable original owner unavailable")?;
    let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|e|format!("checker catalog: {e:?}"))?;
    select(owner,|target|original_ancestor_depth(tree,owner,target),|receiver|{
        let Some(formal)=tree.source_formal_variable_member(receiver,name).map_err(str::to_owned)? else{return Ok(None)};
        let node=tree.member(formal).ok_or("checker original formal unavailable")?;
        let owner=tree.type_node(node.owner).ok_or("checker original formal owner unavailable")?.path;
        if node.metadata.inherited_opaque.is_some()||node.metadata.procedure.is_some(){return Err("checker original variable metadata opaque".into());}
        Ok(Some(VariableFact{formal:Some(formal),owner,name,metadata:Arc::clone(&node.metadata)}))
    },||{
        // Same native ancestry and original hash-qualified catalog as
        // resolve_checker_builtin; scalar rows are borrowed, never copied.
        let mut current=tree.lookup_type(owner).ok_or("checker variable original owner unavailable")?;
        for _ in 0..=tree.types().len(){
            let owner=tree.type_node(current).ok_or("checker original ancestor unavailable")?.path;
            if let Some(row)=catalog.declarations.iter().find(|r|r.owner==owner&&r.name==name&&r.kind==dm_tree::MemberKind::Var){
                if row.metadata.inherited_opaque.is_some()||row.metadata.procedure.is_some(){return Err("checker original builtin variable opaque".into());}
                return Ok(Some(VariableFact{formal:None,owner,name,metadata:Arc::clone(&row.metadata)}));
            }
            let Some(parent)=tree.parent(current) else{return Ok(None)};
            current=parent;
        }
        Err("checker original hierarchy cycle".into())
    })
}

/// Allocation-free traversal of the SAME native parent graph used by the
/// original resolver's ancestry fallback. A retained ancestry cache is optional,
/// not additional semantic authority. Missing nodes/cycles are never absence.
pub fn original_ancestor_depth(tree:&SemanticTree,owner:SymbolId,target:SymbolId)->Result<Option<usize>,String>{
    let mut current=tree.lookup_type(owner).ok_or("original ancestry owner unavailable")?;
    for depth in 0..=tree.types().len(){
        let node=tree.type_node(current).ok_or("original ancestry node unavailable")?;
        if node.path==target{return Ok(Some(depth));}
        let Some(parent)=tree.parent(current) else{return Ok(None)};
        current=parent;
    }
    Err("original ancestry cycle".into())
}

#[cfg(test)]
#[path = "checker_variable_facts_tests.rs"]
mod tests;
