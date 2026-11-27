//! Source-neutral callable indexes issued beside the current body roster.
use super::BodyOccurrence;
use crate::{MemberId, MemberKind, SemanticTree};
use dm_ir::ProcedureIdentity;
use std::{
    collections::{BTreeSet, HashMap},
    sync::Arc,
};

#[path = "frontend_callable_abi_roster.rs"]
mod abi;
pub use abi::{CallableAbiEntry, CallableAbiGraph, CallableAbiMeaning, CallableAbiRoster};
#[derive(Clone, Debug)]
pub struct CallableRoster {
    tree: Arc<SemanticTree>,
    index: Arc<CallableIndexRecipe>,
    abi: Option<Arc<CallableAbiRoster>>,
}
#[derive(Debug)]
pub struct CallableIndexRecipe {
    members: Vec<MemberId>,
    identities: Vec<ProcedureIdentity>,
    ordinals: HashMap<MemberId, usize>,
    dependents: Vec<Vec<usize>>,
    ready: Vec<usize>,
    source_order: Vec<usize>,
    effective: Vec<bool>,
    bindings: BTreeSet<dm_ir::SymRef>,
}
impl PartialEq for CallableRoster {
    fn eq(&self, other: &Self) -> bool {
        std::ptr::eq(self, other)
            || (Arc::ptr_eq(&self.tree, &other.tree) && self.index.members == other.index.members)
    }
}
impl Eq for CallableRoster {}
impl CallableRoster {
    pub(super) fn issue(
        tree: &Arc<SemanticTree>,
        bodies: &[BodyOccurrence],
    ) -> Result<Arc<Self>, String> {
        let mut members = Vec::with_capacity(bodies.len());
        let mut identities = Vec::with_capacity(bodies.len());
        let mut ordinals = HashMap::with_capacity(bodies.len());
        let mut unique = BTreeSet::new();
        for (ordinal, body) in bodies.iter().enumerate() {
            let node = tree.member(body.member).ok_or("body member missing")?;
            let owner = tree.type_node(node.owner).ok_or("body owner missing")?.path;
            let verb = match node.kind {
                MemberKind::Proc => false,
                MemberKind::Verb => true,
                MemberKind::Var => return Err("variable body in procedure index".into()),
            };
            let occurrence = tree
                .member_occurrence(body.member)
                .ok_or("empty procedure chain")?;
            let identity = ProcedureIdentity {
                owner,
                name: node.name,
                verb,
                occurrence,
            };
            if !unique.insert(identity) || ordinals.insert(body.member, ordinal).is_some() {
                return Err("ambiguous current procedure occurrence".into());
            }
            members.push(body.member);
            identities.push(identity);
        }
        let mut dependents = vec![Vec::new(); bodies.len()];
        let mut ready = Vec::new();
        for (ordinal, member) in members.iter().enumerate() {
            match tree.member(*member).ok_or("body member missing")?.previous {
                None => ready.push(ordinal),
                Some(previous) => {
                    if let Some(predecessor) = ordinals.get(&previous) {
                        dependents[*predecessor].push(ordinal);
                    }
                }
            }
        }
        let mut source_order: Vec<_> = (0..bodies.len()).collect();
        source_order.sort_by_key(|&i| {
            let body = &bodies[i];
            (
                body.source.encounter_ordinal,
                body.expanded_span.start,
                body.declaration.0,
            )
        });
        let effective: Vec<_> = members
            .iter()
            .map(|&member| {
                let node = tree.member(member).expect("issued member");
                tree.resolve(node.owner, node.name, node.kind) == Some(member)
            })
            .collect();
        let mut bindings: BTreeSet<_> = tree
            .types()
            .iter()
            .map(|node| dm_ir::SymRef::Type(node.path))
            .collect();
        for (identity, &selected) in identities.iter().zip(&effective) {
            if selected {
                bindings.insert(if identity.verb {
                    dm_ir::SymRef::Verb {
                        owner: identity.owner,
                        name: identity.name,
                        occurrence: identity.occurrence,
                    }
                } else {
                    dm_ir::SymRef::Proc {
                        owner: identity.owner,
                        name: identity.name,
                        occurrence: identity.occurrence,
                    }
                });
            }
        }
        let abi = CallableAbiRoster::issue(tree, &members, &identities).ok();
        Ok(Arc::new(Self {
            tree: Arc::clone(tree),
            index: Arc::new(CallableIndexRecipe {
                members,
                identities,
                ordinals,
                dependents,
                ready,
                source_order,
                effective,
                bindings,
            }),
            abi,
        }))
    }
    /// Rebind the current facade using the existing immutable dense topology.
    /// Changed chunks are checked exactly; body content and variable metadata do
    /// not define a callable index. Procedure metadata refreshes the ABI owner.
    /// Type/layout/ancestry and predecessor changes decline to ordinary issuance.
    pub(super) fn rebind_semantic_owner(&self, tree: &Arc<SemanticTree>) -> Option<Arc<Self>> {
        let old = &self.tree;
        if !Arc::ptr_eq(&old.types, &tree.types)
            || !Arc::ptr_eq(&old.owner_ancestry, &tree.owner_ancestry)
            || old.members.len() != tree.members.len()
            || !Arc::ptr_eq(old.members.chunk_offsets(), tree.members.chunk_offsets())
            || old.members.chunks().len() != tree.members.chunks().len()
        {
            return None;
        }
        let mut changed = Vec::new();
        for (chunk, (before, current)) in old
            .members
            .chunks()
            .iter()
            .zip(tree.members.chunks())
            .enumerate()
        {
            if Arc::ptr_eq(before, current) {
                continue;
            }
            if before.len() != current.len() {
                return None;
            }
            for (within, (a, b)) in before.iter().zip(current.iter()).enumerate() {
                if a.owner != b.owner
                    || a.name != b.name
                    || a.kind != b.kind
                    || a.definition != b.definition
                    || a.previous != b.previous
                {
                    return None;
                }
                if a.kind != MemberKind::Var && a.metadata.procedure != b.metadata.procedure {
                    let index = tree.members.chunk_offsets()[chunk].checked_add(within)?;
                    let member = MemberId(u32::try_from(index).ok()?);
                    changed.push((
                        *self.index.ordinals.get(&member)?,
                        b.metadata.procedure.clone()?,
                    ));
                }
            }
        }
        let mut rebound = self.clone();
        if !changed.is_empty() {
            rebound.abi = Some(self.abi.as_ref()?.rebind_metadata(&changed)?);
        }
        rebound.tree = tree.clone();
        Some(Arc::new(rebound))
    }
    /// The roster for `tree`, a stable-slot splice of this roster's tree that
    /// touched only `touched` (every retained slot holds the member it held):
    /// when no touched member is callable and every indexed callable is the
    /// same node, identities, chains, selection and the ABI are unchanged.
    pub(super) fn rebind_after_stable_splice(
        &self,
        tree: &Arc<SemanticTree>,
        touched: &[MemberId],
    ) -> Option<Arc<Self>> {
        let old = &self.tree;
        if !Arc::ptr_eq(&old.owner_ancestry, &tree.owner_ancestry)
            || old.types.len() != tree.types.len()
            || old
                .types
                .iter()
                .zip(tree.types.iter())
                .any(|(a, b)| a.path != b.path || a.parent != b.parent)
        {
            return None;
        }
        for &id in touched {
            let now = tree.member(id)?;
            if now.kind != MemberKind::Var || old.member(id).is_some_and(|before| before.kind != MemberKind::Var) {
                return None;
            }
        }
        for &member in &self.index.members {
            let (before, now) = (old.member(member)?, tree.member(member)?);
            if before.owner != now.owner
                || before.name != now.name
                || before.kind != now.kind
                || before.definition != now.definition
                || before.previous != now.previous
                || !(Arc::ptr_eq(&before.metadata, &now.metadata)
                    || before.metadata.procedure == now.metadata.procedure)
            {
                return None;
            }
        }
        let mut rebound = self.clone();
        rebound.tree = Arc::clone(tree);
        Some(Arc::new(rebound))
    }
    /// The roster for `tree` and `bodies` after a stable-slot splice of this roster's tree that added callables (new slots)
    /// and touched `touched`: the previous indexes with the new bodies inserted at their ordinals, every later ordinal
    /// shifted, and only the inserted callables, the relinked ones and the chains below them computed again. `None` when the
    /// splice did anything else (types, removals, a reordered body roster): the caller issues the roster afresh.
    pub(super) fn insert_after_stable_splice(
        &self,
        tree: &Arc<SemanticTree>,
        bodies: &[BodyOccurrence],
        touched: &[MemberId],
    ) -> Option<Arc<Self>> {
        const MAX_INSERTED: usize = 64;
        let old = &self.tree;
        if !Arc::ptr_eq(&old.owner_ancestry, &tree.owner_ancestry)
            || old.types.len() != tree.types.len()
            || old
                .types
                .iter()
                .zip(tree.types.iter())
                .any(|(a, b)| a.path != b.path || a.parent != b.parent)
        {
            return None;
        }
        let started = std::time::Instant::now();
        let mut laps: Vec<(&'static str, f64)> = Vec::new();
        let lap = |name: &'static str, laps: &mut Vec<(&'static str, f64)>| laps.push((name, started.elapsed().as_secs_f64()));
        let old_slots = old.members().len();
        let previous = &self.index;
        // The new body roster is the previous one with new slots inserted.
        let mut members = Vec::with_capacity(bodies.len());
        let mut old_to_new = Vec::with_capacity(previous.members.len());
        let mut inserted = Vec::new();
        for (ordinal, body) in bodies.iter().enumerate() {
            let member = body.member;
            if previous.members.get(old_to_new.len()) == Some(&member) {
                old_to_new.push(ordinal);
            } else if member.index() >= old_slots {
                inserted.push(ordinal);
                if inserted.len() > MAX_INSERTED {
                    return None;
                }
            } else {
                return None;
            }
            members.push(member);
        }
        if old_to_new.len() != previous.members.len() || inserted.is_empty() {
            return None;
        }
        // A touched new slot is a var or one of the inserted bodies; a retained callable keeps its node apart from `previous`.
        for &id in touched {
            if id.index() >= old_slots && tree.member(id)?.kind != MemberKind::Var && !inserted.iter().any(|&o| members[o] == id) {
                return None;
            }
        }
        let mut relinked = Vec::new();
        for (old_ordinal, &member) in previous.members.iter().enumerate() {
            let (before, now) = (old.member(member)?, tree.member(member)?);
            if before.owner != now.owner
                || before.name != now.name
                || before.kind != now.kind
                || before.definition != now.definition
                || !(Arc::ptr_eq(&before.metadata, &now.metadata)
                    || before.metadata.procedure == now.metadata.procedure)
            {
                return None;
            }
            if before.previous != now.previous {
                relinked.push(old_to_new[old_ordinal]);
            }
        }
        lap("walk", &mut laps);
        let mut ordinals = previous.ordinals.clone();
        for ordinal in ordinals.values_mut() {
            *ordinal = old_to_new[*ordinal];
        }
        for &ordinal in &inserted {
            if ordinals.insert(members[ordinal], ordinal).is_some() {
                return None;
            }
        }
        lap("ordinals", &mut laps);
        let mut dependents = vec![Vec::new(); members.len()];
        let mut ready = Vec::new();
        for (ordinal, member) in members.iter().enumerate() {
            match tree.member(*member)?.previous {
                None => ready.push(ordinal),
                Some(previous) => {
                    if let Some(predecessor) = ordinals.get(&previous) {
                        dependents[*predecessor].push(ordinal);
                    }
                }
            }
        }
        lap("dependents", &mut laps);
        // The callables whose identity, chain or ABI entry may differ: the inserted and relinked ones and every chain below.
        let mut dirty = vec![false; members.len()];
        let mut stack: Vec<usize> = inserted.iter().chain(&relinked).copied().collect();
        let mut recompute = Vec::new();
        while let Some(ordinal) = stack.pop() {
            if std::mem::replace(&mut dirty[ordinal], true) {
                continue;
            }
            recompute.push(ordinal);
            stack.extend(dependents[ordinal].iter().copied());
        }
        recompute.sort_unstable();
        let identity_of = |member: MemberId| -> Option<ProcedureIdentity> {
            let node = tree.member(member)?;
            Some(ProcedureIdentity {
                owner: tree.type_node(node.owner)?.path,
                name: node.name,
                verb: match node.kind {
                    MemberKind::Proc => false,
                    MemberKind::Verb => true,
                    MemberKind::Var => return None,
                },
                occurrence: tree.member_occurrence(member)?,
            })
        };
        let mut identities = vec![None; members.len()];
        for (old_ordinal, &new) in old_to_new.iter().enumerate() {
            identities[new] = Some(previous.identities[old_ordinal]);
        }
        for &ordinal in &recompute {
            identities[ordinal] = Some(identity_of(members[ordinal])?);
        }
        let identities: Vec<ProcedureIdentity> = identities.into_iter().collect::<Option<_>>()?;
        // An identity names one callable: check the recomputed ones against the callables of their owner and name.
        for &ordinal in &recompute {
            let node = tree.member(members[ordinal])?;
            for &other in tree.type_node(node.owner)?.members.iter() {
                if other == members[ordinal] {
                    continue;
                }
                let Some(&other_ordinal) = ordinals.get(&other) else { continue };
                if identities[other_ordinal] == identities[ordinal] {
                    return None;
                }
            }
        }
        lap("identities", &mut laps);
        // Selection changes only within the (owner, name, kind) groups of the recomputed callables.
        let mut effective = vec![false; members.len()];
        for (old_ordinal, &new) in old_to_new.iter().enumerate() {
            effective[new] = previous.effective[old_ordinal];
        }
        let mut reselect: Vec<usize> = Vec::new();
        for &ordinal in &recompute {
            let node = tree.member(members[ordinal])?;
            for &other in tree.type_node(node.owner)?.members.iter() {
                let other_node = tree.member(other)?;
                if other_node.name == node.name && other_node.kind == node.kind {
                    if let Some(&other_ordinal) = ordinals.get(&other) {
                        reselect.push(other_ordinal);
                    }
                }
            }
        }
        reselect.sort_unstable();
        reselect.dedup();
        let binding = |identity: &ProcedureIdentity| {
            if identity.verb {
                dm_ir::SymRef::Verb { owner: identity.owner, name: identity.name, occurrence: identity.occurrence }
            } else {
                dm_ir::SymRef::Proc { owner: identity.owner, name: identity.name, occurrence: identity.occurrence }
            }
        };
        let mut bindings = previous.bindings.clone();
        let new_to_old: HashMap<usize, usize> = reselect
            .iter()
            .chain(&recompute)
            .filter_map(|&new| old_to_new.binary_search(&new).ok().map(|old| (new, old)))
            .collect();
        let mut touched_ordinals: Vec<usize> = reselect.iter().chain(&recompute).copied().collect();
        touched_ordinals.sort_unstable();
        touched_ordinals.dedup();
        for &ordinal in &touched_ordinals {
            if let Some(&old_ordinal) = new_to_old.get(&ordinal) {
                if previous.effective[old_ordinal] {
                    bindings.remove(&binding(&previous.identities[old_ordinal]));
                }
            }
        }
        for &ordinal in &touched_ordinals {
            let node = tree.member(members[ordinal])?;
            effective[ordinal] = tree.resolve(node.owner, node.name, node.kind) == Some(members[ordinal]);
        }
        for &ordinal in &touched_ordinals {
            if effective[ordinal] {
                bindings.insert(binding(&identities[ordinal]));
            }
        }
        lap("bindings", &mut laps);
        let key = |i: usize| {
            let b = &bodies[i];
            (b.source.encounter_ordinal, b.expanded_span.start, b.declaration.0)
        };
        let mut source_order: Vec<usize> = previous.source_order.iter().map(|&old| old_to_new[old]).collect();
        for &ordinal in &inserted {
            let at = source_order.partition_point(|&other| key(other) < key(ordinal));
            source_order.insert(at, ordinal);
        }
        if !source_order.windows(2).all(|pair| key(pair[0]) <= key(pair[1])) {
            source_order = (0..bodies.len()).collect();
            source_order.sort_by_key(|&i| key(i));
        }
        lap("source_order", &mut laps);
        let abi = self
            .abi
            .as_ref()
            .and_then(|abi| abi.after_insert(tree, &members, &identities, &old_to_new, &recompute).ok());
        lap("abi", &mut laps);
        let mut at = 0.0;
        crate::change_set::record_outcome(format!(
            "callable roster insertion ({} inserted, {} recomputed): {}",
            inserted.len(),
            recompute.len(),
            laps.iter()
                .map(|(name, end)| {
                    let line = format!("{name}={:.3}s", end - at);
                    at = *end;
                    line
                })
                .collect::<Vec<_>>()
                .join(" ")
        ));
        Some(Arc::new(Self {
            tree: Arc::clone(tree),
            index: Arc::new(CallableIndexRecipe {
                members,
                identities,
                ordinals,
                dependents,
                ready,
                source_order,
                effective,
                bindings,
            }),
            abi,
        }))
    }
    /// Every index, the ABI entries and its graph equal another roster's (the insertion proof against a fresh issue).
    pub(super) fn first_difference(&self, other: &Self) -> Option<&'static str> {
        let (a, b) = (&self.index, &other.index);
        if a.members != b.members {
            return Some("members");
        }
        if a.identities != b.identities {
            return Some("identities");
        }
        if a.ordinals != b.ordinals {
            return Some("ordinals");
        }
        if a.dependents != b.dependents {
            return Some("dependents");
        }
        if a.ready != b.ready {
            return Some("ready");
        }
        if a.source_order != b.source_order {
            return Some("source order");
        }
        if a.effective != b.effective {
            return Some("effective");
        }
        if a.bindings != b.bindings {
            return Some("bindings");
        }
        match (&self.abi, &other.abi) {
            (None, None) => None,
            (Some(x), Some(y)) if x == y => None,
            _ => Some("abi"),
        }
    }
    pub(super) fn matches(&self, tree: &Arc<SemanticTree>, bodies: &[BodyOccurrence]) -> bool {
        self.authenticates_tree(tree)
            && self.index.source_order.windows(2).all(|pair| {
                let key = |i: usize| {
                    let b = &bodies[i];
                    (
                        b.source.encounter_ordinal,
                        b.expanded_span.start,
                        b.declaration.0,
                    )
                };
                pair[1] < bodies.len() && pair[0] < bodies.len() && key(pair[0]) <= key(pair[1])
            })
            && self
                .index
                .members
                .iter()
                .copied()
                .eq(bodies.iter().map(|body| body.member))
    }
    /// Exact issued semantic owner, never a structural hash or source revision.
    pub fn authenticates_tree(&self, tree: &Arc<SemanticTree>) -> bool {
        Arc::ptr_eq(&self.tree, tree)
    }
    /// Source-neutral ordering, admitted against current occurrence order below.
    pub fn source_order(&self) -> &[usize] {
        &self.index.source_order
    }
    pub fn source_bindings(&self) -> &BTreeSet<dm_ir::SymRef> {
        &self.index.bindings
    }
    pub fn effective(&self, ordinal: usize) -> Option<bool> {
        self.index.effective.get(ordinal).copied()
    }
    pub fn identity(&self, ordinal: usize) -> Option<ProcedureIdentity> {
        self.index.identities.get(ordinal).copied()
    }
    pub fn ordinal(&self, member: MemberId) -> Option<usize> {
        self.index.ordinals.get(&member).copied()
    }
    pub fn identity_for_member(&self, member: MemberId) -> Option<ProcedureIdentity> {
        self.identity(self.ordinal(member)?)
    }
    pub fn abi(&self) -> Option<&Arc<CallableAbiRoster>> {
        self.abi.as_ref()
    }
    pub fn members(&self) -> &[MemberId] {
        &self.index.members
    }
    pub fn dependents(&self, ordinal: usize) -> &[usize] {
        self.index
            .dependents
            .get(ordinal)
            .map_or(&[], Vec::as_slice)
    }
    pub fn ready(&self) -> &[usize] {
        &self.index.ready
    }
    pub fn visit_storage(&self, mut visitor: impl FnMut(CallableRosterStorage<'_>)) {
        visitor(CallableRosterStorage::IndexOwner(&self.index));
        visitor(CallableRosterStorage::Members(&self.index.members));
        visitor(CallableRosterStorage::Identities(&self.index.identities));
        visitor(CallableRosterStorage::SourceOrder(&self.index.source_order));
        visitor(CallableRosterStorage::Effective(&self.index.effective));
        visitor(CallableRosterStorage::Bindings(&self.index.bindings));
        visitor(CallableRosterStorage::Ready(&self.index.ready));
        visitor(CallableRosterStorage::Dependents(&self.index.dependents));
        visitor(CallableRosterStorage::Ordinals {
            len: self.index.ordinals.len(),
            capacity: self.index.ordinals.capacity(),
        });
    }
}
pub enum CallableRosterStorage<'a> {
    IndexOwner(&'a Arc<CallableIndexRecipe>),
    Members(&'a Vec<MemberId>),
    Identities(&'a Vec<ProcedureIdentity>),
    Ready(&'a Vec<usize>),
    SourceOrder(&'a Vec<usize>),
    Effective(&'a Vec<bool>),
    Bindings(&'a BTreeSet<dm_ir::SymRef>),
    Dependents(&'a Vec<Vec<usize>>),
    Ordinals { len: usize, capacity: usize },
}

#[cfg(test)]
#[path = "frontend_callable_roster_tests.rs"]
mod tests;
