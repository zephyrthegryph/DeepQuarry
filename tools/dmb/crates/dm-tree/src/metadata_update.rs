//! Stable-roster invalidation scheduling; semantic inheritance stays in one core.
//!
//! Full construction and retained updates call the same inheritance resolver.
use crate::{DefinitionMode, MemberId, MemberKind, SemanticTree, Skeleton, Target};
use dm_ir::SymbolId;

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
    members_at_declaration: Vec<Option<MemberId>>,
    dependants: Vec<Vec<MemberId>>,
    order: Vec<MemberId>,
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
        vector(&self.dependants, &mut visit);
        for dependants in &self.dependants {
            vector(dependants, &mut visit);
        }
        vector(&self.order, &mut visit);
    }
    pub(crate) fn capture(tree: &SemanticTree, skeletons: &[Skeleton]) -> Option<Self> {
        if tree.declarations().len() != skeletons.len() {
            return None;
        }
        let mut members_at_declaration = Vec::with_capacity(skeletons.len());
        for (skeleton, target) in skeletons.iter().zip(tree.declarations()) {
            match (skeleton, target) {
                (Skeleton::Type { .. }, Target::Type(_)) => members_at_declaration.push(None),
                (Skeleton::Member { .. }, Target::Member(id)) => {
                    members_at_declaration.push(Some(*id))
                }
                _ => return None,
            }
        }
        let mut dependants = vec![Vec::new(); tree.members().len()];
        for (index, member) in tree.members().iter().enumerate() {
            if let Some(previous) = member.previous {
                dependants
                    .get_mut(previous.index())?
                    .push(MemberId(u32::try_from(index).ok()?));
            }
        }
        let order = resolution_order(tree.members());
        Some(Self {
            roster: skeletons.iter().map(shape).collect(),
            members_at_declaration,
            dependants,
            order,
        })
    }
    /// Exact shape/ordering equality authorizes retaining arena IDs. Return dirty
    /// members in existing inheritance order, including reopened/inherited links.
    pub(crate) fn changed(
        &self,
        previous: &[Skeleton],
        current: &[Skeleton],
    ) -> Option<Vec<MemberId>> {
        if previous.len() != self.roster.len()
            || current.len() != self.roster.len()
            || previous.iter().map(shape).ne(self.roster.iter().copied())
            || current.iter().map(shape).ne(self.roster.iter().copied())
        {
            return None;
        }
        let mut dirty = vec![false; self.dependants.len()];
        let mut queue = Vec::new();
        for (index, (old, new)) in previous.iter().zip(current).enumerate() {
            if old != new {
                let id = self.members_at_declaration[index]?;
                if !dirty[id.index()] {
                    dirty[id.index()] = true;
                    queue.push(id);
                }
            }
        }
        let mut next = 0;
        while let Some(&id) = queue.get(next) {
            next += 1;
            for &child in &self.dependants[id.index()] {
                if !dirty[child.index()] {
                    dirty[child.index()] = true;
                    queue.push(child);
                }
            }
        }
        Some(
            self.order
                .iter()
                .copied()
                .filter(|id| dirty[id.index()])
                .collect(),
        )
    }
}

pub(crate) fn resolution_order(members: &[crate::MemberNode]) -> Vec<MemberId> {
    let mut resolved = vec![false; members.len()];
    let mut order = Vec::with_capacity(members.len());
    for start in 0..members.len() {
        let mut chain = Vec::new();
        let mut cursor = Some(MemberId(start as u32));
        while let Some(id) = cursor {
            if resolved[id.index()] {
                break;
            }
            chain.push(id);
            cursor = members[id.index()].previous;
        }
        for id in chain.into_iter().rev() {
            resolved[id.index()] = true;
            order.push(id);
        }
    }
    order
}
pub(crate) fn apply_opaque_base(tree: &SemanticTree, member: &mut crate::MemberNode) {
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
            let metadata = std::sync::Arc::make_mut(&mut member.metadata);
            metadata.declared_type = match opaque.declared_type {
                dm_ir::DeclaredTypeKnowledge::Known(path) => Some(path),
                dm_ir::DeclaredTypeKnowledge::Unsupported
                | dm_ir::DeclaredTypeKnowledge::KnownUntyped => None,
            };
            metadata.inherited_opaque = Some(opaque.clone());
            break;
        }
        owner = tree.parent(current);
    }
}
pub(crate) fn resolve_metadata(
    tree: &SemanticTree,
    members: &mut [crate::MemberNode],
    order: &[MemberId],
) {
    for &id in order {
        let i = id.index();
        apply_opaque_base(tree, &mut members[i]);
        if members[i].definition == DefinitionMode::Override && members[i].kind == MemberKind::Var {
            if let Some(previous) = members[i].previous {
                let inherited = members[previous.index()].metadata.clone();
                let metadata = std::sync::Arc::make_mut(&mut members[i].metadata);
                metadata.inherited_opaque = inherited.inherited_opaque.clone();
                metadata.declared_type = inherited.declared_type;
                metadata.list_element_type = inherited.list_element_type;
                metadata.flags = inherited.flags;
                metadata.array = inherited.array.clone();
                metadata.declared_initializer = inherited.declared_initializer.clone();
            }
        }
    }
}
impl MetadataDependencies {
    pub(crate) fn update(
        &self,
        previous_tree: &SemanticTree,
        previous: &[Skeleton],
        current: &[Skeleton],
        mut symbols: dm_ir::SymbolTable,
        executor: &dm_exec::BuildExecutor,
    ) -> Option<SemanticTree> {
        let dirty = self.changed(previous, current)?;
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
        let mut members = previous_tree.members.to_vec();
        for (index, skeleton) in current.iter().enumerate() {
            if let (
                Some(id),
                Skeleton::Member {
                    metadata, content, ..
                },
            ) = (self.members_at_declaration[index], skeleton)
            {
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
        tree.members = members.into();
        tree.rebuild_inventory_selectors(&names, executor);
        Some(tree)
    }
}
