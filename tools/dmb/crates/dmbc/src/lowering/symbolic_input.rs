//! Trusted completion handoff; symbolic reuse never reuses output certificates.
use super::*;
use crate::lowering_memo::ResolverRead;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};
#[path = "receipt_groups.rs"]
mod receipt_groups;
#[path = "symbolic_retention.rs"]
mod retained;
pub(super) use receipt_groups::RequestAdmission;
pub use retained::SymbolicRetentionStats;
#[path = "symbolic_partial_admission.rs"]
mod partial_admission;
#[path = "symbolic_candidates.rs"]
mod candidates;
#[path = "symbolic_publication.rs"]
mod symbolic_publication;
pub(super) use candidates::RequestCandidates;

#[derive(Default)]
pub(crate) struct SessionSymbolicMemo {
    records: Mutex<BTreeMap<UnitIdentity, Arc<Record>>>,
    publication: Option<Arc<symbolic_publication::Owner>>,
    attempt: Option<dm_session::ArtifactAttempt<symbolic_publication::Leases>>,
    shared_code: Option<crate::symbolic::shared_procedure_code::Lease>,
    shared_code_pool: Option<Arc<crate::symbolic::shared_procedure_code::SharedProcedureCode>>,
    admitted: Arc<AtomicU64>,
    reused: Arc<AtomicU64>,
    pruned: Arc<AtomicU64>,
    declines: Arc<DeclineCounters>,
    receipt_groups: Arc<receipt_groups::ProcedureGroups>,
}
#[derive(Default)]
struct DeclineCounters {
    source_identity: AtomicU64,
    record_absent: AtomicU64,
    key_changed: AtomicU64,
    read_changed: AtomicU64,
    debug_rebase: AtomicU64,
    modified_reissue: AtomicU64,
    contribution_rebind: AtomicU64,
    capture_excluded: AtomicU64,
    nonreusable_completion: AtomicU64,
}
#[path = "symbolic_local.rs"]
mod local;

pub(super) fn local_certificate(
    roster: &LocalInputRoster<'_>,
    row: &PreparedBody<'_>,
    policy: u128,
) -> Option<local::Certificate> {
    local::Certificate::issue(roster, row, policy)
}

struct Record {
    local: Option<local::Certificate>,
    recipe: Option<crate::lowering_memo::key_recipe::KeyRecipe>,
    key: Arc<[u8]>,
    reads: dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
    versions: Arc<[(dm_ir::ReadDomain, u128)]>,
    value: RecordValue,
    relative_debug: Vec<crate::debug_sources::RelativeDebugAnchor>,
    required_types: Arc<[dm_ir::SymbolId]>,
    modified_recipes: Arc<[crate::modified_initializers::SourceRecipe]>,
}
enum RecordValue {
    Executable(Arc<crate::symbolic::ReusableProcedureArtifact>),
    Selections {
        facts: Arc<dm_ir::SelectedReferences>,
        abi: Vec<u8>,
    },
}
pub(crate) struct Admission {
    previous: Option<Arc<Record>>,
    local: Option<local::Certificate>,
    metadata: Option<Arc<dm_ir::ProcedureMetadata>>,
    store: Option<Arc<SessionSymbolicMemo>>,
    disk: Option<crate::lowering_memo::DiskWriter>,
    key: Arc<[u8]>,
    reads: dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
    versions: Arc<[(dm_ir::ReadDomain, u128)]>,
    relative_debug: Vec<crate::debug_sources::RelativeDebugAnchor>,
}
impl Admission {
    pub(super) fn with_local(mut self, local: Option<local::Certificate>) -> Self {
        self.local = local.map(|certificate| certificate.bind_key(&self.key));
        self
    }
    pub(super) fn with_metadata(mut self, metadata: Arc<dm_ir::ProcedureMetadata>) -> Self {
        self.metadata = Some(metadata);
        self
    }
    pub(super) fn shared_key(&self) -> Arc<[u8]> {
        Arc::clone(&self.key)
    }
}
/// Fields are private: only the ordinary lowerer or exact memo validator issues it.
pub struct CompletedInput {
    inner: Input,
    admission: Option<Admission>,
    verification_reads: Option<Vec<(dm_ir::ResolveQuery, Vec<u8>)>>,
}
enum Input {
    Selections(
        UnitIdentity,
        bool,
        BodyOccurrence,
        Arc<dm_ir::SelectedReferences>,
    ),
    Lowered(Box<LoweredUnit>),
    Reused(crate::symbolic::PreparedContribution),
}
/// Immutable compiler-selected facts. Construction stays in the admitted lowerer.
/// Coordinates remain relative; a query binds them against its current occurrence.
pub struct ProcedureSelections {
    identity: UnitIdentity,
    source: dm_tree::frontend::SourceLocation,
    facts: Option<Arc<dm_ir::SelectedReferences>>,
}
impl ProcedureSelections {
    pub fn source(&self) -> &dm_tree::frontend::SourceLocation {
        &self.source
    }

