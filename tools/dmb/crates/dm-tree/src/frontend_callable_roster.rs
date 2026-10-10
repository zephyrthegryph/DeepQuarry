//! Source-neutral callable indexes issued beside the current body roster.
use super::BodyOccurrence;
use crate::{MemberId, MemberKind, SemanticTree};
use dm_ir::ProcedureIdentity;
use std::{
    collections::{BTreeSet, HashMap},
    sync::Arc,
};

#[derive(Debug)]
pub struct CallableRoster {
    tree: Arc<SemanticTree>,
    members: Vec<MemberId>,
    identities: Vec<ProcedureIdentity>,
    ordinals: HashMap<MemberId, usize>,
    dependents: Vec<Vec<usize>>,
    ready: Vec<usize>,
}
impl PartialEq for CallableRoster {
    fn eq(&self, other: &Self) -> bool {
        std::ptr::eq(self, other)
            || (Arc::ptr_eq(&self.tree, &other.tree) && self.members == other.members)
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
        Ok(Arc::new(Self {
            tree: Arc::clone(tree),
            members,
            identities,
            ordinals,
            dependents,
            ready,
        }))
    }
    pub(super) fn matches(&self, tree: &Arc<SemanticTree>, bodies: &[BodyOccurrence]) -> bool {
        self.authenticates_tree(tree)
            && self
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
        self.identities.get(ordinal).copied()
    }
    pub fn ordinal(&self, member: MemberId) -> Option<usize> {
        self.ordinals.get(&member).copied()
    }
    pub fn identity_for_member(&self, member: MemberId) -> Option<ProcedureIdentity> {
        self.identity(self.ordinal(member)?)
    }
    pub fn members(&self) -> &[MemberId] {
        &self.members
    }
    pub fn dependents(&self, ordinal: usize) -> &[usize] {
        self.dependents.get(ordinal).map_or(&[], Vec::as_slice)
    }
    pub fn ready(&self) -> &[usize] {
        &self.ready
    }
    pub fn visit_storage(&self, mut visitor: impl FnMut(CallableRosterStorage<'_>)) {
        visitor(CallableRosterStorage::Members(&self.members));
        visitor(CallableRosterStorage::Identities(&self.identities));
        visitor(CallableRosterStorage::Ready(&self.ready));
        visitor(CallableRosterStorage::Dependents(&self.dependents));
        visitor(CallableRosterStorage::Ordinals {
            len: self.ordinals.len(),
            capacity: self.ordinals.capacity(),
        });
    }
}
pub enum CallableRosterStorage<'a> {
    Members(&'a Vec<MemberId>),
    Identities(&'a Vec<ProcedureIdentity>),
    Ready(&'a Vec<usize>),
    Dependents(&'a Vec<Vec<usize>>),
    Ordinals { len: usize, capacity: usize },
}

#[cfg(test)]
#[path = "frontend_callable_roster_tests.rs"]
mod tests;
