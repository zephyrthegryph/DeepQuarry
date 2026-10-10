//! Trusted completion handoff; symbolic reuse never reuses output certificates.
use super::*;
use crate::lowering_memo::ResolverRead;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};
#[path = "symbolic_retention.rs"]
mod retained;
pub use retained::SymbolicRetentionStats;

#[derive(Default)]
pub(crate) struct SessionSymbolicMemo {
    records: Mutex<BTreeMap<UnitIdentity, Arc<Record>>>,
    admitted: AtomicU64,
    reused: AtomicU64,
    pruned: AtomicU64,
    declines: DeclineCounters,
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
struct Record {
    key: Arc<[u8]>,
    reads: Arc<[ResolverRead]>,
    versions: Arc<[(dm_ir::ReadDomain, u128)]>,
    value: RecordValue,
    relative_debug: Vec<usize>,
    required_types: Vec<dm_ir::SymbolId>,
    modified_recipes: Vec<crate::modified_initializers::SourceRecipe>,
}
enum RecordValue {
    Executable(Arc<crate::symbolic::ReusableProcedureArtifact>),
    Selections {
        facts: Arc<dm_ir::SelectedReferences>,
        abi: Vec<u8>,
    },
}
pub(crate) struct Admission {
    store: Option<Arc<SessionSymbolicMemo>>,
    disk: Option<crate::lowering_memo::DiskWriter>,
    key: Arc<[u8]>,
    reads: Arc<[ResolverRead]>,
    versions: Arc<[(dm_ir::ReadDomain, u128)]>,
    relative_debug: Vec<usize>,
}
impl Admission {
    pub(super) fn shared_key(&self) -> Arc<[u8]> {
        Arc::clone(&self.key)
    }
}
/// Fields are private: only the ordinary lowerer or exact memo validator issues it.
pub struct CompletedInput {
    inner: Input,
    admission: Option<Admission>,
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
    pub(super) fn selections(
        identity: UnitIdentity,
        effective: bool,
        body: BodyOccurrence,
        facts: Arc<dm_ir::SelectedReferences>,
    ) -> Self {
        Self {
            inner: Input::Selections(identity, effective, body, facts),
            admission: None,
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
        }
    }
    pub(super) fn lowered(unit: LoweredUnit) -> Self {
        Self {
            inner: Input::Lowered(Box::new(unit)),
            admission: None,
        }
    }
    pub(super) fn with_admission(mut self, admission: Option<Admission>) -> Self {
        self.admission = admission;
        self
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
        let value = match self.inner {
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
                        key: admission.key,
                        reads: admission.reads,
                        versions: admission.versions,
                        value: RecordValue::Executable(value.shared_artifact()),
                        relative_debug: admission.relative_debug,
                        required_types: value.required_types().to_vec(),
                        modified_recipes: value
                            .modified_recipes()
                            .expect("reusable contribution has source recipes")
                            .to_vec(),
                    };
                    store
                        .records
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .insert(value.identity(), Arc::new(record));
                    store.admitted.fetch_add(1, Ordering::Relaxed);
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
    /// Idle pressure release preserves code, observation ledgers and rebind
    /// recipes. Numeric link/wire answers are recreated on the next request.
    pub(crate) fn release_bound_images(&self) -> usize {
        let records = self.records.lock().unwrap_or_else(|e| e.into_inner());
        records.values().fold(0usize, |released, record| {
            released.saturating_add(match &record.value {
                RecordValue::Executable(artifact) => artifact.release_bound_images(),
                RecordValue::Selections { .. } => 0,
            })
        })
    }
    pub(super) fn capture_excluded(&self) {
        self.declines
            .capture_excluded
            .fetch_add(1, Ordering::Relaxed);
    }
    pub(super) fn retain_current(&self, frontend: &ColdFrontend) {
        let identities: std::collections::BTreeSet<_> = frontend
            .bodies
            .iter()
            .filter_map(|body| {
                source_unit_identity(frontend, body)
                    .ok()
                    .map(|source| source.identity)
            })
            .collect();
        let mut records = self.records.lock().unwrap_or_else(|e| e.into_inner());
        let before = records.len();
        records.retain(|identity, _| identities.contains(identity));
        self.pruned
            .fetch_add((before - records.len()) as u64, Ordering::Relaxed);
    }
    #[allow(clippy::too_many_arguments)]
    pub(super) fn lookup<R: Resolver>(
        &self,
        key: &[u8],
        host: &R,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        prepared: &PreparedUnit,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        selections_only: bool,
    ) -> Option<CompletedInput> {
        let identity = source_unit_identity(frontend, body)
            .map_err(|_| {
                self.declines
                    .source_identity
                    .fetch_add(1, Ordering::Relaxed);
            })
            .ok()?
            .identity;
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
        if record.key.as_ref() != key {
            self.declines.key_changed.fetch_add(1, Ordering::Relaxed);
            return None;
        }
        let matching = crate::lowering_memo::matching_domains(&record.versions, host);
        if record.reads.iter().any(|read| {
            !matching.contains(&read.query.domain())
                && !same_meaning(&host.resolve(read.query), &read.answer)
        }) {
            self.declines.read_changed.fetch_add(1, Ordering::Relaxed);
            return None;
        }
        let artifact = match &record.value {
            RecordValue::Selections { facts, abi } => {
                if !selections_only
                    || prepared.require_production_abi().is_err()
                    || prepared.abi.as_ref()?.canonical_bytes().as_slice() != abi.as_slice()
                {
                    return None;
                }
                self.reused.fetch_add(1, Ordering::Relaxed);
                let current = source_unit_identity(frontend, body).ok()?;
                return Some(CompletedInput::selections(
                    current.identity,
                    current.effective,
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
        let contribution = crate::symbolic::PreparedContribution::rebind_with_modified(
            artifact,
            frontend,
            body,
            prepared,
            debug,
            &record.required_types,
            modified_seeds,
            Some(record.modified_recipes.clone()),
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
    relative_debug: Vec<usize>,
    write_compact: bool,
) -> Option<Admission> {
    let store = memo.symbolic.clone();
    let disk = write_compact.then(|| memo.completion_writer()).flatten();
    if store.is_none() && disk.is_none() {
        return None;
    }
    Some(Admission {
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
    promotion: &crate::lowering_memo_wire::ResidentPromotion,
) -> Option<Admission> {
    Some(Admission {
        store: Some(Arc::clone(memo.symbolic.as_ref()?)),
        disk: None,
        key: key.into(),
        reads: promotion
            .queries
            .iter()
            .map(|query| ResolverRead {
                query: *query,
                domain: query.domain(),
                answer: host.resolve(*query),
            })
            .collect::<Vec<_>>()
            .into(),
        versions: promotion.versions.clone().into(),
        relative_debug: promotion.relative_debug.clone(),
    })
}
pub(super) fn remember_selections<R: Resolver>(
    memo: &crate::lowering_memo::ProcedureMemo,
    key: Vec<u8>,
    host: &R,
    promotion: &crate::lowering_memo_wire::ResidentPromotion,
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
        key: admission.key,
        reads: admission.reads,
        versions: admission.versions,
        value: RecordValue::Selections {
            facts: Arc::clone(facts),
            abi: abi.canonical_bytes(),
        },
        relative_debug: Vec::new(),
        required_types: Vec::new(),
        modified_recipes: Vec::new(),
    };
    store
        .records
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .insert(identity, Arc::new(record));
    store.admitted.fetch_add(1, Ordering::Relaxed);
}
pub(super) fn accepted_admission(
    memo: &crate::lowering_memo::ProcedureMemo,
    key: Vec<u8>,
    accepted: &dm_session::AcceptedArtifact<crate::lowering_memo::CachedProcedure>,
) -> Option<Admission> {
    Some(Admission {
        store: Some(Arc::clone(memo.symbolic.as_ref()?)),
        disk: None,
        key: key.into(),
        reads: Arc::clone(&accepted.reads),
        versions: Arc::clone(&accepted.versions),
        relative_debug: accepted.value.relative_debug.clone(),
    })
}
