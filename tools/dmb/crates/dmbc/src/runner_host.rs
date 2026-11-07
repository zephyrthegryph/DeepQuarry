//! Process-local artifact ownership for the shared request pipeline.
//! Immutable source contributions and observed artifacts survive across requests;
//! current source issuance, dense table projections and publication stay request-local.
use std::{collections::BTreeMap, path::PathBuf, sync::Arc};

#[path = "runner_disk.rs"]
pub mod disk;
#[path = "runner_engine_payload.rs"]
mod engine_payload;
#[path = "runner_host_idle.rs"]
mod idle;
#[path = "runner_host_idle_census.rs"]
mod idle_census;
#[path = "runner_host_initializers.rs"]
mod initializers;
#[path = "runner_host_memo.rs"]
mod memo;
#[path = "runner_host/policy_capture.rs"]
pub(crate) mod policy_capture;
#[path = "runner_query_snapshot.rs"]
pub(crate) mod query_snapshot;
#[path = "runner_host_resources.rs"]
pub(crate) mod resources;
#[path = "runner_host/workspace_capture.rs"]
pub(crate) mod workspace_capture;
#[path = "runner_host/workspace_discovery.rs"]
pub(crate) mod workspace_discovery;
pub(crate) use engine_payload::{EnginePayload, EnginePayloads};
pub(crate) use memo::SharedRecords;
#[path = "runner_executor_pool.rs"]
mod executor_pool;
pub(crate) use executor_pool::ExecutorPools;

type ProcedureValues = Arc<crate::lowering_memo::RetainedProcedures>;
type HostParts<'a> = (
    Option<memo::MemoView<'a>>,
    HostExecution<'a>,
    Option<&'a mut dm_tree::frontend::RetainedSemanticTree>,
);

