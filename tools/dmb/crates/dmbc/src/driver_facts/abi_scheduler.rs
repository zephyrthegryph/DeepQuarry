//! Current-request scheduling over actual retained ABI receipts.
use super::*;
use crate::procedure_policy::PreparedAbi;
use abi_artifacts::{
    observations::{Answer, Current, Domain, Inputs, Query},
    Artifact,
};
use dm_session::{ObservedArtifactStorageView, Receipt};
use std::{collections::BTreeSet, sync::Mutex};

#[derive(Clone)]
struct Candidate {
    unit: Arc<abi_artifacts::UnitArtifact>,
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
) -> Admitted {
    let Some(batch) = batch else {
        return Admitted::default();
    };
    let Ok(roster) = frontend.callable_roster() else {
        return Admitted::default();
    };
    store.store.enable_incidence();
    let collect_stage = dm_profile::stage("abi.sched.collect");
    let mut candidates = BTreeMap::new();
    let Ok(Some(current_roster)) = frontend.callable_abi_roster() else {
        return Admitted::default();
    };
    let entries = current_roster.entries();
    // The existing batch is a source of candidates, never an admission verdict.
    // Structural roster changes retain exact per-unit receipts on that same owner.
    let current_keys: BTreeSet<_> = entries
        .iter()
        .map(|entry| abi_artifacts::observations::locator(identity(entry.identity)))
        .collect();
    store
        .store
        .visit_key_storage(std::iter::once(abi_artifacts::batch::KEY), |view| {
            if let ObservedArtifactStorageView::Entry { value, .. } = view {
                if let Artifact::Batch(recipe) = value.as_ref() {
                    for row in recipe.rows.iter() {
                        let key = abi_artifacts::observations::locator(identity(row.identity));
                        if current_keys.contains(&key) {
                            candidates.insert(
                                key,
                                Candidate {
                                    unit: row.unit.clone(),
                                    reads: row.reads.clone(),
                                    versions: row.versions.clone(),
                                },
                            );
                            store
                                .batch_rows_selected
                                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                        }
                    }
                }
            }
        });
    let missing: Vec<_> = current_keys
        .iter()
        .filter(|key| !candidates.contains_key(*key))
        .cloned()
        .collect();
    // Snapshot only actual current callable candidates, using the existing exact
    // key bucket index. No other artifact/batch/output owner is cloned or scanned.
    store
        .store
        .visit_key_storage(missing.iter().map(|key| key.as_ref()), |view| {
            if let ObservedArtifactStorageView::Entry {
                key,
                reads,
                versions,
                value,
            } = view
            {
                let Artifact::Unit(unit) = value.as_ref() else {
                    return;
                };
                store
                    .candidate_rows_collected
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                // AbiArtifacts uses current_revision: one variant per exact key.
                // If history is enabled later, this selection is only a hint:
                // current Inputs and the complete semantic receipt below still
                // authorize reuse; a nonmatching selected variant merely misses.
                candidates.insert(
                    key.clone(),
                    Candidate {
                        unit: unit.clone(),
                        reads: reads.clone(),
                        versions: versions.clone(),
                    },
                );
            }
        });
    let mut layouts = HashMap::new();
    for entry in entries {
        let identity = identity(entry.identity);
        if let Some(candidate) = candidates.get(&abi_artifacts::observations::locator(identity)) {
            layouts.insert(entry.member, candidate.unit.abi.clone());
        }
    }

    drop(collect_stage);
    dm_profile::request_mark("abi.sched.collected");
    let validate_stage = dm_profile::stage("abi.sched.validate");
    let inherited = DriverInheritedFacts {
        frontend,
        engine,
        source_layouts: &layouts,
        boundaries,
        unit_members: index,
    };
    // The incidence-qualified roster walks every retained receipt (~3 s on
    // DeepQuarry); full per-row validation below costs a fraction of that.
    // DMB_ABI_QUALIFIED_ROSTER=1 restores it.
    let use_qualified = std::env::var_os("DMB_ABI_QUALIFIED_ROSTER").is_some_and(|value| value == "1");
    let mut qualified = admission.filter(|_| use_qualified).map(|request| {
        store
            .store
            .unchanged_local_candidate_roster(request, Domain::Inputs)
    });
    dm_profile::request_mark("abi.sched.qualified_roster");
    let mut qualified_ordinals = BTreeSet::new();
    let mut accepted = BTreeMap::new();
    let mut dirty = BTreeSet::new();
    // The shared incidence subscription capability selects qualified candidates.
    // Do not rebuild a second coarse domain-delta hint by walking every unit's
    // version array. Uncovered rows still replay their exact current receipts.
    // Decline reasons: no candidate, predecessor lookup, predecessor moved,
    // inherited admission, changed receipt read.
    let mut reasons = [0usize; 5];
    let validate_full = |ordinal: usize, entry: &dm_tree::frontend::CallableAbiEntry| -> Result<Candidate, usize> {
        let identity = identity(entry.identity);
        let key = abi_artifacts::observations::locator(identity);
        let candidate = candidates.get(&key);
        let _ = &key;
            let Some(candidate) = candidate else {
                return Err(0);
            };
            let Ok(predecessor) = inherited.source_predecessor(entry.member) else {
                return Err(1);
            };
            if predecessor != entry.predecessor {
                return Err(2);
            }
            let context = AbiContext {
                identity,
                symbols: evaluator.symbols,
                origin: &frontend.bodies[ordinal].source,
                resolver: evaluator.resolver,
            };
            let structural_stage = dm_profile::stage("abi.sched.structural");
            let structural = abi_artifacts::observations::structural_inputs(frontend, entry.member);
            drop(structural_stage);
            let current = Current {
                inputs: Arc::new(Inputs {
                    definition: structural.as_ref().map(|(definition, _)| *definition),
                    ancestry: structural.map(|(_, ancestry)| ancestry),
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
            // Unissued, observing or uncovered candidates retain full validation.
            let inherited_stage = dm_profile::stage("abi.sched.inherited");
            if inherited.inherited(&context).is_err() {
                return Err(3);
            }
            drop(inherited_stage);
            let _changed_stage = dm_profile::stage("abi.sched.changed");
            if abi_artifacts::admission::changed(
                &candidate.reads,
                &candidate.versions,
                &current,
                admission,
            )
            .is_some()
            {
                return Err(4);
            }
            Ok(candidate.clone())
    };
    // Without the qualified roster every row takes full, independent
    // validation: run it on the worker pool, then merge in roster order.
    let parallel: Option<Vec<Result<Candidate, usize>>> = qualified.is_none().then(|| {
        entries
            .par_iter()
            .enumerate()
            .map(|(ordinal, entry)| validate_full(ordinal, entry))
            .collect()
    });
    for (ordinal, entry) in entries.iter().enumerate() {
        let identity = identity(entry.identity);
        let key = abi_artifacts::observations::locator(identity);
        let candidate = candidates.get(&key);
        let valid = if let Some(results) = &parallel {
            results[ordinal].clone()
        } else { (|| {
            let Some(candidate) = candidate else {
                return Err(0);
            };
            let Ok(predecessor) = inherited.source_predecessor(entry.member) else {
                return Err(1);
            };
            if predecessor != entry.predecessor {
                return Err(2);
            }
            let context = AbiContext {
                identity,
                symbols: evaluator.symbols,
                origin: &frontend.bodies[ordinal].source,
                resolver: evaluator.resolver,
            };
            let structural_stage = dm_profile::stage("abi.sched.structural");
            let structural = abi_artifacts::observations::structural_inputs(frontend, entry.member);
            drop(structural_stage);
            let current = Current {
                inputs: Arc::new(Inputs {
                    definition: structural.as_ref().map(|(definition, _)| *definition),
                    ancestry: structural.map(|(_, ancestry)| ancestry),
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
            // Only the independently issued local Inputs gap can be licensed.
            // Every semantic/negative edge must have an unchanged qualified version.
            if current.inputs.ancestry.is_some() && current.inputs.definition.is_some() {
                for token in qualified
                    .as_mut()
                    .into_iter()
                    .flat_map(|roster| roster.take(&key))
                {
                    if let Some((_, artifact)) = token.admit_local_current(
                        |read| matches!((&read.query, &read.answer),
                            (Query::Inputs, Answer::Inputs(old)) if old.as_ref() == current.inputs.as_ref()),
                        |actual, value| actual == key.as_ref() && matches!(value.as_ref(), Artifact::Unit(unit)
                            if Arc::ptr_eq(unit, &candidate.unit)),
                        |_| {},
                    ) {
                        if let Artifact::Unit(unit) = artifact.value.as_ref() {
                            qualified_ordinals.insert(ordinal);
                            return Ok(Candidate { unit: unit.clone(), reads: artifact.reads, versions: artifact.versions });
                        }
                    }
                }
            }
            // Unissued, observing or uncovered candidates retain full validation.
            let inherited_stage = dm_profile::stage("abi.sched.inherited");
            if inherited.inherited(&context).is_err() {
                return Err(3);
            }
            drop(inherited_stage);
            let _changed_stage = dm_profile::stage("abi.sched.changed");
            if abi_artifacts::admission::changed(
                &candidate.reads,
                &candidate.versions,
                &current,
                admission,
            )
            .is_some()
            {
                return Err(4);
            }
            Ok(candidate.clone())
        })() };
        match valid {
            Ok(candidate) => {
                accepted.insert(ordinal, candidate);
            }
            Err(reason) => {
                reasons[reason] += 1;
                dirty.insert(ordinal);
            }
        }
    }
    drop(validate_stage);
    dm_profile::request_mark("abi.sched.validated");
    // Immediate edges retain failure blocking. Formal edges separately carry
    // selected inherited layouts across intervening nonformal overrides.
    let mut formal = vec![Vec::new(); entries.len()];
    for (ordinal, entry) in entries.iter().enumerate() {
        if let Some(parent) = entry.predecessor.and_then(|member| roster.ordinal(member)) {
            formal[parent].push(ordinal);
        }
    }
    let dirty_roots_len = dirty.len();
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
    // Individually valid rows that are dirty only through an ancestor stay
    // provisional: the wave loop accepts one once every direct parent's final
    // ABI equals the candidate layout this row was validated against.
    let tree = &frontend.snapshot.tree;
    let mut provisional = BTreeMap::new();
    let mut accepted_now = BTreeMap::new();
    let dirty_roots = dirty_roots_len;
    for (ordinal, candidate) in accepted {
        if dirty.contains(&ordinal) {
            let member = entries[ordinal].member;
            provisional.insert(
                ordinal,
                Provisional {
                    candidate,
                    qualified: qualified_ordinals.contains(&ordinal),
                    identity: identity(entries[ordinal].identity),
                    parents: [
                        tree.member(member).and_then(|node| node.previous),
                        entries[ordinal].predecessor,
                    ],
                },
            );
        } else {
            accepted_now.insert(ordinal, candidate);
        }
    }
    crate::daemon_eprintln!(
        "native ABI schedule: entries={} candidates={} accepted={} dirty_roots={} propagated_provisional={} dirty_total={} declines(no_candidate,predecessor_lookup,predecessor_moved,inherited,changed)={:?}",
        entries.len(),
        candidates.len(),
        accepted_now.len(),
        dirty_roots,
        provisional.len(),
        dirty.len(),
        reasons
    );
    let accepted = accepted_now
        .into_iter()
        .map(|(ordinal, candidate)| {
            let qualified = qualified_ordinals.contains(&ordinal);
            let identity = identity(entries[ordinal].identity);
            (ordinal, finish(store, keys, capture, identity, &candidate, qualified))
        })
        .collect();
    Admitted {
        accepted,
        provisional,
        candidate_layouts: layouts,
    }
}

/// Scheduler verdicts for this request (see [`admitted`]).
#[derive(Default)]
pub(super) struct Admitted {
    pub(super) accepted: BTreeMap<usize, crate::procedure_policy::PreparedUnit>,
    pub(super) provisional: BTreeMap<usize, Provisional>,
    /// The retained candidate layout per member that validation compared with.
    pub(super) candidate_layouts: HashMap<MemberId, Arc<PreparedAbi>>,
}

pub(super) struct Provisional {
    candidate: Candidate,
    qualified: bool,
    identity: UnitIdentity,
    /// Immediate (`previous`) and formal predecessor members.
    pub(super) parents: [Option<MemberId>; 2],
}

impl Provisional {
    pub(super) fn accept(
        &self,
        store: &AbiArtifacts,
        keys: &Mutex<Vec<Arc<[u8]>>>,
        capture: Option<&abi_artifacts::batch::Capture>,
    ) -> crate::procedure_policy::PreparedUnit {
        store
            .provisional_reused
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        finish(store, keys, capture, self.identity, &self.candidate, self.qualified)
    }
}

fn finish(
    store: &AbiArtifacts,
    keys: &Mutex<Vec<Arc<[u8]>>>,
    capture: Option<&abi_artifacts::batch::Capture>,
    identity: UnitIdentity,
    candidate: &Candidate,
    qualified: bool,
) -> crate::procedure_policy::PreparedUnit {
    if qualified {
        store
            .qualified_reused
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }
    let unit = &candidate.unit;
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
    crate::procedure_policy::PreparedUnit {
        canonical: unit.canonical.clone(),
        inputs: unit.inputs.clone(),
        abi: Some(unit.abi.clone()),
        executable_body: Vec::new(),
    }
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

/// Current scheduler admission already closes both immediate failure and formal
/// inherited-layout edges. Seed those exact owners once, leaving only dirty
/// roots for the existing executor; this is not source-only skip authority.
pub(super) struct Seed {
    pub(super) layouts: HashMap<MemberId, Arc<PreparedAbi>>,
    pub(super) remaining: Vec<bool>,
    pub(super) results: Vec<Option<crate::procedure_policy::PreparedUnit>>,
    pub(super) ready: Vec<usize>,
}
pub(super) fn seed(
    frontend: &ColdFrontend,
    roster: &dm_tree::frontend::CallableRoster,
    admitted: BTreeMap<usize, crate::procedure_policy::PreparedUnit>,
) -> Result<Seed, AbiError> {
    let mut seed = Seed {
        layouts: HashMap::new(),
        remaining: vec![true; frontend.bodies.len()],
        results: (0..frontend.bodies.len()).map(|_| None).collect(),
        ready: Vec::new(),
    };
    let mut roots: BTreeSet<_> = roster.ready().iter().copied().collect();
    for (ordinal, mut unit) in admitted {
        let body = frontend
            .bodies
            .get(ordinal)
            .ok_or_else(|| AbiError::invariant("admitted ABI ordinal outside current frontend"))?;
        unit.require_production_abi()?;
        unit.executable_body = Vec::new();
        if unit.canonical.is_none() {
            unit.issue_canonical();
        }
        seed.layouts.insert(
            body.member,
            unit.abi.as_ref().expect("validated production ABI").clone(),
        );
        seed.results[ordinal] = Some(unit);
        seed.remaining[ordinal] = false;
        roots.extend(roster.dependents(ordinal).iter().copied());
    }
    seed.ready = roots
        .into_iter()
        .filter(|ordinal| seed.remaining[*ordinal])
        .collect();
    Ok(seed)
}
