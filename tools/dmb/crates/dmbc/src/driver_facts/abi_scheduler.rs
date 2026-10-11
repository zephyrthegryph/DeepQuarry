//! Current-request scheduling over actual retained ABI receipts.
use super::*;
use abi_artifacts::{
    observations::{Answer, Current, Domain, Inputs, Query},
    Artifact,
};
use dm_session::{ObservedArtifactStorageView, Receipt};
use std::{collections::BTreeSet, sync::Mutex};

struct Candidate {
    value: Arc<Artifact>,
    reads: Receipt<Query, Answer, Domain>,
    versions: Arc<[(Domain, u128)]>,
}
/// No verdict survives this request. Missing certificates use ordinary exact
/// replay; local Inputs and the actual current predecessor are never certified
/// by reverse incidence or a semantic-tree identity.
#[allow(clippy::too_many_arguments)]
pub(super) fn admitted(
    store: &AbiArtifacts,
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    evaluator: &DriverEvaluator<'_>,
    boundaries: &BTreeMap<UnitIdentity, BoundaryAbi>,
    resource: Option<u128>,
    lexical: bool,
    index: &BTreeMap<UnitIdentity, MemberId>,
    admission: Option<&abi_artifacts::admission::Admission<'_>>,
    batch: Option<&abi_artifacts::batch::Inputs>,
    keys: &Mutex<Vec<Arc<[u8]>>>,
    capture: Option<&abi_artifacts::batch::Capture>,
) -> BTreeMap<usize, crate::procedure_policy::PreparedUnit> {
    let Some(batch) = batch else {
        return BTreeMap::new();
    };
    let Ok(roster) = frontend.callable_roster() else {
        return BTreeMap::new();
    };
    store.store.enable_incidence();
    let mut candidates = BTreeMap::new();
    let mut changed_domains = BTreeSet::new();
    store.store.visit_storage(|view| {
        if let ObservedArtifactStorageView::Entry {
            key,
            reads,
            versions,
            value,
        } = view
        {
            if !matches!(value.as_ref(), Artifact::Unit(_)) {
                return;
            }
            candidates.insert(
                key.clone(),
                Candidate {
                    value: value.clone(),
                    reads: reads.clone(),
                    versions: versions.clone(),
                },
            );
        }
    });
    for candidate in candidates.values() {
        let versions = &candidate.versions;
        for (domain, previous) in versions.iter() {
            if let Domain::Semantic(domain) = domain {
                let now = admission
                    .map(|request| request.current_version(&Domain::Semantic(*domain)))
                    .unwrap_or_else(|| evaluator.resolver.domain_version(*domain));
                if now.is_some_and(|now| now != *previous) {
                    changed_domains.insert(Domain::Semantic(*domain));
                }
            }
        }
    }
    let mut dirty_keys = BTreeSet::new();
    store.store.visit_affected(
        &changed_domains.into_iter().collect::<Vec<_>>(),
        |key, _| {
            dirty_keys.insert(key.clone());
        },
    );
    let entries = batch.roster.entries();
    let mut layouts = HashMap::new();
    for entry in entries {
        let identity = identity(entry.identity);
        if let Some(Candidate { value, .. }) =
            candidates.get(&abi_artifacts::observations::locator(identity))
        {
            if let Artifact::Unit(unit) = value.as_ref() {
                layouts.insert(entry.member, unit.abi.clone());
            }
        }
    }
    let inherited = DriverInheritedFacts {
        frontend,
        engine,
        source_layouts: &layouts,
        boundaries,
        unit_members: index,
    };
    let mut accepted = BTreeMap::new();
    let mut dirty = BTreeSet::new();
    // Incidence prioritizes possibly changed receipts; it never establishes
    // semantic invalidation. Coarse version changes still replay exact answers.
    let encounter = entries.iter().enumerate();
    let (affected, remaining): (Vec<_>, Vec<_>) = encounter.partition(|(_, entry)| {
        dirty_keys.contains(&abi_artifacts::observations::locator(identity(
            entry.identity,
        )))
    });
    for (ordinal, entry) in affected.into_iter().chain(remaining) {
        let identity = identity(entry.identity);
        let key = abi_artifacts::observations::locator(identity);
        let candidate = candidates.get(&key);
        let valid = (|| {
            let candidate = candidate?;
            let predecessor = inherited.source_predecessor(entry.member).ok()?;
            if predecessor != entry.predecessor {
                return None;
            }
            let context = AbiContext {
                identity,
                symbols: evaluator.symbols,
                origin: &frontend.bodies[ordinal].source,
                resolver: evaluator.resolver,
            };
            inherited.inherited(&context).ok()?;
            let current = Current {
                inputs: Arc::new(Inputs {
                    metadata: entry.metadata.clone(),
                    predecessor: predecessor.and_then(|id| layouts.get(&id).cloned()),
                    engine: batch.engine.clone(),
                    boundary: abi_artifacts::observations::Boundary::capture(
                        boundaries.get(&identity),
                    ),
                    resource,
                    evaluation_resource: evaluator.resource_search_context,
                    lexical,
                    pure_policy: batch.pure_policy,
                }),
                resolver: evaluator.resolver,
            };
            if abi_artifacts::admission::changed(
                &candidate.reads,
                &candidate.versions,
                &current,
                admission,
            )
            .is_some()
            {
                return None;
            }
            Some(candidate)
        })();
        if let Some(candidate) = valid {
            accepted.insert(ordinal, candidate);
        } else {
            dirty.insert(ordinal);
        }
    }
    // Immediate edges retain failure blocking. Formal edges separately carry
    // selected inherited layouts across intervening nonformal overrides.
    let mut formal = vec![Vec::new(); entries.len()];
    for (ordinal, entry) in entries.iter().enumerate() {
        if let Some(parent) = entry.predecessor.and_then(|member| roster.ordinal(member)) {
            formal[parent].push(ordinal);
        }
    }
    let mut pending: Vec<_> = dirty.iter().copied().collect();
    while let Some(ordinal) = pending.pop() {
        for &child in roster
            .dependents(ordinal)
            .iter()
            .chain(formal[ordinal].iter())
        {
            if dirty.insert(child) {
                pending.push(child);
            }
        }
    }
    accepted.retain(|ordinal, _| !dirty.contains(ordinal));
    accepted
        .into_iter()
        .map(|(ordinal, candidate)| {
            let Artifact::Unit(unit) = candidate.value.as_ref() else {
                unreachable!()
            };
            let identity = identity(entries[ordinal].identity);
            keys.lock()
                .unwrap_or_else(|e| e.into_inner())
                .push(abi_artifacts::observations::locator(identity));
            abi_artifacts::batch::record(capture, identity, unit, &candidate.reads);
            store
                .scheduled_reused
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            store
                .reused
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            (
                ordinal,
                crate::procedure_policy::PreparedUnit {
                    canonical: unit.canonical.clone(),
                    inputs: unit.inputs.clone(),
                    abi: Some(unit.abi.clone()),
                    executable_body: Vec::new(),
                },
            )
        })
        .collect()
}
fn identity(value: dm_ir::ProcedureIdentity) -> UnitIdentity {
    UnitIdentity {
        owner: value.owner,
        name: value.name,
        namespace: if value.verb {
            Namespace::Verb
        } else {
            Namespace::Proc
        },
        occurrence: value.occurrence,
    }
}