fn next_session_id() -> u64 {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

/// One semantic session's retained artifacts and bounded executor. A long-lived
/// caller reuses this owner across requests without retaining a publication lease.
pub struct BuildHost {
    // Diagnostic lifecycle markers, never semantic cache admission or output identity.
    session_id: u64,
    engine_generation: u64,
    rich_generation: u64,
    procedure_generation: u64,
    procedure_policy_replacements: u64,
    prepared_sources: Option<Arc<crate::input_snapshot::PreparedInputArtifacts>>,
    shared_engines: Option<Arc<EnginePayloads>>,
    shared_executors: Option<Arc<ExecutorPools>>,
    shared_procedure_code: Option<Arc<crate::symbolic::shared_procedure_code::SharedProcedureCode>>,
    shared_store: Option<Arc<crate::shared_store::SharedStore>>,
    engine: Option<Arc<RetainedEngine>>,
    memo: Option<memo::ResidentMemo>,
    executor: Option<dm_exec::BuildExecutor>,
    procedures: Option<(u128, ProcedureValues)>,
    semantic: Option<dm_tree::frontend::RetainedSemanticTree>,
    query_state: Arc<std::sync::Mutex<query_snapshot::QueryState>>,
    maps: Option<(u128, Arc<crate::map_memo::RetainedMaps>)>,
    initializers: Option<(u128, Arc<crate::initializer_policy::InitializerArtifacts>)>,
    startup: Option<(u128, Arc<crate::startup::StartupArtifacts>)>,
    abi: Option<(u128, Arc<crate::driver_facts::AbiArtifacts>)>,
    initializer_fragments: Option<(u128, Arc<crate::initializer_lowering::InitializerFragments>)>,
    initializer_assemblies: Option<(
        u128,
        Arc<crate::initializer_lowering::InitializerAssemblies>,
    )>,
    class_projections: Option<(u128, Arc<crate::class_projection::ClassProjections>)>,
    required_types: Option<(u128, Arc<crate::required_types::RequiredTypeArtifacts>)>,
    link_bindings: Option<(u128, Arc<dm_link::RetainedBindings>)>,
    stages: Option<(u128, Arc<crate::stage_reuse::StageProducts>)>,
    generation: Option<(u128, Arc<crate::composition::RetainedGeneration>)>,
    host_facts: Option<Arc<crate::request_runner::runner_facts::RetainedHostFacts>>,
    resources: Option<Arc<resources::Resources>>,
    symbolic: Option<(
        u128,
        Arc<crate::lowering::symbolic_input::SessionSymbolicMemo>,
    )>,
    /// The define-dependent state of every other (project, defines) variant this session has built, kept so switching back to
    /// a variant resumes its patch base instead of a full compile. Define-independent owners (engine payload, executors, the
    /// directive/expansion/fragment memo, prepared sources) are shared by all variants and never stashed.
    variants: std::collections::BTreeMap<EngineConfiguration, VariantState>,
    /// The session's query database (doc/incremental_core.md). Shared by every variant: a variant
    /// is another value of the `project` input.
    query_db: Arc<crate::query_db::QueryDb>,
}

/// Everything `BuildHost::engine` used to discard when only the project path or the defines changed.
const MAX_STASHED_VARIANTS: usize = 3;
/// Threads a store of a patch base may use for its footprints (the machine is also a desktop).
const SPILL_WORKERS: usize = 2;

struct VariantState {
    engine: Arc<RetainedEngine>,
    procedures: Option<(u128, ProcedureValues)>,
    semantic: Option<dm_tree::frontend::RetainedSemanticTree>,
    query_state: Arc<std::sync::Mutex<query_snapshot::QueryState>>,
    maps: Option<(u128, Arc<crate::map_memo::RetainedMaps>)>,
    initializers: Option<(u128, Arc<crate::initializer_policy::InitializerArtifacts>)>,
    startup: Option<(u128, Arc<crate::startup::StartupArtifacts>)>,
    abi: Option<(u128, Arc<crate::driver_facts::AbiArtifacts>)>,
    initializer_fragments: Option<(u128, Arc<crate::initializer_lowering::InitializerFragments>)>,
    initializer_assemblies: Option<(
        u128,
        Arc<crate::initializer_lowering::InitializerAssemblies>,
    )>,
    class_projections: Option<(u128, Arc<crate::class_projection::ClassProjections>)>,
    required_types: Option<(u128, Arc<crate::required_types::RequiredTypeArtifacts>)>,
    link_bindings: Option<(u128, Arc<dm_link::RetainedBindings>)>,
    stages: Option<(u128, Arc<crate::stage_reuse::StageProducts>)>,
    generation: Option<(u128, Arc<crate::composition::RetainedGeneration>)>,
    host_facts: Option<Arc<crate::request_runner::runner_facts::RetainedHostFacts>>,
    resources: Option<Arc<resources::Resources>>,
    symbolic: Option<(
        u128,
        Arc<crate::lowering::symbolic_input::SessionSymbolicMemo>,
    )>,
}

#[derive(Clone, Eq, Ord, PartialEq, PartialOrd)]
struct EngineConfiguration {
    analysis_context: Option<crate::policy_request::AnalysisContext>,
    project: PathBuf,
    defines: BTreeMap<String, String>,
    bootstrap_catalog: bool,
    schema: u128,
}

pub(crate) struct RetainedEngine {
    configuration: EngineConfiguration,
    payload: Arc<engine_payload::EnginePayload>,
}
impl RetainedEngine {
    pub(crate) fn abi_engine_owner(&self) -> Arc<EnginePayload> {
        Arc::clone(&self.payload)
    }
}
impl std::ops::Deref for RetainedEngine {
    type Target = engine_payload::EnginePayload;
    fn deref(&self) -> &Self::Target {
        &self.payload
    }
}

impl Default for BuildHost {
    fn default() -> Self {
        Self {
            session_id: next_session_id(),
            query_db: Default::default(),
            engine_generation: 0,
            rich_generation: 0,
            procedure_generation: 0,
            procedure_policy_replacements: 0,
            prepared_sources: Some(Arc::new(
                crate::input_snapshot::PreparedInputArtifacts::default(),
            )),
            shared_engines: None,
            shared_executors: None,
            shared_procedure_code: None,
            shared_store: None,
            engine: None,
            executor: None,
            procedures: None,
            memo: Some(memo::ResidentMemo::default()),
            semantic: Some(dm_tree::frontend::RetainedSemanticTree::new()),
            query_state: Arc::default(),
            maps: None,
            symbolic: None,
            variants: Default::default(),
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            required_types: None,
            link_bindings: None,
            stages: None,
            generation: None,
            host_facts: None,
            resources: None,
        }
    }
}
impl BuildHost {
    pub(crate) fn resources(&mut self) -> Option<Arc<resources::Resources>> {
        self.memo.as_ref()?;
        Some(Arc::clone(
            self.resources
                .get_or_insert_with(|| Arc::new(Default::default())),
        ))
    }
    pub(crate) fn retention_status(&self) -> serde_json::Value {
        serde_json::json!({
            "scope": "process_local_diagnostic_only",
            "session": self.session_id,
            "engine_generation": self.engine_generation,
            "rich_generation": self.rich_generation,
            "procedure_generation": self.procedure_generation,
            "procedure_policy_replacements": self.procedure_policy_replacements,
            "enabled": self.retains_artifacts(),
        })
    }
    pub(crate) fn host_facts(
        &mut self,
    ) -> Option<Arc<crate::request_runner::runner_facts::RetainedHostFacts>> {
        self.memo.as_ref()?;
        Some(Arc::clone(
            self.host_facts
                .get_or_insert_with(|| Arc::new(Default::default())),
        ))
    }
    pub fn host_facts_retention_census(&self) -> Option<crate::heap_census::HeapCensusReport> {
        self.host_facts.as_ref().map(|facts| facts.census())
    }
    pub fn prepared_source_retention_census(&self) -> Option<crate::heap_census::HeapCensusReport> {
        self.prepared_sources
            .as_deref()
            .map(crate::heap_census::prepared_input_census)
    }
    pub(crate) fn generation(
        &mut self,
        policy: u128,
    ) -> Option<Arc<crate::composition::RetainedGeneration>> {
        self.memo.as_ref()?;
        if self
            .generation
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.generation = Some((policy, Arc::new(Default::default())));
        }
        Some(Arc::clone(&self.generation.as_ref().unwrap().1))
    }
    /// Diagnostic only: current model/encoded backing, not process-private memory.
    pub fn generation_retention_census(&self) -> Option<crate::heap_census::HeapCensusReport> {
        self.generation.as_ref().map(|(_, generation)| {
            let mut census = crate::heap_census::HeapCensus::new("retained.generation");
            census.composition_generation(generation);
            census.finish()
        })
    }
    pub(crate) fn prepared_sources(
        &self,
    ) -> Option<Arc<crate::input_snapshot::PreparedInputArtifacts>> {
        self.prepared_sources.clone()
    }
    pub(crate) fn query_state(&self) -> Arc<std::sync::Mutex<query_snapshot::QueryState>> {
        Arc::clone(&self.query_state)
    }
    pub(crate) fn query_tree(&self) -> Option<&Arc<dm_tree::SemanticTree>> {
        self.semantic
            .as_ref()
            .and_then(|semantic| semantic.snapshot_tree())
    }

    pub(crate) fn with_daemon_owners(
        engines: Arc<EnginePayloads>,
        executors: Arc<ExecutorPools>,
        procedures: Arc<crate::symbolic::shared_procedure_code::SharedProcedureCode>,
        store: Arc<crate::shared_store::SharedStore>,
    ) -> Self {
        let mut host = Self::with_shared_engines(engines);
        host.shared_executors = Some(executors);
        host.shared_procedure_code = Some(procedures);
        if crate::shared_store::records_shared() {
            host.memo = Some(memo::ResidentMemo::sharing(&store.records));
            host.shared_store = Some(store);
        }
        host
    }
    pub(crate) fn with_shared_engines(shared_engines: Arc<EnginePayloads>) -> Self {
        Self {
            shared_engines: Some(shared_engines),
            ..Self::default()
        }
    }
    /// CLI adapter: no resident candidates or memo-record construction without disk.
    pub fn one_shot() -> Self {
        Self {
            session_id: next_session_id(),
            query_db: Default::default(),
            engine_generation: 0,
            rich_generation: 0,
            procedure_generation: 0,
            procedure_policy_replacements: 0,
            prepared_sources: None,
            shared_engines: None,
            shared_executors: None,
            shared_procedure_code: None,
            shared_store: None,
            engine: None,
            executor: None,
            procedures: None,
            memo: None,
            semantic: None,
            query_state: Arc::default(),
            maps: None,
            symbolic: None,
            variants: Default::default(),
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            required_types: None,
            link_bindings: None,
            stages: None,
            generation: None,
            host_facts: None,
            resources: None,
        }
    }

    /// Explicit diagnostic traversal of the full symbolic store. Shared backing is
    /// counted once; opaque allocator/index overhead remains identified as unknown.
    /// This is not process-private memory and is not run on the lookup hot path.
    pub fn symbolic_retention_stats(&self) -> Option<crate::lowering::SymbolicRetentionStats> {
        self.symbolic
            .as_ref()
            .map(|(_, store)| store.retention_stats())
    }

    /// Explicit diagnostic traversal of exact retained expansion-input owners.
    pub fn expansion_input_retention_census(&self) -> Option<crate::heap_census::HeapCensusReport> {
        self.memo.as_ref().map(memo::ResidentMemo::input_census)
    }

    /// Constant-time retained declaration counters. Unknown payload ownership is
    /// reported explicitly rather than presented as measured retained bytes.
    pub fn declaration_retention_stats(
        &self,
    ) -> Option<dm_tree::frontend::DeclarationRetentionStats> {
        self.semantic
            .as_ref()
            .map(|state| state.declaration_retention_stats())
    }

    /// Constant-time diagnostic counters for structural metadata resolution.
    /// These exclude the separate unchanged-roster path and admit no artifacts.
    pub fn metadata_resolution_stats(
        &self,
    ) -> Option<dm_tree::owner_metadata::MetadataResolutionStats> {
        self.semantic
            .as_ref()
            .map(|state| state.metadata_resolution_stats())
    }

    /// Explicit diagnostic traversal; never performed during artifact lookup.
    pub fn declaration_retention_census(&self) -> Option<crate::heap_census::HeapCensusReport> {
        self.semantic
            .as_ref()
            .map(crate::heap_census::retained_declaration_census)
    }

    /// Explicit diagnostic traversal; never part of compilation or admission.
    pub fn initializer_assembly_retention_census(
        &self,
    ) -> Option<crate::heap_census::HeapCensusReport> {
        self.initializer_assemblies
            .as_ref()
            .map(|(_, store)| crate::heap_census::initializer_assembly_census(store))
    }

    /// Explicit diagnostic owner traversal, outside artifact admission.
    pub fn owner_projection_retention_census(
        &self,
    ) -> Option<crate::heap_census::HeapCensusReport> {
        self.class_projections
            .as_ref()
            .map(|(_, store)| crate::heap_census::owner_projection_census(store))
    }

    /// Existing memo policy pins compiler/schema; engine() separately admits
    /// exact project/defines/bootstrap/engine bytes and clears this state on change.
    /// Moving the disk cache does not invalidate resident semantic values.

    pub(crate) fn query_db(&self) -> &Arc<crate::query_db::QueryDb> {
        &self.query_db
    }
    pub(crate) fn retains_artifacts(&self) -> bool {
        self.memo.is_some()
    }
    /// True when the next edit can take the body-patch path: a retained generation with an installed patch base.
    /// A session that only answered an unchanged-input hit retains artifacts but no patch base.
    pub(crate) fn retains_patch_base(&self) -> bool {
        self.generation
            .as_ref()
            .is_some_and(|(_, generation)| generation.has_patch_base())
    }
    /// The image the retained patch base describes (None without one): a stored-record hit that would serve a different
    /// image must not leave the base behind (see `request_runner`).
    pub(crate) fn patch_base_image_hash(&self) -> Option<u128> {
        self.generation
            .as_ref()
            .and_then(|(_, generation)| generation.patch_base_image_hash())
    }
    /// Retain map answers across requests; disk snapshots remain request-local.
    pub(crate) fn map_memo(
        &mut self,
        policy: u128,
        disk: Option<Arc<disk::LazyDisk>>,
        publishable: bool,
    ) -> Option<crate::map_memo::MapMemo> {
        if self.memo.is_none() {
            // The one-shot facade uses the same parse/geometry/output leases,
            // but the owner belongs only to this request. Disk is transport only.
            return Some(crate::map_memo::MapMemo::with_resident_for_request(
                policy,
                Arc::new(crate::map_memo::RetainedMaps::current_revision()),
                disk,
                publishable,
            ));
        }
        if self
            .maps
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.maps = Some((
                policy,
                Arc::new(crate::map_memo::RetainedMaps::current_revision()),
            ));
        }
        Some(crate::map_memo::MapMemo::with_resident_for_request(
            policy,
            Arc::clone(&self.maps.as_ref().unwrap().1),
            disk,
            publishable,
        ))
    }
    /// `facts_policy` keys the caches whose content does not depend on `DEBUG` (`ProcedureMemo::facts_policy`): the
    /// initializer transport, whose lowered code always carries debug ops (stripped at link without `DEBUG`).
    pub(crate) fn procedure_memo(
        &mut self,
        policy: u128,
        facts_policy: u128,
        disk: Option<Arc<disk::LazyDisk>>,
        publishable: bool,
    ) -> Option<crate::lowering_memo::ProcedureMemo> {
        if self.memo.is_none() {
            return Some(initializers::one_shot(
                policy,
                facts_policy,
                disk,
                publishable,
                self.engine.as_ref(),
            ));
        }
        if self
            .procedures
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.procedure_generation = self.procedure_generation.saturating_add(1);
            if self.procedures.is_some() {
                self.procedure_policy_replacements =
                    self.procedure_policy_replacements.saturating_add(1);
            }
            self.procedures = Some((
                policy,
                Arc::new(crate::lowering_memo::RetainedProcedures::default()),
            ));
        }
        if self
            .symbolic
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            let symbolic = self.shared_procedure_code.as_ref().map_or_else(
                crate::lowering::symbolic_input::SessionSymbolicMemo::current_revision,
                |owner| {
                    crate::lowering::symbolic_input::SessionSymbolicMemo::with_shared_code(owner)
                },
            );
            self.symbolic = Some((policy, Arc::new(symbolic.with_query_db(&self.query_db))));
        }
        if self
            .initializers
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.initializers = Some((
                policy,
                Arc::new(
                    crate::initializer_policy::InitializerArtifacts::default()
                        .with_query_db(&self.query_db),
                ),
            ));
        }
        // One dependency index per request, shared by lowering, ABI and initializer replays.
        let dep_index = disk
            .as_ref()
            .filter(|_| crate::dep_index::enabled())
            .map(|disk| Arc::new(crate::dep_index::DepIndex::new(Arc::clone(disk), policy)));
        let abi_disk = disk.clone();
        // One transport per request for both initializer stores, as the one-shot facade builds it.
        let initializer_disk = disk.clone().map(|disk| {
            crate::initializer_lowering::disk::Transport::new(
                disk,
                self.engine.as_ref().map(|engine| engine.abi_engine_owner()),
                facts_policy,
                publishable,
                dep_index.clone(),
            )
        });
        let mut memo = crate::lowering_memo::ProcedureMemo::with_resident_for_request(
            policy,
            Arc::clone(&self.procedures.as_ref().unwrap().1),
            disk,
            publishable,
        );
        memo.share_dep_index(dep_index.clone());
        memo.symbolic = Some(self.symbolic.as_ref().unwrap().1.for_request(publishable));
        memo.initializers = Some(
            self.initializers
                .as_ref()
                .unwrap()
                .1
                .for_request(publishable),
        );
        if self
            .startup
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.startup = Some((policy, Arc::new(Default::default())));
        }
        memo.startup = Some(self.startup.as_ref().unwrap().1.for_request(publishable));
        if self
            .abi
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            let artifacts = self.engine.as_ref().map_or_else(
                crate::driver_facts::AbiArtifacts::default,
                |engine| {
                    crate::driver_facts::AbiArtifacts::with_engine_owner(engine.abi_engine_owner())
                },
            );
            self.abi = Some((policy, Arc::new(artifacts.with_query_db(&self.query_db))));
        }
        memo.abi = Some(Arc::clone(&self.abi.as_ref().unwrap().1));
        // The retained ABI store reads and stages per-unit rows through this request's disk snapshot, so a
        // fresh session (restart, eviction, another worktree) does not recompute every unit's ABI.
        if let (Some(disk), Some(abi)) = (abi_disk, &memo.abi) {
            memo.abi_disk = abi.attach_disk(disk, policy, dep_index);
        }
        if self
            .initializer_fragments
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.initializer_fragments = Some((policy, Arc::new(Default::default())));
        }
        memo.initializer_fragments = Some(
            self.initializer_fragments
                .as_ref()
                .unwrap()
                .1
                .for_request_with_disk(publishable, initializer_disk.clone()),
        );
        if self
            .initializer_assemblies
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.initializer_assemblies = Some((policy, Arc::new(Default::default())));
        }
        memo.initializer_assemblies = Some(
            self.initializer_assemblies
                .as_ref()
                .unwrap()
                .1
                .for_request_with_disk(publishable, initializer_disk),
        );
        if self
            .class_projections
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.class_projections = Some((policy, Arc::new(Default::default())));
        }
        memo.class_projections = Some(Arc::new(
            self.class_projections
                .as_ref()
                .unwrap()
                .1
                .with_request(publishable)
                .with_answers(Some(Arc::clone(&self.query_db))),
        ));
        if self
            .required_types
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.required_types = Some((policy, Arc::new(Default::default())));
        }
        memo.required_types = Some(
            self.required_types
                .as_ref()
                .unwrap()
                .1
                .for_request(publishable),
        );
        if self
            .link_bindings
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.link_bindings = Some((policy, Arc::new(Default::default())));
        }
        memo.link_bindings = Some(
            self.link_bindings
                .as_ref()
                .unwrap()
                .1
                .for_request(publishable),
        );
        if self
            .stages
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.stages = Some((policy, Arc::new(Default::default())));
        }
        memo.stages = Some(self.stages.as_ref().unwrap().1.for_request(publishable));
        Some(memo)
    }

    pub(crate) fn prune_foreign_callable_index(&self) {
        if let Some((_, startup)) = &self.startup {
            startup.retain_callable_tree(
                self.semantic
                    .as_ref()
                    .and_then(|state| state.snapshot_tree()),
            );
        }
    }
    /// A fresh session memo: its own expansion admissions over the daemon-wide records (kept for other sessions).
    fn reset_memo(&mut self) {
        if let Some(memo) = self.memo.take() {
            self.memo = Some(memo.released());
        }
    }
    pub(crate) fn clear_regions(&mut self) {
        if let Some((_, startup)) = &self.startup {
            startup.clear_callable_index();
        }
        self.reset_memo();
        if self.semantic.is_some() {
            self.semantic = Some(dm_tree::frontend::RetainedSemanticTree::new());
            *self
                .query_state
                .lock()
                .unwrap_or_else(|error| error.into_inner()) = Default::default();
        }
    }

    #[cfg(test)]
    pub(crate) fn expansion_memo<'a>(
        &'a self,
        disk: Option<&'a dyn dm_preprocess::regions::ExpansionMemo>,
    ) -> Option<impl dm_preprocess::regions::ExpansionMemo + 'a> {
        match &self.memo {
            Some(resident) => Some(resident.with_disk(disk)),
            None => disk.map(memo::MemoView::disk_only),
        }
    }

    pub(crate) fn execution<'a>(
        &'a mut self,
        workers: usize,
        disk: Option<&'a dyn dm_preprocess::regions::ExpansionMemo>,
    ) -> Result<HostParts<'a>, Box<dyn std::error::Error>> {
        self.execution_with_selected_declaration_loans(workers, disk, false, false)
            .map(|(parts, _)| parts)
    }

    pub(crate) fn execution_with_selected_declaration_loans<'a>(
        &'a mut self,
        workers: usize,
        disk: Option<&'a dyn dm_preprocess::regions::ExpansionMemo>,
        selected_original: bool,
        joined_strict: bool,
    ) -> Result<(HostParts<'a>, Option<&'a dm_tree::frontend::RetainedSemanticTree>), Box<dyn std::error::Error>> {
        // These are mutually exclusive admitted request roles. Each returns a
        // disjoint borrow of the existing stashed variant.
        let prior = self.engine.as_ref().and_then(|engine| {
            if selected_original {
                Self::stashed_strict_callable_prior(engine, &self.variants)
            } else if joined_strict {
                Self::stashed_original_type_prior(engine, &self.variants)
            } else {
                None
            }
        });
        let execution = if let Some(shared) = &self.shared_executors {
            HostExecution::Leased(shared.checkout(workers)?)
        } else if self.memo.is_some() {
            if self
                .executor
                .as_ref()
                .is_some_and(|pool| pool.workers() != workers.max(1))
            {
                drop(self.executor.take());
            }
            if self.executor.is_none() {
                self.executor = Some(dm_exec::BuildExecutor::new_unbound(workers)?);
            }
            HostExecution::Retained(self.executor.as_mut().expect("retained pool"))
        } else {
            HostExecution::OneShot(dm_exec::BuildExecutor::new(workers)?)
        };
        let memo = match &self.memo {
            Some(resident) => Some(resident.with_disk(disk)),
            None => disk.map(memo::MemoView::disk_only),
        };
        Ok(((memo, execution, self.semantic.as_mut()), prior))
    }

    fn stashed_strict_callable_prior<'a>(
        original: &RetainedEngine,
        variants: &'a BTreeMap<EngineConfiguration, VariantState>,
    ) -> Option<&'a dm_tree::frontend::RetainedSemanticTree> {
        use crate::policy_request::AnalysisContext;
        let original_configuration = &original.configuration;
        if original_configuration.analysis_context != Some(AnalysisContext::OriginalChecker0290)
            || !original_configuration.defines.is_empty()
        {
            return None;
        }
        let mut strict_configuration = original_configuration.clone();
        strict_configuration.analysis_context = None;
        // Original uses its own initial environment. The ordinary default
        // compiler variant already has these exact target defines admitted.
        crate::pinned_target::admit_defines(&mut strict_configuration.defines).ok()?;
        let strict = variants.get(&strict_configuration)?;
        if !Arc::ptr_eq(&original.payload, &strict.engine.payload) {
            return None;
        }
        let semantic = strict.semantic.as_ref()?;
        semantic.has_current_strict_callable_anchors(&strict_configuration.project, &strict_configuration.defines)
            .then_some(semantic)
    }

    fn stashed_original_type_prior<'a>(
        strict: &RetainedEngine,
        variants: &'a BTreeMap<EngineConfiguration, VariantState>,
    ) -> Option<&'a dm_tree::frontend::RetainedSemanticTree> {
        use crate::policy_request::AnalysisContext;
        let current = &strict.configuration;
        if current.analysis_context.is_some() {
            return None;
        }
        let mut expected = BTreeMap::new();
        crate::pinned_target::admit_defines(&mut expected).ok()?;
        if current.defines != expected {
            return None;
        }
        let mut key = current.clone();
        key.analysis_context = Some(AnalysisContext::OriginalChecker0290);
        key.defines.clear();
        let original = variants.get(&key)?;
        if !Arc::ptr_eq(&strict.payload, &original.engine.payload) {
            return None;
        }
        original.semantic.as_ref()
    }

    /// Leave the current variant (stash its define-dependent state) and enter `configuration` (restore it, or start it empty on the
    /// shared engine payload). Never touches the define-independent owners.
    fn switch_variant(&mut self, configuration: EngineConfiguration) -> Arc<RetainedEngine> {
        let leaving = self.engine.take().expect("a retained engine is being left");
        let semantic_enabled = self.semantic.is_some();
        let stash = VariantState {
            engine: Arc::clone(&leaving),
            procedures: self.procedures.take(),
            semantic: self.semantic.take(),
            query_state: std::mem::take(&mut self.query_state),
            maps: self.maps.take(),
            initializers: self.initializers.take(),
            startup: self.startup.take(),
            abi: self.abi.take(),
            initializer_fragments: self.initializer_fragments.take(),
            initializer_assemblies: self.initializer_assemblies.take(),
            class_projections: self.class_projections.take(),
            required_types: self.required_types.take(),
            link_bindings: self.link_bindings.take(),
            stages: self.stages.take(),
            generation: self.generation.take(),
            host_facts: self.host_facts.take(),
            resources: self.resources.take(),
            symbolic: self.symbolic.take(),
        };
        self.variants.insert(leaving.configuration.clone(), stash);
        // A bounded number of variants stay: the session is "this tree under a few define sets" (production, test, bench).
        // The variant being entered leaves the stash below, so it is never the one dropped here.
        while self.variants.len()
            > MAX_STASHED_VARIANTS + usize::from(self.variants.contains_key(&configuration))
        {
            let Some(victim) = self
                .variants
                .keys()
                .find(|key| **key != configuration)
                .cloned()
            else {
                break;
            };
            if let Some(state) = self.variants.remove(&victim) {
                Self::spill_generation(state.generation.as_ref());
            }
        }
        let retained = if let Some(state) = self.variants.remove(&configuration) {
            let engine = Arc::clone(&state.engine);
            self.procedures = state.procedures;
            self.semantic = state.semantic;
            self.query_state = state.query_state;
            self.maps = state.maps;
            self.initializers = state.initializers;
            self.startup = state.startup;
            self.abi = state.abi;
            self.initializer_fragments = state.initializer_fragments;
            self.initializer_assemblies = state.initializer_assemblies;
            self.class_projections = state.class_projections;
            self.required_types = state.required_types;
            self.link_bindings = state.link_bindings;
            self.stages = state.stages;
            self.generation = state.generation;
            self.host_facts = state.host_facts;
            self.resources = state.resources;
            self.symbolic = state.symbolic;
            engine
        } else {
            let retained = Arc::new(RetainedEngine {
                configuration,
                payload: Arc::clone(&leaving.payload),
            });
            if semantic_enabled {
                // Not seeded from the left variant's frontend: measured, that adopted 4660 subtrees of the test world
                // but cost more (rebased environments, +0.14 GB; frontend 7.4 s against 6.0 s) than the disk expansion
                // memo already saves (doc/incremental_core.md, step 5).
                self.semantic = Some(
                    dm_tree::frontend::RetainedSemanticTree::with_shared_normalized(Arc::clone(
                        &retained.payload.normalized,
                    )),
                );
            }
            retained
        };
        self.engine_generation = self.engine_generation.saturating_add(1);
        self.rich_generation = self.rich_generation.saturating_add(1);
        self.engine = Some(Arc::clone(&retained));
        retained
    }
    /// Borrow decoded data only from a same-project Original variant the
    /// ordinary engine switch actually retained. The request borrows the
    /// roster without keeping its variant, archive, or semantic tree alive.
    pub(crate) fn retained_original_decoded_sources(
        &self, project: &std::path::Path,
    ) -> Option<dm_tree::frontend::DecodedSourceCandidates> {
        use crate::policy_request::AnalysisContext;
        self.variants.iter().find_map(|(key, variant)| {
            if key.project != project || key.analysis_context != Some(AnalysisContext::OriginalChecker0290) {
                return None;
            }
            variant.semantic.as_ref()?.with_remembered_analysis_source(
                |view| view.complete_original_decoded_sources(),
            ).ok().flatten().flatten()
        })
    }

    /// True when the active variant is this manifest under exactly these defines. A session holds several variants; queries read
    /// the active one, so a query for another variant must say so instead of answering from the wrong tree.
    pub(crate) fn serves_variant(
        &self,
        project: &std::path::Path,
        defines: &BTreeMap<String, String>,
    ) -> bool {
        self.serves_variant_context(project,defines,None)
    }
    pub(crate) fn serves_variant_context(&self,project:&std::path::Path,defines:&BTreeMap<String,String>,analysis_context:Option<crate::policy_request::AnalysisContext>)->bool{
        if self.query_state.lock().ok().is_some_and(|state|state.raw_snapshot.as_ref().is_some_and(|raw|raw.matches_context(project,defines,analysis_context))){return true}
        if self.engine.as_ref().is_some_and(|engine|engine.configuration.analysis_context!=analysis_context.map(|context|context.frontend_context())){return false}
        if analysis_context==Some(crate::policy_request::AnalysisContext::OriginalAnalyze0290){return defines.is_empty()&&self.query_state.lock().ok().and_then(|state|state.snapshot.as_ref().map(|snapshot|snapshot.matches_original_analysis_subject(project))).unwrap_or(false)}
        if analysis_context.is_some(){return defines.is_empty()&&self.engine.as_ref().is_some_and(|engine|engine.configuration.defines.is_empty()&&engine.configuration.project.file_name()==project.file_name())}
        // A build admits the pinned target defines (DM_VERSION, DM_BUILD) before it reaches the host; a query names the
        // caller's defines, so admit them the same way before comparing.
        let mut admitted = defines.clone();
        if crate::pinned_target::admit_defines(&mut admitted).is_err() {
            return false;
        }
        self.engine.as_ref().is_none_or(|engine| {
            (engine.configuration.defines == admitted || &engine.configuration.defines == defines)
                && engine.configuration.project.file_name() == project.file_name()
        })
    }
    /// How many other variants this session keeps stashed.
    pub(crate) fn stashed_variants(&self) -> usize {
        self.variants.len()
    }
    /// Drop every stashed variant (their state is recomputable, and each one's patch base is stored first so the next
    /// compile of that variant patches). Returns how many were dropped.
    pub(crate) fn release_stashed_variants(&mut self) -> usize {
        self.spill_stashed_patch_bases();
        let dropped = self.variants.len();
        self.variants.clear();
        dropped
    }
    /// Store one generation's patch base (`variant_spill`), for a state about to be dropped.
    fn spill_generation(generation: Option<&(u128, Arc<crate::composition::RetainedGeneration>)>) {
        if let Some((_, generation)) = generation {
            generation.spill_patch_base(SPILL_WORKERS);
        }
    }
    fn spill_stashed_patch_bases(&self) {
        for state in self.variants.values() {
            Self::spill_generation(state.generation.as_ref());
        }
    }
    /// Store the patch base of the active variant and of every stashed one, before the session or its compiler artifacts
    /// are released. A base already stored is not written again.
    pub(crate) fn spill_patch_bases(&self) {
        Self::spill_generation(self.generation.as_ref());
        self.spill_stashed_patch_bases();
    }

    pub(crate) fn engine(
        &mut self,
        project: PathBuf,
        defines: BTreeMap<String, String>,
        bootstrap_catalog: bool,
        bytes: Vec<u8>,
    ) -> Result<Arc<RetainedEngine>, String> {
        self.engine_with_context(project,defines,bootstrap_catalog,bytes,None)
    }
    pub(crate) fn engine_with_context(
        &mut self, project:PathBuf, defines:BTreeMap<String,String>,
        bootstrap_catalog:bool, bytes:Vec<u8>,
        analysis_context:Option<crate::policy_request::AnalysisContext>,
    )->Result<Arc<RetainedEngine>,String>{
        let configuration = EngineConfiguration {
            analysis_context:analysis_context.map(|context|context.frontend_context()),
            project,
            defines,
            bootstrap_catalog,
            schema: 1,
        };
        if let Some(retained) = &self.engine {
            // A digest is never sufficient admission for this retained owner.
            if retained.configuration == configuration && retained.bytes.as_ref() == bytes {
                return Ok(Arc::clone(retained));
            }
            // Same engine bytes, bootstrap and schema, a different project path or define set: this is a variant switch, not a
            // new compiler. The define-independent owners stay; the define-dependent state of the variant being left is kept
            // under its configuration, and the target variant's own state (patch base included) is brought back if this
            // session has built it before.
            if retained.bytes.as_ref() == bytes
                && retained.configuration.bootstrap_catalog == configuration.bootstrap_catalog
                && retained.configuration.schema == configuration.schema
            {
                return Ok(self.switch_variant(configuration));
            }
        }
        self.variants.clear();
        let payload = if let Some(shared) = &self.shared_engines {
            shared.capture(
                bytes,
                configuration.schema,
                bootstrap_catalog,
                crate::daemon::compiler_identity().map_err(|error| error.to_string())?,
            )?
        } else {
            engine_payload::EnginePayload::capture(
                bytes,
                configuration.schema,
                bootstrap_catalog,
                0,
            )?
        };
        let retained = Arc::new(RetainedEngine {
            configuration,
            payload,
        });
        self.reset_memo();
        self.engine_generation = self.engine_generation.saturating_add(1);
        self.rich_generation = self.rich_generation.saturating_add(1);
        self.procedures = None;
        self.symbolic = None;
        self.initializers = None;
        self.startup = None;
        self.abi = None;
        self.initializer_fragments = None;
        self.initializer_assemblies = None;
        self.class_projections = None;
        self.required_types = None;
        self.link_bindings = None;
        self.stages = None;
        self.generation = None;
        self.host_facts = None;
        self.resources = None;
        self.maps = None;
        if self.semantic.is_some() {
            self.semantic = Some(
                dm_tree::frontend::RetainedSemanticTree::with_shared_normalized(Arc::clone(
                    &retained.payload.normalized,
                )),
            );
            *self
                .query_state
                .lock()
                .unwrap_or_else(|error| error.into_inner()) = Default::default();
        }
        self.engine = Some(Arc::clone(&retained));
        Ok(retained)
    }
}

