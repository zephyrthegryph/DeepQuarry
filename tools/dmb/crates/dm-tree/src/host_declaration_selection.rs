//! Derived once from the same effective metadata used by the resolver.
use crate::*;
use std::collections::BTreeMap;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostDeclarationSelection {
    pub callable_names: Arc<[SymbolId]>,
    pub declared_variable_names: Arc<[SymbolId]>,
    pub scalar_requests: Arc<[constant_resolution::ScalarQuery]>,
}
pub(crate) type Selections = BTreeMap<SymbolId, Arc<HostDeclarationSelection>>;
pub(crate) fn select<M: crate::member_binding::MemberRead + ?Sized>(
    owner: SymbolId,
    members: &M,
    ids: impl IntoIterator<Item = MemberId>,
) -> Arc<HostDeclarationSelection> {
    let mut callable_names = Vec::new();
    let mut declared_variable_names = Vec::new();
    let mut scalar_requests = Vec::new();
    for id in ids {
        let member = members.member(id.index());
        match member.kind {
            MemberKind::Proc | MemberKind::Verb => callable_names.push(member.name),
            MemberKind::Var => {
                if member.definition == DefinitionMode::Declare {
                    declared_variable_names.push(member.name);
                }
                if member.metadata.flags & 2 != 0 {
                    scalar_requests.push(constant_resolution::ScalarQuery::Const {
                        owner,
                        name: member.name,
                    });
                }
            }
        }
    }
    Arc::new(HostDeclarationSelection {
        callable_names: callable_names.into(),
        declared_variable_names: declared_variable_names.into(),
        scalar_requests: scalar_requests.into(),
    })
}
pub(crate) fn collect<M: crate::member_binding::MemberRead + ?Sized>(
    tree: &SemanticTree,
    members: &M,
    ids: impl IntoIterator<Item = MemberId>,
) -> Selections {
    let mut owners = BTreeMap::<SymbolId, Vec<MemberId>>::new();
    for id in ids {
        owners
            .entry(tree.types[members.member(id.index()).owner.index()].path)
            .or_default()
            .push(id);
    }
    owners
        .into_iter()
        .map(|(owner, ids)| (owner, select(owner, members, ids)))
        .collect()
}
impl SemanticTree {
    /// Current symbolic owner roster. Contributions share the effective metadata
    /// artifact receipt; these selections carry no historical source coordinates.
    pub fn host_declaration_selections(
        &self,
    ) -> impl ExactSizeIterator<Item = (SymbolId, &Arc<HostDeclarationSelection>)>
           + DoubleEndedIterator
           + '_ {
        self.host_selections
            .iter()
            .map(|(&owner, value)| (owner, value))
    }
    pub fn host_declaration_selection_storage(
        &self,
    ) -> &Arc<BTreeMap<SymbolId, Arc<HostDeclarationSelection>>> {
        &self.host_selections
    }
    pub(crate) fn refresh_host_selections(&mut self, dirty: &[MemberId]) {
        let owners = dirty
            .iter()
            .map(|id| self.members.member(id.index()).owner)
            .collect::<std::collections::HashSet<_>>();
        if owners.is_empty() {
            return;
        }
        self.refresh_member_callable_names();
        let selections = Arc::make_mut(&mut self.host_selections);
        for owner in owners {
            let node = &self.types[owner.index()];
            selections.insert(
                node.path,
                select(node.path, &self.members, node.members.iter().copied()),
            );
        }
    }
}

#[cfg(test)]
#[path = "host_declaration_selection_tests.rs"]
mod tests;
