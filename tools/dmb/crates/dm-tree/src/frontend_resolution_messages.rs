//! DreamMaker wording and built-in classification for tree resolution failures.
use super::*;

/// `owner`'s authored ancestry (explicit `parent_type` or path prefix), then
/// /datum and the root.
pub(super) fn authored_ancestry(
    owner: dm_ir::SymbolId,
    skeletons: &[Skeleton],
    symbols: &SymbolTable,
) -> Vec<dm_ir::SymbolId> {
    let mut chain = vec![dm_ir::SymbolId::of("/datum"), dm_ir::SymbolId::of("/")];
    let mut current = symbols.text(owner).map(str::to_owned);
    while let Some(path) = current.take() {
        let id = dm_ir::SymbolId::of(&path);
        if chain.contains(&id) || chain.len() > 256 {
            break;
        }
        chain.push(id);
        current = skeletons
            .iter()
            .find_map(|skeleton| match skeleton {
                Skeleton::Type {
                    path: found,
                    explicit_parent: Some(parent),
                    ..
                } if *found == id => symbols.text(*parent).map(str::to_owned),
                _ => None,
            })
            .or_else(|| {
                path.rsplit_once('/')
                    .map(|(head, _)| head.to_owned())
                    .filter(|head| !head.is_empty())
            });
    }
    chain
}

/// Whether no type in `owner`'s authored ancestry (explicit `parent_type` or
/// path prefix) lies under a built-in root other than /datum.
pub(super) fn plain_datum_owner(owner: dm_ir::SymbolId, skeletons: &[Skeleton], symbols: &SymbolTable) -> bool {
    let mut current = symbols.text(owner).map(str::to_owned);
    for _ in 0..256 {
        let Some(path) = current else {
            return true;
        };
        if !dm_ir::builtin_names::is_plain_datum_path(&path) {
            return false;
        }
        let id = dm_ir::SymbolId::of(&path);
        let explicit = skeletons.iter().find_map(|skeleton| match skeleton {
            Skeleton::Type {
                path: found,
                explicit_parent: Some(parent),
                ..
            } if *found == id => symbols.text(*parent).map(str::to_owned),
            _ => None,
        });
        current = explicit.or_else(|| {
            path.rsplit_once('/')
                .map(|(head, _)| head.to_owned())
                .filter(|head| !head.is_empty())
        });
    }
    false
}

/// DreamMaker's wording for tree resolution failures. Symbol IDs and internal
/// enum names never reach user-facing output.
pub(super) fn resolution_message(error: &SnapshotError, symbols: &SymbolTable) -> String {
    let text = |id: &dm_ir::SymbolId| symbols.text(*id).unwrap_or("<unnamed>").to_owned();
    match error {
        SnapshotError::Tree(
            crate::TreeError::Duplicate { name, .. }
            | crate::TreeError::InheritedDuplicate { name, .. },
        ) => format!("{}: duplicate definition", text(name)),
        SnapshotError::Tree(crate::TreeError::MissingOverride { name, kind, .. }) => match kind {
            MemberKind::Var => format!("{}: undefined var", text(name)),
            MemberKind::Proc | MemberKind::Verb => format!("{}: undefined proc", text(name)),
        },
        SnapshotError::Tree(crate::TreeError::MissingParent(path)) => {
            format!("{}: undefined type path", text(path))
        }
        SnapshotError::Tree(crate::TreeError::ConflictingParent(path)) => {
            format!("{}: conflicting parent type", text(path))
        }
        SnapshotError::Tree(crate::TreeError::InheritanceCycle(path)) => {
            format!("{}: circular parent type", text(path))
        }
        SnapshotError::Tree(crate::TreeError::InvalidPath(path)) => {
            format!("{}: invalid type path", text(path))
        }
        SnapshotError::Tree(crate::TreeError::TooManyNodes) => {
            "too many types or members for the native compiler".into()
        }
        _ => "internal compiler error: inconsistent declaration tree".into(),
    }
}