pub(crate) enum HostExecution<'a> {
    Leased(executor_pool::ExecutorLease),
    OneShot(dm_exec::BuildExecutor),
    Retained(&'a mut dm_exec::BuildExecutor),
}
impl HostExecution<'_> {
    pub(crate) fn run<R>(
        self,
        operation: impl FnOnce(&dm_exec::BuildExecutor) -> R,
    ) -> Result<R, dm_exec::RequestError> {
        let control = crate::daemon::control::WorkerContext::capture();
        let enter = || -> Result<_, String> { Ok(control.as_ref().map(|context| context.enter())) };
        match self {
            Self::Leased(mut lease) => {
                let request = dm_profile::RequestContext::capture();
                lease
                    .executor()
                    .with_request_context(request.as_ref(), enter, operation)
            }
            Self::OneShot(mut executor) => executor.with_request_context(None, enter, operation),
            Self::Retained(executor) => {
                let request = dm_profile::RequestContext::capture();
                executor.with_request_context(request.as_ref(), enter, operation)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    fn capture(host: &mut BuildHost, defines: BTreeMap<String, String>) -> Arc<RetainedEngine> {
        host.engine(
            PathBuf::from("E:/fixture/world.dme"),
            defines,
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap()
    }
    #[test]
    fn daemon_hosts_share_engine_payload_but_keep_configuration_and_state_separate() {
        let shared = Arc::new(EnginePayloads::default());
        let mut a = BuildHost::with_shared_engines(Arc::clone(&shared));
        let mut b = BuildHost::with_shared_engines(shared);
        let first = capture(&mut a, BTreeMap::new());
        let second = b
            .engine(
                PathBuf::from("E:/fixture/other-worktree/world.dme"),
                BTreeMap::from([("LOCAL_DEFINE".into(), "1".into())]),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        assert!(!Arc::ptr_eq(&first, &second));
        assert!(Arc::ptr_eq(&first.payload, &second.payload));
        assert_ne!(first.configuration.project, second.configuration.project);
        let a_memo = a.procedure_memo(1, 1, None, true).unwrap();
        let b_memo = b.procedure_memo(1, 1, None, true).unwrap();
        assert!(!Arc::ptr_eq(&a_memo.values, &b_memo.values));
    }
    #[test]
    fn a_variant_switch_keeps_each_variants_state_and_shares_the_engine_payload() {
        let mut host = BuildHost::with_shared_engines(Arc::new(EnginePayloads::default()));
        let testing = || BTreeMap::from([("CITESTING".to_string(), "1".to_string())]);
        let production = capture(&mut host, BTreeMap::new());
        let maps = |policy| {
            Some((
                policy,
                Arc::new(crate::map_memo::RetainedMaps::current_revision()),
            ))
        };
        host.maps = maps(7);
        // The test define set is another variant of the same session: its own empty state, the same engine payload.
        let test = capture(&mut host, testing());
        assert!(!Arc::ptr_eq(&production, &test));
        assert!(Arc::ptr_eq(&production.payload, &test.payload));
        assert!(
            host.maps.is_none(),
            "a new variant starts with no define-dependent state"
        );
        assert!(host.semantic.is_some());
        host.maps = maps(9);
        // Switching back resumes production's state (its patch base lives there), not a fresh one.
        let back = capture(&mut host, BTreeMap::new());
        assert!(Arc::ptr_eq(&back, &production));
        assert_eq!(host.maps.as_ref().map(|(policy, _)| *policy), Some(7));
        let again = capture(&mut host, testing());
        assert!(Arc::ptr_eq(&again, &test));
        assert_eq!(host.maps.as_ref().map(|(policy, _)| *policy), Some(9));
        assert!(host.serves_variant(std::path::Path::new("E:/fixture/world.dme"), &testing()));
        assert!(!host.serves_variant(
            std::path::Path::new("E:/fixture/world.dme"),
            &BTreeMap::new()
        ));
        // Stashed variants are recomputable and go first under pressure.
        assert_eq!(host.release_stashed_variants(), 1);
        let cold = capture(&mut host, BTreeMap::new());
        assert!(!Arc::ptr_eq(&cold, &production));
        assert!(host.maps.is_none());
    }
    fn worker_ids(
        executor: &dm_exec::BuildExecutor,
    ) -> std::collections::HashSet<std::thread::ThreadId> {
        let barrier = std::sync::Barrier::new(executor.workers());
        let ids = Mutex::new(std::collections::HashSet::new());
        executor.scope(|scope| {
            for _ in 0..executor.workers() {
                let barrier = &barrier;
                let ids = &ids;
                scope.spawn(move |_| {
                    ids.lock().unwrap().insert(std::thread::current().id());
                    barrier.wait();
                });
            }
        });
        ids.into_inner().unwrap()
    }
    #[test]
    fn six_daemon_hosts_share_one_returned_pool_without_retaining_host_pools() {
        let engines = Arc::new(EnginePayloads::default());
        let pools = Arc::new(ExecutorPools::default());
        let mut hosts = (0..6)
            .map(|_| {
                BuildHost::with_daemon_owners(
                    Arc::clone(&engines),
                    Arc::clone(&pools),
                    Arc::new(Default::default()),
                    Arc::new(Default::default()),
                )
            })
            .collect::<Vec<_>>();
        let mut prior = None;
        for host in &mut hosts {
            let (_, execution, _) = host.execution(2, None).unwrap();
            let ids = execution.run(worker_ids).unwrap();
            if let Some(prior) = &prior {
                assert_eq!(prior, &ids);
            }
            prior = Some(ids);
            assert!(host.executor.is_none());
            assert_eq!(pools.physical_workers(), 2);
        }
        pools.trim(std::time::Instant::now(), true);
        assert_eq!(pools.physical_workers(), 0);
    }
    #[test]
    fn procedure_facades_share_only_values_and_policy_change_replaces_store() {
        let mut host = BuildHost::default();
        let first = host.procedure_memo(1, 1, None, true).unwrap();
        first
            .counts
            .resident_hits
            .store(7, std::sync::atomic::Ordering::Relaxed);
        let second = host.procedure_memo(1, 1, None, true).unwrap();
        assert!(Arc::ptr_eq(&first.values, &second.values));
        assert_eq!(
            second
                .counts
                .resident_hits
                .load(std::sync::atomic::Ordering::Relaxed),
            0
        );
        let changed = host.procedure_memo(2, 2, None, true).unwrap();
        assert!(!Arc::ptr_eq(&first.values, &changed.values));
        let mut one_shot = BuildHost::one_shot();
        let request = one_shot.procedure_memo(1, 1, None, true).unwrap();
        assert!(request.initializer_fragments.is_some());
        assert!(request.initializer_assemblies.is_some());
        assert!(one_shot.procedures.is_none());
        assert!(one_shot.initializer_fragments.is_none());
    }
    #[test]
    fn retained_requests_reuse_physical_workers_and_count_switch_replaces_them() {
        let mut host = BuildHost::default();
        assert!(host.executor.is_none());
        let (_, execution, _) = host.execution(2, None).unwrap();
        let first = execution.run(worker_ids).unwrap();
        assert_eq!(first.len(), 2);
        let (_, execution, _) = host.execution(2, None).unwrap();
        let second = execution.run(worker_ids).unwrap();
        assert_eq!(first, second);
        let (_, execution, _) = host.execution(1, None).unwrap();
        let changed = execution.run(worker_ids).unwrap();
        assert_eq!(changed.len(), 1);
        assert!(first.is_disjoint(&changed));
    }
    #[test]
    fn retained_request_panic_unbinds_before_next_request() {
        let mut host = BuildHost::default();
        let failure = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let (_, execution, _) = host.execution(1, None).unwrap();
            let _ = execution.run(|executor| {
                executor.scope(|scope| scope.spawn(|_| panic!("scoped request failure")))
            });
        }));
        assert!(failure.is_err());
        let (_, execution, _) = host.execution(1, None).unwrap();
        assert_eq!(execution.run(worker_ids).unwrap().len(), 1);
    }
    #[test]
    fn one_shot_without_disk_has_no_expansion_memo_or_retained_procedure_owner() {
        let mut host = BuildHost::one_shot();
        assert!(host.expansion_memo(None).is_none());
        let no_engine = host.procedure_memo(1, 1, None, true).unwrap();
        assert!(no_engine.abi.as_ref().unwrap().engine_owner().is_none());
        let engine = capture(&mut host, BTreeMap::new());
        let request = host.procedure_memo(1, 1, None, true).unwrap();
        let abi = request.abi.as_ref().unwrap();
        assert!(Arc::ptr_eq(
            abi.engine_owner().unwrap(),
            &engine.abi_engine_owner(),
        ));
        let next_request = host.procedure_memo(1, 1, None, true).unwrap();
        assert!(!Arc::ptr_eq(abi, next_request.abi.as_ref().unwrap()));
        assert!(Arc::ptr_eq(
            abi.engine_owner().unwrap(),
            next_request.abi.as_ref().unwrap().engine_owner().unwrap(),
        ));
        assert!(
            host.abi.is_none(),
            "one-shot ABI owner belongs to the request"
        );
        assert!(request.initializer_fragments.is_some());
        assert!(request.initializer_assemblies.is_some());
        assert!(host.procedures.is_none());
        assert!(host.expansion_memo(None).is_none());
        host.clear_regions();
        assert!(host.expansion_memo(None).is_none());
        assert!(BuildHost::default().expansion_memo(None).is_some());
    }
    #[test]
    fn maps_retain_one_policy_owner_without_retaining_request_disk_snapshots() {
        let mut host = BuildHost::default();
        capture(&mut host, BTreeMap::new());
        assert!(host.map_memo(1, None, true).is_some());
        let first = Arc::clone(&host.maps.as_ref().unwrap().1);
        assert!(host.map_memo(1, None, true).is_some());
        assert!(Arc::ptr_eq(&first, &host.maps.as_ref().unwrap().1));
        assert!(host.map_memo(2, None, true).is_some());
        assert!(!Arc::ptr_eq(&first, &host.maps.as_ref().unwrap().1));
        capture(&mut host, BTreeMap::from([("MODE".into(), "1".into())]));
        assert!(host.maps.is_none());
        let mut one_shot = BuildHost::one_shot();
        assert!(one_shot.map_memo(1, None, true).is_some());
        assert!(one_shot.maps.is_none(), "map ownership is request-local");
    }
    #[test]
    fn map_analysis_does_not_supersede_pending_build_publication() {
        let mut host = BuildHost::default();
        let build = host.map_memo(1, None, true).unwrap();
        let analysis = host.map_memo(1, None, false).unwrap();
        assert!(!analysis.publish_successful());
        assert!(build.publish_successful());
        assert!(!build.publish_successful());
    }
    #[test]
    fn exact_configuration_reuses_owner_and_request_overlay_is_independent() {
        let mut host = BuildHost::default();
        let first = capture(&mut host, BTreeMap::new());
        assert!(first.links.lock().unwrap().is_none());
        let mut overlay = first.link_overlay().unwrap();
        let expected_entries = overlay.inventory.entries.len();
        let expected_references = overlay.references.references.len();
        assert!(expected_entries > 0);
        overlay.inventory.entries.clear();
        overlay.references.references.clear();
        let second = capture(&mut host, BTreeMap::new());
        assert!(Arc::ptr_eq(&first, &second));
        assert!(std::ptr::eq(first.frontend_seed(), second.frontend_seed()));
        assert_eq!(second.frontend_seed().identity, second.snapshot.identity());
        let independent = second.link_overlay().unwrap();
        assert_eq!(independent.inventory.entries.len(), expected_entries);
        assert_eq!(independent.references.references.len(), expected_references);
        let changed = capture(
            &mut host,
            BTreeMap::from([("CITESTING".into(), "1".into())]),
        );
        assert!(!Arc::ptr_eq(&first, &changed));
    }
    #[test]
    fn invalid_changed_engine_does_not_replace_authenticated_owner() {
        let mut host = BuildHost::default();
        let first = capture(&mut host, BTreeMap::new());
        assert!(host
            .engine(
                PathBuf::from("E:/fixture/world.dme"),
                BTreeMap::new(),
                true,
                vec![0]
            )
            .is_err());
        let again = capture(&mut host, BTreeMap::new());
        assert!(Arc::ptr_eq(&first, &again));
    }
    #[test]
    fn generation_is_session_local_policy_scoped_and_reset_by_exact_engine_change() {
        let mut host = BuildHost::default();
        capture(&mut host, BTreeMap::new());
        let first = host.generation(1).unwrap();
        assert!(Arc::ptr_eq(&first, &host.generation(1).unwrap()));
        let changed_policy = host.generation(2).unwrap();
        assert!(!Arc::ptr_eq(&first, &changed_policy));
        capture(
            &mut host,
            BTreeMap::from([("CITESTING".into(), "1".into())]),
        );
        assert!(!Arc::ptr_eq(&changed_policy, &host.generation(2).unwrap()));
        assert!(BuildHost::one_shot().generation(1).is_none());
    }
}

#[cfg(test)]
#[path = "runner_host_callable_tests.rs"]
mod callable_tests;

#[cfg(test)]
#[path = "runner_host_callable_failure_tests.rs"]
mod callable_failure_tests;
/// Diagnostic split of this process's directive memo lookups since the last call.
pub(crate) fn memo_lookups_report() -> String {
    memo::DIRECTIVE_LOOKUPS.report()
}

impl BuildHost {
 /// Evaluate the selected Derived report against this host's actual prepared
 /// source, in process. This lends report DATA only; no query/source authority
 /// or private constructor is exposed. It performs no build or publication.
 pub fn with_prepared_derived_report<R>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config)->std::io::Result<R>)->std::io::Result<R>{
  self.with_prepared_derived_report_to(request,prepared,&mut crate::daemon::stderr_writer(),consume)
 }
 pub fn with_prepared_derived_report_to<R>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config)->std::io::Result<R>)->std::io::Result<R>{
  crate::daemon::control::checkpoint()?;
  // A reentrant report callback is refused instead of blocking on itself.
  let state=self.query_state.try_lock().map_err(|error|match error{std::sync::TryLockError::WouldBlock=>std::io::Error::new(std::io::ErrorKind::WouldBlock,"prepared report query state is already borrowed"),std::sync::TryLockError::Poisoned(_)=>std::io::Error::other("prepared report query state poisoned")})?;
  let snapshot=state.snapshot.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::NotFound,"prepared report has no actual semantic source"))?;
  snapshot.with_prepared_derived_request(request,prepared,diagnostics,consume)
 }
}

