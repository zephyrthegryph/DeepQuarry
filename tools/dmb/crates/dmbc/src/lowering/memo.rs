//! Exact procedure memo replay and source-ordered cold fallback.
#[path = "memo_admission.rs"]
mod admission;
#[path = "memo_verify.rs"]
mod verify;
use super::*;
#[cfg(test)]
pub(super) use admission::lower_one_input;
pub(super) use admission::map_stage;
pub(super) use admission::Admission;
#[path = "rich_sidecars.rs"]
mod rich_sidecars;
#[allow(clippy::too_many_arguments)]
pub(super) fn admit_one_input<'a, 'frontend: 'a, R: Resolver, P: AbiPolicy>(
    frontend: &'frontend ColdFrontend,
    body: &'a BodyOccurrence,
    host: &'a R,
    request_admission: Option<&'a symbolic_input::RequestAdmission<'_, R>>,
    candidates: Option<&symbolic_input::RequestCandidates<'_, '_, R>>,
    local_inputs: Option<&LocalInputRoster<'_>>,
    policy: &'a P,
    startup: Option<&'a crate::startup::CapturedStartup<'frontend>>,
    memo: Option<&'a crate::lowering_memo::ProcedureMemo>,
    bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
    symbolic: bool,
    capture_references: bool,
    selections_only: bool,
    disk_replay_bindings: Option<DiskReplayBindings<'a>>,
    prepared_body: Option<&'a PreparedBody<'frontend>>,
) -> Result<Admission<'a>, Vec<LoweringDiagnostic>> {
    // Symbolic completion cannot discard an explicitly requested analysis sidecar.
    if symbolic && capture_references {
        if let Some(store) = memo.and_then(|memo| memo.symbolic.as_ref()) {
            store.capture_excluded();
        }
    }
    let symbolic = symbolic && !capture_references;
    let Some(memo) = memo else {
        return Ok(Admission::NeedsLowering(Box::new(move || {
            lower_one(
                frontend,
                body,
                host,
                policy,
                startup,
                bodies,
                capture_references,
                prepared_body.map(PreparedBody::source),
            )
            .map(CompletedInput::lowered)
        })));
    };
    let key_start = std::time::Instant::now();
    if startup.is_some_and(|capture| capture.validate_for(frontend).is_err()) {
        return Ok(Admission::NeedsLowering(Box::new(move || {
            lower_one(
                frontend,
                body,
                host,
                policy,
                startup,
                bodies,
                capture_references,
                prepared_body.map(PreparedBody::source),
            )
            .map(CompletedInput::lowered)
        })));
    }
    let owned_body = if prepared_body.is_none() {
        PreparedBody::issue(frontend, body).ok()
    } else {
        None
    };
    let current_body = prepared_body.or(owned_body.as_ref());
    let Some(current_key) = current_body.and_then(|row| {
        crate::lowering_memo::key_recipe::CurrentKey::from_prepared(
            frontend,
            row,
            memo.policy,
            capture_references,
            selections_only,
        )
    }) else {
        return Ok(Admission::NeedsLowering(Box::new(move || {
            lower_one(
                frontend,
                body,
                host,
                policy,
                startup,
                bodies,
                capture_references,
                None,
            )
            .map(CompletedInput::lowered)
        })));
    };
    let current_body = current_body.expect("current key was issued from this row");
    // Exact resident/disk replay already admitted the executable and its reads.
    // Attach the SAME current ABI/body certificate used by fresh production, so
    // publishing a promoted record does not force full-key admission next time.
    let promote_admission = |admission: symbolic_input::Admission| {
        admission
            .with_metadata(Arc::clone(current_key.metadata))
            .with_local(
                (!capture_references && !selections_only)
                    .then(|| {
                        symbolic_input::local_certificate(local_inputs?, current_body, memo.policy)
                    })
                    .flatten(),
            )
    };
    // Frozen ABI policies are prepared before this stage. Their actual folded
    // outputs must enter the key because no resolver call happens on replay.
    let tree = &frontend.snapshot.tree;
    let recording = crate::lowering_memo::RecordingResolver::new(host);
    let ready = (|| {
        let _profile = dm_profile::item("lowering.abi_key_prepare");
        let identity = current_body.source().identity;
        let issued = current_body.input();
        let context = AbiContext {
            identity,
            origin: &body.source,
            resolver: &recording,
            symbols: startup.map_or(tree.symbols(), |startup| startup.plan().symbols.as_ref()),
        };
        let metadata = current_key.metadata;
        let issued_prepared =
            if let Some(unit) = local_inputs.and_then(|inputs| inputs.prepared(current_body)) {
                Some(unit)
            } else {
                policy
                    .prepare_issued(metadata, issued, &context)
                    .ok()?
                    .map(|replay| replay.into_view())
            };
        let (needs_parsed, prepared, prepared_tail) = match issued_prepared {
            Some(prepared) => {
                memo.counts
                    .issued_preparations
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
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
        let current_source = current_body.source();
        return Ok(Admission::NeedsLowering(Box::new(move || {
            lower_one(
                frontend,
                body,
                host,
                policy,
                startup,
                bodies,
                capture_references,
                Some(current_source),
            )
            .map(CompletedInput::lowered)
        })));
    };
    memo.counts.key_preparation_ns.fetch_add(
        key_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
        std::sync::atomic::Ordering::Relaxed,
    );
    let verify_hit = !selections_only && memo.verification.select();
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
            if let Some(mut input) = store.lookup(
                &current_key,
                &prepared_tail,
                host,
                request_admission,
                candidates,
                &recording,
                frontend,
                body,
                &prepared,
                bodies,
                selections_only,
                verify_hit,
                current_body,
            ) {
                if verify_hit {
                    verify::verify(
                        memo,
                        verify::Expected::Input(&input),
                        input.verification_reads(),
                        frontend,
                        body,
                        host,
                        policy,
                        startup,
                        bodies,
                        capture_references,
                        current_body,
                        disk_replay_bindings,
                        "symbolic resident",
                    )?;
                }
                if !selections_only {
                    input.refresh_local_admission(
                        store,
                        local_inputs.and_then(|roster| {
                            symbolic_input::local_certificate(roster, current_body, memo.policy)
                        }),
                    );
                }
                bodies
                    .discard_parsed(body)
                    .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
                memo.counts
                    .resident_hits
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                note(MemoOutcome::ResidentHit, None, None);
                return Ok(Admission::Admitted(input));
            }
        }
    }
    let key = std::cell::OnceCell::new();
    let current_bytes = || key.get_or_init(|| current_key.materialize(&prepared_tail));
    let mut rebound_current = None;
    let (value, changed_query) = {
        let _profile = dm_profile::item("lowering.resident_validate");
        if memo.values.is_empty() {
            (None, None)
        } else {
            memo.visit_resident(current_bytes(), host, &mut |value| {
                let previous = &value.unit;
                if capture_references && previous.selected_references.is_none() {
                    return false;
                }
                let rebased =
                    crate::lowering_memo::rebase_debug(frontend, body, &value.relative_debug);
                rebound_current = rebased.and_then(|origins| {
                    rich_sidecars::rebind(
                        previous, frontend, body, bodies, &recording, &prepared, origins,
                    )
                });
                rebound_current.is_some()
            })
        }
    };
    let mut miss = changed_query.map_or(MemoMissReason::NoExactVariant, |_| {
        MemoMissReason::ReadMeaningChanged
    });
    if let Some(accepted) = value {
        let admission = if symbolic {
            symbolic_input::accepted_admission(memo, current_bytes().clone(), &accepted)
        } else {
            None
        };
        accepted.reads.visit_storage(|view| {
            if let dm_session::ReceiptStorageView::Flat(leaf) = view {
                recording.record_admitted(leaf);
            }
        });
        if let Some(mut unit) = rebound_current {
            unit.origin = body.clone();
            unit.abi = prepared.abi.clone();
            if let Some(member) = frontend.snapshot.tree.member(body.member) {
                if let Some(metadata) = &member.metadata.procedure {
                    unit.metadata = Arc::clone(metadata);
                }
                unit.effective = current_body.source().effective;
            }
            bodies
                .discard_parsed(body)
                .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
            if verify_hit {
                let reads: Vec<_> = accepted
                    .reads
                    .iter()
                    .map(|r| (r.query, r.answer.canonical_bytes()))
                    .collect();
                verify::verify(
                    memo,
                    verify::Expected::Unit(&unit),
                    Some(&reads),
                    frontend,
                    body,
                    host,
                    policy,
                    startup,
                    bodies,
                    capture_references,
                    current_body,
                    disk_replay_bindings,
                    "rich resident",
                )?;
            }
            memo.counts
                .resident_hits
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            note(MemoOutcome::ResidentHit, None, None);
            return Ok(Admission::Admitted(
                CompletedInput::lowered(unit).with_admission(admission.map(promote_admission)),
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
            &current_key,
            &prepared_tail,
            identity,
            crate::lowering_memo_wire::ProcedureReplayContext {
                frontend,
                body,
                parsed,
                bindings: symbolic.then_some(disk_replay_bindings).flatten(),
                selections_only,
                verify: verify_hit,
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
        .then(|| current_body.input().compact());
        lookup_disk(header.map(Into::into), None)
    };
    if let Some(errors) = disk
        .errors
        .and_then(|errors| replay_errors(frontend, body, identity, errors))
    {
        if verify_hit {
            verify::verify(
                memo,
                verify::Expected::Errors(&errors),
                disk.verification_reads.as_deref(),
                frontend,
                body,
                host,
                policy,
                startup,
                bodies,
                capture_references,
                current_body,
                disk_replay_bindings,
                "disk failure",
            )?;
        }
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
        let current = current_body.source();
        if let Some(promotion) = disk.resident.as_ref().filter(|_| memo.symbolic.is_some()) {
            symbolic_input::remember_selections(
                memo,
                current_bytes().clone(),
                host,
                promotion,
                current.identity,
                &prepared,
                &facts,
            );
        }
        return Ok(Admission::Admitted(CompletedInput::selections(
            current.identity,
            current.effective,
            body.clone(),
            facts,
        )));
    }
    if let Some(value) = disk.prepared {
        let admission = disk
            .resident
            .as_ref()
            .filter(|_| memo.symbolic.is_some())
            .and_then(|promotion| {
                symbolic_input::disk_admission(memo, current_bytes().clone(), host, promotion)
            });
        bodies
            .discard_parsed(body)
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
        let input = CompletedInput::reused(value);
        if verify_hit {
            verify::verify(
                memo,
                verify::Expected::Input(&input),
                disk.verification_reads.as_deref(),
                frontend,
                body,
                host,
                policy,
                startup,
                bodies,
                capture_references,
                current_body,
                disk_replay_bindings,
                "compact disk",
            )?;
        }
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        memo.counts
            .compact_disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        note(MemoOutcome::DiskHit, None, None);
        return Ok(Admission::Admitted(
            input.with_admission(admission.map(promote_admission)),
        ));
    }
    if let Some(unit) = disk
        .unit
        .filter(|unit| !capture_references || unit.selected_references.is_some())
    {
        let admission = if symbolic {
            disk.resident.as_ref().and_then(|promotion| {
                symbolic_input::disk_admission(memo, current_bytes().clone(), host, promotion)
            })
        } else {
            None
        };
        bodies
            .discard_parsed(body)
            .map_err(|diagnostic| body_diagnostic(body, diagnostic))?;
        if verify_hit {
            verify::verify(
                memo,
                verify::Expected::Unit(&unit),
                disk.verification_reads.as_deref(),
                frontend,
                body,
                host,
                policy,
                startup,
                bodies,
                capture_references,
                current_body,
                disk_replay_bindings,
                "rich disk",
            )?;
        }
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        note(MemoOutcome::DiskHit, None, None);
        return Ok(Admission::Admitted(
            CompletedInput::lowered(unit).with_admission(admission.map(promote_admission)),
        ));
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
    let local_certificate = (!capture_references && !selections_only)
        .then(|| symbolic_input::local_certificate(local_inputs?, current_body, memo.policy))
        .flatten();
    let current_source = current_body.source();
    let key = key
        .into_inner()
        .unwrap_or_else(|| current_key.materialize(&prepared_tail));
    Ok(Admission::NeedsLowering(Box::new(move || {
        // Replay validates the stored complete read ledger (or its trusted domain
        // receipt). Issue mandatory reads only when producing a new executable.
        let occurrence_start = std::time::Instant::now();
        {
            let _profile = dm_profile::item("lowering.occurrence_reads");
            recording.record_declaration_occurrence(identity);
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
                current: Some(current_source),
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
                    && disk_replay_bindings.is_some_and(|bindings| {
                        crate::lowering_memo_compact::eligible(unit, bindings)
                    });
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
            CompletedInput::lowered(unit).with_admission(admission.map(|a| {
                a.with_metadata(Arc::clone(current_key.metadata))
                    .with_local(local_certificate)
            }))
        })
    })))
}

fn body_diagnostic(
    body: &BodyOccurrence,
    diagnostic: dm_tree::frontend::Diagnostic,
) -> Vec<LoweringDiagnostic> {
    vec![LoweringDiagnostic {
        related: Vec::new(),
        kind: diagnostic.kind,
        identity: None,
        origin: diagnostic.location.unwrap_or_else(|| body.source.clone()),
        message: diagnostic.message,
    }]
}
