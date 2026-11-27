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
    /// Set by the stable-slot path: what the dependency graph must take in.
    pub stable: Option<StableSplice>,
}

/// A splice that kept every retained member slot: rows were only added (new
/// slots at the end of the arena) or changed in place, the type roster and the
/// order of the retained rows are the same.
pub(crate) struct StableSplice {
    /// Each added member: its key, new slot, declaration position among the
    /// members and index among all declaration rows, in declaration order.
    pub added: Vec<(DeclarationKey, MemberId, usize, usize)>,
    /// Each changed member (same key, new row): its slot and row index.
    pub changed: Vec<(MemberId, usize)>,
    /// Retained slots in the dirty cone (their `previous` link or metadata may differ).
    pub relinked: Vec<MemberId>,
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
        let mut laps = Laps::start();
        let delta = current.delta_since(previous);
        laps.lap("delta");
        if delta.changes.is_empty() {
            return Err("no rows changed");
        }
        if std::env::var_os("DMB_CHANGE_SET_DEBUG").is_some() {
            for change in &delta.changes {
                let text = |id: SymbolId| symbols.text(id).or_else(|| previous_tree.symbols.text(id)).unwrap_or("?").to_string();
                let family = match change.key.family {
                    DeclarationFamily::Type => "type".to_string(),
                    DeclarationFamily::Member { name, kind } => format!("{:?} {}", kind, text(name)),
                };
                crate::change_set::record_outcome(format!(
                    "splice debug: owner={} {family} previous={} current={}",
                    text(change.key.owner), change.previous.is_some(), change.current.is_some()
                ));
            }
        }
        let mut changed_keys = HashSet::new();
        let mut names = HashSet::new();
        let mut type_rows_changed = HashSet::new();
        let mut anchors_changed: HashSet<(SymbolId, SymbolId)> = HashSet::new();
        for change in &delta.changes {
            let DeclarationFamily::Member { name, .. } = change.key.family else {
                type_rows_changed.insert(change.key.owner);
                continue;
            };
            let owner = change.key.owner;
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
        // Type paths retained below re-intern into the current table.
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
        laps.lap("symbols");
        // Rows only added or changed in place, retained rows in order, every owner's
        // first row where it was: the type roster cannot have changed, so the
        // stable-slot path needs no replay of the type order.
        let stable_rows = if type_rows_changed.is_empty() {
            self.stable_rows(previous_tree, previous, current, &delta)
        } else {
            None
        };
        laps.lap("rows");
        let roster = match stable_rows {
            Some(_) => None,
            None => splice_types(previous_tree, current, &mut symbols, &type_rows_changed)?,
        };
        laps.lap("types");
        let mut tree = previous_tree.clone();
        tree.default_edits = None;
        tree.symbols = Arc::new(symbols);
        let type_remap: Vec<Option<TypeId>> = match roster {
            Some(roster) => {
                tree.types = roster.types.into();
                tree.by_path = Arc::new(roster.by_path);
                roster.remap
            }
            None => (0..previous_tree.types.len()).map(|index| Some(TypeId(index as u32))).collect(),
        };
        let types_changed = type_remap.len() != tree.types.len()
            || type_remap.iter().enumerate().any(|(index, id)| *id != Some(TypeId(index as u32)));
        let new_type = |old: TypeId| -> Result<TypeId, &'static str> {
            type_remap[old.index()].ok_or("retained member on a removed type")
        };
        // Stable-slot path: rows only added or changed, type roster unchanged,
        // retained rows in the same order: keep every slot, append new ones.
        if !types_changed {
            if let Some(rows) = stable_rows {
                let mut nodes = std::mem::take(&mut tree.members);
                let old_len = nodes.len();
                let mut targets = rows.targets;
                let by_path = Arc::clone(&tree.by_path);
                let fresh_node = |row: &crate::declaration_contributions::DeclarationRow| -> Result<MemberNode, &'static str> {
                    let Skeleton::Member { owner, name, kind, mode, metadata, content } = &row.skeleton else {
                        return Err("added row is not a member");
                    };
                    Ok(MemberNode {
                        definition: *mode,
                        owner: *by_path.get(owner).ok_or("owner missing")?,
                        name: *name,
                        kind: *kind,
                        metadata: Arc::clone(metadata),
                        content: *content,
                        previous: None,
                    })
                };
                let mut fresh_rows: Vec<(usize, MemberId, DefinitionMode)> = Vec::new();
                for changed in &rows.changed {
                    let node = fresh_node(changed.row)?;
                    fresh_rows.push((changed.declaration, changed.slot, node.definition));
                    nodes[changed.slot.index()] = node;
                }
                let mut added_slots = Vec::with_capacity(rows.added.len());
                for added in &rows.added {
                    let node = fresh_node(added.row)?;
                    let mode = node.definition;
                    let slot = MemberId(u32::try_from(nodes.push(node)).map_err(|_| "too many members")?);
                    targets[added.declaration] = Target::Member(slot);
                    fresh_rows.push((added.declaration, slot, mode));
                    added_slots.push(slot);
                }
                fresh_rows.sort_unstable_by_key(|row| row.0);
                let fresh: Vec<(MemberId, DefinitionMode)> = fresh_rows.iter().map(|row| (row.1, row.2)).collect();
                // Owner rosters: each added slot at its place among its owner's members.
                let mut owned: Vec<Arc<[MemberId]>> = tree.types.iter().map(|node| Arc::clone(&node.members)).collect();
                let mut by_owner: HashMap<TypeId, Vec<(u32, MemberId)>> = HashMap::new();
                for (added, &slot) in rows.added.iter().zip(&added_slots) {
                    by_owner.entry(nodes[slot.index()].owner).or_default().push((added.in_owner, slot));
                }
                for (owner, inserts) in by_owner {
                    let mut ids = owned[owner.index()].to_vec();
                    for (at, slot) in inserts {
                        if at as usize > ids.len() {
                            return Err("added member outside its owner roster");
                        }
                        ids.insert(at as usize, slot);
                    }
                    owned[owner.index()] = ids.into();
                }
                let previous_groups: Vec<Group> = rows
                    .changed
                    .iter()
                    .map(|changed| {
                        let node = &previous_tree.members[changed.slot.index()];
                        (node.owner, node.name, node.kind)
                    })
                    .collect();
                laps.lap("arena");
                let mut direct: HashMap<Group, MemberId> = (*previous_tree.direct).clone();
                laps.lap("direct");
                let added_rows: HashMap<MemberId, &Arc<MemberMetadata>> = rows
                    .added
                    .iter()
                    .zip(&added_slots)
                    .filter_map(|(added, slot)| match &added.row.skeleton {
                        Skeleton::Member { metadata, .. } => Some((*slot, metadata)),
                        Skeleton::Type { .. } => None,
                    })
                    .collect();
                // Authored metadata of a dirty slot: an added row's, else the current row of its key.
                let authored = |id: MemberId| -> Arc<MemberMetadata> {
                    if let Some(metadata) = added_rows.get(&id) {
                        return Arc::clone(metadata);
                    }
                    let key = self.key_of_slot(id).expect("retained slot has its stable key");
                    let row = current
                        .owner(key.owner)
                        .and_then(|owner| owner.rows().iter().find(|row| row.key == key))
                        .expect("retained key has its current row");
                    match &row.skeleton {
                        Skeleton::Member { metadata, .. } => Arc::clone(metadata),
                        Skeleton::Type { .. } => unreachable!("member key names a member row"),
                    }
                };
                let (order, affected) = rebind(
                    &tree,
                    &mut nodes,
                    &owned,
                    &fresh,
                    &previous_groups,
                    &anchors_changed,
                    &mut direct,
                    &authored,
                )?;
                laps.lap("rebind");
                tree.direct = Arc::new(direct);
                let mut types = tree.types.to_vec();
                for (node, ids) in types.iter_mut().zip(owned) {
                    node.members = ids;
                }
                tree.types = types.into();
                tree.declaration_targets = targets.into();
                crate::metadata_update::resolve_metadata(&tree, &mut nodes, &order);
                tree.members = nodes;
                for (added, &slot) in rows.added.iter().zip(&added_slots) {
                    tree.member_order.insert(added.position, slot);
                }
                debug_assert_eq!(tree.member_order.len(), tree.members.len());
                let stable = StableSplice {
                    added: rows
                        .added
                        .iter()
                        .zip(&added_slots)
                        .map(|(added, &slot)| (added.row.key, slot, added.position, added.declaration))
                        .collect(),
                    changed: rows.changed.iter().map(|changed| (changed.slot, changed.declaration)).collect(),
                    relinked: order.iter().copied().filter(|id| id.index() < old_len).collect(),
                };
                laps.lap("publish");
                let spliced = finish(tree, &affected, order, &names, executor, types_changed, Some(stable), &mut laps);
                let stable = spliced.stable.as_ref().expect("stable splice");
                crate::change_set::record_outcome(format!(
                    "tree splice: stable slots ({} added, {} changed, {} slots): {}",
                    stable.added.len(),
                    stable.changed.len(),
                    spliced.tree.members.len(),
                    laps.report()
                ));
                return Ok(spliced);
            }
        }
        let old_ids: HashMap<DeclarationKey, MemberId> =
            self.nodes.iter().map(|node| (node.key, node.member)).collect();
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
                            let mut node = previous_tree.members[old.index()].clone();
                            node.owner = new_type(node.owner)?;
                            node
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
        let previous_groups: Vec<Group> = delta
            .changes
            .iter()
            .filter(|change| change.previous.is_some())
            .filter_map(|change| old_ids.get(&change.key))
            .filter_map(|old| {
                let node = &previous_tree.members[old.index()];
                // A removed type takes its whole group with it.
                Some((type_remap[node.owner.index()]?, node.name, node.kind))
            })
            .collect();
        let mut direct: HashMap<Group, MemberId> = previous_tree
            .direct
            .iter()
            .filter_map(|((owner, name, kind), old)| {
                Some(((type_remap[owner.index()]?, *name, *kind), remap[old.index()]?))
            })
            .collect();
        let owned: Vec<Arc<[MemberId]>> = owned.into_iter().map(Arc::from).collect();
        let (order, affected) = rebind(
            &tree,
            &mut nodes,
            &owned,
            &fresh_rows,
            &previous_groups,
            &anchors_changed,
            &mut direct,
            &|id| Arc::clone(&authored[id.index()]),
        )?;
        // Publish the structure the resolver reads before inheriting metadata.
        tree.direct = Arc::new(direct);
        let mut types = tree.types.to_vec();
        for (node, ids) in types.iter_mut().zip(owned) {
            node.members = ids;
        }
        tree.types = types.into();
        tree.declaration_targets = targets.into();
        crate::metadata_update::resolve_metadata(&tree, &mut nodes, &order);
        tree.members = crate::member_arena::MemberArena::from_reusing(nodes, &previous_tree.members);
        tree.member_order = crate::MemberOrder::identity(tree.members.len());
        Ok(finish(tree, &affected, order, &names, executor, types_changed, None, &mut laps))
    }
}

