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
    values: Arc<dm_session::ArtifactStore<OwnerProjection>>,
    publication: Arc<dm_session::ArtifactPublication<ProjectionLeases>>,
    pub(super) attempt: Arc<dm_session::ArtifactAttempt<ProjectionLeases>>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
    /// The session's query database: owner receipts are proven by its answer table and record no domain versions.
    answers: Option<Arc<crate::query_db::QueryDb>>,
}
pub(super) type ProjectionAttempt = dm_session::ArtifactAttempt<ProjectionLeases>;
pub(super) struct ProjectionLeases {
    values: dm_session::ObservedArtifactLease<
        OwnerProjection,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
    >,
    pub(super) types: super::type_roster::TypeLease,
    methods: std::sync::Mutex<Option<Arc<super::method_roster::MethodRoster>>>,
}
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct MemberInput {
    pub kind: MemberKind,
    pub definition: dm_tree::DefinitionMode,
    pub name: SymbolId,
    pub metadata: Arc<dm_ir::DeclarationMeaning>,
    pub default: Option<DefaultValue>,
}
// Current inputs are borrowed until reuse is decided. In particular, unchanged
// list/string defaults are never copied just to compare against their owner.
struct CurrentMemberInput<'a> {
    member: &'a dm_tree::MemberNode,
    default: Option<&'a DefaultValue>,
}
impl CurrentMemberInput<'_> {
    fn matches(&self, previous: &MemberInput) -> bool {
        previous.kind == self.member.kind
            && previous.definition == self.member.definition
            && previous.name == self.member.name
            && (Arc::ptr_eq(&previous.metadata, &self.member.metadata)
                || previous.metadata == self.member.metadata)
            && previous.default.as_ref() == self.default
    }
    fn into_owned(self) -> MemberInput {
        MemberInput {
            kind: self.member.kind,
            definition: self.member.definition,
            name: self.member.name,
            metadata: Arc::clone(&self.member.metadata),
            default: self.default.cloned(),
        }
    }
}
pub(crate) struct OwnerProjection {
    pub inputs: Vec<MemberInput>,
    pub values: Vec<MemberContribution>,
}
impl Default for ClassProjections {
    fn default() -> Self {
        let types = super::type_roster::TypeRoster::default();
        let values = crate::shared_store::artifact_core("class_projection.owners", None);
        let publication = Arc::new(dm_session::ArtifactPublication::default());
        let attempt = Arc::new(publication.begin(ProjectionLeases {
            values: values.lease(),
            types: types.lease(),
            methods: Default::default(),
        }));
        Self {
            types: types.for_attempt(Arc::clone(&attempt)),
            values,
            publication,
            attempt,
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
            answers: None,
        }
    }
}
struct Owner<'a> {
    key: Vec<u8>,
    hit: Option<Arc<OwnerProjection>>,
    inputs: Vec<MemberInput>,
    produced: Vec<MemberContribution>,
    rejected_local_input: bool,
    recorder: RecordingResolver<'a, dm_tree::SemanticTree>,
    next: usize,
    /// This owner's members in source order with the default `produce` is given, for [`Request::prefetch`].
    pending: Vec<(dm_tree::MemberId, Option<&'a DefaultValue>)>,
    /// Contributions computed ahead by [`Request::prefetch`], consumed in order by `produce`.
    prefetched: std::collections::VecDeque<Result<MemberContribution, ProjectionError>>,
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
pub(super) struct MethodRequest<'a> {
    store: &'a ClassProjections,
    previous: Option<Arc<super::method_roster::MethodRoster>>,
    replacement: Option<Vec<super::method_roster::MethodInput>>,
    next: usize,
}
impl MethodRequest<'_> {
    pub(super) fn push(&mut self, input: super::method_roster::MethodInput) {
        if self.replacement.is_none()
            && self.previous.as_ref().and_then(|old| old.input(self.next)) != Some(&input)
        {
            self.replacement = Some(
                self.previous
                    .as_ref()
                    .map(|old| old.input_prefix(self.next))
                    .unwrap_or_default(),
            );
        }
        if let Some(inputs) = self.replacement.as_mut() {
            inputs.push(input);
        }
        self.next += 1;
    }
    pub(super) fn finish(self) -> Arc<super::method_roster::MethodRoster> {
        let roster = match (self.previous, self.replacement) {
            (Some(previous), None) if previous.len() == self.next => previous,
            (Some(previous), None) => Arc::new(super::method_roster::MethodRoster::produce(
                previous.input_prefix(self.next),
            )),
            (_, Some(inputs)) => Arc::new(super::method_roster::MethodRoster::produce(inputs)),
            (None, None) => Arc::new(super::method_roster::MethodRoster::produce(Vec::new())),
        };
        self.store.attempt.with_pending(|leases| {
            *leases.methods.lock().unwrap_or_else(|e| e.into_inner()) = Some(roster.clone());
        });
        roster
    }
}
impl ClassProjections {
    /// Borrow the retained owner as a request-scoped pending group. Analysis
    /// can admit values but cannot supersede or publish a build's successful group.
    pub fn with_request(&self, publishable: bool) -> Self {
        let leases = ProjectionLeases {
            values: self.values.lease(),
            types: self.types.lease(),
            methods: Default::default(),
        };
        let attempt = Arc::new(if publishable {
            self.publication.begin(leases)
        } else {
            self.publication.begin_ephemeral(leases)
        });
        Self {
            types: self.types.for_attempt(Arc::clone(&attempt)),
            values: Arc::clone(&self.values),
            publication: Arc::clone(&self.publication),
            attempt,
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
            answers: self.answers.clone(),
        }
    }
    /// Prove owner receipts by `db`'s answer table instead of domain versions (a session with a query database).
    pub(crate) fn with_answers(mut self, db: Option<Arc<crate::query_db::QueryDb>>) -> Self {
        self.answers = db;
        self
    }
    pub fn publish_successful(&self) -> bool {
        self.attempt.publish_successful()
    }
    fn method_candidate(&self) -> Option<Arc<super::method_roster::MethodRoster>> {
        self.attempt
            .with_pending(|leases| {
                leases
                    .methods
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .clone()
            })
            .flatten()
            .or_else(|| {
                self.publication
                    .with_published(|leases| {
                        leases
                            .methods
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .clone()
                    })
                    .flatten()
            })
    }
    pub(super) fn begin_methods(&self) -> MethodRequest<'_> {
        MethodRequest {
            store: self,
            replacement: None,
            next: 0,
            previous: self.method_candidate(),
        }
    }
    pub(crate) fn census_methods(&self, census: &mut crate::heap_census::HeapCensus) {
        let mut inspect = |leases: &ProjectionLeases| {
            if let Some(roster) = leases
                .methods
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .as_ref()
            {
                if census.arc_object("retained.class_projection.method_roster", roster) {
                    roster.census(census);
                }
            }
        };
        self.attempt.with_pending(&mut inspect);
        self.publication.with_published(&mut inspect);
    }

    pub(super) fn begin<'a>(
        &'a self,
        source: &'a TreeSnapshot,
        order: &[OccurrenceId],
        defaults: &HashMap<OccurrenceId, &'a DefaultValue>,
    ) -> Option<Request<'a>> {
        let tree = source.tree.as_ref();
        let keys = (|| {
            #[allow(clippy::type_complexity)]
            let mut keys: HashMap<
                SymbolId,
                Option<(
                    Vec<u8>,
                    Vec<CurrentMemberInput<'_>>,
                    Vec<(dm_tree::MemberId, Option<&'a DefaultValue>)>,
                )>,
            > = HashMap::new();
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
                    let mut key = b"dmbc-owner-projection-v2-exact-input-roster\0".to_vec();
                    key.extend_from_slice(&owner.bits().to_le_bytes());
                    Some((key, Vec::new(), Vec::new()))
                });
                // A source-bearing default disqualifies only its own type. All
                // occurrences still pass current membership/default admission.
                let default = if member.kind == MemberKind::Var {
                    Some(*defaults.get(&id)?)
                } else {
                    None
                };
                if matches!(default, Some(DefaultValue::Scalar(value)) if source_bearing(value)) {
                    *slot = None;
                }
                let Some((_, inputs, pending)) = slot.as_mut() else {
                    continue;
                };
                inputs.push(CurrentMemberInput { member, default });
                pending.push((member_id, defaults.get(&id).copied()));
            }
            Some(keys)
        })();
        let Some(keys) = keys else {
            self.declined.fetch_add(1, Ordering::Relaxed);
            return None;
        };
        // With a query database, a stored owner's reads are proven by the session's answer table (one answer per query,
        // shared with every stage of the request; `DMB_QUERY_VERIFY=1` checks the tree gives the same answers) and its
        // receipts carry no domain versions. Without one, the tree's domain versions certify them as before.
        let answer = |query: &ResolveQuery| Resolver::resolve(tree, *query);
        let answers = self
            .answers
            .as_deref()
            .filter(|db| db.answers_bound_to(tree))
            .map(|db| db.request_answers(&answer));
        let admission = dm_session::ReceiptAdmission::with_oracle(
            tree,
            answers.as_ref().map(|answers| {
                answers as &dyn dm_session::AnswerOracle<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning>
            }),
        );
        // Owners are independent: compare each with its retained projection in parallel (43k owners).
        use rayon::prelude::*;
        let keys: Vec<_> = keys.into_iter().collect();
        let owners =
            keys.into_par_iter()
                .filter_map(|(owner, key)| {
                    let Some((key, inputs, pending)) = key else {
                        self.declined.fetch_add(1, Ordering::Relaxed);
                        return None;
                    };
                    let mut rejected_local_input = false;
                    let hit =
                        self.attempt
                            .with_pending(|leases| {
                                leases
                                    .values
                                    .visit_receipted_with(
                                        &key,
                                        &mut |reads, _| {
                                            admission.first_changed_receipted(reads, |_| {})
                                        },
                                        &mut |value| {
                                        let matches = value.inputs.len() == inputs.len()
                                            && value.values.len() == value.inputs.len()
                                            && inputs.iter().zip(&value.inputs).all(
                                                |(current, previous)| current.matches(previous),
                                            );
                                        rejected_local_input |= !matches;
                                        matches
                                    },
                                    )
                                    .0
                                    .map(|accepted| accepted.value)
                            })
                            .flatten();
                    if hit.is_some() {
                        self.hits.fetch_add(1, Ordering::Relaxed);
                    }
                    let inputs = if hit.is_some() {
                        Vec::new()
                    } else {
                        inputs
                            .into_iter()
                            .map(CurrentMemberInput::into_owned)
                            .collect()
                    };
                    let pending = if hit.is_some() { Vec::new() } else { pending };
                    Some((
                        owner,
                        Owner {
                            key,
                            hit,
                            inputs,
                            produced: Vec::new(),
                            rejected_local_input,
                            recorder: RecordingResolver::new(tree),
                            next: 0,
                            pending,
                            prefetched: Default::default(),
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
        visitor: impl FnMut(dm_session::ArtifactStorageView<'_, OwnerProjection>),
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
        if let Some(prefetched) = owner.prefetched.pop_front() {
            let contribution = prefetched?;
            owner.produced.push(contribution.clone());
            return Ok(contribution);
        }
        if let Some(hit) = &owner.hit {
            if let Some(contribution) = hit.values.get(index) {
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
    /// Compute every missed owner's contributions in parallel, each owner's members in source order with
    /// the same reads `produce` records, so the source-ordered pass only places them. A fresh session or
    /// a cold compile misses every owner (300k members); a hot one misses only changed owners.
    pub(super) fn prefetch(
        &mut self,
        tree: &dm_tree::SemanticTree,
        evaluator: &(dyn CapturedFieldEvaluator + Sync),
    ) {
        use rayon::prelude::*;
        self.owners.par_iter_mut().for_each(|(path, owner)| {
            if owner.hit.is_some() || owner.next != 0 {
                return;
            }
            let path = *path;
            for (member_id, default) in std::mem::take(&mut owner.pending) {
                let Some(member) = tree.member(member_id) else {
                    owner.prefetched.push_back(Err(ProjectionError::MissingMember));
                    break;
                };
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
                let contribution =
                    member_contribution::produce(tree, member_id, default, true, evaluator);
                let failed = contribution.is_err();
                owner.prefetched.push_back(contribution);
                if failed {
                    break;
                }
            }
        });
    }
    pub(super) fn finish(self) {
        for owner in self.owners.into_values() {
            if owner.hit.is_some() {
                continue;
            }
            if owner.produced.len() != owner.next || owner.next != owner.inputs.len() {
                self.store.declined.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            let reads = owner.recorder.reads();
            let versions = Vec::new();
            let Some(weight) = crate::heap_census::resident_owner_projection_weight(
                &owner.produced,
                &owner.inputs,
                &owner.key,
                &reads,
                &versions,
            ) else {
                self.store.declined.fetch_add(1, Ordering::Relaxed);
                continue;
            };
            self.store.recomputed.fetch_add(1, Ordering::Relaxed);
            self.store.attempt.with_pending(|leases| {
                if owner.rejected_local_input {
                    // Locator and semantic reads do not contain local defaults
                    // or metadata. Preserve the actual fresh owner after this
                    // rejection; equal ledgers cannot re-admit its old payload.
                    return leases.values.insert_fresh_with_qualified_receipt(
                        owner.key.into(),
                        reads.into(),
                        versions.into(),
                        weight,
                        || OwnerProjection {
                            inputs: owner.inputs,
                            values: owner.produced,
                        },
                    )
                    .is_some();
                }
                leases
                    .values
                    .insert_with(owner.key.into(), reads, versions, weight, || {
                        OwnerProjection {
                            inputs: owner.inputs,
                            values: owner.produced,
                        }
                    })
            });
        }
    }
}
#[cfg(test)]
#[path = "retained_tests.rs"]
mod tests;
