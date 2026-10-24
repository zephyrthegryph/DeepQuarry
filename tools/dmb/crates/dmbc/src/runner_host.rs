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
#[path = "runner_query_snapshot.rs"]
pub(crate) mod query_snapshot;
#[path = "runner_host_resources.rs"]
pub(crate) mod resources;
pub(crate) use engine_payload::{EnginePayload, EnginePayloads};
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
    initializer_assemblies: Option<(u128, Arc<crate::initializer_lowering::InitializerAssemblies>)>,
    class_projections: Option<(u128, Arc<crate::class_projection::ClassProjections>)>,
    required_types: Option<(u128, Arc<crate::required_types::RequiredTypeArtifacts>)>,
    link_bindings: Option<(u128, Arc<dm_link::RetainedBindings>)>,
    stages: Option<(u128, Arc<crate::stage_reuse::StageProducts>)>,
    generation: Option<(u128, Arc<crate::composition::RetainedGeneration>)>,
    host_facts: Option<Arc<crate::request_runner::runner_facts::RetainedHostFacts>>,
    resources: Option<Arc<resources::Resources>>,
    symbolic: Option<(u128, Arc<crate::lowering::symbolic_input::SessionSymbolicMemo>)>,
}

#[derive(Clone, Eq, Ord, PartialEq, PartialOrd)]
struct EngineConfiguration {
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
    ) -> Self {
        let mut host = Self::with_shared_engines(engines);
        host.shared_executors = Some(executors);
        host.shared_procedure_code = Some(procedures);
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
        self.generation.as_ref().is_some_and(|(_, generation)| generation.has_patch_base())
    }
    /// The image the retained patch base describes (None without one): a stored-record hit that would serve a different
    /// image must not leave the base behind (see `request_runner`).
    pub(crate) fn patch_base_image_hash(&self) -> Option<u128> {
        self.generation.as_ref().and_then(|(_, generation)| generation.patch_base_image_hash())
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
    pub(crate) fn procedure_memo(
        &mut self,
        policy: u128,
        disk: Option<Arc<disk::LazyDisk>>,
        publishable: bool,
    ) -> Option<crate::lowering_memo::ProcedureMemo> {
        if self.memo.is_none() {
            return Some(initializers::one_shot(
                policy,
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
                policy,
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
                .with_request(publishable),
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
        memo.link_bindings = Some(self.link_bindings.as_ref().unwrap().1.for_request(publishable));
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
    pub(crate) fn clear_regions(&mut self) {
        if let Some((_, startup)) = &self.startup {
            startup.clear_callable_index();
        }
        if self.memo.is_some() {
            self.memo = Some(memo::ResidentMemo::default());
        }
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
        Ok((memo, execution, self.semantic.as_mut()))
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
        while self.variants.len() > MAX_STASHED_VARIANTS + usize::from(self.variants.contains_key(&configuration)) {
            let Some(victim) = self.variants.keys().find(|key| **key != configuration).cloned() else {
                break;
            };
            self.variants.remove(&victim);
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
                self.semantic = Some(dm_tree::frontend::RetainedSemanticTree::with_shared_normalized(Arc::clone(
                    &retained.payload.normalized,
                )));
            }
            retained
        };
        self.engine_generation = self.engine_generation.saturating_add(1);
        self.rich_generation = self.rich_generation.saturating_add(1);
        self.engine = Some(Arc::clone(&retained));
        retained
    }
    /// True when the active variant is this manifest under exactly these defines. A session holds several variants; queries read
    /// the active one, so a query for another variant must say so instead of answering from the wrong tree.
    pub(crate) fn serves_variant(&self, project: &std::path::Path, defines: &BTreeMap<String, String>) -> bool {
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
    /// Drop every stashed variant (their state is recomputable). Returns how many were dropped.
    pub(crate) fn release_stashed_variants(&mut self) -> usize {
        let dropped = self.variants.len();
        self.variants.clear();
        dropped
    }

    pub(crate) fn engine(
        &mut self,
        project: PathBuf,
        defines: BTreeMap<String, String>,
        bootstrap_catalog: bool,
        bytes: Vec<u8>,
    ) -> Result<Arc<RetainedEngine>, String> {
        let configuration = EngineConfiguration {
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
        if self.memo.is_some() {
            self.memo = Some(memo::ResidentMemo::default());
        }
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
        let a_memo = a.procedure_memo(1, None, true).unwrap();
        let b_memo = b.procedure_memo(1, None, true).unwrap();
        assert!(!Arc::ptr_eq(&a_memo.values, &b_memo.values));
    }
    #[test]
    fn a_variant_switch_keeps_each_variants_state_and_shares_the_engine_payload() {
        let mut host = BuildHost::with_shared_engines(Arc::new(EnginePayloads::default()));
        let testing = || BTreeMap::from([("CITESTING".to_string(), "1".to_string())]);
        let production = capture(&mut host, BTreeMap::new());
        let maps = |policy| Some((policy, Arc::new(crate::map_memo::RetainedMaps::current_revision())));
        host.maps = maps(7);
        // The test define set is another variant of the same session: its own empty state, the same engine payload.
        let test = capture(&mut host, testing());
        assert!(!Arc::ptr_eq(&production, &test));
        assert!(Arc::ptr_eq(&production.payload, &test.payload));
        assert!(host.maps.is_none(), "a new variant starts with no define-dependent state");
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
        assert!(!host.serves_variant(std::path::Path::new("E:/fixture/world.dme"), &BTreeMap::new()));
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
        let first = host.procedure_memo(1, None, true).unwrap();
        first
            .counts
            .resident_hits
            .store(7, std::sync::atomic::Ordering::Relaxed);
        let second = host.procedure_memo(1, None, true).unwrap();
        assert!(Arc::ptr_eq(&first.values, &second.values));
        assert_eq!(
            second
                .counts
                .resident_hits
                .load(std::sync::atomic::Ordering::Relaxed),
            0
        );
        let changed = host.procedure_memo(2, None, true).unwrap();
        assert!(!Arc::ptr_eq(&first.values, &changed.values));
        let mut one_shot = BuildHost::one_shot();
        let request = one_shot.procedure_memo(1, None, true).unwrap();
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
        let no_engine = host.procedure_memo(1, None, true).unwrap();
        assert!(no_engine.abi.as_ref().unwrap().engine_owner().is_none());
        let engine = capture(&mut host, BTreeMap::new());
        let request = host.procedure_memo(1, None, true).unwrap();
        let abi = request.abi.as_ref().unwrap();
        assert!(Arc::ptr_eq(
            abi.engine_owner().unwrap(),
            &engine.abi_engine_owner(),
        ));
        let next_request = host.procedure_memo(1, None, true).unwrap();
        assert!(!Arc::ptr_eq(abi, next_request.abi.as_ref().unwrap()));
        assert!(Arc::ptr_eq(
            abi.engine_owner().unwrap(),
            next_request.abi.as_ref().unwrap().engine_owner().unwrap(),
        ));
        assert!(host.abi.is_none(), "one-shot ABI owner belongs to the request");
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