impl BuildHost{
 /// Borrow the host's EXISTING native input-family resource lender. This trait
 /// supplies funding only, never QueryDb/source/witness constructors. No lock
 /// is held across this loan; individual reservations enforce their own domain.
 pub fn source_arena_work(&self)->&dyn dm_preprocess::source_arena_credit::SourceArenaWork{self.query_db.as_ref()}
}

#[path="runner_derived_attempt_report.rs"]mod derived_attempt_report;
pub use derived_attempt_report::{DerivedAttemptReport,FundedDerivedAttemptReport,ReportPayload};

impl BuildHost{
 /// Explicit source-query pressure tier. This can only discard optional
 /// capabilities; no source/result identity or synthetic completeness is issued.
 pub fn release_optional_query_sources(&mut self)->std::io::Result<()>{
  let mut state=self.query_state.try_lock().map_err(|error|match error{std::sync::TryLockError::WouldBlock=>std::io::Error::new(std::io::ErrorKind::WouldBlock,"query sources are currently borrowed"),std::sync::TryLockError::Poisoned(_)=>std::io::Error::other("query source state poisoned")})?;
  if let Some(snapshot)=state.snapshot.as_mut(){snapshot.release_body_queries()}Ok(())
 }
}

impl BuildHost{
 /// Report DATA from this host's current distinct Handler source owner. This
 /// cannot turn a supplied revision or absent semantic model into authority.
 pub fn with_prepared_handlers_report<T>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,consume:impl FnOnce(&dq_analyze::captured_sem_handlers::Data,&dq_analyze::captured_raw_file::Config)->std::io::Result<T>)->std::io::Result<T>{self.with_prepared_handlers_report_to(request,prepared,&mut crate::daemon::stderr_writer(),consume)}
 pub fn with_prepared_handlers_report_to<T>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_sem_handlers::Data,&dq_analyze::captured_raw_file::Config)->std::io::Result<T>)->std::io::Result<T>{
  self.with_prepared_handlers_report_budget_to(request,prepared,diagnostics,|data,config,_|consume(data,config))
 }
 pub(crate) fn with_prepared_handlers_report_budget_to<T>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_sem_handlers::Data,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<T>)->std::io::Result<T>{
  crate::daemon::control::checkpoint()?;
  let state=self.query_state.try_lock().map_err(|error|match error{std::sync::TryLockError::WouldBlock=>std::io::Error::new(std::io::ErrorKind::WouldBlock,"prepared handlers query state is already borrowed"),std::sync::TryLockError::Poisoned(_)=>std::io::Error::other("prepared handlers query state poisoned")})?;
  let handlers=state.handlers_snapshot.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::NotFound,"prepared report has no actual Handler source"))?;
  handlers.with_prepared_report(request,prepared,state.snapshot.as_ref(),diagnostics,consume)
 }
}

