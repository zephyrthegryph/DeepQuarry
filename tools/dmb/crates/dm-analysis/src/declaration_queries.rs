//! Declaration-only policies over the compiler's immutable semantic owner.
//!
//! The raw marker scanner, source ordering, output generation, ALLOW accounting
//! and baselines stay with Analyze. These queries neither build another object
//! tree nor parse a procedure body. Missing engine metadata is an explicit error.
use crate::untyped::Unsupported;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId};
use dm_tree::SemanticTree;

/// The declared list type visible on `owner`, including inherited declarations.
///
/// Matches `Sem::var_decl(...).is_list()` used by `gen tracked_lists`: the
/// declaration must be exactly `/list` or start with `/list/`. A runtime default
/// such as `value = list()` does not make an untyped declaration a list. An
/// inherited default override does not change its declaration's list type.
/// The returned canonical type symbol belongs to the borrowed compiler table;
/// element annotations are separate native metadata, not part of this result.
pub fn tracked_list_declared_type(
    tree: &SemanticTree,
    owner: SymbolId,
    name: SymbolId,
) -> Result<Option<SymbolId>, Unsupported> {
    match Resolver::resolve(tree, ResolveQuery::DeclaredVarType { owner, name }) {
        ResolvedMeaning::DeclaredType(Some(declared)) => {
            let path = tree.symbols().text(declared).ok_or_else(|| {
                Unsupported("native declared-type spelling is unavailable".into())
            })?;
            Ok((path == "/list" || path.starts_with("/list/")).then_some(declared))
        }
        ResolvedMeaning::DeclaredType(None) | ResolvedMeaning::Missing => Ok(None),
        ResolvedMeaning::Unsupported(_) => Err(Unsupported(
            "tracked-list selection needs the current declared variable type; intrinsic coverage is incomplete".into(),
        )),
        _ => Err(Unsupported("declared-variable query returned a foreign answer kind".into())),
    }
}

/// Select marker handles without copying marker contents. Preserve encounter
/// order and multiplicity; the existing generator owns its lexical sort and
/// first-declaration deduplication policy after this selection.
pub fn select_tracked_list_markers<'a, Marker: 'a>(
    tree: &SemanticTree,
    markers: impl IntoIterator<Item = &'a Marker>,
    identity: impl Fn(&'a Marker) -> (&'a str, &'a str),
) -> Result<Vec<&'a Marker>, Unsupported> {
    let mut selected = Vec::new();
    for marker in markers {
        let (owner, name) = identity(marker);
        if tracked_list_declared_type(tree, SymbolId::of(owner), SymbolId::of(name))?.is_some() {
            selected.push(marker);
        }
    }
    Ok(selected)
}

#[cfg(test)]
#[path = "declaration_queries_tests.rs"]
mod tests;
