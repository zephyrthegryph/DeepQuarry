//! Successful ABI batches retain admitted unit owners, never request origins.
use super::{
    observations::{Answer, Boundary, Domain, Query},
    *,
};
use dm_session::{Observation, ObservationHost, Receipt};
use std::collections::BTreeMap;
const KEY: &[u8] = b"dm-process-abi-batch-v1\0";
#[derive(Clone)]
pub(crate) struct Inputs {
    pub(crate) roster: Arc<dm_tree::frontend::CallableAbiRoster>,
    pub(crate) engine: Arc<crate::runner_host::EnginePayload>,
    pub(crate) boundaries: BTreeMap<UnitIdentity, Boundary>,
    pub(crate) resource: Option<u128>,
    pub(crate) evaluation_resource: Option<u128>,
    pub(crate) lexical: bool,
    pub(crate) pure_policy: Option<u128>,
}
impl PartialEq for Inputs {
    fn eq(&self, b: &Self) -> bool {
        Arc::ptr_eq(&self.engine, &b.engine)
            && (Arc::ptr_eq(&self.roster, &b.roster) || self.roster == b.roster)
            && self.boundaries == b.boundaries
            && self.resource == b.resource
            && self.evaluation_resource == b.evaluation_resource
            && self.lexical == b.lexical
            && self.pure_policy == b.pure_policy
    }
}
impl Eq for Inputs {}
pub(in crate::driver_facts) type Capture =
    Mutex<BTreeMap<UnitIdentity, (Arc<UnitArtifact>, Receipt<Query, Answer, Domain>)>>;
