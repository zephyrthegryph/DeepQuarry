//! Bind stable predecessor adjacency from the current validated namespace.
//! Scratch links hold only current dense indices; retained edges hold stable keys.
use super::*;
use std::collections::BTreeSet;

pub(super) fn bind(
    tree: &SemanticTree,
    keys: &[DeclarationKey],
    projection: &HashMap<DeclarationKey, usize>,
    nodes: &mut [DependencyNode],
    previous: &MetadataDependencies,
    changed: &BTreeSet<DeclarationKey>,
) -> Option<()> {
    let absent = usize::MAX;
    let mut first = vec![absent; nodes.len()];
    let mut next = vec![absent; keys.len()];
    // Prepending in reverse reproduces the ordinary producer's dense encounter
    // order exactly, without constructing any candidate edge Vec or Arc.
    for index in (0..tree.members.len()).rev() {
        if let Some(parent) = tree.members[index].previous {
            let parent = *projection.get(keys.get(parent.index())?)?;
            next[index] = first[parent];
            first[parent] = index;
        }
    }
    for (slot, node) in nodes.iter_mut().enumerate() {
        let mut cursor = first[slot];
        let prior = (!changed.contains(&node.key))
            .then(|| previous.slot(node.key))
            .flatten()
            .map(|index| &previous.nodes[index]);
        let mut equal = prior.is_some();
        if let Some(prior) = prior {
            match &prior.dependants {
                None => equal = cursor == absent,
                Some(edges) => {
                    for key in edges.iter() {
                        if cursor == absent || keys.get(cursor) != Some(key) {
                            equal = false;
                            break;
                        }
                        cursor = next[cursor];
                    }
                    equal &= cursor == absent;
                }
            }
            if equal {
                node.dependants = prior.dependants.clone();
                continue;
            }
        }
        cursor = first[slot];
        if cursor == absent {
            node.dependants = None;
            continue;
        }
        let mut edges = Vec::new();
        while cursor != absent {
            edges.push(*keys.get(cursor)?);
            cursor = next[cursor];
        }
        node.dependants = Some(Arc::new(edges));
    }
    Some(())
}
