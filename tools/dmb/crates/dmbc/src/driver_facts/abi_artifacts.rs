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
pub(crate) enum Artifact {
    Unit(Arc<UnitArtifact>),
    Batch(Arc<batch::Recipe>),
}
pub struct AbiArtifacts {
    pub(super) store: dm_session::ObservedArtifactStore<Artifact, Query, Answer, Domain>,
    engine_owner: Option<Arc<crate::runner_host::EnginePayload>>,
    groups: dm_session::ReceiptGroupPool<Query, Answer, Domain>,
    pub(super) reused: AtomicUsize,
    recomputed: AtomicUsize,
    batch_reused: AtomicUsize,
    pub(super) scheduled_reused: AtomicUsize,
    pub(super) batch_rows_selected: AtomicUsize,
    pub(super) candidate_rows_collected: AtomicUsize,
}
impl Default for AbiArtifacts {
    fn default() -> Self {
        Self {
            store: dm_session::ObservedArtifactStore::current_revision(),
            engine_owner: None,
            groups: Default::default(),
            reused: AtomicUsize::new(0),
            recomputed: AtomicUsize::new(0),
            batch_reused: AtomicUsize::new(0),
            scheduled_reused: AtomicUsize::new(0),
            batch_rows_selected: AtomicUsize::new(0),
            candidate_rows_collected: AtomicUsize::new(0),
        }
    }
}
impl AbiArtifacts {
    pub(crate) fn with_engine_owner(engine_owner: Arc<crate::runner_host::EnginePayload>) -> Self {
        Self {
            engine_owner: Some(engine_owner),
            ..Self::default()
        }
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
    pub(crate) fn visit_incidence_buffer(&self, visit: impl FnMut(usize, usize, usize)) {
        self.store.visit_incidence_buffer(visit);
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
    pub(crate) fn visit_incidence_storage(
        &self,
        visit: impl FnMut(&Arc<[dm_session::Observation<Query, Answer, Domain>]>),
    ) -> Option<(usize, usize, usize, usize)> {
        self.store.visit_incidence_storage(visit)
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
        self.store
            .retain_current_keys(keys.iter().map(|key| key.as_ref()));
        self.groups.prune();
    }
}
struct BorrowedResolver<'a>(&'a dyn Resolver);
impl Resolver for BorrowedResolver<'_> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.0.resolve(query)
    }
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.0.domain_version(domain)
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
    inherited.inherited(context)?; // Current boundary/ancestry admission is not a cached certificate.
    let member = inherited
        .unit_members
        .get(&context.identity)
        .ok_or_else(|| AbiError::unsupported("body identity missing"))?;
    let predecessor = inherited
        .source_predecessor(*member)?
        .and_then(|previous| inherited.source_layouts.get(&previous));
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
            Ok(observations::Current {
                inputs: Arc::new(observations::Inputs {
                    metadata: Arc::clone(current_metadata),
                    predecessor: predecessor.cloned(),
                    engine: Arc::clone(engine),
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
    let key = observations::locator(context.identity);
    let base = BorrowedResolver(evaluator.resolver);
    if let Some(current) = &current {
        if let Some(accepted) = store
            .store
            .visit_receipted_with(
                &key,
                &mut |reads, versions| admission::changed(reads, versions, current, admission),
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
    let recording = dm_session::RecordingResolver::new(&base);
    recording.record_declaration_occurrence(dm_ir::ProcedureIdentity {
        owner: context.identity.owner,
        name: context.identity.name,
        verb: context.identity.namespace == Namespace::Verb,
        occurrence: context.identity.occurrence,
    });
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
    let mut unit = policy.prepare_view(metadata, parsed, &recorded_context)?;
    store.recomputed.fetch_add(1, Ordering::Relaxed);
    unit.issue_canonical();
    if let Some(current) = current {
        let abi = Arc::clone(
            unit.abi
                .as_ref()
                .ok_or_else(|| AbiError::invariant("production ABI missing"))?,
        );
        let inputs = Arc::clone(&unit.inputs);
        let reads = observations::reads(current.inputs, recording.reads());
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
        let versions: Vec<_> = recording
            .domain_receipts()
            .into_iter()
            .map(|(domain, version)| (Domain::Semantic(domain), version))
            .collect();
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
