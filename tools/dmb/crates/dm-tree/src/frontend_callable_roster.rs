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
        let abi = CallableAbiRoster::issue(tree, &members, &identities).ok();
        Ok(Arc::new(Self {
            tree: Arc::clone(tree),
            index: Arc::new(CallableIndexRecipe {
                members,
                identities,
                ordinals,
                dependents,
                ready,
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
    pub(super) fn matches(&self, tree: &Arc<SemanticTree>, bodies: &[BodyOccurrence]) -> bool {
        self.authenticates_tree(tree)
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
    Dependents(&'a Vec<Vec<usize>>),
    Ordinals { len: usize, capacity: usize },
}

#[cfg(test)]
#[path = "frontend_callable_roster_tests.rs"]
mod tests;
