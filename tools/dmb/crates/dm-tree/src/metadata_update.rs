//! Stable-roster invalidation scheduling; semantic inheritance stays in one core.
//!
//! Full construction and retained updates call the same inheritance resolver.
use crate::declaration_contributions::{DeclarationKey, KeyedDeclarations};
use crate::{DefinitionMode, MemberId, MemberKind, SemanticTree, Skeleton, Target};
use dm_ir::SymbolId;
use std::collections::HashMap;
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Shape {
    Type {
        path: SymbolId,
        parent: Option<SymbolId>,
    },
    Member {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
        mode: DefinitionMode,
    },
}
fn key_order(key: DeclarationKey) -> (u64, u8, u64, u8, u32) {
    use crate::declaration_contributions::DeclarationFamily;
    let (family, name, kind) = match key.family {
        DeclarationFamily::Type => (0, 0, 0),
        DeclarationFamily::Member { name, kind } => (
            1,
            name.bits(),
            match kind {
                MemberKind::Var => 0,
                MemberKind::Proc => 1,
                MemberKind::Verb => 2,
            },
        ),
    };
    (key.owner.bits(), family, name, kind, key.occurrence)
}
fn shape(skeleton: &Skeleton) -> Shape {
    match skeleton {
        Skeleton::Type {
            path,
            explicit_parent,
        } => Shape::Type {
            path: *path,
            parent: *explicit_parent,
        },
        Skeleton::Member {
            owner,
            name,
            kind,
            mode,
            ..
        } => Shape::Member {
            owner: *owner,
            name: *name,
            kind: *kind,
            mode: *mode,
        },
    }
}
/// Issued only from a successfully constructed tree and its exact authored roster.
/// Array IDs may be retained ONLY while this structural roster remains exact.
pub(crate) struct MetadataDependencies {
    roster: Vec<Shape>,
    members_at_declaration: Vec<Option<usize>>,
    nodes: Vec<DependencyNode>,
    projection: Vec<usize>,
    order: Vec<DeclarationKey>,
}
struct DependencyNode {
    key: DeclarationKey,
    member: MemberId,
    // Stable source keys, never historical dense output/member coordinates.
    dependants: Vec<DeclarationKey>,
}
impl MetadataDependencies {
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        fn vector<T>(values: &Vec<T>, visit: &mut impl FnMut(usize, usize, usize)) {
            visit(
                values.as_ptr() as usize,
                values.len().saturating_mul(std::mem::size_of::<T>()),
                values.capacity().saturating_mul(std::mem::size_of::<T>()),
            );
        }
        // All shape fields are scalar; an added owned field must update this audit.
        for value in &self.roster {
            match value {
                Shape::Type { path: _, parent: _ }
                | Shape::Member {
                    owner: _,
                    name: _,
                    kind: _,
                    mode: _,
                } => (),
            }
        }
        vector(&self.roster, &mut visit);
        vector(&self.members_at_declaration, &mut visit);
        vector(&self.nodes, &mut visit);
        vector(&self.projection, &mut visit);
        for node in &self.nodes {
            vector(&node.dependants, &mut visit);
        }
        vector(&self.order, &mut visit);
    }
    pub(crate) fn capture(tree: &SemanticTree, declarations: &KeyedDeclarations) -> Option<Self> {
        if tree.declarations().len() != declarations.len() {
            return None;
        }
        let mut members_at_declaration = Vec::with_capacity(declarations.len());
        let mut nodes = Vec::with_capacity(tree.members.len());
        let mut keys = vec![None; tree.members.len()];
        for (row, target) in declarations.ordered().zip(tree.declarations()) {
            match (&row.skeleton, target) {
                (Skeleton::Type { .. }, Target::Type(_)) => members_at_declaration.push(None),
                (Skeleton::Member { .. }, Target::Member(id)) => {
                    if keys[id.index()].replace(row.key).is_some() {
                        return None;
                    }
                    members_at_declaration.push(Some(nodes.len()));
                    nodes.push(DependencyNode {
                        key: row.key,
                        member: *id,
                        dependants: Vec::new(),
                    });
                }
                _ => return None,
            }
        }
        let keys: Vec<_> = keys.into_iter().collect::<Option<_>>()?;
        let projection: HashMap<_, _> = nodes
            .iter()
            .enumerate()
            .map(|(index, node)| (node.key, index))
            .collect();
        if projection.len() != nodes.len() {
            return None;
        }
        for (index, member) in tree.members.iter().enumerate() {
            if let Some(previous) = member.previous {
                nodes[*projection.get(&keys[previous.index()])?]
                    .dependants
                    .push(keys[index]);
            }
        }
        let mut stable_projection: Vec<_> = (0..nodes.len()).collect();
        stable_projection.sort_unstable_by_key(|&index| key_order(nodes[index].key));
        let order = resolution_order(tree.members.len(), |id| tree.members[id].previous)
            .into_iter()
            .map(|id| keys[id.index()])
            .collect();
        Some(Self {
            roster: declarations.skeletons().map(shape).collect(),
            members_at_declaration,
            nodes,
            projection: stable_projection,
            order,
        })
    }
    fn slot(&self, key: DeclarationKey) -> Option<usize> {
        let order = key_order(key);
        let index = self
            .projection
            .binary_search_by_key(&order, |&index| key_order(self.nodes[index].key))
            .ok()?;
        Some(self.projection[index])
    }
    /// Exact shape/ordering equality authorizes retaining arena IDs. Return dirty
    /// members in existing inheritance order, including reopened/inherited links.
    pub(crate) fn changed<'a, 'b>(
        &self,
        previous: impl ExactSizeIterator<Item = &'a Skeleton> + Clone,
        current: impl ExactSizeIterator<Item = &'b Skeleton> + Clone,
    ) -> Option<Vec<MemberId>> {
        if previous.len() != self.roster.len()
            || current.len() != self.roster.len()
            || previous.clone().map(shape).ne(self.roster.iter().copied())
            || current.clone().map(shape).ne(self.roster.iter().copied())
        {
            return None;
        }
        let mut dirty = vec![false; self.nodes.len()];
        let mut queue = Vec::new();
        for (index, (old, new)) in previous.zip(current).enumerate() {
            if old != new {
                let slot = self.members_at_declaration[index]?;
                if !dirty[slot] {
                    dirty[slot] = true;
                    queue.push(slot);
                }
            }
        }
        let mut next = 0;
        while let Some(&id) = queue.get(next) {
            next += 1;
            for child in &self.nodes[id].dependants {
                let child = self.slot(*child)?;
                if !dirty[child] {
                    dirty[child] = true;
                    queue.push(child);
                }
            }
        }
        Some(
            self.order
                .iter()
                .filter_map(|key| {
                    let slot = self.slot(*key).expect("validated stable dependency key");
                    dirty[slot].then_some(self.nodes[slot].member)
                })
                .collect(),
        )
    }
}

