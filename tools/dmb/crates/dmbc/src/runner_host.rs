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
#[path = "runner_host_memo.rs"]
mod memo;
#[path = "runner_query_snapshot.rs"]
pub(crate) mod query_snapshot;
pub(crate) use engine_payload::EnginePayloads;
#[path = "runner_executor_pool.rs"]
mod executor_pool;
pub(crate) use executor_pool::ExecutorPools;

type ProcedureValues =
    Arc<crate::lowering_memo::LoweringMemo<crate::lowering_memo::CachedProcedure>>;
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
    generation: Option<(u128, Arc<crate::composition::RetainedGeneration>)>,
    host_facts: Option<Arc<crate::request_runner::runner_facts::RetainedHostFacts>>,
    symbolic: Option<(
        u128,
        Arc<crate::lowering::symbolic_input::SessionSymbolicMemo>,
    )>,
}

#[derive(Eq, PartialEq)]
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
            engine_generation: 0,
            rich_generation: 0,
            procedure_generation: 0,
            procedure_policy_replacements: 0,
            prepared_sources: Some(Arc::new(
                crate::input_snapshot::PreparedInputArtifacts::default(),
            )),
            shared_engines: None,
            shared_executors: None,
            engine: None,
            executor: None,
            procedures: None,
            memo: Some(memo::ResidentMemo::default()),
            semantic: Some(dm_tree::frontend::RetainedSemanticTree::new()),
            query_state: Arc::default(),
            maps: None,
            symbolic: None,
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            required_types: None,
            link_bindings: None,
            generation: None,
            host_facts: None,
        }
    }
}
impl BuildHost {
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
    ) -> Self {
        let mut host = Self::with_shared_engines(engines);
        host.shared_executors = Some(executors);
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
            engine_generation: 0,
            rich_generation: 0,
            procedure_generation: 0,
            procedure_policy_replacements: 0,
            prepared_sources: None,
            shared_engines: None,
            shared_executors: None,
            engine: None,
            executor: None,
            procedures: None,
            memo: None,
            semantic: None,
            query_state: Arc::default(),
            maps: None,
            symbolic: None,
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            required_types: None,
            link_bindings: None,
            generation: None,
            host_facts: None,
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

    pub(crate) fn retains_artifacts(&self) -> bool {
        self.memo.is_some()
    }
    /// Retain map answers across requests; disk snapshots remain request-local.
    pub(crate) fn map_memo(
        &mut self,
        policy: u128,
        disk: Option<Arc<disk::LazyDisk>>,
    ) -> Option<crate::map_memo::MapMemo> {
        if self.memo.is_none() {
            return disk.map(|snapshot| {
                crate::map_memo::MapMemo::with_lazy_disk(policy, 64 * 1024 * 1024, snapshot)
            });
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
        Some(crate::map_memo::MapMemo::with_resident(
            policy,
            Arc::clone(&self.maps.as_ref().unwrap().1),
            disk,
        ))
    }
    pub(crate) fn procedure_memo(
        &mut self,
        policy: u128,
        disk: Option<Arc<disk::LazyDisk>>,
    ) -> Option<crate::lowering_memo::ProcedureMemo> {
        if self.memo.is_none() {
            return disk.map(|snapshot| {
                crate::lowering_memo::ProcedureMemo::with_lazy_disk_only(policy, snapshot)
            });
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
                Arc::new(crate::lowering_memo::LoweringMemo::default()),
            ));
        }
        if self
            .symbolic
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.symbolic = Some((policy, Arc::new(Default::default())));
        }
        if self
            .initializers
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.initializers = Some((policy, Arc::new(Default::default())));
        }
        let mut memo = crate::lowering_memo::ProcedureMemo::with_resident(
            policy,
            Arc::clone(&self.procedures.as_ref().unwrap().1),
            disk,
        );
        memo.symbolic = Some(Arc::clone(&self.symbolic.as_ref().unwrap().1));
        memo.initializers = Some(Arc::clone(&self.initializers.as_ref().unwrap().1));
        if self
            .startup
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.startup = Some((policy, Arc::new(Default::default())));
        }
        memo.startup = Some(Arc::clone(&self.startup.as_ref().unwrap().1));
        if self
            .abi
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.abi = Some((policy, Arc::new(Default::default())));
        }
        memo.abi = Some(Arc::clone(&self.abi.as_ref().unwrap().1));
        if self
            .initializer_fragments
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.initializer_fragments = Some((policy, Arc::new(Default::default())));
        }
        memo.initializer_fragments =
            Some(Arc::clone(&self.initializer_fragments.as_ref().unwrap().1));
        if self
            .initializer_assemblies
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.initializer_assemblies = Some((policy, Arc::new(Default::default())));
        }
        memo.initializer_assemblies =
            Some(Arc::clone(&self.initializer_assemblies.as_ref().unwrap().1));
        if self
            .class_projections
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.class_projections = Some((policy, Arc::new(Default::default())));
        }
        memo.class_projections = Some(Arc::clone(&self.class_projections.as_ref().unwrap().1));
        if self
            .required_types
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.required_types = Some((policy, Arc::new(Default::default())));
        }
        memo.required_types = Some(Arc::clone(&self.required_types.as_ref().unwrap().1));
        if self
            .link_bindings
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
            self.link_bindings = Some((policy, Arc::new(Default::default())));
        }
        memo.link_bindings = Some(Arc::clone(&self.link_bindings.as_ref().unwrap().1));
        Some(memo)
    }

    pub(crate) fn clear_regions(&mut self) {
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
        }
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
        self.generation = None;
        self.host_facts = None;
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
        match self {
            Self::Leased(mut lease) => {
                let request = dm_profile::RequestContext::capture();
                lease.executor().with_request(request.as_ref(), operation)
            }
            Self::OneShot(executor) => Ok(operation(&executor)),
            Self::Retained(executor) => {
                let request = dm_profile::RequestContext::capture();
                executor.with_request(request.as_ref(), operation)
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
        let a_memo = a.procedure_memo(1, None).unwrap();
        let b_memo = b.procedure_memo(1, None).unwrap();
        assert!(!Arc::ptr_eq(&a_memo.values, &b_memo.values));
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
            .map(|_| BuildHost::with_daemon_owners(Arc::clone(&engines), Arc::clone(&pools)))
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
        let first = host.procedure_memo(1, None).unwrap();
        first
            .counts
            .resident_hits
            .store(7, std::sync::atomic::Ordering::Relaxed);
        let second = host.procedure_memo(1, None).unwrap();
        assert!(Arc::ptr_eq(&first.values, &second.values));
        assert_eq!(
            second
                .counts
                .resident_hits
                .load(std::sync::atomic::Ordering::Relaxed),
            0
        );
        let changed = host.procedure_memo(2, None).unwrap();
        assert!(!Arc::ptr_eq(&first.values, &changed.values));
        assert!(BuildHost::one_shot().procedure_memo(1, None).is_none());
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
    fn one_shot_without_disk_has_no_memo_and_engine_capture_does_not_enable_it() {
        let mut host = BuildHost::one_shot();
        assert!(host.expansion_memo(None).is_none());
        capture(&mut host, BTreeMap::new());
        assert!(host.expansion_memo(None).is_none());
        host.clear_regions();
        assert!(host.expansion_memo(None).is_none());
        assert!(BuildHost::default().expansion_memo(None).is_some());
    }
    #[test]
    fn maps_retain_one_policy_owner_without_retaining_request_disk_snapshots() {
        let mut host = BuildHost::default();
        capture(&mut host, BTreeMap::new());
        assert!(host.map_memo(1, None).is_some());
        let first = Arc::clone(&host.maps.as_ref().unwrap().1);
        assert!(host.map_memo(1, None).is_some());
        assert!(Arc::ptr_eq(&first, &host.maps.as_ref().unwrap().1));
        assert!(host.map_memo(2, None).is_some());
        assert!(!Arc::ptr_eq(&first, &host.maps.as_ref().unwrap().1));
        capture(&mut host, BTreeMap::from([("MODE".into(), "1".into())]));
        assert!(host.maps.is_none());
        assert!(BuildHost::one_shot().map_memo(1, None).is_none());
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
