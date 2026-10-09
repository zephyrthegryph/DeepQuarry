//! Process-local artifact ownership for the shared request pipeline.
//! Immutable source contributions and observed artifacts survive across requests;
//! current source issuance, dense table projections and publication stay request-local.
use crate::{engine::EngineSnapshot, engine_link::EngineLinkFacts};
use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{Arc, Mutex, OnceLock},
};

#[path = "runner_disk.rs"]
mod disk;
#[path = "runner_host_idle.rs"]
mod idle;
#[path = "runner_host_memo.rs"]
mod memo;

type ProcedureValues =
    Arc<crate::lowering_memo::LoweringMemo<crate::lowering_memo::CachedProcedure>>;
type HostParts<'a> = (
    Option<memo::MemoView<'a>>,
    HostExecution<'a>,
    Option<&'a mut dm_tree::frontend::RetainedSemanticTree>,
);

/// One semantic session's retained artifacts and bounded executor. A long-lived
/// caller reuses this owner across requests without retaining a publication lease.
pub struct BuildHost {
    disk_warmup: disk::WarmupState,
    engine: Option<Arc<RetainedEngine>>,
    memo: Option<memo::ResidentMemo>,
    executor: Option<dm_exec::BuildExecutor>,
    procedures: Option<(u128, ProcedureValues)>,
    semantic: Option<dm_tree::frontend::RetainedSemanticTree>,
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
    link_bindings: Option<(u128, Arc<dm_link::RetainedBindings>)>,
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
    pub(crate) bytes: Arc<[u8]>,
    pub(crate) snapshot: EngineSnapshot,
    links: Mutex<Option<EngineLinkFacts>>,
    seed: OnceLock<dm_tree::frontend::EngineSeed>,
}

impl Default for BuildHost {
    fn default() -> Self {
        Self {
            disk_warmup: Default::default(),
            engine: None,
            executor: None,
            procedures: None,
            memo: Some(memo::ResidentMemo::default()),
            semantic: Some(dm_tree::frontend::RetainedSemanticTree::new()),
            maps: None,
            symbolic: None,
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            link_bindings: None,
        }
    }
}
impl BuildHost {
    /// CLI adapter: no resident candidates or memo-record construction without disk.
    pub fn one_shot() -> Self {
        Self {
            disk_warmup: Default::default(),
            engine: None,
            executor: None,
            procedures: None,
            memo: None,
            semantic: None,
            maps: None,
            symbolic: None,
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            link_bindings: None,
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
    pub(crate) fn disk_admission(&mut self, policy: u128) -> disk::DiskAdmission {
        self.disk_warmup.admit(self.memo.is_some(), policy)
    }

    pub(crate) fn retains_artifacts(&self) -> bool {
        self.memo.is_some()
    }
    /// Retain map answers across requests; disk snapshots remain request-local.
    pub(crate) fn map_memo(
        &mut self,
        policy: u128,
        disk: Option<Arc<dm_cache::CacheSnapshot>>,
    ) -> Option<crate::map_memo::MapMemo> {
        if self.memo.is_none() {
            return disk.map(|snapshot| {
                crate::map_memo::MapMemo::with_disk(policy, 64 * 1024 * 1024, snapshot)
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
        disk: Option<Arc<dm_cache::CacheSnapshot>>,
    ) -> Option<crate::lowering_memo::ProcedureMemo> {
        if self.memo.is_none() {
            return disk.map(|snapshot| {
                crate::lowering_memo::ProcedureMemo::with_disk_only(policy, snapshot)
            });
        }
        if self
            .procedures
            .as_ref()
            .is_none_or(|(previous, _)| *previous != policy)
        {
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
        self.disk_warmup.clear();
        if self.memo.is_some() {
            self.memo = Some(memo::ResidentMemo::default());
        }
        if self.semantic.is_some() {
            self.semantic = Some(dm_tree::frontend::RetainedSemanticTree::new());
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
    ) -> Result<HostParts<'a>, dm_exec::ExecutorError> {
        let execution = if self.memo.is_some() {
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
        let snapshot = EngineSnapshot::from_bytes(&bytes, configuration.schema)
            .map_err(|error| format!("engine template: {error:?}"))?;
        let snapshot = if bootstrap_catalog {
            snapshot
                .with_bootstrap_catalog()
                .map_err(|error| format!("engine catalog: {error:?}"))?
        } else {
            snapshot
        };
        let retained = Arc::new(RetainedEngine {
            configuration,
            bytes: bytes.into(),
            snapshot,
            links: Mutex::new(None),
            seed: OnceLock::new(),
        });
        if self.memo.is_some() {
            self.memo = Some(memo::ResidentMemo::default());
        }
        self.disk_warmup.clear();
        self.procedures = None;
        self.symbolic = None;
        self.initializers = None;
        self.startup = None;
        self.abi = None;
        self.initializer_fragments = None;
        self.initializer_assemblies = None;
        self.class_projections = None;
        self.link_bindings = None;
        self.maps = None;
        if self.semantic.is_some() {
            self.semantic = Some(dm_tree::frontend::RetainedSemanticTree::new());
        }
        self.engine = Some(Arc::clone(&retained));
        Ok(retained)
    }
}

pub(crate) enum HostExecution<'a> {
    OneShot(dm_exec::BuildExecutor),
    Retained(&'a mut dm_exec::BuildExecutor),
}
impl HostExecution<'_> {
    pub(crate) fn run<R>(
        self,
        operation: impl FnOnce(&dm_exec::BuildExecutor) -> R,
    ) -> Result<R, dm_exec::RequestError> {
        match self {
            Self::OneShot(executor) => Ok(operation(&executor)),
            Self::Retained(executor) => {
                let request = dm_profile::RequestContext::capture();
                executor.with_request(request.as_ref(), operation)
            }
        }
    }
}

impl RetainedEngine {
    pub(crate) fn frontend_seed(&self) -> &dm_tree::frontend::EngineSeed {
        self.seed.get_or_init(|| self.snapshot.frontend_seed())
    }

    /// Return a mutable request overlay without altering the pinned baseline.
    /// First capture stays at the ordinary pipeline's linking-input boundary.
    pub(crate) fn link_overlay(&self) -> Result<EngineLinkFacts, String> {
        let mut retained = self
            .links
            .lock()
            .map_err(|_| "retained engine links poisoned")?;
        if retained.is_none() {
            *retained = Some(crate::engine_link::capture(&self.bytes, &self.snapshot)?);
        }
        let baseline = retained.as_ref().expect("captured engine links");
        Ok(EngineLinkFacts {
            inventory: baseline.inventory.clone(),
            references: baseline.references.clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn capture(host: &mut BuildHost, defines: BTreeMap<String, String>) -> Arc<RetainedEngine> {
        host.engine(
            PathBuf::from("E:/fixture/world.dme"),
            defines,
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap()
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
}