/// What every splice does after its members are published: owner selections,
/// callable names, the inventory of the changed names, ancestry.
#[allow(clippy::too_many_arguments)]
fn finish(
    mut tree: SemanticTree,
    affected: &[Group],
    order: Vec<MemberId>,
    names: &HashSet<SymbolId>,
    executor: &dm_exec::BuildExecutor,
    types_changed: bool,
    stable: Option<StableSplice>,
    laps: &mut Laps,
) -> Spliced {
    tree.refresh_member_callable_names();
    laps.lap("callable_names");
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
    laps.lap("selections");
    tree.rebuild_inventory_selectors(names, executor);
    laps.lap("inventory");
    if types_changed {
        let by_path = Arc::clone(&tree.by_path);
        Arc::make_mut(&mut tree.host_selections).retain(|path, _| by_path.contains_key(path));
        tree.rebuild_owner_ancestry();
    }
    Spliced {
        tree,
        dirty: order.len(),
        stable,
    }
}

/// The splice core shared by both paths: effective kinds of the fresh rows,
/// the changed groups' chains, the descendant groups that inherit through
/// them, their inherited predecessors and the dirty cone in inheritance order.
/// `nodes` and `owned` are the current members and owner rosters (slot
/// coordinates), `direct` the current selectors (updated here). Returns the
/// dirty cone in resolution order and the renormalized groups.
#[allow(clippy::too_many_arguments)]
fn rebind<N>(
    tree: &SemanticTree,
    nodes: &mut N,
    owned: &[Arc<[MemberId]>],
    fresh_rows: &[(MemberId, DefinitionMode)],
    previous_groups: &[Group],
    anchors_changed: &HashSet<(SymbolId, SymbolId)>,
    direct: &mut HashMap<Group, MemberId>,
    authored: &dyn Fn(MemberId) -> Arc<MemberMetadata>,
) -> Result<(Vec<MemberId>, Vec<Group>), &'static str>
where
    N: std::ops::Index<usize, Output = MemberNode> + std::ops::IndexMut<usize>,
{
    let root = SymbolId::of("/");
    // callable_namespace anchors: last authored non-implicit proc/verb of
    // (owner, name), else the intrinsic row (ambiguous intrinsics decline).
    let anchor = |nodes: &N, owner: TypeId, name: SymbolId| -> Result<Option<MemberKind>, &'static str> {
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
    let effective = |nodes: &N, owner: TypeId, name: SymbolId, authored: MemberKind| -> Result<MemberKind, &'static str> {
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
    for &(id, mode) in fresh_rows {
        let node = &nodes[id.index()];
        if mode == DefinitionMode::Implicit && matches!(node.kind, MemberKind::Proc | MemberKind::Verb) {
            let kind = effective(&*nodes, node.owner, node.name, node.kind)?;
            nodes[id.index()].kind = kind;
        }
    }
    // A changed anchor must not move an existing implicit callable to the
    // other namespace (that regroups chains the splice does not rebuild).
    let mut children = vec![Vec::new(); tree.types.len()];
    for (index, node) in tree.types.iter().enumerate() {
        if let Some(parent) = node.parent {
            children[parent.index()].push(TypeId(index as u32));
        }
    }
    for &(owner, name) in anchors_changed {
        let Some(owner) = tree.lookup_type(owner) else {
            continue;
        };
        let mut stack = vec![owner];
        while let Some(current) = stack.pop() {
            for id in owned[current.index()].iter() {
                let node = &nodes[id.index()];
                if node.name == name
                    && node.definition == DefinitionMode::Implicit
                    && !fresh_rows.iter().any(|(fresh, _)| fresh == id)
                    && effective(&*nodes, node.owner, name, node.kind)? != node.kind
                {
                    return Err("changed anchor moves an implicit callable");
                }
            }
            stack.extend(children[current.index()].iter().copied());
        }
    }
    // Changed groups: every current changed row and every removed/changed
    // retained row, each under its effective kind.
    let mut groups: HashSet<Group> = HashSet::new();
    for &(id, _) in fresh_rows {
        let node = &nodes[id.index()];
        groups.insert((node.owner, node.name, node.kind));
    }
    groups.extend(previous_groups.iter().copied());
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
        if mode == DefinitionMode::Declare && previous.is_some() {
            return Err("inherited redeclaration");
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
        nodes[id.index()].metadata = authored(*id);
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
    Ok((order, affected))
}

/// Number of types the root and engine hierarchy rows ensure before any
/// authored row (their first-encounter closure under lexical parents).
pub(crate) fn engine_type_prefix<'a>(
    tree: &SemanticTree,
    engine_rows: impl Iterator<Item = &'a Skeleton>,
) -> Option<u32> {
    let mut seen = HashSet::new();
    seen.insert(SymbolId::of("/"));
    for row in engine_rows {
        let mut cursor = Some(match row {
            Skeleton::Type { path, .. } => *path,
            Skeleton::Member { owner, .. } => *owner,
        });
        while let Some(path) = cursor {
            if !seen.insert(path) {
                break;
            }
            let text = tree.symbols.text(path)?;
            cursor = match dm_ir::TypePath::parse(text).ok()?.parent() {
                Some(parent) => Some(tree.lookup_type(SymbolId::of(parent.as_str()))
                    .map(|id| tree.types[id.index()].path)?),
                None => None,
            };
        }
    }
    let start = seen.len();
    (start <= tree.types.len() && tree.types[..start].iter().all(|node| seen.contains(&node.path)))
        .then_some(start as u32)
}

