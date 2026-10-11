//! Complete source-neutral callable ABI inputs, issued from the current tree.
use crate::{DefinitionMode, MemberId, SemanticTree, TypeNode};
use dm_ir::{ProcedureIdentity, ProcedureMetadata, SymbolId};
use std::collections::BTreeMap;
use std::sync::Arc;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallableAbiEntry {
    pub member: MemberId,
    pub identity: ProcedureIdentity,
    pub metadata: Arc<ProcedureMetadata>,
    pub predecessor: Option<MemberId>,
}
/// Complete symbolic ABI inputs, separate from current arena bindings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallableAbiMeaning {
    pub identity: ProcedureIdentity,
    pub metadata: Arc<ProcedureMetadata>,
    pub definition: DefinitionMode,
    pub immediate_predecessor: Option<ProcedureIdentity>,
    pub predecessor: Option<ProcedureIdentity>,
}
#[derive(Debug, PartialEq, Eq)]
pub struct CallableAbiGraph {
    entries: Vec<CallableAbiMeaning>,
    ancestry: Vec<(SymbolId, Arc<[SymbolId]>)>,
}
impl CallableAbiGraph {
    pub fn entries(&self) -> &[CallableAbiMeaning] {
        &self.entries
    }
    pub fn visit_storage(
        &self,
        mut visit: impl FnMut(&Vec<CallableAbiMeaning>, &Vec<(SymbolId, Arc<[SymbolId]>)>),
    ) {
        visit(&self.entries, &self.ancestry);
    }
}
#[derive(Debug)]
pub struct CallableAbiRoster {
    entries: Vec<CallableAbiEntry>,
    types: Arc<[TypeNode]>,
    graph: Arc<CallableAbiGraph>,
}
impl PartialEq for CallableAbiRoster {
    fn eq(&self, other: &Self) -> bool {
        self.entries == other.entries
            && (Arc::ptr_eq(&self.graph, &other.graph) || self.graph == other.graph)
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
        let identity_for = |member: MemberId| -> Result<ProcedureIdentity, String> {
            let node = tree.member(member).ok_or("ABI predecessor member absent")?;
            let owner = tree
                .type_node(node.owner)
                .ok_or("ABI predecessor owner absent")?
                .path;
            Ok(ProcedureIdentity {
                owner,
                name: node.name,
                verb: node.kind == crate::MemberKind::Verb,
                occurrence: tree
                    .member_occurrence(member)
                    .ok_or("ABI predecessor occurrence absent")?,
            })
        };
        let mut entries = Vec::with_capacity(members.len());
        let mut meanings = Vec::with_capacity(members.len());
        let mut ancestry = BTreeMap::new();
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
            if !ancestry.contains_key(&identity.owner) {
                let paths = match tree.owner_ancestry.get(&identity.owner) {
                    Some(paths) => paths.clone(),
                    None => {
                        let mut paths = Vec::new();
                        let mut owner = Some(node.owner);
                        while let Some(id) = owner {
                            if paths.len() >= tree.types().len() {
                                return Err("ABI owner ancestry cycle".into());
                            }
                            let ty = tree.type_node(id).ok_or("ABI owner ancestry absent")?;
                            paths.push(ty.path);
                            owner = ty.parent;
                        }
                        Arc::from(paths)
                    }
                };
                ancestry.insert(identity.owner, paths);
            }
            meanings.push(CallableAbiMeaning {
                identity,
                definition: node.definition,
                metadata: node
                    .metadata
                    .procedure
                    .clone()
                    .ok_or("ABI metadata missing")?,
                immediate_predecessor: first.map(&identity_for).transpose()?,
                predecessor: formal.or(first).map(&identity_for).transpose()?,
            });
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
            graph: Arc::new(CallableAbiGraph {
                entries: meanings,
                ancestry: ancestry.into_iter().collect(),
            }),
        }))
    }
    pub fn graph(&self) -> &Arc<CallableAbiGraph> {
        &self.graph
    }
    pub fn entries(&self) -> &[CallableAbiEntry] {
        &self.entries
    }
    pub fn visit_storage(&self, mut visit: impl FnMut(&Vec<CallableAbiEntry>, &Arc<[TypeNode]>)) {
        visit(&self.entries, &self.types);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Text(&'static str);
    impl dm_preprocess::SourceProvider for Text {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    fn roster(source: &'static str) -> Arc<CallableAbiRoster> {
        let frontend = crate::frontend::build(
            std::path::Path::new("abi-graph.dme"),
            &Text(source),
            &Default::default(),
            1,
        )
        .unwrap();
        frontend.callable_abi_roster().unwrap().unwrap().clone()
    }
    #[test]
    fn symbolic_graph_survives_arena_shifts_but_tracks_selected_and_immediate_edges() {
        let first =
            roster("/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n");
        let changed = roster("/var/unrelated = 1\n/datum/unrelated\n/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n");
        assert_ne!(first.entries()[0].member, changed.entries()[0].member);
        assert_ne!(
            first, changed,
            "current binding equality must remain strict"
        );
        assert_eq!(first.graph(), changed.graph());
        let formal = roster("/datum/a/proc/p(x=1)\n    set invisibility = 9\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n");
        assert_ne!(first.graph(), formal.graph());
        let reparented = roster("/datum/b\n/datum/a\n    parent_type = /datum/b\n/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n");
        assert_ne!(
            first.graph(),
            reparented.graph(),
            "relevant owner ancestry is semantic input"
        );
        let interleaved = roster("/datum/a/proc/p(x=1)\n    return x\n/datum/a/mid/p(x=2)\n    return ..()\n/datum/a/mid/leaf/p(x=3)\n    return ..()\n");
        let graph = interleaved.graph().entries();
        assert_eq!(graph[2].immediate_predecessor, Some(graph[1].identity));
        assert_eq!(graph[2].predecessor, Some(graph[0].identity));
    }
}