    pub fn identity(&self) -> UnitIdentity {
        self.identity
    }
    pub fn facts(&self) -> Option<&dm_ir::SelectedReferences> {
        self.facts.as_deref()
    }
}
impl CompletedInput {
    pub(super) fn refresh_local_admission(
        &mut self,
        store: &Arc<SessionSymbolicMemo>,
        certificate: Option<local::Certificate>,
    ) {
        let Some(certificate) = certificate else {
            return;
        };
        if let Some(admission) = self.admission.as_mut().filter(|a| a.previous.is_some()) {
            admission.store = Some(Arc::clone(store));
            admission.local = Some(certificate.bind_key(&admission.key));
        }
    }
    pub(super) fn selections(
        identity: UnitIdentity,
        effective: bool,
        body: BodyOccurrence,
        facts: Arc<dm_ir::SelectedReferences>,
    ) -> Self {
        Self {
            inner: Input::Selections(identity, effective, body, facts),
            admission: None,
            verification_reads: None,
        }
    }

    pub fn into_selected(self) -> ProcedureSelections {
        let identity = self.identity();
        let source = match &self.inner {
            Input::Selections(_, _, body, _) => body.source.clone(),
            Input::Lowered(unit) => unit.origin.source.clone(),
            Input::Reused(value) => value.current_source().clone(),
        };
        let facts = match self.inner {
            Input::Selections(_, _, _, facts) => Some(facts),
            Input::Lowered(unit) => unit.selected_references,
            Input::Reused(value) => value.selected_facts().cloned(),
        };
        ProcedureSelections {
            identity,
            source,
            facts,
        }
    }