struct TypeRoster {
    types: Vec<crate::TypeNode>,
    by_path: HashMap<SymbolId, TypeId>,
    remap: Vec<Option<TypeId>>,
}

/// Replay the full constructor's type ordering (root and engine prefix, then
/// first encounter over authored rows with lexical ancestors first) and its
/// parent rules. `None` when the roster is unchanged. Existing types must keep
/// their parent, explicit flag and synthetic flag; new types need acyclic
/// parents. Anything else declines to the full constructor.
fn splice_types(
    previous: &SemanticTree,
    current: &KeyedDeclarations,
    symbols: &mut dm_ir::SymbolTable,
    type_rows_changed: &HashSet<SymbolId>,
) -> Result<Option<TypeRoster>, &'static str> {
    let start = previous.authored_type_start.ok_or("engine type prefix unknown")? as usize;
    let mut order: Vec<SymbolId> = previous.types[..start].iter().map(|node| node.path).collect();
    let mut index: HashMap<SymbolId, usize> =
        order.iter().enumerate().map(|(position, path)| (*path, position)).collect();
    let mut lexical: HashMap<SymbolId, Option<SymbolId>> = HashMap::new();
    let mut declared = HashSet::new();
    let mut explicit: HashMap<SymbolId, SymbolId> = HashMap::new();
    for row in current.skeletons() {
        let path = match row {
            Skeleton::Type { path, explicit_parent } => {
                declared.insert(*path);
                if let Some(parent) = explicit_parent {
                    if explicit.insert(*path, *parent).is_some_and(|old| old != *parent) {
                        return Err("conflicting explicit parent");
                    }
                }
                *path
            }
            Skeleton::Member { owner, .. } => *owner,
        };
        let mut chain = Vec::new();
        let mut cursor = Some(path);
        while let Some(path) = cursor {
            if index.contains_key(&path) || chain.contains(&path) {
                break;
            }
            chain.push(path);
            let text = symbols.text(path).ok_or("type path missing from symbols")?.to_string();
            let parent = dm_ir::TypePath::parse(&text)
                .map_err(|_| "invalid type path")?
                .parent()
                .map(|parent| symbols.intern(parent.as_str()))
                .transpose()
                .map_err(|_| "symbol collision")?;
            lexical.insert(path, parent);
            cursor = parent;
        }
        for path in chain.into_iter().rev() {
            index.insert(path, order.len());
            order.push(path);
        }
    }
    if order.len() == previous.types.len()
        && order.iter().zip(previous.types.iter()).all(|(path, node)| *path == node.path)
        && type_rows_changed.is_empty()
    {
        return Ok(None);
    }
    for path in type_rows_changed {
        if previous.lookup_type(*path).is_some() && index.contains_key(path) {
            return Err("type row of an existing type changed");
        }
    }
    let root = SymbolId::of("/");
    let datum = SymbolId::of("/datum");
    let mut types = Vec::with_capacity(order.len());
    for (position, &path) in order.iter().enumerate() {
        if position < start {
            let mut node = previous.types[position].clone();
            node.members = Arc::from([]);
            types.push(node);
            continue;
        }
        let parent = match explicit.get(&path) {
            Some(parent) => Some(TypeId(*index.get(parent).ok_or("missing explicit parent")? as u32)),
            None => lexical.get(&path).copied().flatten().map(|lexical| {
                if lexical == root && path != datum && index.contains_key(&datum) {
                    TypeId(index[&datum] as u32)
                } else {
                    TypeId(index[&lexical] as u32)
                }
            }),
        };
        types.push(crate::TypeNode {
            path,
            parent,
            explicit_parent: explicit.contains_key(&path),
            synthetic: !declared.contains(&path),
            members: Arc::from([]),
        });
    }
    // Existing types keep their shape exactly; new types must be acyclic.
    let mut remap = vec![None; previous.types.len()];
    for (old_index, node) in previous.types.iter().enumerate() {
        let Some(&position) = index.get(&node.path) else {
            continue;
        };
        remap[old_index] = Some(TypeId(position as u32));
        let new = &types[position];
        let old_parent = node.parent.map(|id| previous.types[id.index()].path);
        let new_parent = new.parent.map(|id| types[id.index()].path);
        if old_parent != new_parent
            || node.explicit_parent != new.explicit_parent
            || node.synthetic != new.synthetic
        {
            return Err("existing type hierarchy changed");
        }
    }
    for start_index in 0..types.len() {
        let mut cursor = types[start_index].parent;
        let mut steps = 0;
        while let Some(id) = cursor {
            steps += 1;
            if steps > types.len() {
                return Err("inheritance cycle");
            }
            cursor = types[id.index()].parent;
        }
    }
    let by_path = order
        .iter()
        .enumerate()
        .map(|(position, path)| (*path, TypeId(position as u32)))
        .collect();
    Ok(Some(TypeRoster {
        types,
        by_path,
        remap,
    }))
}

