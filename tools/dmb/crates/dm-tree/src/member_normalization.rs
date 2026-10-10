//! One normalization implementation for full construction and keyed contributions.
//! Namespace and predecessor semantics remain authoritative here.
use crate::*;
use std::collections::HashMap;
pub(crate) fn formal_chain<T: Copy + PartialEq>(
    ids: &[T],
    mut is_formal: impl FnMut(T) -> bool,
) -> Vec<T> {
    let formal = ids.iter().copied().find(|&id| is_formal(id));
    formal
        .into_iter()
        .chain(ids.iter().copied().filter(|id| Some(*id) != formal))
        .collect()
}
pub(crate) fn normalize_groups<M: crate::member_binding::MemberWrite + ?Sized>(
    tree: &mut SemanticTree,
    members: &mut M,
    modes: &[DefinitionMode],
    groups: HashMap<(TypeId, SymbolId, MemberKind), Vec<MemberId>>,
) {
    // Formal definitions establish a group's base irrespective of source
    // position; overrides keep encounter order. BYOND compile-only probes show
    // implicit-before-formal and formal-before-implicit compile identically.
    for (key, ids) in groups {
        let chain = formal_chain(&ids, |id| modes[id.index()] == DefinitionMode::Declare);
        let mut previous = None;
        for id in &chain {
            members.set_previous(id.index(), previous);
            previous = Some(*id);
        }
        if let Some(last) = chain.last() {
            Arc::make_mut(&mut tree.direct).insert(key, *last);
        }
    }
}
pub(crate) fn resolve_previous<M: crate::member_binding::MemberWrite + ?Sized>(
    tree: &SemanticTree,
    members: &mut M,
    modes: &[DefinitionMode],
    root: SymbolId,
    callable_kinds: &crate::callable_namespace::CallableKinds,
    indices: impl IntoIterator<Item = usize>,
) -> Result<(), TreeError> {
    for i in indices {
        callable_namespace::validate_explicit(
            tree,
            members.member(i),
            modes[i],
            root,
            callable_kinds,
        )?;
        if members.member(i).previous.is_none() {
            let node = members.member(i);
            let mut parent = tree.parent(node.owner);
            let mut previous = None;
            while let Some(owner) = parent {
                if tree.types[owner.index()].path == root {
                    break;
                }
                if let Some(id) = tree.direct.get(&(owner, node.name, node.kind)) {
                    previous = Some(*id);
                    break;
                }
                parent = tree.parent(owner);
            }
            members.set_previous(i, previous);
            metadata_update::apply_opaque_base(tree, members, i);
            let node = members.member(i);
            if modes[i] == DefinitionMode::Override
                && previous.is_none()
                && node.metadata.inherited_opaque.is_none()
            {
                let mut ancestry = Vec::new();
                let mut cursor = Some(node.owner);
                while let Some(owner) = cursor {
                    if ancestry.len() == 16 {
                        break;
                    }
                    ancestry.push(
                        tree.symbols
                            .text(tree.types[owner.index()].path)
                            .unwrap_or("<unknown>"),
                    );
                    cursor = tree.parent(owner);
                }
                let candidates: Vec<_> = (0..modes.len())
                    .map(|index| (index, members.member(index)))
                    .filter(|(_, candidate)| {
                        candidate.name == node.name && candidate.kind == node.kind
                    })
                    .take(8)
                    .map(|(index, candidate)| {
                        (
                            tree.symbols
                                .text(tree.types[candidate.owner.index()].path)
                                .unwrap_or("<unknown>"),
                            modes[index],
                        )
                    })
                    .collect();
                eprintln!("dm-tree missing override: name={} ancestry={ancestry:?} source_candidates={candidates:?}", tree.symbols.text(node.name).unwrap_or("<unknown>"));
                return Err(TreeError::MissingOverride {
                    owner: tree.types[node.owner.index()].path,
                    name: node.name,
                    kind: node.kind,
                });
            }
            members.set_previous(i, previous);
        }
    }
    Ok(())
}
