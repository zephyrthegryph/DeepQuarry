//! Immutable ABI answers; revision authority and executable bodies remain current.
use super::*;
use crate::procedure_policy::{PreparedAbi, PreparedUnit};
use dm_codegen_byond::ProcedureInputs;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};
#[path = "abi_observations.rs"]
pub(crate) mod observations;
use observations::{Answer, Domain, Query};
#[path = "abi_admission.rs"]
pub(super) mod admission;
pub(crate) struct UnitArtifact {
    pub(crate) canonical: Option<Arc<crate::procedure_policy::PreparedCanonical>>,
    pub(crate) inputs: Arc<ProcedureInputs>,
    pub(crate) abi: Arc<PreparedAbi>,
}
#[path = "abi_batch.rs"]
pub(super) mod batch;
#[path = "abi_store.rs"]
mod store;
use store::AbiStore;
#[path = "abi_disk.rs"]
mod disk;
pub(crate) use disk::{admit_initializer_engine_bucket, initializer_engine_record};
pub(crate) enum Artifact {
    Unit(Arc<UnitArtifact>),
    Batch(Arc<batch::Recipe>),
}
/// Owner of one request's ABI disk transport (see [`AbiArtifacts::attach_disk`]).
pub(crate) struct AbiDiskLease(#[allow(dead_code)] Arc<disk::Transport>);

pub struct AbiArtifacts {
    pub(super) store: AbiStore,
    engine_owner: Option<Arc<crate::runner_host::EnginePayload>>,
    /// Disk transport of the current request. Weak: the request's `AbiDiskLease` owns it, so a retained
    /// store never keeps a cache snapshot alive between requests.
    disk: std::sync::RwLock<std::sync::Weak<disk::Transport>>,
    /// Strong owner of the transport of a one-shot store (`with_disk`); retained stores leave it empty.
    #[allow(dead_code)]
    pinned_disk: Option<Arc<disk::Transport>>,
    groups: Arc<dm_session::ReceiptGroupPool<Query, Answer, Domain>>,
    pub(super) reused: AtomicUsize,
    recomputed: AtomicUsize,
    pub(super) provisional_reused: AtomicUsize,
    /// Whole-batch replay validates every retained receipt sequentially (~3 s on DeepQuarry);
    /// the parallel per-unit admission is the default. DMB_ABI_BATCH_REPLAY=1 restores it.
    pub(super) batch_replay: bool,
    /// Build the batch recipe after each successful batch. Only whole-batch replay (and tests of
    /// the recipe itself) read it; the per-unit scheduler finds the same rows through the
    /// exact-key index, and building the recipe costs 0.5-0.8 s per edit on DeepQuarry.
    pub(super) batch_recipes: bool,
    batch_reused: AtomicUsize,
    pub(super) scheduled_reused: AtomicUsize,
    pub(super) batch_rows_selected: AtomicUsize,
    pub(super) candidate_rows_collected: AtomicUsize,
    /// The retained session's query database: semantic receipts are certified by its answers.
    pub(crate) query_db: Option<Arc<crate::query_db::QueryDb>>,
}
impl Default for AbiArtifacts {
    fn default() -> Self {
        let batch_replay = std::env::var_os("DMB_ABI_BATCH_REPLAY").is_some_and(|value| value == "1");
        let batch_recipes = batch_replay
            || std::env::var_os("DMB_ABI_BATCH_RECIPES").is_some_and(|value| value == "1");
        Self {
            // Recipes bind to one session's frontend: a store that builds them stays private.
            store: AbiStore::new(batch_recipes),
            engine_owner: None,
            disk: std::sync::RwLock::new(std::sync::Weak::new()),
            pinned_disk: None,
            groups: crate::shared_store::receipt_pool("abi"),
            reused: AtomicUsize::new(0),
            recomputed: AtomicUsize::new(0),
            provisional_reused: AtomicUsize::new(0),
            batch_replay,
            batch_recipes,
            batch_reused: AtomicUsize::new(0),
            scheduled_reused: AtomicUsize::new(0),
            batch_rows_selected: AtomicUsize::new(0),
            candidate_rows_collected: AtomicUsize::new(0),
            query_db: None,
        }
    }
}
impl AbiArtifacts {
    /// Cap exposed ABI payload/receipt ownership only. The existing shared
    /// engine baseline remains separately owned and is not called byte-bounded.
    pub(crate) fn compact_for_pressure(&self, bytes: usize) -> dm_session::PressurePrune {
        let report = self
            .store
            .prune_for_pressure(bytes, Self::compact_payload_charge);
        self.groups.prune();
        report
    }
    /// Semantic receipts of this store are certified by the session's query database.
    pub(crate) fn with_query_db(mut self, db: &Arc<crate::query_db::QueryDb>) -> Self {
        self.query_db = Some(Arc::clone(db));
        self
    }
    pub(crate) fn with_engine_owner(engine_owner: Arc<crate::runner_host::EnginePayload>) -> Self {
        Self {
            engine_owner: Some(engine_owner),
            ..Self::default()
        }
    }

    /// Enable whole-batch replay and the qualified roster (their own tests).
    #[cfg(test)]
    pub(crate) fn with_retained_shortcuts(mut self) -> Self {
        self.batch_replay = true;
        self.batch_recipes = true;
        self
    }

    /// Build batch recipes without enabling replay or the qualified roster (recipe tests).
    #[cfg(test)]
    pub(crate) fn with_batch_recipes(mut self) -> Self {
        self.batch_recipes = true;
        self
    }

    pub(crate) fn with_disk(
        engine: Arc<crate::runner_host::EnginePayload>,
        disk: Arc<crate::runner_host::disk::LazyDisk>,
        policy: u128,
    ) -> Self {
        Self::with_disk_index(engine, disk, policy, None)
    }

    /// `with_disk`, certifying rows through a persisted dependency index.
    pub(crate) fn with_disk_index(
        engine: Arc<crate::runner_host::EnginePayload>,
        disk: Arc<crate::runner_host::disk::LazyDisk>,
        policy: u128,
        index: Option<Arc<crate::dep_index::DepIndex>>,
    ) -> Self {
        let mut store = Self::with_engine_owner(Arc::clone(&engine));
        let transport = Arc::new(disk::Transport::new(disk, policy, engine).with_index(index));
        *store.disk.write().unwrap_or_else(|error| error.into_inner()) = Arc::downgrade(&transport);
        store.pinned_disk = Some(transport);
        store
    }

    /// Attach this request's disk snapshot to a retained store so a fresh session (restart, eviction,
    /// another worktree) hydrates ABI rows from disk instead of recomputing every unit, and stages the
    /// rows this request computes. Dropping the returned lease detaches it. `None` without an engine owner.
    pub(crate) fn attach_disk(
        &self,
        disk: Arc<crate::runner_host::disk::LazyDisk>,
        policy: u128,
        index: Option<Arc<crate::dep_index::DepIndex>>,
    ) -> Option<AbiDiskLease> {
        let engine = Arc::clone(self.engine_owner.as_ref()?);
        let transport = Arc::new(disk::Transport::new(disk, policy, engine).with_index(index));
        *self.disk.write().unwrap_or_else(|error| error.into_inner()) = Arc::downgrade(&transport);
        Some(AbiDiskLease(transport))
    }

    pub(crate) fn engine_owner(&self) -> Option<&Arc<crate::runner_host::EnginePayload>> {
        self.engine_owner.as_ref()
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, Artifact, Query, Answer, Domain>,
        ),
    ) {
        self.store.visit_storage(visitor);
    }
    pub(crate) fn visit_group_storage(&self, visitor: impl FnMut(usize, usize, usize)) {
        self.groups.visit_storage(visitor);
    }
    pub fn structural_selection_counts(&self) -> (usize, usize) {
        (
            self.batch_rows_selected.load(Ordering::Relaxed),
            self.candidate_rows_collected.load(Ordering::Relaxed),
        )
    }
    pub fn scheduled_reused(&self) -> usize {
        self.scheduled_reused.load(Ordering::Relaxed)
    }
    pub fn batch_reused(&self) -> usize {
        self.batch_reused.load(Ordering::Relaxed)
    }
    pub fn totals(&self) -> (usize, usize) {
        (
            self.reused.load(Ordering::Relaxed),
            self.recomputed.load(Ordering::Relaxed),
        )
    }
    pub(super) fn prune(&self, keys: &Mutex<Vec<Arc<[u8]>>>) {
        let keys = keys.lock().unwrap_or_else(|error| error.into_inner());
        self.prune_keys(keys.iter().map(|key| key.as_ref()));
    }
    pub(super) fn prune_keys<'a>(&self, keys: impl IntoIterator<Item = &'a [u8]>) {
        self.store.retain_current_keys(keys);
        self.groups.prune();
    }
}
struct BorrowedResolver<'a>(&'a dyn Resolver);
impl Resolver for BorrowedResolver<'_> {
    // The borrowed resolver is the request's own, so its observation interface is the borrowed
    // one: a transparent recorder over it (the unit's `RecordingResolver`) can then take answers
    // an admitted disk row already proved, without another resolve per read.
    fn observes_reads(&self) -> bool {
        self.0.observes_reads()
    }
    fn transparent_receipt_observer(&self) -> Option<dm_ir::TransparentReceiptObserver<'_>> {
        self.0.transparent_receipt_observer()
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.0.resolve(query)
    }
    fn answer_world(&self) -> Option<u128> {
        self.0.answer_world()
    }
}
#[allow(clippy::too_many_arguments)] // This is the single optional artifact adapter around current ABI preparation.
pub(super) fn prepare(
    store: &AbiArtifacts,
    keys: &Mutex<Vec<Arc<[u8]>>>,
    metadata: &dm_ir::ProcedureMetadata,
    settings: Option<&dm_tree::frontend::IssuedProcedureSettings<'_>>,
    parsed: dm_tree::frontend::ItemView<'_>,
    context: &AbiContext<'_>,
    evaluator: &DriverEvaluator<'_>,
    inherited: &DriverInheritedFacts<'_>,
    lexical: bool,
    resource: Option<u128>,
    admission: Option<&admission::Admission<'_>>,
    batch_capture: Option<&batch::Capture>,
) -> Result<PreparedUnit, AbiError> {
    // Always authenticate the current issued header/settings before accepting old answers.
    let authenticated = settings.is_some_and(|proof| proof.authenticates(parsed, metadata));
    let mut symbols = dm_ir::SymbolTable::default();
    if !authenticated
        && dm_tree::settings::extract_settings_view(parsed, &mut symbols)
            .map_err(AbiError::unsupported)?
            .as_ref()
            != metadata.settings.as_ref()
    {
        return Err(AbiError::unsupported(
            "captured procedure setting tree differs from actual body",
        ));
    }
    let stage = dm_profile::stage("abi.unit.inherited");
    inherited.inherited(context)?; // Current boundary/ancestry admission is not a cached certificate.
    let member = inherited
        .unit_members
        .get(&context.identity)
        .ok_or_else(|| AbiError::unsupported("body identity missing"))?;
    let predecessor = inherited
        .source_predecessor(*member)?
        .and_then(|previous| inherited.source_layouts.get(&previous));
    drop(stage);
    let stage = dm_profile::stage("abi.unit.current_inputs");
    let pure_policy = evaluator
        .pure_calls
        .map(|calls| calls.immutable_policy_identity());
    let current = store
        .engine_owner
        .as_ref()
        .filter(|owner| std::ptr::eq(&owner.snapshot, inherited.engine))
        .filter(|_| !matches!(pure_policy, Some(None)))
        .map(|engine| {
            let current_metadata = inherited
                .frontend
                .snapshot
                .tree
                .member(*member)
                .and_then(|node| node.metadata.procedure.as_ref())
                .ok_or_else(|| AbiError::invariant("current ABI metadata missing"))?;
            if !std::ptr::eq(current_metadata.as_ref(), metadata)
                && current_metadata.canonical_bytes() != metadata.canonical_bytes()
            {
                return Err(AbiError::unsupported(
                    "ABI metadata differs from current declaration",
                ));
            }
            let structural = observations::structural_inputs(inherited.frontend, *member);
            Ok(observations::Current {
                inputs: Arc::new(observations::Inputs {
                    definition: structural.as_ref().map(|(definition, _)| *definition),
                    ancestry: structural.map(|(_, ancestry)| ancestry),
                    metadata: Arc::clone(current_metadata),
                    predecessor: predecessor.cloned(),
                    engine: Arc::downgrade(engine),
                    boundary: observations::Boundary::capture(
                        inherited.boundaries.get(&context.identity),
                    ),
                    resource,
                    evaluation_resource: evaluator.resource_search_context,
                    lexical,
                    pure_policy: pure_policy.flatten(),
                }),
                resolver: evaluator.resolver,
            })
        })
        .transpose()?;
    drop(stage);
    let key = observations::locator(context.identity);
    let base = BorrowedResolver(evaluator.resolver);
    let stage = dm_profile::stage("abi.unit.admission");
    if let Some(current) = &current {
        if let Some(accepted) = store
            .store
            .visit_receipted_with(
                &key,
                &mut |reads, _| admission::changed(reads, current, admission),
                &mut |value| matches!(value.as_ref(), Artifact::Unit(_)),
            )
            .0
        {
            keys.lock()
                .unwrap_or_else(|error| error.into_inner())
                .push(Arc::clone(&key));
            store.reused.fetch_add(1, Ordering::Relaxed);
            let Artifact::Unit(artifact) = accepted.value.as_ref() else {
                unreachable!("unit consumer checked")
            };
            batch::record(batch_capture, context.identity, artifact, &accepted.reads);
            return Ok(PreparedUnit {
                canonical: artifact.canonical.clone(),
                inputs: artifact.inputs.clone(),
                abi: Some(Arc::clone(&artifact.abi)),
                executable_body: Vec::new(),
            });
        }
    }
    drop(stage);
    // A session's answer table proves ABI receipts: their reads carry no domain version.
    let recording = dm_session::RecordingResolver::new(&base);
    let issued_identity = dm_ir::ProcedureIdentity {
        owner: context.identity.owner,
        name: context.identity.name,
        verb: context.identity.namespace == Namespace::Verb,
        occurrence: context.identity.occurrence,
    };
    let evaluated = DriverEvaluator {
        pure_calls: evaluator.pure_calls,
        resource_search_context: evaluator.resource_search_context,
        resolver: &recording,
        symbols: evaluator.symbols,
    };
    let lexical_evaluator = LexicalAbiEvaluator(&evaluated);
    let selected: &dyn CapturedConstantEvaluator = if lexical {
        &lexical_evaluator
    } else {
        &evaluated
    };
    let policy = crate::procedure_policy::CapturedProcedurePolicy {
        evaluator: selected,
        inherited,
        resource_search_context: resource,
    };
    let recorded_context = AbiContext {
        resolver: &recording,
        ..*context
    };
    // Unknown custom policies have no portable proof. They use the exact current
    // producer and resident admission, never a hash-only disk shortcut.
    let portable_policy = evaluator
        .pure_calls
        .map_or(Some(None), |calls| calls.immutable_policy_bytes().map(Some));
    let transport = store.disk.read().unwrap_or_else(|error| error.into_inner()).upgrade();
    let disk = transport.as_deref().filter(|_| portable_policy.is_some());
    static DISK_LOOKUP: dm_profile::Accumulator = dm_profile::Accumulator::new("abi.disk_lookup");
    static DISK_STAGE: dm_profile::Accumulator = dm_profile::Accumulator::new("abi.disk_stage");
    static RECOMPUTE: dm_profile::Accumulator = dm_profile::Accumulator::new("abi.recompute");
    let lookup_timer = DISK_LOOKUP.time();
    let transported = disk.and_then(|disk| {
        current.as_ref().and_then(|current| {
            disk.lookup(
                &key,
                issued_identity,
                current,
                portable_policy.flatten(),
                &recording,
            )
        })
    });
    drop(lookup_timer);
    let was_transported = transported.is_some();
    let mut unit = if let Some(unit) = transported {
        store.reused.fetch_add(1, Ordering::Relaxed);
        unit
    } else {
        let _timer = RECOMPUTE.time();
        recording.record_declaration_occurrence(issued_identity);
        store.recomputed.fetch_add(1, Ordering::Relaxed);
        policy.prepare_view(metadata, parsed, &recorded_context)?
    };
    unit.issue_canonical();
    if let Some(current) = current {
        let abi = Arc::clone(
            unit.abi
                .as_ref()
                .ok_or_else(|| AbiError::invariant("production ABI missing"))?,
        );
        let inputs = Arc::clone(&unit.inputs);
        let semantic_reads = recording.reads();
        // A row hydrated from disk is already there: staging it again would only grow its bucket.
        if let Some(disk) = disk.filter(|_| !was_transported) {
            let _timer = DISK_STAGE.time();
            let observer = recording.transparent_receipt_observer();
            disk.stage(
                &key,
                issued_identity,
                &current.inputs,
                portable_policy.flatten(),
                &UnitArtifact {
                    canonical: unit.canonical.clone(),
                    inputs: Arc::clone(&inputs),
                    abi: Arc::clone(&abi),
                },
                &semantic_reads,
                observer.as_ref().map(|observer| observer.provider()),
            );
        }
        let reads = observations::reads(current.inputs, semantic_reads);
        // Inputs stays a separate leaf; semantic runs share only exact individual
        // observations and domain identities. No dependency edges are collapsed.
        let reads = store
            .groups
            .intern_receipt(reads, |a, b| {
                matches!(
                    (&a.query, &b.query),
                    (Query::Semantic(_), Query::Semantic(_))
                ) && a.domain == b.domain
            })
            .map_err(AbiError::invariant)?;
        let versions: Vec<(Domain, u128)> = Vec::new();
        // Current-roster mode has no byte admission budget. This is an inline
        // accounting charge only; opt-in census separately walks actual owners.
        let charge = std::mem::size_of::<Artifact>()
            + std::mem::size_of::<observations::Inputs>()
            + key.len();
        let captured_reads = reads.clone();
        if let Some(accepted) = store.store.insert_with_receipt(
            Arc::clone(&key),
            reads,
            versions.into(),
            charge,
            || {
                Artifact::Unit(Arc::new(UnitArtifact {
                    inputs,
                    abi,
                    canonical: unit.canonical.clone(),
                }))
            },
        ) {
            if let Artifact::Unit(artifact) = accepted.as_ref() {
                batch::record(batch_capture, context.identity, artifact, &captured_reads);
            }
            keys.lock()
                .unwrap_or_else(|error| error.into_inner())
                .push(key);
        }
    }
    unit.executable_body = Vec::new();
    Ok(unit)
}

#[cfg(test)]
#[path = "abi_observations_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "abi_artifacts_production_tests.rs"]
mod production_tests;

#[cfg(test)]
#[path = "abi_pressure_tests.rs"]
mod pressure_tests;
