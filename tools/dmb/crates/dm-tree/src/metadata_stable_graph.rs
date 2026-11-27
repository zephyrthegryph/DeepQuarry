//! The dependency graph after a stable-slot splice, updated in place of a new
//! capture: retained slots keep their nodes, added members get theirs, and only
//! the predecessors whose dependants changed get new edge lists.
use super::*;
use crate::metadata_update::splice::StableSplice;
use std::collections::HashSet;

impl MetadataDependencies {
    /// This graph for `tree`, the stable splice of `previous_tree` described by
    /// `stable`, with `current` its declarations. `None` when the graph does not
    /// line up with the previous tree (the caller captures one afresh).
    pub(crate) fn after_stable_splice(
        &self,
        previous_tree: &SemanticTree,
        tree: &SemanticTree,
        current: &KeyedDeclarations,
        stable: &StableSplice,
    ) -> Option<Self> {
        if self.by_slot.len() != previous_tree.members.len()
            || self.nodes.len() != previous_tree.member_count()
            || current.len() != self.roster.len() + stable.added.len()
        {
            return None;
        }
        let rows = current.roster();
        let row_of = |declaration: usize| current.row(*rows.get(declaration)?);
        // Rows: insert the added ones at their (final, ascending) row indices, then the changed shapes.
        let mut roster = self.roster.clone();
        for &(_, _, _, declaration) in &stable.added {
            roster.insert(declaration, shape(&row_of(declaration)?.skeleton));
        }
        for &(_, declaration) in &stable.changed {
            *roster.get_mut(declaration)? = shape(&row_of(declaration)?.skeleton);
        }
        // Nodes in declaration order: the added ones at their final member positions.
        let mut nodes: Vec<DependencyNode> = self
            .nodes
            .iter()
            .map(|node| DependencyNode {
                key: node.key,
                member: node.member,
                dependants: node.dependants.clone(),
            })
            .collect();
        let mut old_to_new: Vec<u32> = Vec::with_capacity(self.nodes.len());
        {
            let mut inserted = stable.added.iter().map(|added| added.2).peekable();
            let mut new_index = 0usize;
            for _ in 0..self.nodes.len() {
                while inserted.peek() == Some(&new_index) {
                    inserted.next();
                    new_index += 1;
                }
                old_to_new.push(new_index as u32);
                new_index += 1;
            }
        }
        for &(key, slot, position, _) in &stable.added {
            if position > nodes.len() {
                return None;
            }
            nodes.insert(position, DependencyNode { key, member: slot, dependants: None });
        }
        let members_at_declaration: Vec<Option<usize>> = {
            let mut count = 0usize;
            roster
                .iter()
                .map(|shape| match shape {
                    Shape::Member { .. } => {
                        count += 1;
                        Some(count - 1)
                    }
                    Shape::Type { .. } => None,
                })
                .collect()
        };
        if members_at_declaration.iter().flatten().count() != nodes.len() {
            return None;
        }
        let mut by_slot = vec![u32::MAX; tree.members.len()];
        for (index, node) in nodes.iter().enumerate() {
            *by_slot.get_mut(node.member.index())? = index as u32;
        }
        // Projection: old entries renumbered, the added ones inserted by key order.
        let mut projection: Vec<usize> = self
            .projection
            .iter()
            .map(|&old| old_to_new[old] as usize)
            .collect();
        for &(key, _, position, _) in &stable.added {
            let order = key_order(key);
            let at = projection.partition_point(|&index| key_order(nodes[index].key) < order);
            if projection.get(at).is_some_and(|&index| key_order(nodes[index].key) == order) {
                return None;
            }
            projection.insert(at, position);
        }
        let keys: Vec<DeclarationKey> = nodes.iter().map(|node| node.key).collect();
        let key_of = |id: MemberId| -> Option<DeclarationKey> {
            let node = *by_slot.get(id.index())?;
            (node != u32::MAX).then(|| keys[node as usize])
        };
        // Dependants: every predecessor whose dependant list can differ gets its list again, in declaration order.
        let moved: HashSet<MemberId> = stable
            .relinked
            .iter()
            .copied()
            .chain(stable.added.iter().map(|added| added.1))
            .collect();
        let mut predecessors: HashSet<MemberId> = HashSet::new();
        for &id in &moved {
            if let Some(previous) = previous_tree.members.get(id.index()).and_then(|node| node.previous) {
                predecessors.insert(previous);
            }
            if let Some(previous) = tree.members.get(id.index())?.previous {
                predecessors.insert(previous);
            }
        }
        if !predecessors.is_empty() {
            let order = tree.member_order();
            for predecessor in predecessors {
                let node = *by_slot.get(predecessor.index())? as usize;
                let mut dependants: Vec<MemberId> = Vec::new();
                for key in nodes[node].dependants.as_deref().into_iter().flatten() {
                    let index = self.slot(*key)?;
                    let id = self.nodes[index].member;
                    if !moved.contains(&id) {
                        dependants.push(id);
                    }
                }
                for &id in &moved {
                    if tree.members.get(id.index())?.previous == Some(predecessor) {
                        dependants.push(id);
                    }
                }
                let mut ranked = dependants
                    .into_iter()
                    .map(|id| Some((order.position_of(id)?, id)))
                    .collect::<Option<Vec<_>>>()?;
                ranked.sort_unstable_by_key(|ranked| ranked.0);
                nodes[node].dependants = if ranked.is_empty() {
                    None
                } else {
                    Some(Arc::new(
                        ranked.into_iter().map(|(_, id)| key_of(id)).collect::<Option<Vec<_>>>()?,
                    ))
                };
            }
        }
        Some(Self {
            roster,
            members_at_declaration,
            nodes,
            projection,
            by_slot,
        })
    }

    /// The first difference from `other` (verification): every field.
    pub(crate) fn first_difference(&self, other: &Self) -> Option<String> {
        if self.roster != other.roster {
            return Some("roster".into());
        }
        if self.members_at_declaration != other.members_at_declaration {
            return Some("members at declaration".into());
        }
        if self.nodes.len() != other.nodes.len() {
            return Some("node count".into());
        }
        for (index, (a, b)) in self.nodes.iter().zip(&other.nodes).enumerate() {
            if a.key != b.key || a.member != b.member || a.dependants.as_deref() != b.dependants.as_deref() {
                return Some(format!("node {index}: {:?}/{:?} vs {:?}/{:?}", a.key, a.member, b.key, b.member));
            }
        }
        if self.projection != other.projection {
            return Some("projection".into());
        }
        if self.by_slot != other.by_slot {
            return Some("slots".into());
        }
        None
    }
}

