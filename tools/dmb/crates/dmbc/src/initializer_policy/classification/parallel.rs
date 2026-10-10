//! Per-type independent evaluation; token issuance and output ordering remain serial.
use super::*;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};
struct Bucket {
    ordinals: Vec<usize>,
}
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
    let factory_policy = evaluator.factory.recording_policy_identity();
    if factory_policy.is_none() {
        if let Some(reuse) = reuse {
            artifact::retain_roster(reuse, &[]);
            if let Some(keys) = &reuse.store.prepared_keys {
                keys.clear();
            }
            reuse.store.roster.clear();
            reuse.store.modifiers.retain_keys(&[]);
            reuse
                .store
                .declined
                .fetch_add(writes.len() as u64, Ordering::Relaxed);
        }
    }
    let reuse = reuse.filter(|_| factory_policy.is_some());
    let mut buckets: Vec<Bucket> = Vec::new();
    let mut indexes = std::collections::HashMap::new();
    for (ordinal, write) in writes.iter().enumerate() {
        let index = *indexes.entry(write.lexical_owner).or_insert_with(|| {
            let index = buckets.len();
            buckets.push(Bucket {
                ordinals: Vec::new(),
            });
            index
        });
        buckets[index].ordinals.push(ordinal);
    }
    let modifier_keys = reuse.and_then(|reuse| {
        crate::initializer_policy::modifier_facts::keys(writes, evaluator, reuse)
    });
    let facts = map_buckets(&buckets, evaluator, executor, |_, bucket, worker| {
        if let (Some(reuse), Some(keys)) = (reuse, modifier_keys.as_ref()) {
            return crate::initializer_policy::modifier_facts::modifier_facts_reused(
                bucket.ordinals.iter().map(|&ordinal| &writes[ordinal]),
                symbols,
                worker,
                &bucket.ordinals,
                evaluator,
                reuse,
                keys,
            );
        }
        modifier_facts_indexed(
            bucket.ordinals.iter().map(|&ordinal| &writes[ordinal]),
            symbols,
            worker,
            Some(&bucket.ordinals),
        )
    })?;
    let mut issues = Vec::new();
    let mut admitted = Vec::with_capacity(facts.len());
    for facts in facts {
        match facts {
            Ok(facts) => admitted.push(facts),
            Err(error) => issues.extend(error.issues),
        }
    }
    if !issues.is_empty() {
        issues.sort_by_key(|issue| issue.source_ordinal);
        return Err(ClassificationError { issues });
    }
    let prepared_keys = reuse.map(|reuse| {
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
        let policy = factory_policy.expect("certified reuse policy");
        let keys = reuse
            .store
            .prepared_keys
            .as_ref()
            .and_then(|owner| owner.prepare(writes, &ordered_facts, reuse, policy))
            .unwrap_or_else(|| {
                Arc::new(
                    writes
                        .iter()
                        .zip(&ordered_facts)
                        .map(|(write, &fact)| {
                            Arc::<[u8]>::from(artifact::key(write, fact, reuse, policy))
                        })
                        .collect(),
                )
            });
        artifact::retain_roster(reuse, &keys);
        keys
    });
    // No evaluation begins unless every modifier boundary was admitted.
    // Request-local physical sharing only. The pool disappears after this pass;
    // admitted receipts hold their leaves and replay every original observation.
    let receipt_pool = reuse.map(|_| artifact::ReceiptPool::default());
    let classified = map_buckets(&buckets, evaluator, executor, |index, bucket, worker| {
        let mut ordinal = 0;
        let result = if let Some(reuse) = reuse {
            bucket
                .ordinals
                .iter()
                .enumerate()
                .map(|(local, &global)| {
                    ordinal = local;
                    artifact::classify_one_keyed_grouped(
                        &writes[global],
                        symbols,
                        worker,
                        admitted[index][local],
                        global,
                        evaluator,
                        reuse,
                        prepared_keys.as_ref().map(|keys| &keys[global]),
                        receipt_pool.as_ref().filter(|_| bucket.ordinals.len() > 1),
                    )
                })
                .collect()
        } else {
            classify_pending(
                bucket.ordinals.iter().map(|&ordinal| &writes[ordinal]),
                symbols,
                worker,
                &admitted[index],
                &mut ordinal,
            )
        };
        result.map_err(|failure| ClassificationIssue {
            kind: failure.kind,
            source_ordinal: bucket.ordinals[ordinal],
            reason: failure.reason,
        })
    })?;
    let mut ordered: Vec<Option<PendingWrite>> = (0..writes.len()).map(|_| None).collect();
    let mut errors = Vec::new();
    for (bucket, result) in buckets.iter().zip(classified) {
        match result {
            Ok(pending) => {
                for (ordinal, mut pending) in bucket.ordinals.iter().copied().zip(pending) {
                    pending.write.source_ordinal = ordinal;
                    ordered[ordinal] = Some(pending);
                }
            }
            Err(error) => errors.push(error),
        }
    }
    if let Some(error) = errors.into_iter().min_by_key(|error| error.source_ordinal) {
        return Err(ClassificationError {
            issues: vec![error],
        });
    }
    let mut source_ordinal = 0;
    let pending = ordered
        .into_iter()
        .map(|pending| pending.expect("all successful initializer buckets cover source roster"));
    let result = match reuse {
        Some(reuse) if reuse.store.roster_enabled => {
            reuse
                .store
                .roster
                .finish(pending.collect(), debug_defined, &mut source_ordinal)
        }
        _ => finish_pending(pending, debug_defined, &mut source_ordinal),
    };
    result.map_err(|reason| ClassificationError {
        issues: vec![ClassificationIssue {
            kind: ClassificationIssueKind::Unsupported,
            source_ordinal,
            reason,
        }],
    })
}
