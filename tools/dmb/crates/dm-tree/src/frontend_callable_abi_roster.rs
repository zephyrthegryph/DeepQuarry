//! Complete source-neutral callable ABI inputs, issued from the current tree.
use crate::{DefinitionMode, MemberId, SemanticTree, TypeNode};
use dm_ir::{ProcedureIdentity, ProcedureMetadata};
use std::sync::Arc;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallableAbiEntry {
    pub member: MemberId,
    pub identity: ProcedureIdentity,
    pub metadata: Arc<ProcedureMetadata>,
    pub predecessor: Option<MemberId>,
}
#[derive(Debug)]
pub struct CallableAbiRoster {
    entries: Vec<CallableAbiEntry>,
    types: Arc<[TypeNode]>,
}
impl PartialEq for CallableAbiRoster {
    fn eq(&self, other: &Self) -> bool {
        self.entries == other.entries
            && (Arc::ptr_eq(&self.types, &other.types)
                || (self.types.len() == other.types.len()
                    && self
                        .types
                        .iter()
                        .zip(other.types.iter())
                        .all(|(a, b)| a.path == b.path && a.parent == b.parent)))
    }
}
impl Eq for CallableAbiRoster {}
impl CallableAbiRoster {
    pub(super) fn issue(
        tree: &SemanticTree,
        members: &[MemberId],
        identities: &[ProcedureIdentity],
    ) -> Result<Arc<Self>, String> {
        if members.len() != identities.len() {
            return Err("ABI identity/member roster length differs".into());
        }
        let mut entries = Vec::with_capacity(members.len());
        for (&member, &identity) in members.iter().zip(identities) {
            let node = tree.member(member).ok_or("ABI member missing")?;
            let first = node.previous;
            let mut cursor = first;
            let mut formal = None;
            for _ in 0..tree.members().len() {
                let Some(id) = cursor else { break };
                let previous = tree.member(id).ok_or("ABI predecessor missing")?;
                if previous.definition == DefinitionMode::Declare {
                    formal = Some(id);
                    break;
                }
                cursor = previous.previous;
            }
            entries.push(CallableAbiEntry {
                member,
                identity,
                metadata: node
                    .metadata
                    .procedure
                    .clone()
                    .ok_or("ABI metadata missing")?,
                predecessor: formal.or(first),
            });
        }
        Ok(Arc::new(Self {
            entries,
            types: tree.shared_types(),
        }))
    }
    pub fn entries(&self) -> &[CallableAbiEntry] {
        &self.entries
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(&Vec<CallableAbiEntry>, &Arc<[TypeNode]>)) {
        visit(&self.entries, &self.types);
    }
}
