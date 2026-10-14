//! Change-set splice of added, removed and changed member rows into a retained
//! tree (doc/structural_change_set.md, consumer 2).
//!
//! Dense member IDs follow authored declaration order, so the spliced arena is
//! rebuilt in the current order with every retained `previous` link remapped.
//! Only the changed (owner, name, kind) groups and the same-name groups of
//! their descendants are renormalized and re-inherited; everything else keeps
//! the retained effective node. Any shape the full constructor would treat
//! differently (type rows, implicit owners or members, duplicates, inherited
//! redeclarations, missing overrides, opaque engine bases) declines with a
//! reason so the full path runs and reports exactly as a fresh build would.
use super::MetadataDependencies;
use crate::declaration_contributions::{DeclarationFamily, DeclarationKey, KeyedDeclarations};
use crate::{
    DefinitionMode, MemberId, MemberKind, MemberMetadata, MemberNode, SemanticTree, Skeleton,
    Target, TypeId,
};
use dm_ir::SymbolId;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

pub(crate) struct Spliced {
    pub tree: SemanticTree,
    pub dirty: usize,
}

type Group = (TypeId, SymbolId, MemberKind);

impl MetadataDependencies {
    pub(crate) fn splice(
        &self,
        previous_tree: &SemanticTree,
        previous: &KeyedDeclarations,
        current: &KeyedDeclarations,
        mut symbols: dm_ir::SymbolTable,
        executor: &dm_exec::BuildExecutor,
    ) -> Result<Spliced, &'static str> {
        let type_rows = |declarations: &KeyedDeclarations| -> Vec<(SymbolId, Option<SymbolId>)> {
            declarations
                .skeletons()
                .filter_map(|row| match row {
                    Skeleton::Type {
                        path,
                        explicit_parent,
                    } => Some((*path, *explicit_parent)),
                    Skeleton::Member { .. } => None,
                })
                .collect()
        };
        if type_rows(previous) != type_rows(current) {
            return Err("type rows changed");
        }
        let delta = current.delta_since(previous);
        if delta.changes.is_empty() {
            return Err("no member rows changed");
        }
        let mut changed_keys = HashSet::new();
        let mut names = HashSet::new();
        let mut anchors_changed: HashSet<(TypeId, SymbolId)> = HashSet::new();
        for change in &delta.changes {
            let DeclarationFamily::Member { name, .. } = change.key.family else {
                return Err("type row changed");
            };
            let owner = previous_tree
                .lookup_type(change.key.owner)
                .ok_or("member on a new owner")?;
            if previous_tree.types[owner.index()].synthetic {
                return Err("member on an implicit owner");
            }
            for row in [change.previous, change.current].into_iter().flatten() {
                let Skeleton::Member { kind, mode, .. } = &row.skeleton else {
                    return Err("member row became a type row");
                };
                // A non-implicit callable row is a namespace anchor for
                // implicit callables of the same name at and below its owner.
                if *mode != DefinitionMode::Implicit
                    && matches!(kind, MemberKind::Proc | MemberKind::Verb)
                {
                    anchors_changed.insert((owner, name));
                }
            }
            changed_keys.insert(change.key);
            names.insert(name);
        }
        // Lexical authority as in update(): keep only paths the tree must keep.
        for node in previous_tree.types() {
            if symbols.text(node.path).is_none() {
                let text = previous_tree.symbols.text(node.path).ok_or("symbol lost")?;
                if symbols.intern(text).map_err(|_| "symbol collision")? != node.path {
                    return Err("symbol collision");
                }
            }
        }
        for name in delta.changes.iter().filter(|change| change.current.is_some()).filter_map(
            |change| match change.key.family {
                DeclarationFamily::Member { name, .. } => Some(name),
                DeclarationFamily::Type => None,
            },
        ) {
            if symbols.text(name).is_none() {
                return Err("member name missing from current symbols");
            }
        }
        let old_ids: HashMap<DeclarationKey, MemberId> =
            self.nodes.iter().map(|node| (node.key, node.member)).collect();
        let mut tree = previous_tree.clone();
        tree.symbols = Arc::new(symbols);
        // Rebuild the arena in current authored order.
        let old_len = previous_tree.members.len();
        let mut remap: Vec<Option<MemberId>> = vec![None; old_len];
        let mut nodes: Vec<MemberNode> = Vec::with_capacity(old_len + changed_keys.len());
        let mut authored: Vec<Arc<MemberMetadata>> = Vec::with_capacity(nodes.capacity());
        let mut targets = Vec::with_capacity(current.len());
        let mut fresh = Vec::new();
        let mut fresh_rows: Vec<(MemberId, DefinitionMode)> = Vec::new();
        for row in current.ordered() {
            match &row.skeleton {
                Skeleton::Type { path, .. } => {
                    targets.push(Target::Type(*tree.by_path.get(path).ok_or("type missing")?))
                }
                Skeleton::Member {
                    owner,
                    name,
                    kind,
                    mode,
                    metadata,
                    content,
                } => {
                    let id = MemberId(u32::try_from(nodes.len()).map_err(|_| "too many members")?);
                    let old = old_ids.get(&row.key).copied();
                    if let Some(old) = old {
                        remap[old.index()] = Some(id);
                    }
                    if changed_keys.contains(&row.key) {
                        fresh_rows.push((id, *mode));
                    }
                    let node = match old {
                        Some(old) if !changed_keys.contains(&row.key) => {
                            previous_tree.members[old.index()].clone()
                        }
                        _ => {
                            fresh.push(id);
                            MemberNode {
                                definition: *mode,
                                owner: *tree.by_path.get(owner).ok_or("owner missing")?,
                                name: *name,
                                kind: *kind,
                                metadata: Arc::clone(metadata),
                                content: *content,
                                previous: None,
                            }
                        }
                    };
                    authored.push(Arc::clone(metadata));
                    nodes.push(node);
                    targets.push(Target::Member(id));
                }
            }
        }
        for node in &mut nodes {
            node.previous = node.previous.and_then(|old| remap[old.index()]);
        }
        let mut owned = vec![Vec::new(); tree.types.len()];
        for (index, node) in nodes.iter().enumerate() {
            owned[node.owner.index()].push(MemberId(index as u32));
        }
        let root = SymbolId::of("/");
        // callable_namespace anchors: last authored non-implicit proc/verb of
        // (owner, name), else the intrinsic row (ambiguous intrinsics decline).
        let anchor = |nodes: &[MemberNode], owner: TypeId, name: SymbolId| -> Result<Option<MemberKind>, &'static str> {
            if let Some(node) = owned[owner.index()].iter().rev().map(|id| &nodes[id.index()]).find(|node| {
                node.name == name
                    && node.definition != DefinitionMode::Implicit
                    && matches!(node.kind, MemberKind::Proc | MemberKind::Verb)
            }) {
                return Ok(Some(node.kind));
            }
            let path = tree.types[owner.index()].path;
            let proc = tree.inventory.index.contains_key(&(path, name, MemberKind::Proc));
            let verb = tree.inventory.index.contains_key(&(path, name, MemberKind::Verb));
            match (proc, verb) {
                (true, true) => Err("ambiguous intrinsic callable anchor"),
                (true, false) => Ok(Some(MemberKind::Proc)),
                (false, true) => Ok(Some(MemberKind::Verb)),
                (false, false) => Ok(None),
            }
        };
        let effective = |nodes: &[MemberNode], owner: TypeId, name: SymbolId, authored: MemberKind| -> Result<MemberKind, &'static str> {
            let mut cursor = Some(owner);
            while let Some(current) = cursor {
                if current != owner && tree.types[current.index()].path == root {
                    break;
                }
                if let Some(kind) = anchor(nodes, current, name)? {
                    return Ok(kind);
                }
                cursor = tree.parent(current);
            }
            Ok(authored)
        };
        for &(id, mode) in &fresh_rows {
            let node = &nodes[id.index()];
            if mode == DefinitionMode::Implicit && matches!(node.kind, MemberKind::Proc | MemberKind::Verb) {
                let kind = effective(&nodes, node.owner, node.name, node.kind)?;
                nodes[id.index()].kind = kind;
            }
        }
        // A changed anchor must not move an existing implicit callable to the
        // other namespace (that regroups chains the splice does not rebuild).
        for &(owner, name) in &anchors_changed {
            let mut stack = vec![owner];
            while let Some(current) = stack.pop() {
                for id in &owned[current.index()] {
                    let node = &nodes[id.index()];
                    if node.name == name
                        && node.definition == DefinitionMode::Implicit
                        && !fresh_rows.iter().any(|(fresh, _)| fresh == id)
                        && effective(&nodes, node.owner, name, node.kind)? != node.kind
                    {
                        return Err("changed anchor moves an implicit callable");
                    }
                }
                stack.extend(
                    tree.types
                        .iter()
                        .enumerate()
                        .filter(|(_, child)| child.parent == Some(current))
                        .map(|(index, _)| TypeId(index as u32)),
                );
            }
        }
        // Changed groups: every current changed row and every removed/changed
        // retained row, each under its effective kind.
        let mut groups: HashSet<Group> = HashSet::new();
        for &(id, _) in &fresh_rows {
            let node = &nodes[id.index()];
            groups.insert((node.owner, node.name, node.kind));
        }
        for change in &delta.changes {
            if change.previous.is_some() {
                if let Some(old) = old_ids.get(&change.key) {
                    let node = &previous_tree.members[old.index()];
                    groups.insert((node.owner, node.name, node.kind));
                }
            }
        }
        let mut children = vec![Vec::new(); tree.types.len()];
        for (index, node) in tree.types.iter().enumerate() {
            if let Some(parent) = node.parent {
                children[parent.index()].push(TypeId(index as u32));
            }
        }
        let mut direct: HashMap<Group, MemberId> = tree
            .direct
            .iter()
            .filter_map(|(key, old)| remap[old.index()].map(|id| (*key, id)))
            .collect();
        let mut dirty = Vec::new();
        let mut heads = Vec::new();
        // Changed groups: renormalize the owner-local chain (formal first).
        let mut affected: Vec<Group> = groups.iter().copied().collect();
        affected.sort_by_key(|(owner, name, kind)| (owner.0, name.bits(), *kind as u8));
        for &(owner, name, kind) in &affected {
            let ids: Vec<MemberId> = owned[owner.index()]
                .iter()
                .copied()
                .filter(|id| nodes[id.index()].name == name && nodes[id.index()].kind == kind)
                .collect();
            let declares = ids
                .iter()
                .filter(|id| nodes[id.index()].definition == DefinitionMode::Declare)
                .count();
            if declares > 1 {
                return Err("duplicate declaration");
            }
            if kind != MemberKind::Var && declares == 1 {
                // Formals stay unique across both callable namespaces.
                let other = if kind == MemberKind::Proc { MemberKind::Verb } else { MemberKind::Proc };
                if owned[owner.index()].iter().any(|id| {
                    let node = &nodes[id.index()];
                    node.name == name && node.kind == other
                }) {
                    return Err("callable formal in both namespaces");
                }
            }
            let chain = crate::member_normalization::formal_chain(&ids, |id| {
                nodes[id.index()].definition == DefinitionMode::Declare
            });
            let mut previous = None;
            for id in &chain {
                nodes[id.index()].previous = previous;
                previous = Some(*id);
                dirty.push(*id);
            }
            match chain.first() {
                Some(head) => heads.push(*head),
                None => {}
            }
            match chain.last() {
                Some(last) => {
                    direct.insert((owner, name, kind), *last);
                }
                None => {
                    direct.remove(&(owner, name, kind));
                }
            }
        }
        // Descendant groups of the same name inherit through the changed group.
        let mut seen: HashSet<Group> = affected.iter().copied().collect();
        for &(owner, name, kind) in &affected {
            let mut stack = children[owner.index()].clone();
            while let Some(child) = stack.pop() {
                stack.extend(children[child.index()].iter().copied());
                let group = (child, name, kind);
                if !seen.insert(group) || !direct.contains_key(&group) {
                    continue;
                }
                let ids: Vec<MemberId> = owned[child.index()]
                    .iter()
                    .copied()
                    .filter(|id| nodes[id.index()].name == name && nodes[id.index()].kind == kind)
                    .collect();
                for id in &ids {
                    let node = &nodes[id.index()];
                    if node.previous.is_none_or(|p| nodes[p.index()].owner != child) {
                        heads.push(*id);
                    }
                    dirty.push(*id);
                }
            }
        }
        // Inherited predecessors for every group head, as resolve_previous.
        for &head in &heads {
            let node = &nodes[head.index()];
            let (owner, name, kind, mode) = (node.owner, node.name, node.kind, node.definition);
            let mut parent = tree.parent(owner);
            let mut previous = None;
            while let Some(current) = parent {
                if tree.types[current.index()].path == root {
                    break;
                }
                if let Some(id) = direct.get(&(current, name, kind)) {
                    previous = Some(*id);
                    break;
                }
                parent = tree.parent(current);
            }
            if mode == DefinitionMode::Declare && kind == MemberKind::Var && previous.is_some() {
                return Err("inherited variable redeclaration");
            }
            if mode == DefinitionMode::Override && previous.is_none() {
                return Err("override without inherited declaration");
            }
            if mode == DefinitionMode::Declare && kind != MemberKind::Var {
                // validate_explicit: an inherited anchor of the other kind is a duplicate.
                let other = if kind == MemberKind::Proc { MemberKind::Verb } else { MemberKind::Proc };
                let mut cursor = tree.parent(owner);
                while let Some(current) = cursor {
                    if tree.types[current.index()].path == root {
                        break;
                    }
                    if direct.contains_key(&(current, name, other))
                        || tree.inventory.index.contains_key(&(
                            tree.types[current.index()].path,
                            name,
                            other,
                        ))
                    {
                        return Err("callable declared over the other namespace");
                    }
                    if direct.contains_key(&(current, name, kind)) {
                        break;
                    }
                    cursor = tree.parent(current);
                }
            }
            nodes[head.index()].previous = previous;
        }
        // Re-inherit metadata from authored values over the dirty cone.
        let dirty_set: HashSet<MemberId> = dirty.iter().copied().collect();
        for id in &dirty {
            nodes[id.index()].metadata = Arc::clone(&authored[id.index()]);
        }
        let mut order = Vec::with_capacity(dirty.len());
        let mut placed = HashSet::new();
        for &start in &dirty {
            let mut chain = Vec::new();
            let mut cursor = Some(start);
            while let Some(id) = cursor {
                if !dirty_set.contains(&id) || placed.contains(&id) {
                    break;
                }
                chain.push(id);
                cursor = nodes[id.index()].previous;
            }
            for id in chain.into_iter().rev() {
                if placed.insert(id) {
                    order.push(id);
                }
            }
        }
        // Publish the structure the resolver reads before inheriting metadata.
        tree.direct = Arc::new(direct);
        let mut types = tree.types.to_vec();
        for (node, ids) in types.iter_mut().zip(owned) {
            node.members = ids.into();
        }
        tree.types = types.into();
        tree.declaration_targets = targets.into();
        crate::metadata_update::resolve_metadata(&tree, &mut nodes, &order);
        tree.members = crate::member_arena::MemberArena::from_reusing(nodes, &previous_tree.members);
        tree.refresh_member_callable_names();
        let owners: HashSet<TypeId> = affected.iter().map(|group| group.0).chain(
            order.iter().map(|id| tree.members[id.index()].owner),
        )
        .collect();
        {
            let selections = Arc::make_mut(&mut tree.host_selections);
            for owner in owners {
                let node = &tree.types[owner.index()];
                if node.members.is_empty() {
                    selections.remove(&node.path);
                } else {
                    selections.insert(
                        node.path,
                        crate::host_declaration_selection::select(
                            node.path,
                            &tree.members,
                            node.members.iter().copied(),
                        ),
                    );
                }
            }
        }
        tree.rebuild_inventory_selectors(&names, executor);
        let _ = fresh;
        Ok(Spliced {
            tree,
            dirty: order.len(),
        })
    }
}

