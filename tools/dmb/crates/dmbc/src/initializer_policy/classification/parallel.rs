//! Per-type independent evaluation; token issuance and output ordering remain serial.
use super::token_roster::preparation::{Bucket, Policy, Preparation};
use super::*;
mod demand;
use demand::ParallelDemand;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};
fn map_buckets<T: Send>(
    buckets: &[Bucket],
    evaluator: ParallelEvaluator<'_>,
    executor: &dm_exec::BuildExecutor,
    operation: impl Fn(usize, &Bucket, &dyn CapturedInitializerEvaluator) -> T + Sync,
) -> Result<Vec<T>, ClassificationError> {
    let next = AtomicUsize::new(0);
    let outputs: Vec<Mutex<Option<T>>> = (0..buckets.len()).map(|_| Mutex::new(None)).collect();
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for _ in 0..executor.workers().min(buckets.len()) {
                let next = &next;
                let outputs = &outputs;
                let operation = &operation;
                scope.spawn(move |_| {
                    let _stage = dm_profile::stage("initializer.classification");
                    let mut calls = 0;
                    evaluator
                        .factory
                        .with_evaluator(evaluator.engine, &mut |worker| {
                            calls += 1;
                            assert_eq!(calls, 1, "initializer factory invoked its operation twice");
                            loop {
                                let index = next.fetch_add(1, Ordering::Relaxed);
                                let Some(bucket) = buckets.get(index) else {
                                    break;
                                };
                                *outputs[index]
                                    .lock()
                                    .expect("initializer result lock poisoned") =
                                    Some(operation(index, bucket, worker));
                            }
                        });
                    assert_eq!(calls, 1, "initializer factory did not invoke its operation");
                });
            }
        })
    }))
    .map_err(|_| ClassificationError {
        issues: vec![ClassificationIssue {
            kind: ClassificationIssueKind::Unsupported,
            source_ordinal: 0,
            reason: "initializer classification worker panicked".into(),
        }],
    })?;
    Ok(outputs
        .into_iter()
        .map(|output| {
            output
                .into_inner()
                .expect("initializer result lock poisoned")
                .expect("initializer evaluator factory must call its operation once")
        })
        .collect())
}
pub(in crate::initializer_policy) fn classify(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: ParallelEvaluator<'_>,
    debug_defined: bool,
    executor: &dm_exec::BuildExecutor,
) -> Result<ClassifiedInitializers, ClassificationError> {
    classify_with_reuse(writes, symbols, evaluator, debug_defined, executor, None)
}
pub(in crate::initializer_policy) fn classify_with_reuse(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: ParallelEvaluator<'_>,
    debug_defined: bool,
    executor: &dm_exec::BuildExecutor,
    reuse: Option<artifact::InitializerReuse<'_>>,
) -> Result<ClassifiedInitializers, ClassificationError> {
    classify_with_reuse_using::<super::demand::Compatibility>(writes,symbols,evaluator,debug_defined,executor,reuse)
}
pub(in crate::initializer_policy) fn classify_with_reuse_checked(writes:&[InitializerWrite],symbols:&SymbolTable,evaluator:ParallelEvaluator<'_>,debug_defined:bool,executor:&dm_exec::BuildExecutor,reuse:Option<artifact::InitializerReuse<'_>>)->Result<ClassifiedInitializers,InitializerClassificationFailure>{
    crate::daemon::control::checkpoint().map_err(InitializerClassificationFailure::Operational)?;
    let result=classify_with_reuse_using::<super::demand::Checked>(writes,symbols,evaluator,debug_defined,executor,reuse);
    if matches!(&result,Err(InitializerClassificationFailure::Operational(_))){return result;}
    // Completed semantic/empty/late-factory paths also belong to this operation.
    if let Err(actual)=crate::daemon::control::checkpoint(){if let Some(reuse)=reuse{reuse.store.roster.clear_preparation();}return Err(InitializerClassificationFailure::Operational(actual));}
    result
}
pub(in crate::initializer_policy) fn classify_with_reuse_using<D:ParallelDemand>(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: ParallelEvaluator<'_>,
    debug_defined: bool,
    executor: &dm_exec::BuildExecutor,
    reuse: Option<artifact::InitializerReuse<'_>>,
) -> Result<ClassifiedInitializers, D::ReportFailure> {
    let factory_policy = evaluator.factory.recording_policy_identity();
    if factory_policy.is_none() {
        if let Some(reuse) = reuse {
            artifact::retain_roster(reuse, &[]);
            reuse.store.roster.clear();
            reuse.store.modifiers.retain_keys(&[]);
            reuse
                .store
                .declined
                .fetch_add(writes.len() as u64, Ordering::Relaxed);
        }
    }
    let reuse = reuse.filter(|_| factory_policy.is_some());
    // One provider-bound context spans both modifier and value passes. It is
    // borrowed only by this wave; mutex/cell synchronization comes from the
    // existing ReceiptAdmission, and observing providers still replay exactly.
    let admission_host = reuse.map(|reuse| super::super::current_admission::Host(reuse.resolver));
    // Receipts are certified by the session's current answers when it has a query database.
    let answer = |query: &dm_ir::ResolveQuery| -> dm_ir::ResolvedMeaning {
        use dm_session::ObservationHost;
        admission_host
            .as_ref()
            .expect("answers exist only with an admission host")
            .answer_for_admission(query)
    };
    let answers = reuse
        .and_then(|reuse| reuse.store.query_db.as_deref())
        .map(|db| db.request_answers(&answer));
    let admission = admission_host.as_ref().map(|host| {
        dm_session::observations::ReceiptAdmission::with_oracle(
            host,
            answers.as_ref().map(|answers| {
                answers as &dyn dm_session::AnswerOracle<dm_ir::ResolveQuery, dm_ir::ResolvedMeaning>
            }),
        )
    });

    let phase = dm_profile::detail_timer("init.classify.preparation");
    let preparation = match reuse.filter(|reuse| reuse.store.roster_enabled) {
        Some(reuse) => reuse.store.roster.preparation(writes),
        None => Preparation::new(writes),
    };
    drop(phase);
    let buckets = preparation.buckets.as_ref();
    let phase = dm_profile::detail_timer("init.classify.modifier_keys");
    let modifier_keys = reuse.and_then(|reuse| {
        crate::initializer_policy::modifier_facts::keys_in(
            writes,
            evaluator,
            reuse,
            Some(&preparation),
        )
    });
    drop(phase);
    let phase = dm_profile::detail_timer("init.classify.modifier_facts");
    let facts = map_buckets(buckets,evaluator,executor,|_,bucket,worker|{
        D::modifiers(bucket.ordinals.iter().map(|&ordinal|&writes[ordinal]),symbols,worker,&bucket.ordinals,evaluator,reuse,modifier_keys.as_deref(),admission.as_ref())
    }).map_err(|error|{if let Some(reuse)=reuse{reuse.store.roster.clear_preparation();}D::semantic(error)})?;
    drop(phase);
    let mut issues = Vec::new();
    let mut operational = None;
    let mut admitted = Vec::with_capacity(facts.len());
    for facts in facts {
        match facts {
            Ok(facts) => admitted.push(facts),
            Err(error) => match D::split(error){Ok(source)=>issues.extend(source.issues),Err(actual)=>if operational.is_none(){operational=Some(actual)}},
        }
    }
    if let Some(actual)=operational{if let Some(reuse)=reuse{reuse.store.roster.clear_preparation();}return Err(D::operational(actual));}
    if !issues.is_empty() {
        if let Some(reuse) = reuse {
            reuse.store.roster.clear_preparation();
        }
        issues.sort_by_key(|issue| issue.source_ordinal);
        return Err(D::semantic(ClassificationError { issues }));
    }
    let phase = dm_profile::detail_timer("init.classify.locators");
    let locators = reuse.map(|reuse| {
        let policy = factory_policy.expect("certified reuse policy");
        let preparation_policy = Policy {
            classification: reuse.policy,
            factory: policy,
            resource: reuse.resource_search_context,
            engine: evaluator.engine.map(|engine| engine.identity()),
        };
        if reuse.store.roster_enabled {
            if let Some(keys) = modifier_keys.as_ref().and_then(|keys| {
                preparation.admitted_locations(keys, &admitted, preparation_policy)
            }) {
                artifact::retain_roster(reuse, &keys.keys);
                return keys.keys.clone();
            }
        }
        let mut ordered_facts = vec![None; writes.len()];
        for (bucket, facts) in buckets.iter().zip(&admitted) {
            for (&ordinal, &fact) in bucket.ordinals.iter().zip(facts) {
                ordered_facts[ordinal] = Some(fact);
            }
        }
        let ordered_facts: Vec<_> = ordered_facts
            .into_iter()
            .map(|fact| fact.expect("modifier buckets cover the write roster"))
            .collect();
        let mut duplicates = std::collections::HashMap::<Vec<u8>, usize>::new();
        let keys = Arc::new(
            writes
                .iter()
                .zip(&ordered_facts)
                .map(|(write, &fact)| {
                    let mut key = artifact::key(write, fact, reuse, policy);
                    let duplicate = duplicates.entry(key.clone()).or_default();
                    key.extend_from_slice(&(*duplicate as u32).to_le_bytes());
                    *duplicate += 1;
                    Arc::<[u8]>::from(key)
                })
                .collect::<Vec<_>>(),
        );
        artifact::retain_roster(reuse, &keys);
        if reuse.store.roster_enabled {
            if let Some(inputs) = modifier_keys.as_ref() {
                preparation.remember_locations(
                    inputs,
                    ordered_facts,
                    keys.clone(),
                    preparation_policy,
                );
            }
        }
        keys
    });
    // No evaluation begins unless every modifier boundary was admitted.
    // Request-local physical sharing only. The pool disappears after this pass;
    // admitted receipts hold their leaves and replay every original observation.
    drop(phase);
    let phase = dm_profile::detail_timer("init.classify.values");
    let mut tokens = super::token_owner::RequestTokens::new(
        debug_defined,
        reuse.map(|reuse| reuse.store.roster.as_ref()),
    );
    let receipt_pool = reuse.map(|_| crate::shared_store::receipt_pool::<_, _, _>("initializer.classification"));
    let classified = map_buckets(buckets, evaluator, executor, |index, bucket, worker| {
        let mut ordinal = 0;
        let result = if let Some(reuse) = reuse {
            bucket
                .ordinals
                .iter()
                .enumerate()
                .map(|(local, &global)| {
                    ordinal = local;
                    artifact::classify_one_keyed_grouped_with::<D>(
                        &writes[global],
                        symbols,
                        worker,
                        admitted[index][local],
                        global,
                        evaluator,
                        reuse,
                        locators.as_ref().map(|keys| &keys[global]),
                        receipt_pool.as_deref().filter(|_| bucket.ordinals.len() > 1),
                        modifier_keys
                            .as_ref()
                            .map(|keys| keys[global].shared_input()),
                        Some(&tokens),
                        admission.as_ref(),
                    )
                })
                .collect()
        } else {
            classify_pending_with::<D>(
                bucket.ordinals.iter().map(|&ordinal| &writes[ordinal]),
                symbols,
                worker,
                &admitted[index],
                &mut ordinal,
            )
        };
        // Check while this exact worker operation/control context is still live,
        // including genuine semantic exits, before the factory callback unwinds.
        D::finish(result).map_err(|failure| D::failure(failure,bucket.ordinals[ordinal]))
    })
    .map_err(|error| {
        if let Some(reuse) = reuse {
            reuse.store.roster.clear_preparation();
        }
        D::semantic(error)
    })?;
    drop(phase);
    let _phase = dm_profile::detail_timer("init.classify.finish");
    let mut ordered: Vec<Option<PendingWrite>> = (0..writes.len()).map(|_| None).collect();
    let mut errors = Vec::new();
    let mut operational = None;
    for (bucket, result) in buckets.iter().zip(classified) {
        match result {
            Ok(pending) => {
                for (ordinal, mut pending) in bucket.ordinals.iter().copied().zip(pending) {
                    pending.write.source_ordinal = ordinal;
                    ordered[ordinal] = Some(pending);
                }
            }
            Err(error) => match D::split(error){Ok(source)=>errors.push(source.issues),Err(actual)=>if operational.is_none(){operational=Some(actual)}},
        }
    }
    if let Some(actual)=operational{if let Some(reuse)=reuse{reuse.store.roster.clear_preparation();}return Err(D::operational(actual));}
    if let Some(issues) = errors
        .into_iter()
        .min_by_key(|issues| issues[0].source_ordinal)
    {
        if let Some(reuse) = reuse {
            reuse.store.roster.clear_preparation();
        }
        return Err(D::semantic(ClassificationError { issues }));
    }
    let mut source_ordinal = 0;
    let pending = ordered
        .into_iter()
        .map(|pending| pending.expect("all successful initializer buckets cover source roster"));
    let result = match reuse {
        Some(reuse) if reuse.store.roster_enabled => reuse.store.roster.finish_shared(
            pending.collect(),
            debug_defined,
            &mut source_ordinal,
            tokens.issuer(),
        ),
        _ => finish_pending_shared(pending, &mut source_ordinal, tokens.issuer()),
    };
    result.map_err(|reason| {
        if let Some(reuse) = reuse {
            reuse.store.roster.clear_preparation();
        }
        D::semantic(ClassificationError {
            issues: vec![ClassificationIssue {
                kind: ClassificationIssueKind::Unsupported,
                source_ordinal,
                reason,
            }],
        })
    })
}

#[cfg(test)]
#[path="parallel_checked_tests.rs"]
mod checked_tests;
