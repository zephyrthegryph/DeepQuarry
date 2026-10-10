//! Trusted completion handoff; symbolic reuse never reuses output certificates.
use super::*;
use crate::lowering_memo::{RecordingResolver, ResolverRead};
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
    key: Vec<u8>,
    reads: Arc<[ResolverRead]>,
    versions: Arc<[(dm_ir::ReadDomain, u128)]>,
    artifact: Arc<crate::symbolic::ReusableProcedureArtifact>,
    relative_debug: Vec<usize>,
    required_types: Vec<dm_ir::SymbolId>,
    modified_recipes: Vec<crate::modified_initializers::SourceRecipe>,
}
pub(crate) struct Admission {
    store: Arc<SessionSymbolicMemo>,
    key: Vec<u8>,
    reads: Arc<[ResolverRead]>,
    versions: Arc<[(dm_ir::ReadDomain, u128)]>,
    relative_debug: Vec<usize>,
}
/// Fields are private: only the ordinary lowerer or exact memo validator issues it.
pub struct CompletedInput {
    inner: Input,
    admission: Option<Admission>,
}
enum Input {
    Lowered(Box<LoweredUnit>),
    Reused(crate::symbolic::PreparedContribution),
}
impl CompletedInput {
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
            Input::Lowered(unit) => unit.identity,
            Input::Reused(value) => value.identity(),
        }
    }
    pub fn effective(&self) -> bool {
        match &self.inner {
            Input::Lowered(unit) => unit.effective,
            Input::Reused(value) => value.effective(),
        }
    }
    pub(super) fn into_lowered(self) -> LoweredUnit {
        match self.inner {
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
            Input::Reused(value) => value,
            Input::Lowered(unit) => {
                unit.require_production_abi()
                    .map_err(|_| crate::cold::ColdError::NonAuthoritativeAbi)?;
                crate::symbolic::prepare_contribution(*unit, symbols, source, external, detail)
                    .map_err(crate::cold::ColdError::Linking)?
            }
        };
        if let Some(admission) = self.admission {
            if value.is_reusable() {
                let record = Record {
                    key: admission.key,
                    reads: admission.reads,
                    versions: admission.versions,
                    artifact: value.shared_artifact(),
                    relative_debug: admission.relative_debug,
                    required_types: value.required_types().to_vec(),
                    modified_recipes: value
                        .modified_recipes()
                        .expect("reusable contribution has source recipes")
                        .to_vec(),
                };
                admission
                    .store
                    .records
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .insert(value.identity(), Arc::new(record));
                admission.store.admitted.fetch_add(1, Ordering::Relaxed);
            } else {
                admission
                    .store
                    .declines
                    .nonreusable_completion
                    .fetch_add(1, Ordering::Relaxed);
            }
        }
        Ok(value)
    }
}
impl SessionSymbolicMemo {
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
    pub(super) fn lookup<R: Resolver>(
        &self,
        key: &[u8],
        host: &R,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        prepared: &PreparedUnit,
        bodies: &dm_tree::frontend::BodyArena<'_>,
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
        if record.key != key {
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
                            recipe.reissue(parsed, host, frontend.snapshot.tree.symbols(), &debug)
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
            &record.artifact,
            frontend,
            body,
            prepared,
            debug,
            &record.required_types,
            modified_seeds,
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
    key: Vec<u8>,
    recording: &RecordingResolver<'_, impl Resolver>,
    relative_debug: Vec<usize>,
) -> Option<Admission> {
    Some(Admission {
        store: Arc::clone(memo.symbolic.as_ref()?),
        key,
        reads: recording.reads().into(),
        versions: recording.domain_receipts().into(),
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
        store: Arc::clone(memo.symbolic.as_ref()?),
        key,
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
pub(super) fn accepted_admission(
    memo: &crate::lowering_memo::ProcedureMemo,
    key: Vec<u8>,
    accepted: &dm_session::AcceptedArtifact<crate::lowering_memo::CachedProcedure>,
) -> Option<Admission> {
    Some(Admission {
        store: Arc::clone(memo.symbolic.as_ref()?),
        key,
        reads: Arc::clone(&accepted.reads),
        versions: Arc::clone(&accepted.versions),
        relative_debug: accepted.value.relative_debug.clone(),
    })
}