/// DMB_SPLICE_VERIFY=1: compare a spliced tree with the full constructor's.
pub(crate) fn verify_enabled() -> bool {
    std::env::var_os("DMB_SPLICE_VERIFY").is_some_and(|value| value == "1")
}
pub(crate) fn first_difference(spliced: &SemanticTree, full: &SemanticTree) -> Option<String> {
    if spliced.types.len() != full.types.len() {
        return Some("type count".into());
    }
    for (index, (a, b)) in spliced.types.iter().zip(full.types.iter()).enumerate() {
        if a.path != b.path || a.parent != b.parent || a.members != b.members {
            return Some(format!("type {index}"));
        }
    }
    if spliced.members.len() != full.members.len() {
        return Some("member count".into());
    }
    for (index, (a, b)) in spliced.members.iter().zip(full.members.iter()).enumerate() {
        if a != b {
            return Some(format!("member {index}: {a:?} vs {b:?}"));
        }
    }
    if spliced.direct != full.direct {
        return Some("direct".into());
    }
    if spliced.declaration_targets != full.declaration_targets {
        return Some("declaration targets".into());
    }
    if spliced.host_selections != full.host_selections {
        return Some("host selections".into());
    }
    if spliced.member_callable_names != full.member_callable_names {
        return Some("callable names".into());
    }
    if spliced.identity != full.identity {
        return Some("identity".into());
    }
    None
}

#[cfg(test)]
#[path = "metadata_splice_tests.rs"]
mod tests;
