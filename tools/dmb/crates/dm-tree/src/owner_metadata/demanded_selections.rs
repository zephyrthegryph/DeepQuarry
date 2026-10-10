//! Current queried-name receipts in the existing owner artifact store.
//! Only queried ancestor paths are retained, never owner times inherited-name rosters.
use super::*;
use std::sync::{Mutex, Weak};

#[derive(Default, Debug)]
pub struct CallableDemands {
    tokens: Mutex<BTreeMap<selections::SelectionKey, u128>>,
}
impl CallableDemands {
    pub fn visit_storage(&self, visitor: impl FnOnce(usize, usize)) {
        let tokens = self
            .tokens
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        visitor(&*tokens as *const _ as usize, tokens.len());
    }
}
pub(super) type CurrentDemands = Mutex<Weak<CallableDemands>>;
const PREFIX: &[u8] = b"callable-demand-v1";
fn key((owner, name, verb): selections::SelectionKey) -> Arc<[u8]> {
    let mut bytes = PREFIX.to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.extend_from_slice(&name.bits().to_le_bytes());
    bytes.push(u8::from(verb));
    bytes.into()
}
fn member_key(tree: &SemanticTree, id: MemberId) -> Option<(SymbolId, SymbolId, bool, u32)> {
    let member = tree.member(id)?;
    let before = tree.types[member.owner.index()]
        .members
        .iter()
        .take_while(|&&other| other != id)
        .filter(|other| {
            let other = &tree.members[other.index()];
            other.kind == member.kind && other.name == member.name
        })
        .count();
    Some((
        tree.types[member.owner.index()].path,
        member.name,
        member.kind == MemberKind::Verb,
        u32::try_from(before).ok()?,
    ))
}
pub(super) fn inputs(
    tree: &SemanticTree,
    index: usize,
    name: SymbolId,
    verb: bool,
    parent_certificate: Option<u128>,
) -> Option<Arc<CallableInputs>> {
    let node = &tree.types[index];
    let kind = if verb {
        MemberKind::Verb
    } else {
        MemberKind::Proc
    };
    let members = node
        .members
        .iter()
        .filter(|id| {
            let member = &tree.members[id.index()];
            member.kind == kind && member.name == name
        })
        .map(|&id| {
            let member = &tree.members[id.index()];
            Some(CallableFact {
                key: member_key(tree, id)?,
                definition: member.definition,
                content: 0,
                metadata: Arc::clone(&member.metadata),
                previous: match member.previous {
                    Some(id) => Some(member_key(tree, id)?),
                    None => None,
                },
            })
        })
        .collect::<Option<Vec<_>>>()?;
    Some(Arc::new(CallableInputs {
        members: members.into(),
        intrinsic: tree
            .inventory
            .intrinsic
            .iter()
            .filter(|member| {
                member.owner == node.path && member.name == name && member.kind == kind
            })
            .cloned()
            .collect::<Vec<_>>()
            .into(),
        parent: node.parent.map(|parent| tree.types[parent.index()].path),
        parent_certificate,
        complete: tree.inventory.complete,
        hierarchy_certified: tree.inventory.hierarchy_certified,
    }))
}
struct Host<'a>(&'a Arc<CallableInputs>);
impl ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host<'_> {
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::CallableSelection(..) => {
                MetadataAnswer::CallableLocal(Arc::clone(self.0))
            }
            _ => unreachable!("name-specific callable receipt"),
        }
    }
}
impl RetainedMetadata {
    pub(super) fn demanded_keys(&self, tree: &SemanticTree) -> Vec<Arc<[u8]>> {
        let current = self
            .current_demands
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        current.upgrade().map_or_else(Vec::new, |current| {
            current
                .tokens
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .keys()
                .filter(|selection| tree.lookup_type(selection.0).is_some())
                .copied()
                .map(key)
                .collect()
        })
    }
    pub(super) fn begin_selection_revision(&self, tree: &SemanticTree) {
        let mut current = self
            .current_demands
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let retained = current.upgrade().map_or_else(Vec::new, |current| {
            current
                .tokens
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .keys()
                .copied()
                .collect::<Vec<_>>()
        });
        let mut keys = Vec::new();
        self.store.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { key: existing, .. } = view {
                if !existing.starts_with(PREFIX) {
                    keys.push(Arc::clone(existing));
                }
            }
        });
        keys.extend(
            retained
                .iter()
                .filter(|selection| tree.lookup_type(selection.0).is_some())
                .copied()
                .map(key),
        );
        self.store
            .retain_current_keys(keys.iter().map(AsRef::as_ref));
        *current = Arc::downgrade(&tree.owner_callable_demands);
    }
    pub(crate) fn demanded_selection(
        &self,
        tree: &SemanticTree,
        selection: selections::SelectionKey,
    ) -> Option<u128> {
        if let Some(token) = tree
            .owner_callable_demands
            .tokens
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .get(&selection)
            .copied()
        {
            return Some(token);
        }
        // Seal the current issuer while the iterative parent chain is admitted.
        // Old snapshots may read their existing receipts but cannot alter the store.
        let current = self
            .current_demands
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if !current
            .upgrade()
            .is_some_and(|current| Arc::ptr_eq(&current, &tree.owner_callable_demands))
        {
            return None;
        }
        let mut index = tree.lookup_type(selection.0)?;
        let mut chain = Vec::new();
        loop {
            // At most one visit per type is possible in an acyclic parent chain.
            // Erroring/custom trees must decline rather than loop or index panic.
            if chain.len() >= tree.types.len() {
                return None;
            }
            let node = tree.types.get(index.index())?;
            chain.push(index);
            match node.parent {
                Some(parent) => index = parent,
                None => break,
            }
        }
        let mut parent_certificate = None;
        for index in chain.into_iter().rev() {
            let node = &tree.types[index.index()];
            let selection = (node.path, selection.1, selection.2);
            let cached = tree
                .owner_callable_demands
                .tokens
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .get(&selection)
                .copied();
            let token = if let Some(cached) = cached {
                cached
            } else {
                let inputs = inputs(
                    tree,
                    index.index(),
                    selection.1,
                    selection.2,
                    parent_certificate,
                )?;
                let host = Host(&inputs);
                let existing = self
                    .store
                    .lookup(&key(selection), &host)
                    .and_then(|entry| entry.callable.as_ref().map(|(_, token)| *token));
                let token = if let Some(token) = existing {
                    token
                } else {
                    let token = u128::from(callables::issue_token()?);
                    let query =
                        MetadataQuery::CallableSelection(selection.0, selection.1, selection.2);
                    let ledger = ObservationLedger::default();
                    ledger.record(query, host.answer(&query), query.domain(), None);
                    let owner = self.store.insert_with_owned(
                        key(selection),
                        ledger.reads(),
                        ledger.domain_receipts(),
                        0,
                        || EffectiveOwner {
                            selection: Arc::new(crate::HostDeclarationSelection {
                                callable_names: Arc::from([]),
                                declared_variable_names: Arc::from([]),
                                scalar_requests: Arc::from([]),
                            }),
                            values: Arc::from([]),
                            hierarchy: None,
                            callable: Some((inputs, token)),
                            variable: None,
                        },
                    )?;
                    owner.callable.as_ref()?.1
                };
                tree.owner_callable_demands
                    .tokens
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .insert(selection, token);
                token
            };
            parent_certificate = Some(token);
        }
        parent_certificate
    }
}

#[cfg(test)]
#[path = "demanded_selection_tests.rs"]
mod tests;