    pub(super) fn reused(value: crate::symbolic::PreparedContribution) -> Self {
        Self {
            inner: Input::Reused(value),
            admission: None,
            verification_reads: None,
        }
    }
    pub(super) fn lowered(unit: LoweredUnit) -> Self {
        Self {
            inner: Input::Lowered(Box::new(unit)),
            admission: None,
            verification_reads: None,
        }
    }
    pub(super) fn with_admission(mut self, admission: Option<Admission>) -> Self {
        self.admission = admission;
        self
    }
    pub(super) fn verification_reads(&self) -> Option<&[(dm_ir::ResolveQuery, Vec<u8>)]> {
        self.verification_reads.as_deref()
    }
    pub(super) fn verification_unit(&self) -> Option<&LoweredUnit> {
        if let Input::Lowered(v) = &self.inner {
            Some(v)
        } else {
            None
        }
    }
    pub(super) fn verification_prepared(&self) -> Option<&crate::symbolic::PreparedContribution> {
        if let Input::Reused(v) = &self.inner {
            Some(v)
        } else {
            None
        }
    }
    pub fn identity(&self) -> UnitIdentity {
        match &self.inner {
            Input::Selections(identity, _, _, _) => *identity,
            Input::Lowered(unit) => unit.identity,
            Input::Reused(value) => value.identity(),
        }
    }
    pub fn effective(&self) -> bool {
        match &self.inner {
            Input::Selections(_, effective, _, _) => *effective,
            Input::Lowered(unit) => unit.effective,
            Input::Reused(value) => value.effective(),
        }
    }
    pub(super) fn into_lowered(self) -> LoweredUnit {
        match self.inner {
            Input::Selections(_, _, _, _) => {
                unreachable!("query-only facts cannot become executable IR")
            }
            Input::Lowered(unit) => *unit,
            Input::Reused(_) => unreachable!("compatibility requests disable symbolic replay"),
        }
    }
    pub fn prepare(
        self,
        symbols: &dm_ir::SymbolTable,
        source: &std::collections::BTreeSet<dm_ir::SymRef>,
        external: &crate::symbolic::ReferenceBindings,
        detail: bool,
    ) -> Result<crate::symbolic::PreparedContribution, crate::cold::ColdError> {
        let mut value = match self.inner {
            Input::Selections(_, _, _, _) => {
                unreachable!("query-only facts cannot become executable contribution")
            }
            Input::Reused(value) => value,
            Input::Lowered(unit) => {
                unit.require_production_abi()
                    .map_err(|_| crate::cold::ColdError::NonAuthoritativeAbi)?;
                crate::symbolic::prepare_contribution(*unit, symbols, source, external, detail)
                    .map_err(crate::cold::ColdError::Linking)?
            }
        };
        if let Some(store) = self
            .admission
            .as_ref()
            .and_then(|admission| admission.store.as_ref())
        {
            if value.is_reusable() {
                store.share_current_code(&mut value);
            }
        }
        if let Some(admission) = self.admission {
            if let Some(writer) = &admission.disk {
                writer.queue_compact(
                    &admission.key,
                    &admission.reads,
                    &admission.versions,
                    &value,
                    &admission.relative_debug,
                );
            }
            if let Some(store) = admission.store {
                if value.is_reusable() {
                    let record = Record {
                        local: admission.local,
                        recipe: admission.metadata.and_then(|metadata| {
                            crate::lowering_memo::key_recipe::KeyRecipe::new(
                                &admission.key,
                                metadata,
                            )
                        }),
                        key: admission.key,
                        reads: admission.reads,
                        versions: admission.versions,
                        value: RecordValue::Executable(value.shared_artifact()),
                        relative_debug: admission.relative_debug,
                        required_types: Arc::clone(value.required_types_owner()),
                        modified_recipes: Arc::clone(
                            value
                                .modified_recipes_owner()
                                .expect("reusable contribution has source recipes"),
                        ),
                    };
                    if store.insert_record_rebinding(
                        value.identity(),
                        record,
                        admission.previous.as_ref(),
                    ) {
                        store.admitted.fetch_add(1, Ordering::Relaxed);
                    }
                } else {
                    store
                        .declines
                        .nonreusable_completion
                        .fetch_add(1, Ordering::Relaxed);
                }
            }
        }
        Ok(value)
    }
}
impl SessionSymbolicMemo {
    pub(crate) fn with_shared_code(
        owner: &Arc<crate::symbolic::shared_procedure_code::SharedProcedureCode>,
    ) -> Self {
        Self {
            publication: Some(Arc::new(symbolic_publication::Owner::default())),
            shared_code: Some(owner.lease()),
            shared_code_pool: Some(Arc::clone(owner)),
            ..Self::default()
        }
    }
    /// Idle pressure release preserves code, observation ledgers and rebind
    /// recipes. Numeric link/wire answers are recreated on the next request.
    pub(crate) fn release_bound_images(&self) -> usize {
        let mut released = 0usize;
        self.visit_records(|record| {
            if let RecordValue::Executable(artifact) = &record.value {
                released = released.saturating_add(artifact.release_bound_images());
            }
        });
        released
    }
    pub(super) fn capture_excluded(&self) {
        self.declines
            .capture_excluded
            .fetch_add(1, Ordering::Relaxed);
    }
    pub(super) fn retain_current(
        &self,
        frontend: &ColdFrontend,
        prepared: Option<&PreparedBodyRoster<'_>>,
    ) {
        if self.attempt.is_some() {
            // Pending begins empty. Only fully admitted current units claim it;
            // failed/analysis attempts cannot prune the published roster.
            self.receipt_groups.prune();
            return;
        }
        let identities: std::collections::BTreeSet<_> = if let Some(prepared) = prepared {
            prepared
                .ordered()
                .map(|row| row.source().identity)
                .collect()
        } else {
            frontend
                .bodies
                .iter()
                .filter_map(|body| {
                    source_unit_identity(frontend, body)
                        .ok()
                        .map(|source| source.identity)
                })
                .collect()
        };
        let mut records = self.records.lock().unwrap_or_else(|e| e.into_inner());
        let before = records.len();
        let mut code_keys = Vec::new();
        records.retain(|identity, record| {
            let retained = identities.contains(identity);
            if retained && self.shared_code.is_some() {
                if let RecordValue::Executable(artifact) = &record.value {
                    code_keys.extend(artifact.code_owner_keys());
                }
            }
            retained
        });
        self.pruned
            .fetch_add((before - records.len()) as u64, Ordering::Relaxed);
        if let Some(lease) = &self.shared_code {
            lease.retain_current_keys(code_keys.iter().map(Vec::as_slice));
        }
        drop(records);
        self.receipt_groups.prune();
    }
    #[allow(clippy::too_many_arguments)]
    pub(super) fn lookup<R: Resolver>(
        &self,
        key: &crate::lowering_memo::key_recipe::CurrentKey<'_>,
        prepared_tail: &crate::lowering_memo::key_recipe::PreparedKey,
        host: &R,
        request_admission: Option<&RequestAdmission<'_, R>>,
        candidates: Option<&RequestCandidates<'_, '_, R>>,
        observer: &crate::lowering_memo::RecordingResolver<'_, R>,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        prepared: &PreparedUnit,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        selections_only: bool,
        verify: bool,
        current: &PreparedBody<'_>,
    ) -> Option<CompletedInput> {
        let identity = current.source().identity;
        if let Some(attempt) = &self.attempt {
            let mut completed = None;
            if let Some(candidates) = candidates {
                // Extraction holds only the request roster lock. Rebind/observer
                // callbacks and pending claims execute after that guard drops.
                for candidate in candidates.take_identity(identity) {
                    let accepted = attempt
                        .with_pending(|leases| {
                            leases.records.claim_current(
                                candidate,
                                |_, record| {
                                    completed = self.lookup_record(
                                        record,
                                        key,
                                        prepared_tail,
                                        host,
                                        request_admission,
                                        observer,
                                        frontend,
                                        body,
                                        prepared,
                                        bodies,
                                        selections_only,
                                        verify,
                                        current,
                                        true,
                                    );
                                    completed.is_some()
                                },
                                |leaf| observer.record_admitted(leaf),
                            )
                        })
                        .flatten();
                    if accepted.is_some() {
                        let mut input = completed.take()?;
                        if let Input::Reused(value) = &mut input.inner {
                            self.share_current_code(value);
                        }
                        return Some(input);
                    }
                    completed = None;
                }
            }
            let mut accept = |record: &Arc<Record>| {
                completed = self.lookup_record(
                    record,
                    key,
                    prepared_tail,
                    host,
                    request_admission,
                    observer,
                    frontend,
                    body,
                    prepared,
                    bodies,
                    selections_only,
                    verify,
                    current,
                    true,
                );
                completed.is_some()
            };
            let locator = symbolic_publication::BorrowedLocator::new(identity, key, prepared_tail);
            let digest = locator.digest();
            let accepted = attempt
                .with_pending(|leases| {
                    leases
                        .records
                        .visit_borrowed_receipted_with_value(
                            digest,
                            &|candidate| locator.matches(candidate),
                            &mut |reads, _, record| {
                                // The private publication producer stages a clone
                                // of this SAME record.reads owner and qualified
                                // record.versions owner. Ordinary cross-host
                                // lease lookup still requires exact replay.
                                validate_published_record(
                                    reads,
                                    record,
                                    request_admission,
                                    observer,
                                )
                            },
                            &mut accept,
                        )
                        .0
                })
                .flatten();
            let mut completed = accepted.and(completed)?;
            if let Input::Reused(value) = &mut completed.inner {
                self.share_current_code(value);
            }
            return Some(completed);
        }
        let record = self
            .records
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&identity)
            .cloned()
            .or_else(|| {
                self.declines.record_absent.fetch_add(1, Ordering::Relaxed);
                None
            })?;
        self.lookup_record(
            &record,
            key,
            prepared_tail,
            host,
            request_admission,
            observer,
            frontend,
            body,
            prepared,
            bodies,
            selections_only,
            verify,
            current,
            false,
        )
    }
    #[allow(clippy::too_many_arguments)]
    fn lookup_record<R: Resolver>(
        &self,
        record: &Arc<Record>,
        key: &crate::lowering_memo::key_recipe::CurrentKey<'_>,
        prepared_tail: &crate::lowering_memo::key_recipe::PreparedKey,
        host: &R,
        request_admission: Option<&RequestAdmission<'_, R>>,
        observer: &crate::lowering_memo::RecordingResolver<'_, R>,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        prepared: &PreparedUnit,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        selections_only: bool,
        verify: bool,
        current: &PreparedBody<'_>,
        reads_validated: bool,
    ) -> Option<CompletedInput> {
        if !key.matches(&record.key, record.recipe.as_ref(), prepared_tail) {
            self.declines.key_changed.fetch_add(1, Ordering::Relaxed);
            return None;
        }
        let changed = if reads_validated {
            false
        } else {
            let matching = partial_admission::matching_domains(&record.versions, host, request_admission);
            let fully_certified = !host.observes_reads()
                && record.reads.iter().all(|read| {
                    read.domain == read.query.domain() && matching.contains(&read.domain)
                });
            if fully_certified {
                // Candidate-specific complete certificates do not populate a shared
                // leaf verdict. Each accepted leaf still reaches the observer.
                record.reads.visit_storage(|view| {
                    if let dm_session::ReceiptStorageView::Flat(leaf) = view {
                        observer.record_admitted(leaf);
                    }
                });
                false
            } else if let Some(admission) = request_admission {
                // Preserve this candidate's exact matching issuer domains;
                // unknown/changed domains still replay every positive/negative
                // edge. Partial admission never seeds a full-leaf verdict.
                partial_admission::changed(admission, &record.reads, &record.versions, observer)
                    .is_some()
            } else {
                record
                    .reads
                    .iter()
                    .any(|read| !same_meaning(&observer.resolve(read.query), &read.answer))
            }
        };
        if changed {
            self.declines.read_changed.fetch_add(1, Ordering::Relaxed);
            return None;
        }
        if reads_validated {
            // The core claim callback runs after the current-input predicate.
            // Populate this same recorder before building the refreshed receipt.
            record.reads.visit_storage(|view| {
                if let dm_session::ReceiptStorageView::Flat(leaf) = view {
                    observer.record_admitted(leaf);
                }
            });
        }
        let mut input = self.rebind_record(
            record,
            observer,
            frontend,
            body,
            prepared,
            bodies,
            selections_only,
            verify,
            current,
        )?;
        if !selections_only {
            // Exact key/ABI/reads and current source reissue have all succeeded.
            // Publish only through completion's existing pending lease; the old
            // immutable payload remains claimed by its previous publication.
            input.admission = Some(Admission {
                previous: Some(Arc::clone(record)),
                local: None,
                metadata: Some(Arc::clone(key.metadata)),
                store: None,
                disk: None,
                key: Arc::clone(&record.key),
                reads: receipt_groups::grouped(&self.receipt_groups, observer.reads()),
                versions: observer.domain_receipts().into(),
                relative_debug: record.relative_debug.clone(),
            });
        }
        Some(input)
    }
    #[allow(clippy::too_many_arguments)]
    fn rebind_record<R: Resolver>(
        &self,
        record: &Arc<Record>,
        host: &R,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        prepared: &PreparedUnit,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        selections_only: bool,
        verify: bool,
        current: &PreparedBody<'_>,
    ) -> Option<CompletedInput> {
        let artifact = match &record.value {
            RecordValue::Selections { facts, abi } => {
                if !selections_only
                    || prepared.require_production_abi().is_err()
                    || prepared.abi.as_ref()?.canonical_bytes().as_slice() != abi.as_slice()
                {
                    return None;
                }
                self.reused.fetch_add(1, Ordering::Relaxed);
                return Some(CompletedInput::selections(
                    current.source().identity,
                    current.source().effective,
                    body.clone(),
                    Arc::clone(facts),
                ));
            }
            RecordValue::Executable(artifact) if !selections_only => artifact,
            RecordValue::Executable(_) => return None,
        };
        let debug = crate::lowering_memo::rebase_debug(frontend, body, &record.relative_debug)
            .or_else(|| {
                self.declines.debug_rebase.fetch_add(1, Ordering::Relaxed);
                None
            })?;
        let modified_seeds = if record.modified_recipes.is_empty() {
            Vec::new()
        } else {
            bodies
                .with_parsed(body, |parsed| {
                    record
                        .modified_recipes
                        .iter()
                        .map(|recipe| {
                            recipe.reissue(
                                parsed,
                                frontend,
                                host,
                                frontend.snapshot.tree.symbols(),
                                &debug,
                            )
                        })
                        .collect::<Option<Vec<_>>>()
                })
                .ok()
                .flatten()
                .or_else(|| {
                    self.declines
                        .modified_reissue
                        .fetch_add(1, Ordering::Relaxed);
                    None
                })?
        };
        let contribution = crate::symbolic::PreparedContribution::rebind_with_modified_current(
            artifact,
            frontend,
            body,
            prepared,
            debug,
            Arc::clone(&record.required_types),
            modified_seeds,
            Some(Arc::clone(&record.modified_recipes)),
            Some(current),
        )
        .or_else(|| {
            // Includes ABI/identity, current helper-origin and source-binding
            // refusal; do not misleadingly attribute every None to ABI alone.
            self.declines
                .contribution_rebind
                .fetch_add(1, Ordering::Relaxed);
            None
        })?;
        self.reused.fetch_add(1, Ordering::Relaxed);
        Some(CompletedInput {
            inner: Input::Reused(contribution),
            admission: None,
            verification_reads: verify.then(|| {
                record
                    .reads
                    .iter()
                    .map(|r| (r.query, r.answer.canonical_bytes()))
                    .collect()
            }),
        })
    }
}

