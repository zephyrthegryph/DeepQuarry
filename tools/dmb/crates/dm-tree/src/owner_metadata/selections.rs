//! Name-qualified callable projections share the existing metadata store.
use super::*;
pub(super) type SelectionKey = (SymbolId, SymbolId, bool);
pub(super) fn key((owner, name, verb): SelectionKey) -> Arc<[u8]> {
    let mut bytes = b"callable-selection-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.extend_from_slice(&name.bits().to_le_bytes());
    bytes.push(u8::from(verb));
    bytes.into()
}
fn roster<M: std::ops::Index<usize, Output = MemberNode>>(
    tree: &SemanticTree,
    members: &M,
) -> BTreeMap<SymbolId, std::collections::BTreeSet<SymbolId>> {
    tree.types
        .iter()
        .map(|node| {
            let names = node
                .members
                .iter()
                .filter_map(|id| {
                    let member = &members[id.index()];
                    if member.kind != MemberKind::Var {
                        Some(member.name)
                    } else {
                        None
                    }
                })
                .collect();
            (node.path, names)
        })
        .collect()
}

pub(super) fn keys<M: std::ops::Index<usize, Output = MemberNode>>(
    tree: &SemanticTree,
    members: &M,
    order: &[MemberId],
) -> Vec<Arc<[u8]>> {
    order
        .iter()
        .filter_map(|id| {
            let member = &members[id.index()];
            (member.kind != MemberKind::Var)
                .then_some((tree.types[member.owner.index()].path, member.name))
        })
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .flat_map(|(owner, name)| [key((owner, name, false)), key((owner, name, true))])
        .collect()
}
struct Host<'a>(&'a Arc<CallableInputs>);
impl ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host<'_> {
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::CallableSelection(..) => {
                MetadataAnswer::CallableLocal(Arc::clone(self.0))
            }
            _ => unreachable!("selection receipt"),
        }
    }
}
impl RetainedMetadata {
    pub(crate) fn certify_selections(&self, tree: &SemanticTree) -> BTreeMap<SelectionKey, u128> {
        self.begin_selection_revision(tree);
        let mut certificates = BTreeMap::new();
        let names = roster(tree, &tree.members);
        for index in crate::metadata_update::dependency_order(tree.types.len(), |i| {
            tree.types[i].parent.map(|p| p.index())
        }) {
            let node = &tree.types[index];
            let parent = node.parent.map(|p| tree.types[p.index()].path);
            for &name in &names[&node.path] {
                for verb in [false, true] {
                    let selection = (node.path, name, verb);
                    let parent_certificate =
                        parent.and_then(|p| certificates.get(&(p, name, verb)).copied());
                    // A parent without a local same-name projection retains its
                    // conservative complete callable receipt, including inherited
                    // formal anchors and negative namespace decisions.
                    let parent_certificate = parent_certificate
                        .or_else(|| parent.and_then(|p| tree.owner_callables.get(&p).copied()));
                    if parent.is_some() && parent_certificate.is_none() {
                        continue;
                    }
                    let Some(inputs) = super::demanded_selections::inputs(
                        tree,
                        index,
                        name,
                        verb,
                        parent_certificate,
                    ) else {
                        continue;
                    };
                    let host = Host(&inputs);
                    if let Some(entry) = self.store.lookup(&key(selection), &host) {
                        if let Some((_, token)) = &entry.callable {
                            certificates.insert(selection, *token);
                            continue;
                        }
                    }
                    let Some(token) = super::callables::issue_token() else {
                        continue;
                    };
                    let ledger = ObservationLedger::default();
                    let query =
                        MetadataQuery::CallableSelection(selection.0, selection.1, selection.2);
                    ledger.record(query, host.answer(&query), query.domain(), None);
                    self.store.insert_with(
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
                            callable: Some((inputs, u128::from(token))),
                            variable: None,
                        },
                    );
                    certificates.insert(selection, u128::from(token));
                }
            }
        }
        certificates
    }
}