/// DMB_SPLICE_VERIFY=1: compare a spliced tree with the full constructor's.
pub(crate) fn verify_enabled() -> bool {
    std::env::var_os("DMB_SPLICE_VERIFY").is_some_and(|value| value == "1")
}
/// The first difference between two trees, compared by declaration order:
/// member slots may differ (a spliced tree keeps its slots, a full build
/// numbers them afresh), so every member reference is compared as the
/// declaration position of the slot it names.
pub(crate) fn first_difference(spliced: &SemanticTree, full: &SemanticTree) -> Option<String> {
    if spliced.types.len() != full.types.len() {
        return Some("type count".into());
    }
    if spliced.member_count() != full.member_count() {
        return Some("member count".into());
    }
    let position_a = spliced.member_order.positions(spliced.members.len());
    let position_b = full.member_order.positions(full.members.len());
    let a_at = |id: MemberId| position_a[id.index()];
    let b_at = |id: MemberId| position_b[id.index()];
    for (index, (a, b)) in spliced.types.iter().zip(full.types.iter()).enumerate() {
        if a.path != b.path
            || a.parent != b.parent
            || !a.members.iter().map(|id| a_at(*id)).eq(b.members.iter().map(|id| b_at(*id)))
            || a.explicit_parent != b.explicit_parent
            || a.synthetic != b.synthetic
        {
            return Some(format!("type {index}"));
        }
    }
    for (index, ((_, a), (_, b))) in spliced.members_in_order().zip(full.members_in_order()).enumerate() {
        let mut a = a.clone();
        let mut b = b.clone();
        let (pa, pb) = (a.previous.map(a_at), b.previous.map(b_at));
        a.previous = None;
        b.previous = None;
        if a != b || pa != pb {
            return Some(format!("member {index}: {a:?} (previous {pa:?}) vs {b:?} (previous {pb:?})"));
        }
    }
    let direct = |tree: &SemanticTree, at: &dyn Fn(MemberId) -> u32| {
        let mut rows: Vec<_> = tree.direct.iter().map(|((owner, name, kind), id)| (owner.0, name.bits(), *kind, at(*id))).collect();
        rows.sort_unstable();
        rows
    };
    if direct(spliced, &a_at) != direct(full, &b_at) {
        return Some("direct".into());
    }
    let targets = |tree: &SemanticTree, at: &dyn Fn(MemberId) -> u32| {
        tree.declaration_targets
            .iter()
            .map(|target| match target {
                Target::Type(id) => (false, id.0),
                Target::Member(id) => (true, at(*id)),
            })
            .collect::<Vec<_>>()
    };
    if targets(spliced, &a_at) != targets(full, &b_at) {
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

/// An added member row of a stable splice.
struct AddedRow<'a> {
    row: &'a crate::declaration_contributions::DeclarationRow,
    /// Declaration position among the current members.
    position: usize,
    /// Index among its owner's current members.
    in_owner: u32,
    /// Index among all current declaration rows.
    declaration: usize,
}
/// A row whose key both rosters hold, with a different row.
struct ChangedRow<'a> {
    slot: MemberId,
    row: &'a crate::declaration_contributions::DeclarationRow,
    declaration: usize,
}
struct StableRows<'a> {
    /// The current declaration targets; an added row's entry is filled when its slot is issued.
    targets: Vec<Target>,
    added: Vec<AddedRow<'a>>,
    changed: Vec<ChangedRow<'a>>,
}

