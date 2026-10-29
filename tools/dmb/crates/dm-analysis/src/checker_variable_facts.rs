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
    let ancestry = Q::Ancestry(owner);
    let expected = Resolver::resolve(tree, ancestry);
    if resolver.source_owner() != Resolver::source_owner(tree)
        || resolver.resolve(ancestry) != expected
    {
        return Err("checker variable host lacks issued receiver/source provenance".into());
    }
    let M::Symbols(ancestors) = expected else {
        return Err("checker variable ancestry unavailable".into());
    };
    let source_candidate = |receiver| -> Result<Option<VariableFact>, String> {
        let query = Q::SourceVarDeclaration {
            owner: receiver,
            name,
        };
        let answer = resolver.resolve(query);
        if answer != Resolver::resolve(tree, query) {
            return Err("checker source-variable query differs from issued declaration".into());
        }
        match answer {
            M::Member {
                owner,
                name: actual,
                data,
                ..
            } if actual == name && data.inherited_opaque.is_none() && data.procedure.is_none() => {
                let formal = tree
                    .source_formal_variable_member(owner, name)
                    .map_err(str::to_owned)?
                    .ok_or("issued source formal unavailable")?;
                if !Arc::ptr_eq(
                    &tree
                        .member(formal)
                        .ok_or("issued source formal disappeared")?
                        .metadata,
                    &data,
                ) {
                    return Err("source formal does not borrow selected original metadata".into());
                }
                Ok(Some(VariableFact {
                    formal: Some(formal),
                    owner,
                    name,
                    metadata: data,
                }))
            }
            M::Missing => Ok(None),
            _ => Err("checker source-variable declaration is unavailable or opaque".into()),
        }
    };
    let mut source = source_candidate(owner)?;
    if source.as_ref().is_some_and(|fact| fact.owner == owner) {
        return Ok(source);
    }
    if source.is_none() && owner != SymbolId::of("/") {
        source = source_candidate(SymbolId::of("/"))?;
    }
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
        _ => return Err("checker variable needs exact hash-qualified builtin facts".into()),
    };
    match (source, builtin) {
        (Some(source), Some(builtin)) => {
            let a = ancestors
                .iter()
                .position(|&p| p == source.owner)
                .ok_or("source variable outside issued ancestry")?;
            let b = ancestors
                .iter()
                .position(|&p| p == builtin.owner)
                .ok_or("builtin variable outside issued ancestry")?;
            Ok(Some(if a <= b { source } else { builtin }))
        }
        (Some(fact), None) | (None, Some(fact)) => Ok(Some(fact)),
        (None, None) => Ok(None),
    }
}

#[cfg(test)]
#[path = "checker_variable_facts_tests.rs"]
mod tests;
