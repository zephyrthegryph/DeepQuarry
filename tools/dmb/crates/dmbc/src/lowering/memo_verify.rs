//! Procedure-hit verification only. Other memo stages remain outside this coverage.
use super::*;
use std::sync::atomic::Ordering;
type Reads = [(dm_ir::ResolveQuery, Vec<u8>)];
fn read_difference(old: &Reads, fresh: &Reads) -> Option<&'static str> {
    fn canonical(reads: &Reads) -> Option<BTreeMap<dm_ir::ResolveQuery, &[u8]>> {
        let mut out = BTreeMap::new();
        for (query, answer) in reads {
            if out
                .insert(*query, answer.as_slice())
                .is_some_and(|previous| previous != answer.as_slice())
            {
                return None;
            }
        }
        Some(out)
    }
    match (canonical(old), canonical(fresh)) {
        (Some(a), Some(b)) if a == b => None,
        _ => Some("complete canonical read ledger"),
    }
}
fn diagnostics_equal(a: &[LoweringDiagnostic], b: &[LoweringDiagnostic]) -> bool {
    a.len() == b.len()
        && a.iter().zip(b).all(|(a, b)| {
            a.kind == b.kind
                && a.identity == b.identity
                && a.origin == b.origin
                && a.message == b.message
                && a.related.len() == b.related.len()
                && a.related
                    .iter()
                    .zip(&b.related)
                    .all(|(a, b)| a.origin == b.origin && a.message == b.message)
        })
}
pub(super) enum Expected<'a> {
    Input(&'a CompletedInput),
    Unit(&'a LoweredUnit),
    Errors(&'a [LoweringDiagnostic]),
}
#[allow(clippy::too_many_arguments)]
pub(super) fn verify<R: Resolver, P: AbiPolicy>(
    memo: &crate::lowering_memo::ProcedureMemo,
    expected: Expected<'_>,
    old_reads: Option<&Reads>,
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    capture_references: bool,
    current: &PreparedBody<'_>,
    bindings: Option<DiskReplayBindings<'_>>,
    hit: &'static str,
) -> Result<(), Vec<LoweringDiagnostic>> {
    memo.verification.checked.fetch_add(1, Ordering::Relaxed);
    let recording = crate::lowering_memo::RecordingResolver::new(host);
    let identity = current.source().identity;
    recording.record_declaration_occurrence(dm_ir::ProcedureIdentity {
        owner: identity.owner,
        name: identity.name,
        verb: identity.namespace == Namespace::Verb,
        occurrence: identity.occurrence,
    });
    // No memo/store/publication is passed to the producer. Current source and
    // policy are mandatory, and fresh observations never contain replay edges.
    let independent = bodies.fork_body(body).map_err(|error| {
        vec![LoweringDiagnostic {
            kind: DiagnosticKind::Internal,
            identity: Some(identity),
            origin: body.source.clone(),
            related: Vec::new(),
            message: format!(
                "procedure verification parser fork failed: {}",
                error.message
            ),
        }]
    })?;
    let fresh = lower_one(
        frontend,
        body,
        &recording,
        policy,
        startup,
        &independent,
        capture_references,
        Some(current.source()),
    );
    let reads: Vec<_> = recording
        .reads()
        .iter()
        .map(|r| (r.query, r.answer.canonical_bytes()))
        .collect();
    let mut difference = old_reads.and_then(|old| read_difference(old, &reads));
    let first_query = if difference.is_some() {
        old_reads.and_then(|old| {
            old.iter().chain(reads.iter()).find_map(|(query, _)| {
                let a = old.iter().find(|r| r.0 == *query).map(|r| r.1.as_slice());
                let b = reads.iter().find(|r| r.0 == *query).map(|r| r.1.as_slice());
                (a != b).then_some(*query)
            })
        })
    } else {
        None
    };
    if old_reads.is_none() {
        difference = Some("original receipt unavailable");
    }
    if difference.is_none() {
        let equal = match (expected, fresh) {
            (Expected::Errors(old), Err(fresh)) => diagnostics_equal(old, &fresh),
            (Expected::Unit(old), Ok(fresh)) => {
                crate::lowering_memo_wire::verification_unit_equal(old, &fresh)
            }
            (Expected::Input(old), Ok(fresh)) => {
                if let Some(unit) = old.verification_unit() {
                    crate::lowering_memo_wire::verification_unit_equal(unit, &fresh)
                } else if let (Some(old), Some(bindings)) = (old.verification_prepared(), bindings)
                {
                    let symbols = startup.map_or(frontend.snapshot.tree.symbols(), |v| {
                        v.plan().symbols.as_ref()
                    });
                    crate::symbolic::prepare_contribution(
                        fresh,
                        symbols,
                        bindings.source,
                        bindings.external,
                        false,
                    )
                    .is_ok_and(|fresh| old.verification_equal(&fresh))
                } else {
                    false
                }
            }
            (Expected::Errors(_), Ok(_)) => {
                difference = Some("cached failure became a successful current producer result");
                false
            }
            (_, Err(ref errors)) => {
                difference = Some(
                    if errors.iter().any(|e| e.kind == DiagnosticKind::Internal) {
                        "fresh producer returned an internal diagnostic"
                    } else {
                        "cached success became a current producer rejection"
                    },
                );
                false
            }
        };
        if !equal && difference.is_none() {
            difference = Some("symbolic output, helpers, warnings or current diagnostics");
        }
    }
    if let Some(category) = difference {
        memo.verification.mismatches.fetch_add(1, Ordering::Relaxed);
        return Err(vec![LoweringDiagnostic {
            kind: DiagnosticKind::Internal,
            identity: Some(identity),
            origin: body.source.clone(),
            related: Vec::new(),
            message: format!("procedure memo verification mismatch ({hit}): {category}; first_query={first_query:?}"),
        }]);
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    struct Local;
    impl AbiPolicy for Local {
        fn inputs(
            &self,
            identity: UnitIdentity,
            metadata: &ProcedureMetadata,
            symbols: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            // This fixture owns no formals/settings. Do not fabricate inputs for
            // a changed signature or silently turn a production ABI into local ABI.
            if !metadata.signature.parameters.is_empty()
                || metadata.signature.variadic
                || !metadata.settings.is_empty()
            {
                return Err(
                    "verification fixture requires the issued no-argument signature".into(),
                );
            }
            let owner = symbols
                .text(identity.owner)
                .ok_or("current owner spelling missing")?;
            let name = symbols
                .text(identity.name)
                .ok_or("current procedure spelling missing")?;
            Ok(ProcedureInputs {
                procedure_identity: Some(dm_ir::ProcedureIdentity {
                    owner: identity.owner,
                    name: identity.name,
                    verb: identity.namespace == Namespace::Verb,
                    occurrence: identity.occurrence,
                }),
                current_type_path: Some(owner.into()),
                current_proc_path: Some(format!("{}/proc/{name}", owner.trim_end_matches('/'))),
                ..Default::default()
            })
        }
    }
    #[test]
    fn current_producer_verification_rejects_stale_success_and_failure_locations() {
        for source in [
            "/proc/probe()\n    return 7\n",
            "\n\n/proc/probe()\n    var/value = 1\n    var/value = 2\n",
        ] {
            let frontend = dm_tree::frontend::build(
                std::path::Path::new("verify.dme"),
                &Source(source),
                &Default::default(),
                1,
            )
            .unwrap();
            let body = &frontend.bodies[0];
            let current = PreparedBody::issue(&frontend, body).unwrap();
            let arena = dm_tree::frontend::BodyArena::new_typed(
                &frontend,
                dm_codegen_byond::typed_statements_supported,
            );
            let host = frontend.snapshot.tree.as_ref();
            let recording = crate::lowering_memo::RecordingResolver::new(host);
            let id = current.source().identity;
            recording.record_declaration_occurrence(dm_ir::ProcedureIdentity {
                owner: id.owner,
                name: id.name,
                verb: false,
                occurrence: id.occurrence,
            });
            let result = lower_one(
                &frontend,
                body,
                &recording,
                &Local,
                None,
                &arena,
                false,
                Some(current.source()),
            );
            let reads: Vec<_> = recording
                .reads()
                .iter()
                .map(|r| (r.query, r.answer.canonical_bytes()))
                .collect();
            let memo = crate::lowering_memo::ProcedureMemo::new(17);
            match result {
                Ok(mut unit) => {
                    verify(
                        &memo,
                        Expected::Unit(&unit),
                        Some(&reads),
                        &frontend,
                        body,
                        host,
                        &Local,
                        None,
                        &arena,
                        false,
                        &current,
                        None,
                        "fixture",
                    )
                    .unwrap();
                    unit.code.procedure.local_count += 1;
                    let errors = verify(
                        &memo,
                        Expected::Unit(&unit),
                        Some(&reads),
                        &frontend,
                        body,
                        host,
                        &Local,
                        None,
                        &arena,
                        false,
                        &current,
                        None,
                        "fixture",
                    )
                    .unwrap_err();
                    assert_eq!(errors[0].kind, DiagnosticKind::Internal);
                    assert!(errors[0].message.contains("symbolic output"));
                }
                Err(mut errors) => {
                    verify(
                        &memo,
                        Expected::Errors(&errors),
                        Some(&reads),
                        &frontend,
                        body,
                        host,
                        &Local,
                        None,
                        &arena,
                        false,
                        &current,
                        None,
                        "fixture",
                    )
                    .unwrap();
                    errors[0].origin.line += 1;
                    assert!(verify(
                        &memo,
                        Expected::Errors(&errors),
                        Some(&reads),
                        &frontend,
                        body,
                        host,
                        &Local,
                        None,
                        &arena,
                        false,
                        &current,
                        None,
                        "fixture"
                    )
                    .is_err());
                }
            }
            assert_eq!(memo.verification.checked.load(Ordering::Relaxed), 2);
            assert_eq!(memo.verification.mismatches.load(Ordering::Relaxed), 1);
        }
    }
    #[test]
    fn actual_resident_hit_runs_fresh_producer_before_return() {
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("verify-hit.dme"),
            &Source("/proc/probe()\n    return 7\n"),
            &Default::default(),
            1,
        )
        .unwrap();
        let body = &frontend.bodies[0];
        let current = PreparedBody::issue(&frontend, body).unwrap();
        let host = frontend.snapshot.tree.as_ref();
        let memo = crate::lowering_memo::ProcedureMemo::new(17).with_all_procedure_verification();
        for _ in 0..2 {
            let arena = dm_tree::frontend::BodyArena::new_typed(
                &frontend,
                dm_codegen_byond::typed_statements_supported,
            );

            let result = super::super::lower_one_input(
                &frontend,
                body,
                host,
                None,
                &Local,
                None,
                Some(&memo),
                &arena,
                false,
                false,
                false,
                None,
                Some(&current),
            )
            .unwrap();
            assert!(result.verification_unit().is_some());
        }
        assert_eq!(memo.counts.resident_hits.load(Ordering::Relaxed), 1);
        assert_eq!(memo.procedure_verification_counts(), (1, 0));
    }

    #[test]
    fn missing_negative_read_and_changed_answer_fail_exact_ledger_comparison() {
        let query = dm_ir::ResolveQuery::GlobalProc(SymbolId::of("formerly_missing"));
        let missing = vec![(query, dm_ir::ResolvedMeaning::Missing.canonical_bytes())];
        assert!(read_difference(&missing, &missing).is_none());
        assert!(read_difference(&[], &missing).is_some());
        let changed = vec![(
            query,
            dm_ir::ResolvedMeaning::Presence(true).canonical_bytes(),
        )];
        assert!(read_difference(&missing, &changed).is_some());
        assert!(read_difference(&missing, &[missing[0].clone(), missing[0].clone()]).is_none());
    }
}