#[path="runner_handlers_attempt_report.rs"]mod handlers_attempt_report;
pub use handlers_attempt_report::HandlersAttemptReport;

impl BuildHost{
 pub(crate) fn with_prepared_derived_report_budget_to<R>(&self,request:&crate::request::BuildRequest,prepared:&crate::request::BuildOutcome,diagnostics:&mut impl std::io::Write,consume:impl FnOnce(&dq_analyze::captured_derived_reads::DerivedReadData,&dq_analyze::captured_raw_file::Config,&Arc<dq_analyze::captured_generator_budget::Budget>)->std::io::Result<R>)->std::io::Result<R>{
  crate::daemon::control::checkpoint()?;let state=self.query_state.try_lock().map_err(|_|std::io::Error::new(std::io::ErrorKind::WouldBlock,"prepared report query state already borrowed"))?;let snapshot=state.snapshot.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::NotFound,"prepared report has no actual source"))?;snapshot.with_prepared_derived_request_budget(request,prepared,diagnostics,consume)
 }
}

impl BuildHost{
 /// Resource admission diagnostic only (not heap/RSS or a source/completion
 /// grant). Refreshes existing weak reservations without constructing a model.
 pub fn source_input_admission_bytes(&self)->std::io::Result<usize>{self.query_db.source_input_admission_bytes()}
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SelectedReportMode {
    Ordinary,
    Combined,
    GenericV2(dq_analyze::selected_exclusions_wire::JudgmentV2),
}

const SELECTED_REPORT_RETAINED: usize = 1024 * 1024;
impl BuildHost {
    /// Standalone read-only native ImageDir report. No generic workspace
    /// snapshot, exclusion roster, compiler or checker publication is issued.
    pub fn write_original_image_dir_report(
        &mut self, root:&std::path::Path, cache:&std::path::Path, timeout_seconds:u16,
        output:&mut impl std::io::Write,
    )->std::io::Result<bool>{
        self.with_original_image_dir_report_using(root,cache,timeout_seconds,|terminal,report,_credit|{
            crate::daemon::control::begin_publication()?;
            report.publish(output)?;
            Ok(terminal.clean)
        })
    }

    pub(crate) fn with_original_image_dir_report_using<T>(
        &mut self, root:&std::path::Path, cache:&std::path::Path, timeout_seconds:u16,
        finish:impl FnOnce(
            dq_analyze::selected_exclusions_wire::NamedImageDirTerminal,
            crate::selected_report_spool::Verified,
            dm_preprocess::source_arena_credit::SourceArenaCredit,
        )->std::io::Result<T>,
    )->std::io::Result<T>{
        use crate::input_snapshot::NamedImageDirNoticeMode;
        use dq_analyze::selected_exclusions_wire::{NamedImageDirSchema,NamedImageDirTerminal};
        self.with_staged_original_image_dir_using(root,cache,timeout_seconds,NamedImageDirNoticeMode::Forbid,
            |frame,clean,diagnostics,report,credit| {
                if diagnostics.is_some() {
                    return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"notice-free ImageDir acquired diagnostics"));
                }
                let terminal=NamedImageDirTerminal{schema:NamedImageDirSchema::V1,frame,clean,report:image_dir_stream_seal(&report)};
                terminal.require()?;
                finish(terminal,report,credit)
            })
    }

    /// Stage both outputs, validate the same input receipt, and only then
    /// publish the Original warnings/hints and exact policy report separately.
    pub fn write_original_image_dir_report_with_notices(
        &mut self, root:&std::path::Path, cache:&std::path::Path, timeout_seconds:u16,
        diagnostics:&mut impl std::io::Write, output:&mut impl std::io::Write,
    )->std::io::Result<bool>{
        self.with_original_image_dir_notices_using(root,cache,timeout_seconds,|terminal,notice_spool,report,_credit|{
            crate::daemon::control::begin_publication()?;
            if let Some(notices)=notice_spool { notices.publish(diagnostics)?; }
            report.publish(output)?;
            Ok(terminal.clean)
        })
    }

    pub(crate) fn with_original_image_dir_notices_using<T>(
        &mut self, root:&std::path::Path, cache:&std::path::Path, timeout_seconds:u16,
        finish:impl FnOnce(
            dq_analyze::selected_exclusions_wire::NamedImageDirNoticeTerminal,
            Option<crate::selected_report_spool::Verified>,
            crate::selected_report_spool::Verified,
            dm_preprocess::source_arena_credit::SourceArenaCredit,
        )->std::io::Result<T>,
    )->std::io::Result<T>{
        use crate::input_snapshot::NamedImageDirNoticeMode;
        use dq_analyze::selected_exclusions_wire::{NamedImageDirNoticeSchema,NamedImageDirNoticeTerminal};
        self.with_staged_original_image_dir_using(root,cache,timeout_seconds,NamedImageDirNoticeMode::WarningsAndHints,
            |frame,clean,diagnostics,report,credit| {
                let terminal=NamedImageDirNoticeTerminal{schema:NamedImageDirNoticeSchema::V1,frame,clean,
                    diagnostics:diagnostics.as_ref().map(image_dir_stream_seal),report:image_dir_stream_seal(&report)};
                terminal.require()?;
                finish(terminal,diagnostics,report,credit)
            })
    }

    fn with_staged_original_image_dir_using<T>(
        &mut self, root:&std::path::Path, cache:&std::path::Path, timeout_seconds:u16,
        notice_mode:crate::input_snapshot::NamedImageDirNoticeMode,
        finish:impl FnOnce(
            dq_analyze::selected_exclusions_wire::Frame, bool,
            Option<crate::selected_report_spool::Verified>,
            crate::selected_report_spool::Verified,
            dm_preprocess::source_arena_credit::SourceArenaCredit,
        )->std::io::Result<T>,
    )->std::io::Result<T>{
        use crate::daemon::{control,prepare_deadline};
        use crate::input_snapshot::NamedImageDirNoticeMode;
        use dq_analyze::captured_generator_budget::Budget;
        use std::io;
        if !self.retains_artifacts() || !root.is_absolute() || !cache.is_absolute(){
            return Err(io::Error::new(io::ErrorKind::InvalidInput,"named ImageDir requires an actual resident host and absolute root/cache"));
        }
        let deadline=prepare_deadline::capture(crate::request::BuildCommand::PrepareQuery,Some(timeout_seconds),std::time::Instant::now())?
            .ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"named ImageDir requires an explicit deadline"))?;
        let _deadline=if control::WorkerContext::capture().is_none(){
            Some(control::bind_with_deadline(control::Cancellation::default(),deadline))
        }else{None};
        control::checkpoint()?;
        let path_bound=root.as_os_str().len().checked_add(cache.as_os_str().len())
            .and_then(|n|n.checked_mul(32)).and_then(|n|n.checked_add(32*1024))
            .ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
        let credit=self.source_arena_work().reserve(SELECTED_REPORT_RETAINED.checked_add(path_bound)
            .ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)?;
        let root=std::fs::canonicalize(root)?;
        let cache=std::fs::canonicalize(cache)?;
        if !root.is_dir() || !cache.is_dir() || cache.starts_with(&root)
            || root.capacity().checked_add(cache.capacity()).is_none_or(|n|n>path_bound){
            return Err(io::Error::new(io::ErrorKind::InvalidInput,"named ImageDir requires an existing cache outside its workspace"));
        }
        let capture=crate::input_snapshot::NamedImageDirCapture::prepare(&root,self.query_db(),notice_mode)?;
        let budget=Budget::new(SELECTED_REPORT_RETAINED).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
        let (clean,report)=query_snapshot::stage_named_image_dir(
            &capture.frontend,&root,&capture.config,&budget,crate::selected_report_spool::Stage::new(&cache)?,
        )?;
        let diagnostics=match notice_mode {
            NamedImageDirNoticeMode::Forbid => None,
            NamedImageDirNoticeMode::WarningsAndHints => capture.frontend.with_original_preprocess_notices(|notices| {
                if notices.is_empty() { return Ok(None); }
                let mut stage=crate::selected_report_spool::Stage::new(&cache)?;
                crate::diagnostics::write_named_image_dir_notices(&mut stage,notices)?;
                Ok(Some(query_snapshot::checked_selected_report_stage(stage)?))
            })?,
        };
        let frame=capture.require_current(self.source_arena_work())?;
        control::checkpoint()?;
        // Keep the actual capture and budgets alive through publication.
        let result=finish(frame,clean,diagnostics,report,credit);
        drop(capture);
        result
    }
}


