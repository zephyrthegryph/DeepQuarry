//! Exact procedure memo replay and source-ordered cold fallback.
use super::*;
#[allow(clippy::too_many_arguments)]
pub(super) fn lower_one_input<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    symbolic: bool,
) -> Result<CompletedInput, Vec<LoweringDiagnostic>> {
    let Some(memo) = memo else {
        return lower_one(frontend, body, host, policy, startup, bodies)
            .map(CompletedInput::lowered);
    };
    let key_start = std::time::Instant::now();
    if startup.is_some_and(|capture| capture.validate_for(frontend).is_err()) {
        return lower_one(frontend, body, host, policy, startup, bodies)
            .map(CompletedInput::lowered);
    }
    let Some(mut key) = crate::lowering_memo::key(frontend, body, memo.policy) else {
        return lower_one(frontend, body, host, policy, startup, bodies)
            .map(CompletedInput::lowered);
    };
    // Frozen ABI policies are prepared before this stage. Their actual folded
    // outputs must enter the key because no resolver call happens on replay.
    let tree = &frontend.snapshot.tree;
    let recording = crate::lowering_memo::RecordingResolver::new(host);
    let ready = (|| {
        let _profile = dm_profile::item("lowering.abi_key_prepare");
        let node = tree.member(body.member)?;
        let identity = source_unit_identity(frontend, body).ok()?.identity;
        let issued = frontend.body_input(body).ok()?;
        let context = AbiContext {
            identity,
            origin: &body.source,
            resolver: &recording,
            symbols: startup.map_or(tree.symbols(), |startup| startup.plan().symbols.as_ref()),
        };
        let metadata = node.metadata.procedure.as_ref()?;
        let (needs_parsed, prepared) = match policy
            .prepare_issued(metadata, &issued, &context)
            .ok()?
        {
            Some(replay) => {
                memo.counts
                    .issued_preparations
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let prepared = replay.into_view();
                crate::lowering_memo::prepared_replay_key(&mut key, &prepared)?;
                (false, prepared)
            }
            None => {
                memo.counts
                    .parsed_preparations
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let prepared = bodies
                    .with_parsed(body, |parsed| {
                        policy.prepare_captured(metadata, parsed, &context)
                    })
                    .ok()?
                    .ok()?;
                crate::lowering_memo::prepared_key(&mut key, &prepared, body.expanded_span.start)?;
                (true, prepared)
            }
        };
        Some((
            needs_parsed,
            prepared,
            dm_ir::ProcedureIdentity {
                owner: identity.owner,
                name: identity.name,
                verb: identity.namespace == Namespace::Verb,
                occurrence: identity.occurrence,
            },
        ))
    })();
    let Some((needs_parsed, prepared, identity)) = ready else {
        return lower_one(frontend, body, host, policy, startup, bodies)
            .map(CompletedInput::lowered);
    };
    memo.counts.key_preparation_ns.fetch_add(
        key_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
        std::sync::atomic::Ordering::Relaxed,
    );
    let lookup_start = std::time::Instant::now();
    let note = |outcome, reason, changed_query| {
        memo.counts.lookup_ns.fetch_add(
            lookup_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            std::sync::atomic::Ordering::Relaxed,
        );
        memo.note(crate::lowering_memo::MemoExplanation {
            identity,
            outcome,
            reason,
            changed_query,
        });
    };
    use crate::lowering_memo::{MemoMissReason, MemoOutcome};
    if symbolic {
        if let Some(store) = &memo.symbolic {
            if let Some(input) = store.lookup(&key, host, frontend, body, &prepared) {
                bodies
                    .discard_parsed(body)
                    .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
                memo.counts
                    .resident_hits
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                note(MemoOutcome::ResidentHit, None, None);
                return Ok(input);
            }
        }
    }
    let (value, changed_query) = {
        let _profile = dm_profile::item("lowering.resident_validate");
        memo.values.visit_receipted(&key, host, &mut |value| {
            let previous = &value.unit;
            let rebased = crate::lowering_memo::rebase_debug(frontend, body, &value.relative_debug);
            let absolute =
                !previous.code.modified_instances.is_empty() || !previous.source_helpers.is_empty();
            rebased.as_ref().is_some_and(|origins| {
                !absolute
                    || (previous.origin.expanded_span == body.expanded_span
                        && *origins == previous.debug_origins)
            })
        })
    };
    let mut miss = changed_query.map_or(MemoMissReason::NoExactVariant, |_| {
        MemoMissReason::ReadMeaningChanged
    });
    if let Some(accepted) = value {
        let admission = if symbolic {
            symbolic_input::accepted_admission(memo, key.clone(), &accepted)
        } else {
            None
        };
        let value = accepted.value;
        let _profile = dm_profile::item("lowering.resident_replay");
        // AST-bearing private sidecars still contain expanded spans. Ordinary
        // code contains only symbolic operands/debug ordinals and can move.
        let previous = &value.unit;
        let rebased = crate::lowering_memo::rebase_debug(frontend, body, &value.relative_debug);
        let absolute_sidecars =
            !previous.code.modified_instances.is_empty() || !previous.source_helpers.is_empty();
        if rebased.as_ref().is_some_and(|origins| {
            !absolute_sidecars
                || (previous.origin.expanded_span == body.expanded_span
                    && *origins == previous.debug_origins)
        }) {
            memo.counts
                .resident_hits
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let mut unit = previous.clone();
            unit.debug_origins = rebased.expect("checked relative origins");
            unit.origin = body.clone();
            unit.abi = prepared.abi.clone();
            if let Some(member) = frontend.snapshot.tree.member(body.member) {
                if let Some(metadata) = &member.metadata.procedure {
                    unit.metadata = Arc::clone(metadata);
                }
                unit.effective =
                    frontend
                        .snapshot
                        .tree
                        .resolve(member.owner, member.name, member.kind)
                        == Some(body.member);
            }
            bodies
                .discard_parsed(body)
                .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
            note(MemoOutcome::ResidentHit, None, None);
            return Ok(CompletedInput::lowered(unit).with_admission(admission));
        }
        miss = MemoMissReason::UnrebasablePrivateSidecar;
    }
    let lookup_disk = |parsed: Option<&dm_syntax::Item>| {
        memo.lookup_procedure(
            &key,
            identity,
            crate::lowering_memo_wire::ProcedureReplayContext {
                frontend,
                body,
                parsed,
            },
            host,
            &prepared,
        )
    };
    let disk = if needs_parsed {
        bodies
            .with_parsed(body, |parsed| lookup_disk(Some(parsed.item())))
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?
    } else {
        let header = (!prepared
            .abi
            .as_ref()
            .is_none_or(|abi| abi.source_helpers.is_empty()))
        .then(|| frontend.compact_body(body).ok())
        .flatten();
        lookup_disk(header)
    };
    if let Some(errors) = disk
        .errors
        .and_then(|errors| replay_errors(frontend, body, identity, errors))
    {
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        bodies
            .discard_parsed(body)
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
        note(MemoOutcome::DiskHit, None, None);
        return Err(errors);
    }
    if let Some(unit) = disk.unit {
        let admission = if symbolic {
            disk.resident.as_ref().and_then(|promotion| {
                symbolic_input::disk_admission(memo, key.clone(), host, promotion)
            })
        } else {
            None
        };
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        bodies
            .discard_parsed(body)
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
        note(MemoOutcome::DiskHit, None, None);
        return Ok(CompletedInput::lowered(unit).with_admission(admission));
    }
    if let Some(reason) = disk.miss {
        miss = reason;
    }
    let changed_query = changed_query.or(disk.changed_query);
    if changed_query.is_some() {
        miss = MemoMissReason::ReadMeaningChanged;
    }
    note(MemoOutcome::Recomputed, Some(miss), changed_query);
    memo.counts
        .recomputed
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    // Replay validates the stored complete read ledger (or its trusted domain
    // receipt). Issue mandatory reads only when producing a new executable.
    let occurrence_start = std::time::Instant::now();
    {
        let _profile = dm_profile::item("lowering.occurrence_reads");
        recording.record_occurrence(identity);
    }
    memo.counts.occurrence_reads_ns.fetch_add(
        occurrence_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
        std::sync::atomic::Ordering::Relaxed,
    );
    let capture = RefCell::new(MemoCapture::default());
    let result = lower_one_captured(
        frontend,
        body,
        &recording,
        policy,
        bodies,
        LoweringCapture {
            startup,
            capture: Some(&capture),
            ready: needs_parsed.then_some(prepared),
        },
    );
    let mut admission = None;
    if let Ok(unit) = &result {
        let reads = recording.reads();
        let relative_debug = capture.borrow().debug.clone();
        if relative_debug.len() == unit.debug_origins.entries.len()
            && crate::lowering_memo::rebase_debug(frontend, body, &relative_debug).as_ref()
                == Some(&unit.debug_origins)
        {
            if symbolic {
                admission = symbolic_input::admission(
                    memo,
                    key.clone(),
                    &recording,
                    relative_debug.clone(),
                );
            }
            memo.queue_disk(
                &key,
                &reads,
                unit,
                &relative_debug,
                &recording.domain_receipts(),
            );
            memo.remember(
                key,
                reads,
                unit,
                relative_debug,
                recording.domain_receipts(),
            );
        }
    } else if let Some(errors) = &capture.borrow().errors {
        memo.remember_failure(
            &key,
            Some(identity),
            &recording.reads(),
            errors,
            &recording.domain_receipts(),
        );
    }
    result.map(|unit| CompletedInput::lowered(unit).with_admission(admission))
}

fn body_diagnostic(
    body: &BodyOccurrence,
    diagnostic: dm_tree::frontend::Diagnostic,
) -> Vec<LoweringDiagnostic> {
    vec![LoweringDiagnostic {
        kind: diagnostic.kind,
        identity: None,
        origin: diagnostic.location.unwrap_or_else(|| body.source.clone()),
        message: diagnostic.message,
    }]
}
