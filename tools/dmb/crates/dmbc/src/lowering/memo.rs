//! Exact procedure memo replay and source-ordered cold fallback.
use super::*;
#[allow(clippy::too_many_arguments)]
pub(super) fn lower_one_input<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    request_admission: Option<&symbolic_input::RequestAdmission<'_, R>>,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    symbolic: bool,
    capture_references: bool,
    selections_only: bool,
    disk_replay_bindings: Option<DiskReplayBindings<'_>>,
) -> Result<CompletedInput, Vec<LoweringDiagnostic>> {
    // Symbolic completion cannot discard an explicitly requested analysis sidecar.
    if symbolic && capture_references {
        if let Some(store) = memo.and_then(|memo| memo.symbolic.as_ref()) {
            store.capture_excluded();
        }
    }
    let symbolic = symbolic && !capture_references;
    let Some(memo) = memo else {
        return lower_one(
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
        )
        .map(CompletedInput::lowered);
    };
    let key_start = std::time::Instant::now();
    if startup.is_some_and(|capture| capture.validate_for(frontend).is_err()) {
        return lower_one(
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
        )
        .map(CompletedInput::lowered);
    }
    let Some(current_key) = crate::lowering_memo::key_recipe::CurrentKey::new(
        frontend,
        body,
        memo.policy,
        capture_references,
        selections_only,
    ) else {
        return lower_one(
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
        )
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
        let (needs_parsed, prepared, prepared_tail) = match policy
            .prepare_issued(metadata, &issued, &context)
            .ok()?
        {
            Some(replay) => {
                memo.counts
                    .issued_preparations
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let prepared = replay.into_view();
                let tail = crate::lowering_memo::key_recipe::PreparedKey::issued(&prepared)?;
                (false, prepared, tail)
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
                let mut tail = Vec::new();
                crate::lowering_memo::prepared_key(&mut tail, &prepared, body.expanded_span.start)?;
                (
                    true,
                    prepared,
                    crate::lowering_memo::key_recipe::PreparedKey::Parsed(tail),
                )
            }
        };
        Some((
            needs_parsed,
            prepared,
            prepared_tail,
            dm_ir::ProcedureIdentity {
                owner: identity.owner,
                name: identity.name,
                verb: identity.namespace == Namespace::Verb,
                occurrence: identity.occurrence,
            },
        ))
    })();
    let Some((needs_parsed, prepared, prepared_tail, identity)) = ready else {
        return lower_one(
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
        )
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
    if symbolic || selections_only {
        if let Some(store) = &memo.symbolic {
            if let Some(input) = store.lookup(
                &current_key,
                &prepared_tail,
                host,
                request_admission,
                &recording,
                frontend,
                body,
                &prepared,
                bodies,
                selections_only,
            ) {
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
    let key = current_key.materialize(&prepared_tail);
    let (value, changed_query) = {
        let _profile = dm_profile::item("lowering.resident_validate");
        memo.values.visit_receipted(&key, host, &mut |value| {
            let previous = &value.unit;
            if capture_references && previous.selected_references.is_none() {
                return false;
            }
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
            return Ok(CompletedInput::lowered(unit).with_admission(
                admission.map(|a| a.with_metadata(Arc::clone(current_key.metadata))),
            ));
        }
        miss = MemoMissReason::UnrebasablePrivateSidecar;
    }
    let lookup_disk = |parsed: Option<crate::argument_sources::ProcedureHeader<'_>>,
                       active: Option<&dm_tree::frontend::ParsedBody<'_>>| {
        let modified_issuer = crate::lowering_memo_compact::CurrentModifiedIssuer {
            frontend,
            body,
            bodies,
            host,
            parsed: active,
        };
        memo.lookup_procedure(
            &key,
            identity,
            crate::lowering_memo_wire::ProcedureReplayContext {
                frontend,
                body,
                parsed,
                bindings: symbolic.then_some(disk_replay_bindings).flatten(),
                selections_only,
                modified: Some(&modified_issuer),
            },
            host,
            &prepared,
        )
    };
    let disk = if needs_parsed {
        bodies
            .with_parsed(body, |parsed| {
                lookup_disk(Some(parsed.item().into()), Some(parsed))
            })
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?
    } else {
        let header = (!prepared
            .abi
            .as_ref()
            .is_none_or(|abi| abi.source_helpers.is_empty()))
        .then(|| frontend.compact_body(body).ok())
        .flatten();
        lookup_disk(header.map(Into::into), None)
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
    if let Some(facts) = disk.selections {
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        memo.counts
            .compact_disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        bodies
            .discard_parsed(body)
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
        note(MemoOutcome::DiskHit, None, None);
        let current = source_unit_identity(frontend, body).map_err(|message| {
            vec![LoweringDiagnostic {
                kind: dm_tree::frontend::DiagnosticKind::Internal,
                identity: None,
                origin: body.source.clone(),
                message,
            }]
        })?;
        if let Some(promotion) = &disk.resident {
            symbolic_input::remember_selections(
                memo,
                key.clone(),
                host,
                promotion,
                current.identity,
                &prepared,
                &facts,
            );
        }
        return Ok(CompletedInput::selections(
            current.identity,
            current.effective,
            body.clone(),
            facts,
        ));
    }
    if let Some(value) = disk.prepared {
        let admission = disk.resident.as_ref().and_then(|promotion| {
            symbolic_input::disk_admission(memo, key.clone(), host, promotion)
        });
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        memo.counts
            .compact_disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        bodies
            .discard_parsed(body)
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
        note(MemoOutcome::DiskHit, None, None);
        return Ok(CompletedInput::reused(value)
            .with_admission(admission.map(|a| a.with_metadata(Arc::clone(current_key.metadata)))));
    }
    if let Some(unit) = disk
        .unit
        .filter(|unit| !capture_references || unit.selected_references.is_some())
    {
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
        return Ok(CompletedInput::lowered(unit)
            .with_admission(admission.map(|a| a.with_metadata(Arc::clone(current_key.metadata)))));
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
            capture_references,
        },
    );
    let mut admission = None;
    if let Ok(unit) = &result {
        let reads: Arc<[crate::lowering_memo::ResolverRead]> = recording.reads().into();
        let versions: Arc<[(dm_ir::ReadDomain, u128)]> = recording.domain_receipts().into();
        let relative_debug = capture.borrow().debug.clone();
        if relative_debug.len() == unit.debug_origins.entries.len()
            && crate::lowering_memo::rebase_debug(frontend, body, &relative_debug).as_ref()
                == Some(&unit.debug_origins)
        {
            let compact_eligible = symbolic
                && disk_replay_bindings
                    .is_some_and(|bindings| crate::lowering_memo_compact::eligible(unit, bindings));
            let compact = compact_eligible && memo.completion_writer().is_some();
            if symbolic {
                admission = symbolic_input::admission(
                    memo,
                    Arc::from(key.as_slice()),
                    Arc::clone(&reads),
                    Arc::clone(&versions),
                    relative_debug.clone(),
                    compact,
                );
            }
            if !compact {
                if symbolic && memo.completion_writer().is_some() {
                    memo.counts
                        .compact_fallback_ineligible
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                }
                if selections_only {
                    memo.queue_selections(&key, &reads, unit, &versions);
                } else {
                    memo.queue_disk(&key, &reads, unit, &relative_debug, &versions);
                }
            }
            // The completion producer retains the reusable symbolic artifact.
            // Keeping another RichIR graph for the same compact-eligible unit
            // duplicates its instructions, origins and dependency ledger and
            // walks that graph solely to charge a second cache. Noncompact
            // units and compatibility callers retain the rich fallback. A
            // declined symbolic completion remains a normal cold miss.
            let symbolic_resident = compact_eligible && memo.symbolic.is_some();
            if memo.retains_resident() && !symbolic_resident {
                let retained_key = admission.as_ref().map_or_else(
                    || Arc::from(key.as_slice()),
                    |admission| admission.shared_key(),
                );
                memo.remember_shared(retained_key, reads, unit, relative_debug, versions);
            }
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
    result.map(|unit| {
        CompletedInput::lowered(unit)
            .with_admission(admission.map(|a| a.with_metadata(Arc::clone(current_key.metadata))))
    })
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