fn image_dir_stream_seal(stream:&crate::selected_report_spool::Verified)->dq_analyze::selected_exclusions_wire::Seal {
    use dq_analyze::selected_exclusions_wire::{Hex128,Seal};
    Seal{length:stream.length(),hash:Hex128(stream.hash())}
}

fn original_exclusions_invalid() -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::InvalidInput, "selected report requires the exact authored Original workspace request")
}

fn original_exclusions_shape(request: &crate::request::BuildRequest, roster: crate::daemon::selected_report_wire::Roster)
    -> std::io::Result<(&crate::policy_request::WorkspacePolicyRequest, &std::path::Path)>
{
    use crate::{policy_request::AnalysisContext, request::BuildCommand};
    if request.command != BuildCommand::PrepareQuery || !request.exact_inputs
        || request.no_daemon || !request.project.is_absolute() || !request.defines.is_empty()
        || request.engine_template.is_some() || request.bootstrap_catalog || request.record_inputs.is_some()
        || request.replay_inputs.is_some() || request.trace_path.is_some() || request.artifact_directory.is_some()
        || request.output_store.is_some() || request.source_questions.is_some() || request.diagnostic_declarations {
        return Err(original_exclusions_invalid());
    }
    let wanted = request.policy_inputs.as_ref().ok_or_else(original_exclusions_invalid)?;
    let workspace = wanted.workspace.as_ref().ok_or_else(original_exclusions_invalid)?;
    if wanted.analysis_context != Some(AnalysisContext::OriginalAnalyze0290) || !wanted.workspace_auxiliary.is_empty()
        || !wanted.workspace_generators.is_empty() || !wanted.files.is_empty() || !wanted.search_folders.is_empty()
        || !workspace.root.is_absolute() || !workspace.configuration.is_absolute()
        || workspace.recursive_roots.len() != roster.workspace_roots().len() || workspace.recursive_roots.iter().any(|path| !path.is_absolute()) {
        return Err(original_exclusions_invalid());
    }
    let cache = request.cache_root.as_deref().filter(|path| path.is_absolute()).ok_or_else(original_exclusions_invalid)?;
    Ok((workspace, cache))
}

impl BuildHost {
    /// Preflight the wire request before it may supersede another caller. The
    /// producer repeats these path checks under its own resource admission.
    pub(crate) fn original_exclusions_paths(
        request: &crate::request::BuildRequest, roster: crate::daemon::selected_report_wire::Roster,
    )
        -> std::io::Result<(std::path::PathBuf, std::path::PathBuf)>
    {
        let (_, cache) = original_exclusions_shape(request, roster)?;
        let intent = request.policy_inputs.as_ref().ok_or_else(original_exclusions_invalid)?.clone().admit()?;
        let workspace = intent.workspace().ok_or_else(original_exclusions_invalid)?;
        if workspace.recursive_roots.iter().zip(roster.workspace_roots()).any(|(actual, expected)| *actual != workspace.root.join(expected))
            || workspace.configuration != workspace.root.join("tools/ci/lint_scopes.toml")
            || dm_preprocess::regions::canonical_path(&request.project) != workspace.root.join("deepquarry.dme") {
            return Err(original_exclusions_invalid());
        }
        let physical_cache = std::fs::canonicalize(cache)?;
        if !physical_cache.is_dir() || physical_cache.starts_with(std::fs::canonicalize(&workspace.root)?) {
            return Err(original_exclusions_invalid());
        }
        Ok((workspace.root.clone(), physical_cache))
    }

    pub(crate) fn qualify_original_exclusions(
        exclusions: &[String], mode: SelectedReportMode,
    ) -> std::io::Result<crate::daemon::selected_report_wire::Roster> {
        Self::plan_original_exclusions(exclusions, mode).map(|plan| plan.roster())
    }

    fn plan_original_exclusions(exclusions: &[String], mode: SelectedReportMode) -> std::io::Result<query_snapshot::SelectedReportPlan> {
        use std::io::{Error, ErrorKind};
        if exclusions.len() > 256 || exclusions.iter().any(|name| name.len() > 128) {
            return Err(Error::new(ErrorKind::InvalidInput, "selected report exclusions exceed the control bound"));
        }
        let budget = dq_analyze::captured_generator_budget::Budget::new(SELECTED_REPORT_RETAINED)
            .map_err(|message| Error::new(ErrorKind::OutOfMemory, message))?;
        let plan = match mode {
            SelectedReportMode::GenericV2(judgment) =>
                query_snapshot::validate_selected_report_selection_v2(exclusions, &budget, judgment),
            _ => query_snapshot::validate_selected_report_selection(exclusions, &budget),
        }?;
        if matches!(plan.roster(), dq_analyze::selected_exclusions_wire::Roster::WithUntyped
            | dq_analyze::selected_exclusions_wire::Roster::WithStoredAndTracked)
            && mode != SelectedReportMode::Combined {
            return Err(Error::new(ErrorKind::Unsupported, "the selected semantic roster requires the combined Original Checker report"));
        }
        Ok(plan)
    }

    /// Prepare and write an explicitly qualified Original Analyze roster.
    /// Both report and preparation diagnostics are private until the actual
    /// selected producer union and unused-ALLOW audit have finished.
    pub fn write_original_exclusions_report(
        &mut self, request: crate::request::BuildRequest, exclusions: &[String],
        diagnostics: &mut impl std::io::Write, output: &mut impl std::io::Write,
    ) -> Result<bool, Box<dyn std::error::Error>> {
        use dq_analyze::selected_exclusions_wire::Roster;
        if Self::qualify_original_exclusions(exclusions, SelectedReportMode::Ordinary)? == Roster::AllRawFilePolicies {
            return self.with_raw_file_exclusions_report(request, exclusions, |_, clean, report, _credit| {
                crate::daemon::control::begin_publication()?;
                report.publish(output)?;
                Ok(clean)
            });
        }
        self.with_original_exclusions_report(request, exclusions, |_, _, clean, staged_diagnostics, report, _credit| {
            crate::daemon::control::begin_publication()?;
            if let Some(staged) = staged_diagnostics {
                staged.publish(diagnostics)?;
            }
            report.publish(output)?;
            Ok(clean)
        })
    }

    /// Closed Analyze-only raw-file roster. This prepares no compiler model and
    /// issues a RawQueryPrepared outcome for the later distinct wire route.
    pub(crate) fn with_raw_file_exclusions_report<T>(
        &mut self, mut request: crate::request::BuildRequest, exclusions: &[String],
        finish: impl FnOnce(&crate::request::BuildOutcome, bool, crate::selected_report_spool::Verified,
            dm_preprocess::source_arena_credit::SourceArenaCredit) -> std::io::Result<T>,
    ) -> Result<T, Box<dyn std::error::Error>> {
        use crate::daemon::{control, prepare_deadline};
        use dq_analyze::{captured_generator_budget::Budget, selected_exclusions_wire::Roster};
        use std::io;
        if !self.retains_artifacts() { return Err(original_exclusions_invalid().into()); }
        let plan = Self::plan_original_exclusions(exclusions, SelectedReportMode::Ordinary)?;
        if plan.roster() != Roster::AllRawFilePolicies { return Err(original_exclusions_invalid().into()); }
        let (workspace, cache) = original_exclusions_shape(&request, plan.roster())?;
        let _deadline = if control::WorkerContext::capture().is_none() {
            prepare_deadline::capture(request.command, request.timeout_seconds, std::time::Instant::now())?
                .map(|deadline| control::bind_with_deadline(control::Cancellation::default(), deadline))
        } else { None };
        control::checkpoint()?;
        let metadata = workspace.recursive_roots.iter().map(|path| path.as_os_str())
            .chain([cache.as_os_str(), request.project.as_os_str(), workspace.root.as_os_str(), workspace.configuration.as_os_str()])
            .try_fold(0usize, |total, value| total.checked_add(value.len()))
            .and_then(|n| n.checked_mul(32)).and_then(|n| n.checked_add(32 * 1024))
            .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?;
        let total = SELECTED_REPORT_RETAINED.checked_add(metadata).ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?;
        let credit = self.source_arena_work().reserve(total)?;
        let (root, physical_cache) = Self::original_exclusions_paths(&request, plan.roster())?;
        request.policy_inputs.as_mut().ok_or_else(original_exclusions_invalid)?.workspace_auxiliary =
            vec![crate::policy_request::WorkspaceAuxiliaryQuestion::AllRawFilePolicies];
        let retained = Budget::new(SELECTED_REPORT_RETAINED).map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?;
        let stage = crate::selected_report_spool::Stage::new(&physical_cache)?;
        let prepared = crate::request_runner::run_build_with_host(request, self)?;
        let (clean, verified) = {
            let state = self.query_state.try_lock().map_err(|_| io::Error::new(io::ErrorKind::WouldBlock, "selected raw-file query state is borrowed"))?;
            let raw = state.raw_snapshot.as_ref().ok_or_else(|| io::Error::other("selected raw-file report has no current source-only snapshot"))?;
            raw.stage_raw_file_report(&prepared, exclusions, &retained, &root, &plan, stage)?
        };
        Ok(finish(&prepared, clean, verified, credit)?)
    }

    /// One actual complete Original source preparation, with separately
    /// admitted checker and Analyze policies. All transcripts are verified
    /// before either tool receives bytes. The bool combines the Analyze result
    /// and severity status from the selected ordered Checker phases.
    pub fn write_combined_selected_original_reports(
        &mut self, request: crate::request::BuildRequest, exclusions: &[String],
        diagnostics: &mut impl std::io::Write, checker: &mut impl std::io::Write,
        analyze: &mut impl std::io::Write,
    )->Result<bool,Box<dyn std::error::Error>>{
        self.with_selected_original_reports_using(request,exclusions,SelectedReportMode::Combined,|_,_,clean,notices,checker_report,report,_credit|{
            let (_,checker_report)=checker_report.ok_or_else(||std::io::Error::other("combined checker transcript absent"))?;
            crate::daemon::control::begin_publication()?;
            if let Some(notices)=notices{notices.publish(diagnostics)?;}
            checker_report.publish(checker)?;
            report.publish(analyze)?;
            Ok(clean)
        })
    }