pub(super) fn record(
    capture: Option<&Capture>,
    identity: UnitIdentity,
    unit: &Arc<UnitArtifact>,
    reads: &Receipt<Query, Answer, Domain>,
) {
    if let Some(capture) = capture {
        capture
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(identity, (unit.clone(), reads.clone()));
    }
}
pub(crate) struct Recipe {
    pub(crate) prepared: Arc<crate::driver_facts::PreparedAbiUnits>,
    pub(crate) keys: Vec<Arc<[u8]>>,
}
struct Current<'a> {
    inputs: Arc<Inputs>,
    resolver: &'a dyn Resolver,
}
impl ObservationHost<Query, Answer, Domain> for Current<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Inputs => Answer::Unissued,
            Query::BatchInputs => Answer::BatchInputs(self.inputs.clone()),
            Query::Semantic(query) => Answer::Semantic(self.resolver.resolve(*query)),
        }
    }
    fn version(&self, domain: &Domain) -> Option<u128> {
        match domain {
            Domain::Inputs | Domain::BatchInputs => None,
            Domain::Semantic(domain) => self.resolver.domain_version(*domain),
        }
    }
    fn equivalent(&self, a: &Answer, b: &Answer) -> bool {
        a == b
            || match (a, b) {
                (Answer::Semantic(a), Answer::Semantic(b)) => {
                    a.canonical_bytes() == b.canonical_bytes()
                }
                _ => false,
            }
    }
}
pub(in crate::driver_facts) fn inputs(
    store: &AbiArtifacts,
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    boundaries: &BTreeMap<UnitIdentity, BoundaryAbi>,
    evaluator: &DriverEvaluator<'_>,
    resource: Option<u128>,
    lexical: bool,
) -> Option<Arc<Inputs>> {
    if evaluator.resolver.observes_reads() {
        return None;
    }
    let engine = store
        .engine_owner
        .as_ref()
        .filter(|owner| std::ptr::eq(&owner.snapshot, engine))?;
    let roster = frontend.callable_abi_roster().ok()??;
    if roster.entries().is_empty() {
        return None;
    }
    let pure_policy = evaluator
        .pure_calls
        .map(|calls| calls.immutable_policy_identity());
    if matches!(pure_policy, Some(None)) {
        return None;
    }
    Some(Arc::new(Inputs {
        roster: roster.clone(),
        engine: engine.clone(),
        boundaries: boundaries
            .iter()
            .map(|(id, b)| (*id, Boundary::capture(Some(b))))
            .collect(),
        resource,
        evaluation_resource: evaluator.resource_search_context,
        lexical,
        pure_policy: pure_policy.flatten(),
    }))
}
pub(in crate::driver_facts) fn replay(
    store: &AbiArtifacts,
    inputs: &Arc<Inputs>,
    resolver: &dyn Resolver,
) -> Option<PreparedSourceAbi> {
    let current = Current {
        inputs: inputs.clone(),
        resolver,
    };
    let artifact = store
        .store
        .visit_receipted(KEY, &current, &mut |v| {
            matches!(v.as_ref(), Artifact::Batch(_))
        })
        .0?
        .value;
    let Artifact::Batch(recipe) = artifact.as_ref() else {
        return None;
    };
    // The same immutable producer owner carries complete coverage. No current
    // origin or body contexts are cached, and replay allocates no unit facade roster.
    let keys = Mutex::new(
        recipe
            .keys
            .iter()
            .cloned()
            .chain(std::iter::once(Arc::from(KEY)))
            .collect(),
    );
    store.prune(&keys);
    store
        .reused
        .fetch_add(recipe.prepared.entries().len(), Ordering::Relaxed);
    store.batch_reused.fetch_add(1, Ordering::Relaxed);
    Some(PreparedSourceAbi {
        units: recipe.prepared.clone(),
        diagnostics: Vec::new(),
    })
}
pub(in crate::driver_facts) fn remember(
    store: &AbiArtifacts,
    inputs: Arc<Inputs>,
    resolver: &dyn Resolver,
    capture: &Capture,
    prepared: &Arc<crate::driver_facts::PreparedAbiUnits>,
) {
    // Consume only actual chosen artifact owners/receipts from this producer.
    // Multiple historical variants of the same locator cannot substitute here.
    let mut admitted = std::mem::take(&mut *capture.lock().unwrap_or_else(|e| e.into_inner()));
    let mut keys = Vec::with_capacity(inputs.roster.entries().len());
    if prepared.entries().len() != inputs.roster.entries().len() {
        return;
    }
    let mut observations: BTreeMap<Query, Vec<Observation<Query, Answer, Domain>>> =
        BTreeMap::new();
    for (entry, (member, selected)) in inputs.roster.entries().iter().zip(prepared.entries()) {
        let identity = UnitIdentity {
            owner: entry.identity.owner,
            name: entry.identity.name,
            namespace: if entry.identity.verb {
                Namespace::Verb
            } else {
                Namespace::Proc
            },
            occurrence: entry.identity.occurrence,
        };
        let key = super::observations::locator(identity);
        let Some((unit, reads)) = admitted.remove(&identity) else {
            return;
        };
        // Capture must be the actual selected payload represented by this owner.
        if *member != entry.member
            || !Arc::ptr_eq(&selected.inputs, &unit.inputs)
            || !selected
                .abi
                .as_ref()
                .is_some_and(|abi| Arc::ptr_eq(abi, &unit.abi))
        {
            return;
        }
        keys.push(key);
        for read in reads
            .iter()
            .filter(|read| matches!(read.query, Query::Semantic(_)))
        {
            let values = observations.entry(read.query.clone()).or_default();
            if !values.contains(read) {
                values.push(read.clone());
            }
        }
    }
    let mut reads = vec![Observation {
        query: Query::BatchInputs,
        domain: Domain::BatchInputs,
        answer: Answer::BatchInputs(inputs),
    }];
    reads.extend(observations.into_values().flatten());
    let versions: Vec<_> = reads
        .iter()
        .filter_map(|read| match &read.domain {
            Domain::Semantic(domain) => resolver
                .domain_version(*domain)
                .map(|v| (read.domain.clone(), v)),
            _ => None,
        })
        .collect::<BTreeMap<_, _>>()
        .into_iter()
        .collect();
    let Ok(reads) = store.groups.intern_receipt(reads, |a, b| {
        matches!(
            (&a.query, &b.query),
            (Query::Semantic(_), Query::Semantic(_))
        ) && a.domain == b.domain
    }) else {
        return;
    };
    store.store.insert_with_receipt(
        Arc::from(KEY),
        reads,
        versions.into(),
        std::mem::size_of::<Recipe>(),
        || {
            Artifact::Batch(Arc::new(Recipe {
                prepared: prepared.clone(),
                keys,
            }))
        },
    );
}