fn validate_published_record<R: Resolver>(
    reads: &dm_session::Receipt<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning, dm_ir::ReadDomain>,
    record: &Record,
    admission: Option<&RequestAdmission<'_, R>>,
    observer: &crate::lowering_memo::RecordingResolver<'_, R>,
) -> Option<dm_ir::ResolveQuery> {
    if let Some(admission) = admission {
        admission.first_changed_receipted(reads, &record.versions, |leaf| {
            observer.record_admitted(leaf)
        })
    } else {
        reads.iter().find_map(|read| {
            (!same_meaning(&observer.resolve(read.query), &read.answer)).then_some(read.query)
        })
    }
}
fn same_meaning(current: &dm_ir::ResolvedMeaning, previous: &dm_ir::ResolvedMeaning) -> bool {
    // Exact equality also proves canonical equality without allocating two
    // encoded buffers. Keep canonical comparison for semantically equal values
    // whose noncanonical provenance differs across current source revisions.
    current == previous || current.canonical_bytes() == previous.canonical_bytes()
}
pub(super) fn admission(
    memo: &crate::lowering_memo::ProcedureMemo,
    key: Arc<[u8]>,
    reads: Arc<[ResolverRead]>,
    versions: Arc<[(dm_ir::ReadDomain, u128)]>,
    relative_debug: Vec<crate::debug_sources::RelativeDebugAnchor>,
    write_compact: bool,
) -> Option<Admission> {
    let store = memo.symbolic.clone();
    let disk = write_compact.then(|| memo.completion_writer()).flatten();
    if store.is_none() && disk.is_none() {
        return None;
    }
    let reads = store.as_ref().map_or_else(
        || reads.clone().into(),
        |store| receipt_groups::grouped(&store.receipt_groups, reads.iter().cloned().collect()),
    );
    Some(Admission {
        previous: None,
        local: None,
        metadata: None,
        store,
        disk,
        key,
        reads,
        versions,
        relative_debug,
    })
}
pub(super) fn disk_admission<R: Resolver>(
    memo: &crate::lowering_memo::ProcedureMemo,
    key: Vec<u8>,
    host: &R,
    promotion: &crate::lowering_memo_wire::ResidentPromotion<'_>,
) -> Option<Admission> {
    let store = Arc::clone(memo.symbolic.as_ref()?);
    let (reads, versions) = promotion.current_observations(host);
    let reads = receipt_groups::grouped(&store.receipt_groups, reads);
    Some(Admission {
        previous: None,
        local: None,
        metadata: None,
        store: Some(store),
        disk: None,
        key: key.into(),
        reads,
        versions: versions.into(),
        relative_debug: promotion.relative_debug.clone(),
    })
}
pub(super) fn remember_selections<R: Resolver>(
    memo: &crate::lowering_memo::ProcedureMemo,
    key: Vec<u8>,
    host: &R,
    promotion: &crate::lowering_memo_wire::ResidentPromotion<'_>,
    identity: UnitIdentity,
    prepared: &PreparedUnit,
    facts: &Arc<dm_ir::SelectedReferences>,
) {
    let Some(abi) = prepared.abi.as_ref() else {
        return;
    };
    let Some(admission) = disk_admission(memo, key, host, promotion) else {
        return;
    };
    let Some(store) = admission.store else {
        return;
    };
    let record = Record {
        local: None,
        recipe: None,
        key: admission.key,
        reads: admission.reads,
        versions: admission.versions,
        value: RecordValue::Selections {
            facts: Arc::clone(facts),
            abi: abi.canonical_bytes(),
        },
        relative_debug: Vec::new(),
        required_types: Arc::from([]),
        modified_recipes: Arc::from([]),
    };
    if store.insert_record(identity, record) {
        store.admitted.fetch_add(1, Ordering::Relaxed);
    }
}
pub(super) fn accepted_admission<R: Resolver>(
    memo: &crate::lowering_memo::ProcedureMemo,
    key: Vec<u8>,
    accepted: &dm_session::AcceptedArtifact<crate::lowering_memo::CachedProcedure>,
    current: &crate::lowering_memo::RecordingResolver<'_, R>,
) -> Option<Admission> {
    let store = Arc::clone(memo.symbolic.as_ref()?);
    let reads = receipt_groups::grouped(&store.receipt_groups, current.reads());
    Some(Admission {
        previous: None,
        local: None,
        metadata: None,
        store: Some(store),
        disk: None,
        key: key.into(),
        reads,
        versions: current.domain_receipts().into(),
        relative_debug: accepted.value.relative_debug.clone(),
    })
}

#[cfg(test)]
#[path = "rich_promotion_tests.rs"]
mod rich_promotion_tests;
