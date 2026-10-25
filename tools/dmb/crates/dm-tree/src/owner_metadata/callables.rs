//! Owner-local callable facts, linked by exact parent certificates. No ancestor
//! member roster is copied into descendants.
use super::*;
use crate::token_digest::{self, TokenDigest};
type MemberKey = (SymbolId, SymbolId, bool, u32);
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallableFact {
    pub key: MemberKey,
    pub definition: DefinitionMode,
    pub content: u128,
    pub metadata: Arc<MemberMetadata>,
    pub previous: Option<MemberKey>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallableInputs {
    pub members: Arc<[CallableFact]>,
    pub intrinsic: Arc<[IntrinsicMember]>,
    pub parent: Option<SymbolId>,
    pub parent_certificate: Option<u128>,
    pub complete: bool,
    pub hierarchy_certified: bool,
}
impl CallableInputs {
    /// The token of this exact input state under the artifact `key`: parent token, local members (key, definition,
    /// content, metadata fingerprint, predecessor), engine intrinsics and both completeness gates. See `token_digest`.
    pub(super) fn token(&self, key: &[u8]) -> u128 {
        let mut digest = TokenDigest::new(b"owner-callable-token-v1");
        digest.bytes(key);
        digest.len(self.members.len());
        for fact in self.members.iter() {
            member_key(&mut digest, fact.key);
            digest
                .u8(token_digest::definition_byte(fact.definition))
                .u128(fact.content)
                .u128(crate::tree_identity::metadata_fingerprint(&fact.metadata))
                .bool(fact.previous.is_some());
            if let Some(previous) = fact.previous {
                member_key(&mut digest, previous);
            }
        }
        digest.len(self.intrinsic.len());
        for member in self.intrinsic.iter() {
            token_digest::intrinsic(&mut digest, member);
        }
        digest
            .opt_symbol(self.parent)
            .opt_u128(self.parent_certificate)
            .bool(self.complete)
            .bool(self.hierarchy_certified)
            .finish()
    }
}
fn member_key(digest: &mut TokenDigest, (owner, name, verb, occurrence): MemberKey) {
    digest.symbol(owner).symbol(name).bool(verb).u32(occurrence);
}
pub(super) fn key(owner: SymbolId) -> Arc<[u8]> {
    let mut bytes = b"owner-callable-certificate-v1".to_vec();
    bytes.extend_from_slice(&owner.bits().to_le_bytes());
    bytes.into()
}
struct Host<'a>(&'a BTreeMap<SymbolId, Arc<CallableInputs>>);
impl ObservationHost<MetadataQuery, MetadataAnswer, MetadataDomain> for Host<'_> {
    fn answer(&self, query: &MetadataQuery) -> MetadataAnswer {
        match query {
            MetadataQuery::CallableLocal(owner) => {
                MetadataAnswer::CallableLocal(Arc::clone(&self.0[owner]))
            }
            _ => unreachable!("callable certificates only record owner-local inputs"),
        }
    }
}
impl RetainedMetadata {
    pub(crate) fn certify_callables(&self, tree: &SemanticTree) -> BTreeMap<SymbolId, u128> {
        let mut counts = BTreeMap::<(SymbolId, SymbolId, bool), u32>::new();
        let mut member_keys = BTreeMap::new();
        for (index, member) in tree.members.iter().enumerate() {
            if member.kind == MemberKind::Var {
                continue;
            }
            let family = (
                tree.types[member.owner.index()].path,
                member.name,
                member.kind == MemberKind::Verb,
            );
            let occurrence = counts.entry(family).or_default();
            member_keys.insert(index, (family.0, family.1, family.2, *occurrence));
            let Some(next) = occurrence.checked_add(1) else {
                return BTreeMap::new();
            };
            *occurrence = next;
        }
        let mut certificates = BTreeMap::new();
        let mut inputs = BTreeMap::new();
        let order = crate::metadata_update::dependency_order(tree.types.len(), |index| {
            tree.types[index].parent.map(|id| id.index())
        });
        for index in order {
            let node = &tree.types[index];
            let parent = node.parent.map(|id| tree.types[id.index()].path);
            let parent_certificate = parent.and_then(|owner| certificates.get(&owner).copied());
            if parent.is_some() && parent_certificate.is_none() {
                continue;
            }
            let members = node
                .members
                .iter()
                .filter_map(|id| {
                    let member = &tree.members[id.index()];
                    (member.kind != MemberKind::Var).then(|| CallableFact {
                        key: member_keys[&id.index()],
                        definition: member.definition,
                        content: member.content,
                        metadata: Arc::clone(&member.metadata),
                        previous: member.previous.map(|id| member_keys[&id.index()]),
                    })
                })
                .collect::<Vec<_>>()
                .into();
            let intrinsic = tree
                .inventory
                .intrinsic
                .iter()
                .filter(|member| member.owner == node.path && member.kind != MemberKind::Var)
                .cloned()
                .collect::<Vec<_>>()
                .into();
            inputs.insert(
                node.path,
                Arc::new(CallableInputs {
                    members,
                    intrinsic,
                    parent,
                    parent_certificate,
                    complete: tree.inventory.complete,
                    hierarchy_certified: tree.inventory.hierarchy_certified,
                }),
            );
            let host = Host(&inputs);
            if let Some(value) = self.store.lookup(&key(node.path), &host) {
                if let Some(version) = value.callable_token() {
                    certificates.insert(node.path, version);
                    continue;
                }
            }
            let version = inputs[&node.path].token(&key(node.path));
            let query = MetadataQuery::CallableLocal(node.path);
            let ledger = ObservationLedger::default();
            ledger.record(query, host.answer(&query), query.domain(), None);
            self.store.insert_with(
                key(node.path),
                ledger.reads(),
                ledger.domain_receipts(),
                0,
                || EffectiveOwner::Callable {
                    inputs: Arc::clone(&inputs[&node.path]),
                    version,
                },
            );
            certificates.insert(node.path, version);
        }
        certificates
    }
}

#[cfg(test)]
#[path = "callable_tests.rs"]
mod tests;
