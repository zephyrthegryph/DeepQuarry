//! Borrowed prior semantic authority, applied only after CURRENT namespace binding.
use super::*;
use crate::member_binding::{CurrentProjection, MemberWrite};
use std::collections::{BTreeSet, HashMap};

#[derive(Clone, Copy)]
pub(crate) struct StructuralMetadata<'a> {
    pub(crate) tree: &'a SemanticTree,
    pub(crate) declarations: &'a KeyedDeclarations,
    pub(crate) graph: &'a MetadataDependencies,
}
impl StructuralMetadata<'_> {
    /// Rebind unchanged effective rows through current stable-key projections.
    /// No old TypeId/MemberId is installed in the new tree. Parent and predecessor
    /// changes enter the current dirty cone; the ordinary resolver handles it.
    pub(crate) fn apply<M: MemberWrite + ?Sized>(
        self,
        tree: &SemanticTree,
        declarations: &KeyedDeclarations,
        members: &mut M,
        projection: &CurrentProjection,
        order: &[MemberId],
    ) -> Option<BTreeSet<DeclarationKey>> {
        if tree.intrinsic_fields != self.tree.intrinsic_fields
            || projection.keys.len() != order.len()
            || projection.ids.len() != order.len()
        {
            return None;
        }
        let delta = declarations.delta_since(self.declarations);
        let changed: BTreeSet<_> = delta.changes.iter().map(|row| row.key).collect();
        let mut parent_equal = HashMap::new();
        for index in dependency_order(tree.types.len(), |index| {
            tree.types[index].parent.map(|parent| parent.index())
        }) {
            let node = &tree.types[index];
            let current_parent = node.parent.map(|parent| tree.types[parent.index()].path);
            let same = self.tree.by_path.get(&node.path).is_some_and(|old_id| {
                let old = &self.tree.types[old_id.index()];
                let old_parent = old
                    .parent
                    .map(|parent| self.tree.types[parent.index()].path);
                current_parent == old_parent
                    && current_parent
                        .map_or(true, |parent| parent_equal.get(&parent) == Some(&true))
            });
            parent_equal.insert(node.path, same);
        }
        let mut old_keys = vec![None; self.tree.members.len()];
        for node in &self.graph.nodes {
            old_keys[node.member.index()] = Some(node.key);
        }
        let mut dirty = BTreeSet::new();
        let mut reused = Vec::new();
        for &id in order {
            let key = *projection.keys.get(id.index())?;
            if projection.ids.get(&key) != Some(&id) {
                return None;
            }
            let current = members.member(id.index());
            let previous_key = match current.previous {
                Some(previous) => Some(*projection.keys.get(previous.index())?),
                None => None,
            };
            let old = self.graph.slot(key).map(|slot| &self.graph.nodes[slot]);
            let same = old.is_some_and(|node| {
                let member = &self.tree.members[node.member.index()];
                let old_previous = member
                    .previous
                    .and_then(|previous| old_keys[previous.index()]);
                !changed.contains(&key)
                    && parent_equal.get(&key.owner) == Some(&true)
                    && self.tree.types[member.owner.index()].path == key.owner
                    && member.name == current.name
                    && member.kind == current.kind
                    && member.definition == current.definition
                    && old_previous == previous_key
                    && previous_key.map_or(true, |previous| !dirty.contains(&previous))
            });
            if same {
                reused.push((
                    id,
                    Arc::clone(&self.tree.members[old.unwrap().member.index()].metadata),
                ));
            } else {
                dirty.insert(key);
            }
        }
        // Admission completes before mutating the current binding overlay.
        for (id, metadata) in reused {
            members.set_metadata(id.index(), metadata);
        }
        Some(dirty)
    }
}