pub(crate) fn resolution_order(
    len: usize,
    previous: impl Fn(usize) -> Option<MemberId>,
) -> Vec<MemberId> {
    dependency_order(len, |index| previous(index).map(MemberId::index))
        .into_iter()
        .map(|index| MemberId(index as u32))
        .collect()
}
/// Shared dependency ordering for validated member and type graphs.
pub(crate) fn dependency_order(
    len: usize,
    previous: impl Fn(usize) -> Option<usize>,
) -> Vec<usize> {
    let mut resolved = vec![false; len];
    let mut order = Vec::with_capacity(len);
    for start in 0..len {
        let mut chain = Vec::new();
        let mut cursor = Some(start);
        while let Some(index) = cursor {
            if resolved[index] {
                break;
            }
            chain.push(index);
            cursor = previous(index);
        }
        for index in chain.into_iter().rev() {
            resolved[index] = true;
            order.push(index);
        }
    }
    order
}
pub(crate) fn apply_opaque_base<M: crate::member_binding::MemberWrite + ?Sized>(
    tree: &SemanticTree,
    members: &mut M,
    index: usize,
) {
    let member = members.member(index);
    if member.definition != DefinitionMode::Override
        || member.previous.is_some()
        || member.kind != MemberKind::Var
    {
        return;
    }
    let mut owner = Some(member.owner);
    while let Some(current) = owner {
        if let Some(opaque) = tree
            .intrinsic_fields
            .get(&(tree.types[current.index()].path, member.name))
        {
            let declared_type = match opaque.declared_type {
                dm_ir::DeclaredTypeKnowledge::Known(path) => Some(path),
                dm_ir::DeclaredTypeKnowledge::Unsupported
                | dm_ir::DeclaredTypeKnowledge::KnownUntyped => None,
            };
            if member.metadata.declared_type == declared_type
                && member.metadata.inherited_opaque.as_ref() == Some(opaque)
            {
                return;
            }
            let mut metadata = member.metadata.as_ref().clone();
            metadata.declared_type = declared_type;
            metadata.inherited_opaque = Some(opaque.clone());
            members.set_metadata(index, Arc::new(metadata));
            return;
        }
        owner = tree.parent(current);
    }
}
pub(crate) fn resolve_metadata<M: crate::member_binding::MemberWrite + ?Sized>(
    tree: &SemanticTree,
    members: &mut M,
    order: &[MemberId],
) {
    for &id in order {
        let i = id.index();
        apply_opaque_base(tree, members, i);
        let member = members.member(i);
        if member.definition == DefinitionMode::Override && member.kind == MemberKind::Var {
            if let Some(previous) = member.previous {
                let inherited = members.member(previous.index()).metadata;
                let current = member.metadata;
                if current.inherited_opaque == inherited.inherited_opaque
                    && current.declared_type == inherited.declared_type
                    && current.list_element_type == inherited.list_element_type
                    && current.flags == inherited.flags
                    && current.array == inherited.array
                    && current.declared_initializer == inherited.declared_initializer
                {
                    continue;
                }
                let mut metadata = current.as_ref().clone();
                metadata.inherited_opaque = inherited.inherited_opaque.clone();
                metadata.declared_type = inherited.declared_type;
                metadata.list_element_type = inherited.list_element_type;
                metadata.flags = inherited.flags;
                metadata.array = inherited.array.clone();
                metadata.declared_initializer = inherited.declared_initializer.clone();
                members.set_metadata(i, Arc::new(metadata));
            }
        }
    }
}
impl MetadataDependencies {
    pub(crate) fn update<'a, 'b>(
        &self,
        previous_tree: &SemanticTree,
        previous: impl ExactSizeIterator<Item = &'a Skeleton> + Clone,
        current: impl ExactSizeIterator<Item = &'b Skeleton> + Clone,
        mut symbols: dm_ir::SymbolTable,
        executor: &dm_exec::BuildExecutor,
    ) -> Option<SemanticTree> {
        let dirty = self.changed(previous, current.clone())?;
        let mut tree = previous_tree.clone();
        // Current exact symbol authority replaces old lexical spellings. Keep
        // only implicit parent paths that the full constructor would ensure.
        for node in previous_tree.types() {
            if symbols.text(node.path).is_none() {
                let text = previous_tree.symbols.text(node.path)?;
                if symbols.intern(text).ok()? != node.path {
                    return None;
                }
            }
        }
        tree.symbols = std::sync::Arc::new(symbols);
        let dirty_set: std::collections::HashSet<_> = dirty.iter().copied().collect();
        let mut members = previous_tree.members.clone();
        for (index, skeleton) in current.enumerate() {
            if let (
                Some(slot),
                Skeleton::Member {
                    metadata, content, ..
                },
            ) = (self.members_at_declaration[index], skeleton)
            {
                let id = self.nodes[slot].member;
                if dirty_set.contains(&id) {
                    // Reset from CURRENT authored metadata before inheritance;
                    // never treat old effective flags/arrays as authored input.
                    members[id.index()].metadata = std::sync::Arc::clone(metadata);
                    members[id.index()].content = *content;
                }
            }
        }
        resolve_metadata(&tree, &mut members, &dirty);
        let names: std::collections::HashSet<_> =
            dirty.iter().map(|id| members[id.index()].name).collect();
        tree.members = members;
        tree.refresh_host_selections(&dirty);
        tree.rebuild_inventory_selectors(&names, executor);
        Some(tree)
    }
}

#[cfg(test)]
#[path = "metadata_stable_key_tests.rs"]
mod stable_key_tests;