    pub(crate) fn with_original_exclusions_report<T>(
        &mut self, request: crate::request::BuildRequest, exclusions: &[String],
        finish: impl FnOnce(
            crate::daemon::selected_report_wire::Roster, &crate::request::BuildOutcome, bool,
            Option<crate::selected_report_spool::Verified>, crate::selected_report_spool::Verified,
            dm_preprocess::source_arena_credit::SourceArenaCredit,
        ) -> std::io::Result<T>,
    ) -> Result<T, Box<dyn std::error::Error>> {
        self.with_selected_original_reports_using(request,exclusions,SelectedReportMode::Ordinary,|roster,prepared,clean,diagnostics,checker,report,credit|{
            if checker.is_some(){return Err(std::io::Error::other("ordinary selected report acquired a checker transcript"));}
            finish(roster,prepared,clean,diagnostics,report,credit)
        })
    }

    pub(crate) fn with_selected_original_reports_using<T>(
        &mut self, request: crate::request::BuildRequest, exclusions: &[String], mode: SelectedReportMode,
        finish: impl FnOnce(
            crate::daemon::selected_report_wire::Roster, &crate::request::BuildOutcome, bool,
            Option<crate::selected_report_spool::Verified>, Option<(dq_analyze::selected_exclusions_wire::Frame, crate::selected_report_spool::Verified)>, crate::selected_report_spool::Verified,
            dm_preprocess::source_arena_credit::SourceArenaCredit,
        ) -> std::io::Result<T>,
    ) -> Result<T, Box<dyn std::error::Error>> {
        self.stage_selected_original_reports_using(request, exclusions, mode, false, |roster, prepared, clean, diagnostics, checker, report, credit, _| {
            finish(roster, prepared, clean, diagnostics, checker, report, credit)
        })
    }

    /// Stage Checker and Analyze together, then compile through the ordinary
    /// native frontend on this same retained host. Both actual input closures
    /// must still be current before the compiled pair can be installed.
    pub fn compile_with_original_selected_reports(
        &mut self,
        prepare: crate::request::BuildRequest,
        compile: crate::request::BuildRequest,
        exclusions: &[String],
        diagnostics: &mut impl std::io::Write,
        checker: &mut impl std::io::Write,
        analyze: &mut impl std::io::Write,
    ) -> Result<(crate::request::BuildOutcome, bool), Box<dyn std::error::Error>> {
        self.with_compiled_selected_reports_using(prepare, compile, exclusions, |staged| {
            staged.publish(diagnostics, checker, analyze)
        })
    }

    pub(crate) fn with_compiled_selected_reports_using<T>(
        &mut self, prepare: crate::request::BuildRequest, compile: crate::request::BuildRequest,
        exclusions: &[String],
        finish: impl FnOnce(crate::daemon::selected_report_wire::CompiledSelectedReports) -> std::io::Result<T>,
    ) -> Result<T, Box<dyn std::error::Error>> {
        use crate::daemon::{control, prepare_deadline};
        use std::io;
        original_exclusions_shape(&prepare, crate::daemon::selected_report_wire::Roster::Base)?;
        crate::request_runner::validate_joined_compile_request(&compile, self)?;
        if !compile.project.is_absolute()
            || dm_preprocess::regions::canonical_path(&compile.project)
                != dm_preprocess::regions::canonical_path(&prepare.project)
            || !compile.defines.is_empty()
            || compile.engine_template.is_some()
            || compile.bootstrap_catalog
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput,
                "compound phases require the same project and default source settings").into());
        }
        if prepare.timeout_seconds.is_none() || prepare.timeout_seconds != compile.timeout_seconds {
            return Err(io::Error::new(io::ErrorKind::InvalidInput,
                "compound phases require one matching explicit deadline").into());
        }
        let requested = prepare_deadline::capture(
            prepare.command, prepare.timeout_seconds, std::time::Instant::now(),
        )?.ok_or_else(|| io::Error::other("compound request deadline absent"))?;
        let _deadline = if control::WorkerContext::capture().is_none() {
            Some(control::bind_with_deadline(control::Cancellation::default(), requested))
        } else {
            if control::current_deadline().is_none_or(|inherited| inherited > requested) {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,
                    "inherited operation must have a deadline within the compound request budget").into());
            }
            None
        };
        let (joined, roster, frame, clean, notices, checked, report, credit) =
            self.stage_selected_original_reports_using(
                prepare, exclusions, SelectedReportMode::Combined, true,
                |roster, prepared, clean, notices, checked, report, credit, joined| {
                    let joined = joined.ok_or_else(|| io::Error::other("combined input closure absent"))?;
                    let checked = checked.ok_or_else(|| io::Error::other("combined Checker output absent"))?;
                    let frame = crate::daemon::selected_report_wire::Frame::from_prepared(prepared)?;
                    frame.require_checker_frame(checked.0)?;
                    Ok((joined, roster, frame, clean, notices, checked, report, credit))
                },
            )?;
        let compiled = crate::request_runner::compile_with_joined_selected_inputs(compile, self, &joined)?;
        if !matches!(compiled, crate::request::BuildOutcome::Published { .. }) {
            return Err(io::Error::other("exact native compilation did not publish a pair").into());
        }
        Ok(finish(crate::daemon::selected_report_wire::CompiledSelectedReports {
            compiled, roster, frame, clean, diagnostics: notices, checker: checked, report, _credit: credit,
        })?)
    }

    pub(crate) fn stage_selected_original_reports_using<T>(
        &mut self, mut request: crate::request::BuildRequest, exclusions: &[String], mode: SelectedReportMode, retain_joined: bool,
        finish: impl FnOnce(
            crate::daemon::selected_report_wire::Roster, &crate::request::BuildOutcome, bool,
            Option<crate::selected_report_spool::Verified>, Option<(dq_analyze::selected_exclusions_wire::Frame, crate::selected_report_spool::Verified)>, crate::selected_report_spool::Verified,
            dm_preprocess::source_arena_credit::SourceArenaCredit, Option<crate::request_runner::JoinedSelectedInputs>,
        ) -> std::io::Result<T>,
    ) -> Result<T, Box<dyn std::error::Error>> {
        use crate::selected_report_spool::Stage;
        use dq_analyze::captured_generator_budget::Budget;
        use std::io;
        if retain_joined && mode != SelectedReportMode::Combined {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined input retention requires selected Checker and Analyze").into());
        }
        if !self.retains_artifacts() {
            return Err(original_exclusions_invalid().into());
        }
        let plan = Self::plan_original_exclusions(exclusions, mode)?;
        let (requested_workspace, cache) = original_exclusions_shape(&request, plan.roster())?;
        // Preparation inherits this deadline. Keep the binding through the
        // producer joins and final validation instead of restarting its clock.
        use crate::daemon::{control, prepare_deadline};
        let _deadline = if control::WorkerContext::capture().is_none() {
            prepare_deadline::capture(request.command, request.timeout_seconds, std::time::Instant::now())?
                .map(|deadline| control::bind_with_deadline(control::Cancellation::default(), deadline))
        } else {
            None
        };
        control::checkpoint()?;
        // The narrow retained ALLOW envelope belongs to the real native input
        // family throughout every child. Also fund the small request, capture
        // comparison and private spool names before cloning them.
        let spool_metadata = requested_workspace.recursive_roots.iter()
            .map(|path| path.as_os_str())
            .chain([cache.as_os_str(), request.project.as_os_str(), requested_workspace.root.as_os_str(), requested_workspace.configuration.as_os_str()])
            .try_fold(0usize, |total, value| total.checked_add(value.len()))
            .and_then(|n| n.checked_mul(32)).and_then(|n| n.checked_add(32 * 1024))
            .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?;
        let combined = mode == SelectedReportMode::Combined;
        let combined_metadata=if combined{cache.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(4096)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?}else{0};
        let total = SELECTED_REPORT_RETAINED.checked_add(spool_metadata).and_then(|n|n.checked_add(combined_metadata))
            .ok_or_else(|| io::Error::from(io::ErrorKind::OutOfMemory))?;
        let credit = self.source_arena_work().reserve(total)?;
        let (workspace_root, physical_cache) = Self::original_exclusions_paths(&request, plan.roster())?;
        if combined && !plan.supports_combined() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput,"combined report requires a qualified semantic roster").into());
        }
        if !plan.questions().is_empty() {
            request.policy_inputs.as_mut().ok_or_else(original_exclusions_invalid)?.workspace_auxiliary = plan.questions().to_vec();
        }
        let retained = Budget::new(SELECTED_REPORT_RETAINED).map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?;
        let mut diagnostic_stage = Stage::new(&physical_cache)?;
        let report_stage = Stage::new(&physical_cache)?;
        let mut checker_stage=combined.then(||Stage::new(&physical_cache)).transpose()?;
        let mut joined = None;
        let (prepared, checker_frame) = crate::request_runner::prepare_selected_report(
            request, self, &mut diagnostic_stage, checker_stage.as_mut(), retain_joined.then_some(&mut joined),
            plan.needs_library_sites_baseline(),
        )?;
        let prepared_outcome = prepared.preparation?;
        prepared.diagnostics?;
        let (mut clean, verified) = {
            let state = self.query_state.try_lock().map_err(|_| io::Error::new(io::ErrorKind::WouldBlock, "selected report current query state is already borrowed"))?;
            let snapshot = state.snapshot.as_ref().ok_or_else(|| io::Error::other("selected report has no current snapshot"))?;
            if plan.roster() == crate::daemon::selected_report_wire::Roster::WithUntyped {
                let checker = checker_frame.as_ref().ok_or_else(|| io::Error::other("selected untyped requires the staged Checker source"))?;
                snapshot.require_staged_checker_body_domain(checker)?;
            }
            let handlers = if plan.requires_handlers() {
                Some(state.handlers_snapshot.as_ref().ok_or_else(|| io::Error::other("selected handlers has no actual current partial child"))?)
            } else { None };
            snapshot.stage_selected_report(&prepared_outcome, exclusions, &retained, &workspace_root, &plan, handlers, report_stage)?
        };
        let verified_diagnostics = if diagnostic_stage.length() != 0 {
            Some(query_snapshot::checked_selected_report_stage(diagnostic_stage)?)
        } else {
            None
        };
        let checker = match (checker_stage, checker_frame) {
            (Some(stage), Some(transcript)) => {
                crate::daemon::selected_report_wire::Frame::from_prepared(&prepared_outcome)?
                    .require_checker_frame(transcript.frame)?;
                let verified = query_snapshot::checked_selected_report_stage(stage)?;
                clean &= transcript.clean;
                Some((transcript.frame, verified))
            }
            (None, None) => None,
            _ => return Err(io::Error::other("combined checker did not issue its matching transcript").into()),
        };
        if retain_joined != joined.is_some() {
            return Err(io::Error::other("selected report preparation did not retain its joined inputs").into());
        }
        Ok(finish(plan.roster(), &prepared_outcome, clean, verified_diagnostics, checker, verified, credit, joined)?)
    }
}

#[cfg(test)]
mod joined_selected_publication_control {
    use super::*;
    use crate::{
        policy_request::{AnalysisContext, PolicyInputRequest, WorkspacePolicyRequest},
        request::{BuildOutcome, BuildRequest, Command},
    };
    use std::path::Path;

