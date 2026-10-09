//! One normalization implementation for full construction and keyed contributions.
//! Namespace and predecessor semantics remain authoritative here.
use crate::*;
use std::collections::HashMap;
pub(crate) fn normalize_groups(
    tree: &mut SemanticTree,
    members: &mut [MemberNode],
    modes: &[DefinitionMode],
    groups: HashMap<(TypeId, SymbolId, MemberKind), Vec<MemberId>>,
) {
    // Formal definitions establish a group's base irrespective of source
    // position; overrides keep encounter order. BYOND compile-only probes show
    // implicit-before-formal and formal-before-implicit compile identically.
    for (key, ids) in groups {
        let formal = ids
            .iter()
            .copied()
            .find(|id| modes[id.index()] == DefinitionMode::Declare);
        let chain: Vec<_> = formal
            .into_iter()
            .chain(ids.into_iter().filter(|id| Some(*id) != formal))
            .collect();
        let mut previous = None;
        for id in &chain {
            members[id.index()].previous = previous;
            previous = Some(*id);
        }
        if let Some(last) = chain.last() {
            Arc::make_mut(&mut tree.direct).insert(key, *last);
        }
    }
}
pub(crate) fn resolve_previous(
    tree: &SemanticTree,
    members: &mut [MemberNode],
    modes: &[DefinitionMode],
    root: SymbolId,
    callable_kinds: &crate::callable_namespace::CallableKinds,
    indices: impl IntoIterator<Item = usize>,
) -> Result<(), TreeError> {
    for i in indices {
        callable_namespace::validate_explicit(tree, &members[i], modes[i], root, callable_kinds)?;
        if members[i].previous.is_none() {
            let node = &members[i];
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
            members[i].previous = previous;
            metadata_update::apply_opaque_base(tree, &mut members[i]);
            let node = &members[i];
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
                let candidates: Vec<_> = members
                    .iter()
                    .enumerate()
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
            members[i].previous = previous;
        }
    }
    Ok(())
}
