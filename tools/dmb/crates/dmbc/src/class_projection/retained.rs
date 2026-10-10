//! Owner-local symbolic payloads; current encounter placement never enters storage.
use super::{
    member_contribution::{self, MemberContribution},
    *,
};
use crate::lowering_memo::RecordingResolver;
use dm_ir::{ResolveQuery, Resolver};
use std::sync::atomic::{AtomicU64, Ordering};

pub struct ClassProjections {
    pub(crate) types: super::type_roster::TypeRoster,
    values: dm_session::ArtifactStore<Vec<MemberContribution>>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
}
impl Default for ClassProjections {
    fn default() -> Self {
        Self {
            types: Default::default(),
            values: dm_session::ArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        }
    }
}
struct Owner<'a> {
    key: Vec<u8>,
    hit: Option<Arc<Vec<MemberContribution>>>,
    produced: Vec<MemberContribution>,
    recorder: RecordingResolver<'a, dm_tree::SemanticTree>,
    next: usize,
}
pub(super) struct Request<'a> {
    store: &'a ClassProjections,
    owners: HashMap<SymbolId, Owner<'a>>,
}
fn source_bearing(value: &SemanticValue) -> bool {
    match value {
        SemanticValue::ModifiedInstance(_) => true,
        SemanticValue::List(entries) => entries
            .iter()
            .any(|(key, value)| key.as_ref().is_some_and(source_bearing) || source_bearing(value)),
        _ => false,
    }
}
fn default_bytes(value: &DefaultValue) -> Option<Vec<u8>> {
    let mut bytes = Vec::new();
    match value {
        DefaultValue::Transform(matrix) => {
            bytes.push(2);
            for bits in matrix {
                bytes.extend_from_slice(&bits.to_le_bytes());
            }
        }
        DefaultValue::Scalar(value) => {
            if source_bearing(value) {
                return None;
            }
            bytes.push(0);
            bytes.extend_from_slice(&value.canonical_bytes());
        }
        DefaultValue::InitializerExpression { token, canonical } => {
            bytes.push(1);
            bytes.extend_from_slice(&token.to_le_bytes());
            bytes.extend_from_slice(&(canonical.len() as u64).to_le_bytes());
            bytes.extend_from_slice(canonical);
        }
    }
    Some(bytes)
}
fn chunk(key: &mut Vec<u8>, bytes: &[u8]) {
    key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    key.extend_from_slice(bytes);
}
impl ClassProjections {
    pub(super) fn begin<'a>(
        &'a self,
        source: &'a TreeSnapshot,
        order: &[OccurrenceId],
        defaults: &HashMap<OccurrenceId, &DefaultValue>,
    ) -> Option<Request<'a>> {
        let tree = source.tree.as_ref();
        let keys = (|| {
            let mut keys: HashMap<SymbolId, Option<Vec<u8>>> = HashMap::new();
            // This scan issues no diagnostics or semantic queries: uncertain input
            // declines retention, leaving original encounter/error order to produce.
            for &id in order {
                let occurrence = source.occurrences.get(id)?;
                let Target::Member(member_id) = occurrence.target else {
                    continue;
                };
                let member = tree.member(member_id)?;
                let owner = tree.type_node(member.owner)?.path;
                let slot = keys.entry(owner).or_insert_with(|| {
                    let mut key = b"dmbc-owner-projection-v1-symbolic-token-roster\0".to_vec();
                    key.extend_from_slice(&owner.bits().to_le_bytes());
                    Some(key)
                });
                // A source-bearing default disqualifies only its own type. All
                // occurrences still pass current membership/default admission.
                let default = if member.kind == MemberKind::Var {
                    Some(default_bytes(defaults.get(&id)?))
                } else {
                    None
                };
                if matches!(default, Some(None)) {
                    *slot = None;
                }
                let Some(key) = slot.as_mut() else { continue };
                key.push(member.kind as u8);
                key.push(member.definition as u8);
                key.extend_from_slice(&member.name.bits().to_le_bytes());
                chunk(key, &member.metadata.canonical_bytes());
                if let Some(Some(default)) = default {
                    chunk(key, &default);
                }
            }
            Some(keys)
        })();
        let Some(keys) = keys else {
            self.values.retain_current_keys(std::iter::empty::<&[u8]>());
            self.declined.fetch_add(1, Ordering::Relaxed);
            return None;
        };
        self.values
            .retain_current_keys(keys.values().filter_map(|key| key.as_deref()));
        let owners = keys
            .into_iter()
            .filter_map(|(owner, key)| {
                let Some(key) = key else {
                    self.declined.fetch_add(1, Ordering::Relaxed);
                    return None;
                };
                let hit = self.values.lookup(&key, tree);
                if hit.is_some() {
                    self.hits.fetch_add(1, Ordering::Relaxed);
                }
                Some((
                    owner,
                    Owner {
                        key,
                        hit,
                        produced: Vec::new(),
                        recorder: RecordingResolver::new(tree),
                        next: 0,
                    },
                ))
            })
            .collect();
        Some(Request {
            store: self,
            owners,
        })
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(dm_session::ArtifactStorageView<'_, Vec<MemberContribution>>),
    ) {
        self.values.visit_storage(visitor);
    }
}
impl Request<'_> {
    pub(super) fn produce(
        &mut self,
        tree: &dm_tree::SemanticTree,
        member_id: dm_tree::MemberId,
        default: Option<&DefaultValue>,
        evaluator: &dyn CapturedFieldEvaluator,
    ) -> Result<MemberContribution, ProjectionError> {
        let member = tree
            .member(member_id)
            .ok_or(ProjectionError::MissingMember)?;
        let path = tree
            .type_node(member.owner)
            .ok_or(ProjectionError::MissingMember)?
            .path;
        let Some(owner) = self.owners.get_mut(&path) else {
            return member_contribution::produce(tree, member_id, default, true, evaluator);
        };
        let index = owner.next;
        owner.next += 1;
        if let Some(hit) = &owner.hit {
            if let Some(contribution) = hit.get(index) {
                return Ok(contribution.clone());
            }
            owner.hit = None;
            // No partial payload is admitted: an unexpected length falls back
            // for this member and declines remembering the incomplete owner.
        }
        owner.recorder.resolve(ResolveQuery::Ancestry(path));
        match member.kind {
            MemberKind::Var => {
                owner.recorder.resolve(ResolveQuery::VarStorage {
                    owner: path,
                    name: member.name,
                });
            }
            MemberKind::Proc | MemberKind::Verb => {
                owner.recorder.resolve(ResolveQuery::OverrideChain {
                    owner: path,
                    name: member.name,
                    verb: member.kind == MemberKind::Verb,
                });
            }
        }
        let contribution = member_contribution::produce(tree, member_id, default, true, evaluator)?;
        owner.produced.push(contribution.clone());
        Ok(contribution)
    }
    pub(super) fn finish(self) {
        for owner in self.owners.into_values() {
            if owner.hit.is_some() {
                continue;
            }
            if owner.produced.len() != owner.next {
                self.store.declined.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            let reads = owner.recorder.reads();
            let versions = owner.recorder.domain_receipts();
            let Some(weight) = crate::heap_census::resident_owner_projection_weight(
                &owner.produced,
                &owner.key,
                &reads,
                &versions,
            ) else {
                self.store.declined.fetch_add(1, Ordering::Relaxed);
                continue;
            };
            self.store.recomputed.fetch_add(1, Ordering::Relaxed);
            self.store
                .values
                .insert_with(owner.key.into(), reads, versions, weight, || owner.produced);
        }
    }
}
#[cfg(test)]
#[path = "retained_tests.rs"]
mod tests;