    fn put(root: &Path, relative: &str, text: &str) {
        let path = root.join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn request(command: &str, project: &Path, cache: &Path) -> BuildRequest {
        let Command::Build(request) = crate::cli::parse(&[
            command.into(), project.to_string_lossy().into_owned(),
        ]).unwrap() else { panic!("expected a build request") };
        let mut request = *request;
        request.no_cache = true;
        request.exact_inputs = true;
        request.progress_enabled = false;
        request.workers = 1;
        request.timeout_seconds = Some(60);
        request.cache_root = Some(cache.to_owned());
        request
    }

    #[test]
    fn actual_combined_untyped_uses_canonical_proof_and_keeps_exclusive_issuance_distinct() {
        use crate::daemon::{control, selected_report_wire::Roster};
        use dm_analysis::value_query::{ArchiveValueQueries, ValueQueryFailure};
        use dm_tree::frontend::BodySyntaxQueries;
        use dq_analyze::{captured_allow_annotations::{full_unused, Operation}, captured_generator_budget::Budget};
        let root = crate::test_scratch::dir("joined-selected-untyped-project");
        let cache = crate::test_scratch::dir("joined-selected-untyped-cache");
        let project = root.join("deepquarry.dme");
        let configuration = root.join("tools/ci/lint_scopes.toml");
        put(&root, "deepquarry.dme", "#include \"code/probe.dm\"\n");
        put(&root, "code/probe.dm", concat!(
            "/datum/probe\n    var/link\n",
            "/datum/probe/proc/save(datum/probe/other)\n    set mystery = 1\n    link = other\n    return 1\n",
        ));
        put(&root, "tools/ci/lint_scopes.toml", include_str!("../../../../ci/lint_scopes.toml"));
        let mut prepare = request("prepare-query", &project, &cache);
        prepare.policy_inputs = Some(PolicyInputRequest {
            analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
            workspace: Some(WorkspacePolicyRequest {
                root: root.clone(), recursive_roots: vec![root.join("code"), root.join("maps")], configuration,
            }),
            ..Default::default()
        });
        let budget = Budget::new(1 << 20).unwrap();
        let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
        let selection = full_unused::registered_full_selection(&[], &mut work).unwrap();
        let exclusions: Vec<_> = selection.names().iter()
            .filter(|name| !Roster::WithUntyped.names().contains(&name.as_str()))
            .map(|name| format!("-{name}")).collect();
        assert!(BuildHost::plan_original_exclusions(&exclusions, SelectedReportMode::Ordinary).is_err());
        let mut host = BuildHost::default();
        let _deadline = control::bind_with_deadline(control::Cancellation::default(),
            std::time::Instant::now() + std::time::Duration::from_secs(60));
        let (checker, analyze) = host.stage_selected_original_reports_using(
            prepare, &exclusions, SelectedReportMode::Combined, false,
            |roster, _, clean, _, checker, analyze, _, _| {
                assert_eq!(roster, Roster::WithUntyped);
                assert!(!clean);
                let mut checked = Vec::new();
                checker.unwrap().1.publish(&mut checked)?;
                let mut analyzed = Vec::new();
                analyze.publish(&mut analyzed)?;
                Ok((checked, analyzed))
            },
        ).unwrap();
        let checked: serde_json::Value = serde_json::from_slice(&checker).unwrap();
        assert!(checked["diagnostics"].as_array().unwrap().iter().any(|row| row["family"] == "unknown_setting"), "{checked}");
        let analyzed = std::str::from_utf8(&analyze).unwrap();
        assert!(analyzed.contains("[untyped/typed]"), "{analyzed}");
        assert!(analyzed.contains("allow annotations: 0 unused"), "{analyzed}");

        let state = host.query_state.lock().unwrap();
        let snapshot = state.snapshot.as_ref().unwrap();
        let capture = snapshot.workspace_semantic_inputs(crate::policy_request::WorkspaceAuxiliaryQuestion::Untyped).unwrap();
        let mut issued = Vec::new();
        capture.visit_untyped_inputs(|_, input| issued.push(Arc::clone(input)));
        assert_eq!(issued.len(), 1, "staging must not issue the compatibility value input");
        let input = &issued[0];
        assert!(input.requires_canonical_bodies());
        assert!(matches!(input.compute_checked(), Err(ValueQueryFailure::Unsupported(_))));
        let db = host.query_db();
        let archive = input.archive();
        let ordinal = archive.occurrences().iter().position(|row| {
            archive.tree().member(row.member).is_some_and(|member| {
                member.name == dm_ir::SymbolId::of("save")
            })
        }).unwrap();
        let syntax = &archive.syntax_inputs().unwrap()[ordinal];
        let product = db.syntax_product_checked(syntax).unwrap();
        let bodies = db.db().stats(dm_query::Kind(4)).computed;
        let proofs = db.db().stats(dm_query::Kind(5)).computed;
        let proof = db.value_proof_checked(input).unwrap();
        assert!(Arc::ptr_eq(&product, &db.syntax_product_checked(syntax).unwrap()));
        assert!(Arc::ptr_eq(&proof, &db.value_proof_checked(input).unwrap()));
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed, bodies);
        assert_eq!(db.db().stats(dm_query::Kind(5)).computed, proofs);
        let compatibility = capture.untyped_input(input.exempt_types()).unwrap();
        assert!(!compatibility.requires_canonical_bodies());
        assert!(proof.validate_for(&compatibility).is_err());
    }

    #[test]
    fn actual_joined_selected_inputs_veto_native_install_and_recover() {
        use crate::daemon::{control, selected_report_wire::Roster};
        use dq_analyze::{captured_allow_annotations::{full_unused, Operation}, captured_generator_budget::Budget};
        let root = crate::test_scratch::dir("joined-selected-project");
        let cache = crate::test_scratch::dir("joined-selected-cache");
        let project = root.join("deepquarry.dme");
        let configuration = root.join("tools/ci/lint_scopes.toml");
        let scopes = include_str!("../../../../ci/lint_scopes.toml");
        put(&root, "deepquarry.dme", "#include \"code/bridge.dm\"\n");
        put(&root, "code/bridge.dm", "#include \"common.dm\"\n");
        put(&root, "code/common.dm", concat!(
            "#define CAPABILITIES(...)\n#define PROC_REF(P) #P\n",
            "/datum/act\n/datum/act/eval\n/datum/receiver\n",
            "/proc/check_field(datum/receiver/argument)\n",
            "#ifdef SPACEMAN_DMM\n    return argument.field\n",
            "#else\n    return 1687\n#endif\n",
            "/obj/probe\n/obj/probe/proc/dynamic(datum/act/eval/A)\n    return vars[\"probe\"]\n",
            "CAPABILITIES(/obj/probe,when(PROC_REF(dynamic)))\n",
        ));
        put(&root, "tools/ci/lint_scopes.toml", scopes);
        let mut prepare = request("prepare-query", &project, &cache);
        prepare.policy_inputs = Some(PolicyInputRequest {
            analysis_context: Some(AnalysisContext::OriginalAnalyze0290),
            workspace: Some(WorkspacePolicyRequest {
                root: root.clone(), recursive_roots: vec![root.join("code"), root.join("maps")],
                configuration: configuration.clone(),
            }),
            ..Default::default()
        });
        let mut compile = request("compile", &project, &cache);
        let artifacts = cache.join("artifacts");
        compile.artifact_directory = Some(artifacts.clone());
        compile.output_store = Some(cache.join("pairs"));

        let budget = Budget::new(1 << 20).unwrap();
        let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
        let selection = full_unused::registered_full_selection(&[], &mut work).unwrap();
        let exclusions: Vec<_> = selection.names().iter()
            .filter(|name| !Roster::WithSemanticReads.names().contains(&name.as_str()))
            .map(|name| format!("-{name}")).collect();

        let mut host = BuildHost::default();
        let mut foreign = compile.clone();
        foreign.defines.insert("NATIVE_ONLY_FIXTURE".into(), "1".into());
        let incompatible = host.compile_with_original_selected_reports(
            prepare.clone(), foreign, &exclusions,
            &mut std::io::sink(), &mut std::io::sink(), &mut std::io::sink(),
        ).expect_err("different source settings must fail before staging");
        assert!(incompatible.to_string().contains("default source settings"), "{incompatible}");

        for shared_edit in [false, true] {
            let _deadline = control::bind_with_deadline(control::Cancellation::default(),
                std::time::Instant::now() + std::time::Duration::from_secs(60));
            let joined = host.stage_selected_original_reports_using(
                prepare.clone(), &exclusions, SelectedReportMode::Combined, true,
                |_, _, clean, _, checker, analyze, _, joined| {
                    assert!(!clean);
                    assert!(checker.is_some());
                    assert!(analyze.length() > 0);
                    Ok(joined.unwrap())
                },
            ).unwrap();
            if shared_edit {
                let shared_path = root.join("code/common.dm");
                let before = std::fs::read_to_string(&shared_path).unwrap();
                let after = before.replace("return 1687", "return 1688");
                assert_ne!(before, after);
                std::fs::write(shared_path, after).unwrap();
            } else {
                // Only the report observed this configuration file.
                std::fs::write(&configuration, format!("{scopes}\n# newer report config\n")).unwrap();
            }
            let failure = crate::request_runner::compile_with_joined_selected_inputs(compile.clone(), &mut host, &joined)
                .expect_err("stale Original closure must veto the actual native install");
            assert!(failure.to_string().contains("both phases"), "{failure}");
            if shared_edit {
                assert!(failure.to_string().contains("shared input differs"), "{failure}");
            }
            assert!(!artifacts.join("deepquarry.dmb").exists());
            assert!(!artifacts.join("deepquarry.rsc").exists());
        }

        let mut diagnostics = Vec::new();
        let mut checker_bytes = Vec::new();
        let mut analyze_bytes = Vec::new();
        let (outcome, clean) = host.compile_with_original_selected_reports(
            prepare.clone(), compile, &exclusions, &mut diagnostics, &mut checker_bytes, &mut analyze_bytes,
        ).unwrap();
        assert!(matches!(outcome, BuildOutcome::Published { .. }));
        assert!(!clean);
        assert!(artifacts.join("deepquarry.dmb").is_file());
        assert!(artifacts.join("deepquarry.rsc").is_file());
        assert!(std::str::from_utf8(&checker_bytes).unwrap().contains("undefined field"));
        assert!(std::str::from_utf8(&analyze_bytes).unwrap().contains("[reads/dynamic_read]"));

        // The real publication left the Strict variant active. The next
        // selected pair must lend exactly that variant's already-built memo.
        let strict = host.engine.as_ref().unwrap().configuration.clone();
        assert!(strict.analysis_context.is_none());
        let before = host.semantic.as_ref().unwrap().callable_owner_hits();
        // A source edit prevents exact same-mode Original frontend reuse from
        // skipping the semantic pass under test. Existing owners are unchanged.
        let path = root.join("code/common.dm");
        let mut current = std::fs::read_to_string(&path).unwrap();
        current.push_str("#ifdef SPACEMAN_DMM\n/datum/only_new_original/proc/anchor()\n    return 0\n#endif\n");
        std::fs::write(path, current).unwrap();
        let mut warm_notices = Vec::new();
        let mut warm_checker = Vec::new();
        let mut warm_analyze = Vec::new();
        let warm = host.write_combined_selected_original_reports(
            prepare, &exclusions, &mut warm_notices, &mut warm_checker, &mut warm_analyze,
        ).unwrap();
        let current = host.engine.as_ref().unwrap();
        let prior = BuildHost::stashed_strict_callable_prior(current, &host.variants).unwrap();
        assert!(std::ptr::eq(prior, host.variants[&strict].semantic.as_ref().unwrap()));
        assert!(prior.callable_owner_hits() > before, "actual selected Original reused authored Strict callable owners");
        assert_eq!(warm, clean);
        assert_eq!(warm_notices, diagnostics);
        let mut previous: serde_json::Value = serde_json::from_slice(&checker_bytes).unwrap();
        let mut fresh: serde_json::Value = serde_json::from_slice(&warm_checker).unwrap();
        for name in ["source_revision", "semantic_revision", "policy_revision"] {
            let previous_revision = previous.as_object_mut().unwrap().remove(name).unwrap();
            let fresh_revision = fresh.as_object_mut().unwrap().remove(name).unwrap();
            let value = fresh_revision.as_str().unwrap();
            assert_eq!(value.len(), 32);
            assert!(value.bytes().all(|byte| byte.is_ascii_hexdigit()));
            assert_ne!(previous_revision, fresh_revision, "actual Original source edit must reissue {name}");
        }
        assert_eq!(fresh, previous, "current diagnostic results retain their exact source locations and notes");
        assert_eq!(warm_analyze, analyze_bytes);
    }
}
