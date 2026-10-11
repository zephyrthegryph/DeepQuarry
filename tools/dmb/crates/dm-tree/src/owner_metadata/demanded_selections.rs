//! Current queried-name receipts in the existing owner artifact store.
//! Proc, verb, and variable names share one demand lifecycle and issuer.
//! Only queried ancestor paths are retained, never owner times inherited-name rosters.
use super::*;
use std::sync::{Mutex, Weak};

#[derive(Default, Debug)]
pub struct CallableDemands {
    tokens: Mutex<BTreeMap<(SymbolId, SymbolId, u8), u128>>,
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
const PREFIX: &[u8] = b"member-name-demand-v2";
fn key((owner, name, namespace): (SymbolId, SymbolId, u8)) -> Arc<[u8]> {
    let mut bytes = PREFIX.to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.extend_from_slice(&name.bits().to_le_bytes());
    bytes.push(namespace);
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
    verb: Option<bool>,
    parent_certificate: Option<u128>,
) -> Option<Arc<CallableInputs>> {
    let node = &tree.types[index];
    let matches_kind = |kind| match verb {
        Some(true) => kind == MemberKind::Verb,
        Some(false) => kind == MemberKind::Proc,
        None => matches!(kind, MemberKind::Proc | MemberKind::Verb),
    };
    let members = node
        .members
        .iter()
        .filter(|id| {
            let member = &tree.members[id.index()];
            matches_kind(member.kind) && member.name == name
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
                member.owner == node.path && member.name == name && matches_kind(member.kind)
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
struct Host(MetadataAnswer);
impl ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host {
    fn answer(&self, _: &MetadataQuery) -> MetadataAnswer {
        self.0.clone()
    }
}
impl RetainedMetadata {
    pub(crate) fn demanded_member_name(&self, tree: &SemanticTree, name: SymbolId) -> Option<u128> {
        // An incomplete snapshot sharing this demand owner cannot borrow a
        // negative token issued only after a complete hierarchy admission.
        let answer = tree.source_member_callable_name(name)?;
        let selection = (SymbolId::of("/"), name, 4);
        if let Some(token) = tree
            .owner_callable_demands
            .tokens
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&selection)
            .copied()
        {
            return Some(token);
        }
        let current = self
            .current_demands
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if !current
            .upgrade()
            .is_some_and(|owner| Arc::ptr_eq(&owner, &tree.owner_callable_demands))
        {
            return None;
        }
        let query = MetadataQuery::MemberName(name);
        let host = Host(MetadataAnswer::MemberName(answer));
        let token_of = |value: &EffectiveOwner| match value {
            EffectiveOwner::MemberName { version } => Some(*version),
            _ => None,
        };
        let token = if let Some(token) = self
            .store
            .lookup(&key(selection), &host)
            .and_then(|v| token_of(&v))
        {
            token
        } else {
            let token = u128::from(callables::issue_token()?);
            let ledger = ObservationLedger::default();
            ledger.record(query, host.answer(&query), query.domain(), None);
            let owner = self.store.insert_with_owned(
                key(selection),
                ledger.reads(),
                ledger.domain_receipts(),
                0,
                || EffectiveOwner::MemberName { version: token },
            )?;
            token_of(&owner)?
        };
        tree.owner_callable_demands
            .tokens
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(selection, token);
        Some(token)
    }
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
        // Deferral belongs to this provisional tree, never shared issuer state:
        // another worktree can publish its own admitted owner independently.
        if tree.selection_publication_deferred {
            return;
        }
        let mut current = self
            .current_demands
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if current
            .upgrade()
            .is_some_and(|current| Arc::ptr_eq(&current, &tree.owner_callable_demands))
        {
            return;
        }
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
    pub(crate) fn bind_selection_owner(&self, tree: &SemanticTree) {
        self.begin_selection_revision(tree);
    }
    pub(crate) fn demanded_selection(
        &self,
        tree: &SemanticTree,
        selection: selections::SelectionKey,
    ) -> Option<u128> {
        self.demanded_name(tree, (selection.0, selection.1, u8::from(selection.2)))
    }
    pub(crate) fn demanded_variable(
        &self,
        tree: &SemanticTree,
        owner: SymbolId,
        name: SymbolId,
    ) -> Option<u128> {
        self.demanded_name(tree, (owner, name, 2))
    }
    pub(crate) fn demanded_presence(
        &self,
        tree: &SemanticTree,
        owner: SymbolId,
        name: SymbolId,
    ) -> Option<u128> {
        self.demanded_name(tree, (owner, name, 3))
    }
    fn demanded_name(
        &self,
        tree: &SemanticTree,
        selection: (SymbolId, SymbolId, u8),
    ) -> Option<u128> {
        if tree.selection_publication_deferred {
            return None;
        }
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
                let (query, answer) = if selection.2 == 2 {
                    (
                        MetadataQuery::VariableLocal(selection.0, selection.1),
                        MetadataAnswer::VariableLocal(variables::local_inputs(
                            tree,
                            index.index(),
                            selection.1,
                            parent_certificate,
                        )?),
                    )
                } else {
                    (
                        if selection.2 == 3 {
                            MetadataQuery::CallablePresence(selection.0, selection.1)
                        } else {
                            MetadataQuery::CallableSelection(
                                selection.0,
                                selection.1,
                                selection.2 == 1,
                            )
                        },
                        MetadataAnswer::CallableLocal(inputs(
                            tree,
                            index.index(),
                            selection.1,
                            if selection.2 == 3 {
                                None
                            } else {
                                Some(selection.2 == 1)
                            },
                            parent_certificate,
                        )?),
                    )
                };
                let host = Host(answer);
                let token_of = |entry: &EffectiveOwner| {
                    if selection.2 == 2 {
                        entry.variable_token()
                    } else {
                        entry.callable_token()
                    }
                };
                let existing = self
                    .store
                    .lookup(&key(selection), &host)
                    .and_then(|entry| token_of(&entry));
                let token = if let Some(token) = existing {
                    token
                } else {
                    let token = u128::from(callables::issue_token()?);
                    let ledger = ObservationLedger::default();
                    ledger.record(query, host.answer(&query), query.domain(), None);
                    let owner = self.store.insert_with_owned(
                        key(selection),
                        ledger.reads(),
                        ledger.domain_receipts(),
                        0,
                        || match host.0 {
                            MetadataAnswer::CallableLocal(inputs) => EffectiveOwner::Callable {
                                inputs,
                                version: token,
                            },
                            MetadataAnswer::VariableLocal(inputs) => EffectiveOwner::Variable {
                                inputs,
                                version: token,
                            },
                            _ => unreachable!("name-specific receipt"),
                        },
                    )?;
                    token_of(&owner)?
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