impl MetadataDependencies {
    /// The slot's stable key, when the slot is in this graph.
    pub(crate) fn key_of_slot(&self, id: MemberId) -> Option<DeclarationKey> {
        let node = *self.by_slot.get(id.index())?;
        (node != u32::MAX).then(|| self.nodes[node as usize].key)
    }
    /// Whether `current` is `previous` with member rows added or changed and
    /// nothing removed or moved, and if so where each added row goes. One pass
    /// in step over both rosters; rows of an owner whose contribution is the
    /// same allocation are compared by handle, the rest by key.
    fn stable_rows<'a>(
        &self,
        previous_tree: &SemanticTree,
        previous: &KeyedDeclarations,
        current: &'a KeyedDeclarations,
        delta: &crate::declaration_contributions::DeclarationDelta<'_>,
    ) -> Option<StableRows<'a>> {
        let mut added_keys = HashSet::new();
        let mut changed_keys = HashSet::new();
        for change in &delta.changes {
            match (change.previous, change.current) {
                (None, Some(_)) => {
                    added_keys.insert(change.key);
                }
                (Some(_), Some(_)) => {
                    changed_keys.insert(change.key);
                }
                _ => return None,
            }
        }
        let changed_owners: HashSet<SymbolId> = current
            .owners()
            .filter(|(owner, contribution)| {
                previous
                    .owner(**owner)
                    .is_none_or(|old| !Arc::ptr_eq(old, contribution))
            })
            .map(|(owner, _)| *owner)
            .collect();
        let (before, after) = (previous.roster(), current.roster());
        let previous_targets = previous_tree.declarations();
        if previous_targets.len() != before.len() || self.by_slot.len() != previous_tree.members.len() {
            return None;
        }
        let mut targets = Vec::with_capacity(after.len());
        let mut added = Vec::new();
        let mut changed = Vec::new();
        let mut in_owner: HashMap<SymbolId, u32> = HashMap::new();
        // Owners of added rows that a row of their own already preceded (so their type id stays).
        let added_owners: HashSet<SymbolId> = added_keys.iter().map(|key| key.owner).collect();
        if added_owners.iter().any(|owner| previous_tree.lookup_type(*owner).is_none()) {
            return None;
        }
        let mut owners_seen: HashSet<SymbolId> = HashSet::new();
        let mut position = 0usize;
        let mut cursor = 0usize;
        for (declaration, handle) in after.iter().enumerate() {
            if changed_owners.contains(&handle.owner) {
                let row = current.row(*handle)?;
                let member = matches!(row.skeleton, Skeleton::Member { .. });
                let ordinal = if member {
                    let count = in_owner.entry(handle.owner).or_insert(0);
                    *count += 1;
                    *count - 1
                } else {
                    0
                };
                if added_keys.contains(&row.key) {
                    // A first row of its owner would move the owner's type id.
                    if !member || !owners_seen.contains(&handle.owner) {
                        return None;
                    }
                    added.push(AddedRow { row, position, in_owner: ordinal, declaration });
                    targets.push(Target::Member(MemberId(u32::MAX)));
                    position += 1;
                    continue;
                }
                let old = previous.row(*before.get(cursor)?)?;
                if old.key != row.key {
                    return None;
                }
                if added_owners.contains(&handle.owner) {
                    owners_seen.insert(handle.owner);
                }
                if changed_keys.contains(&row.key) {
                    let Target::Member(slot) = previous_targets[cursor] else {
                        return None;
                    };
                    changed.push(ChangedRow { slot, row, declaration });
                }
            } else if before.get(cursor) != Some(handle) {
                return None;
            }
            let target = previous_targets[cursor];
            if matches!(target, Target::Member(_)) {
                position += 1;
            }
            targets.push(target);
            cursor += 1;
        }
        (cursor == before.len() && added.len() == added_keys.len() && changed.len() == changed_keys.len())
            .then_some(StableRows { targets, added, changed })
    }
}

/// Wall time of each step of one splice, for its outcome line.
pub(crate) struct Laps {
    mark: std::time::Instant,
    laps: Vec<(&'static str, f64)>,
}
impl Laps {
    fn start() -> Self {
        Self { mark: std::time::Instant::now(), laps: Vec::new() }
    }
    fn lap(&mut self, step: &'static str) {
        let now = std::time::Instant::now();
        self.laps.push((step, (now - self.mark).as_secs_f64()));
        self.mark = now;
    }
    fn report(&self) -> String {
        self.laps.iter().map(|(step, secs)| format!("{step}={secs:.3}s")).collect::<Vec<_>>().join(" ")
    }
}
