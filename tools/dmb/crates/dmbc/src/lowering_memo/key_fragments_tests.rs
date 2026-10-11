use super::*;
#[test]
fn streamed_locator_matches_materialized_key_for_every_fragment_kind() {
    let metadata = Arc::new(dm_ir::ProcedureMetadata {
        signature: dm_ir::ProcedureSignature {
            parameters: Arc::from([]),
            variadic: false,
            return_annotation: None,
        },
        settings: Arc::from([]),
    });
    let tails = [
        PreparedKey::Parsed(vec![]),
        PreparedKey::Parsed(vec![0, 1, 255]),
        PreparedKey::Issued(Arc::from(b"issued-tail".as_slice())),
    ];
    for references in [false, true] {
        for selections in [false, true] {
            for termination in 0..=255 {
                for tail in &tails {
                    let current = CurrentKey {
                        prefix: [73; 41],
                        metadata: &metadata,
                        source: b"return \xce\xa9",
                        termination,
                        references,
                        selections,
                    };
                    let bytes = current.materialize(tail);
                    assert_eq!(
                        current.record_key(tail),
                        crate::lowering_memo::ProcedureMemo::record_key(&bytes)
                    );
                    assert!(current.matches(&bytes, None, tail));
                    assert!(!current.matches(&bytes[..bytes.len() - 1], None, tail));
                    let changed = CurrentKey {
                        source: b"return 7",
                        ..current
                    };
                    assert!(!changed.matches(&bytes, None, tail));
                }
            }
        }
    }
}
#[test]
fn borrowed_exact_key_rejects_semantic_metadata_change_and_accepts_equal_current_owner() {
    let metadata = Arc::new(dm_ir::ProcedureMetadata {
        signature: dm_ir::ProcedureSignature {
            parameters: Arc::from([]),
            variadic: false,
            return_annotation: None,
        },
        settings: Arc::from([]),
    });
    let tail = PreparedKey::Issued(Arc::from(b"abi".as_slice()));
    let current = CurrentKey {
        prefix: [0; 41],
        metadata: &metadata,
        source: b"return 1",
        termination: 1,
        references: false,
        selections: false,
    };
    let bytes = current.materialize(&tail);
    let equal = Arc::new((*metadata).clone());
    let shifted = CurrentKey {
        metadata: &equal,
        ..current
    };
    assert!(shifted.matches(&bytes, None, &tail));
    assert_eq!(shifted.record_key(&tail), current.record_key(&tail));
    let mut changed = (*metadata).clone();
    changed.signature.variadic = true;
    let changed = Arc::new(changed);
    let changed = CurrentKey {
        metadata: &changed,
        ..current
    };
    assert!(!changed.matches(&bytes, None, &tail));
    assert_ne!(changed.record_key(&tail), current.record_key(&tail));
}

#[test]
fn borrowed_disk_failure_admission_keeps_exact_keys_and_negative_reads() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/proc/probe()\n    return missing()\n".into())
        }
    }
    struct Host(bool);
    impl dm_ir::Resolver for Host {
        fn resolve(&self, _: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            if self.0 {
                dm_ir::ResolvedMeaning::Missing
            } else {
                dm_ir::ResolvedMeaning::Symbol(dm_ir::SymbolId::of("present"))
            }
        }
    }
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("probe.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let body = &frontend.bodies[0];
    let current = CurrentKey::new(&frontend, body, 7, false, false).unwrap();
    let tail = PreparedKey::Parsed(vec![1, 2]);
    let key = current.materialize(&tail);
    let identity = dm_ir::ProcedureIdentity {
        owner: dm_ir::SymbolId::of("/"),
        name: dm_ir::SymbolId::of("probe"),
        verb: false,
        occurrence: 0,
    };
    let query = dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of("missing"));
    let read = crate::lowering_memo::ResolverRead {
        query,
        domain: query.domain(),
        answer: dm_ir::ResolvedMeaning::Missing,
    };
    let errors = [dm_codegen_byond::LowerError {
        statement: "returnmissing()".into(),
        reason: "missing: undefined proc".into(),
        span: None,
        primary_anchor: None,
        related: vec![],
        kind: dm_codegen_byond::LowerErrorKind::SourceError,
    }];
    let bytes =
        crate::lowering_memo_wire::encode_failure(&key, Some(identity), &[read], &[], &errors)
            .unwrap();
    let frame = dm_cache::encode_variants(&[bytes]).unwrap();
    let prepared = crate::procedure_policy::PreparedUnit::local_only(
        Default::default(),
        &frontend
            .body_input(body)
            .unwrap()
            .compact()
            .materialize_relative(),
    );
    let replay = |candidate: &CurrentKey<'_>, host: &Host| {
        crate::lowering_memo_wire::candidates(&frame)
            .unwrap()
            .procedure_matching(
                &|bytes| candidate.matches(bytes, None, &tail),
                identity,
                crate::lowering_memo_wire::ProcedureReplayContext {
                    frontend: &frontend,
                    body,
                    parsed: None,
                    bindings: None,
                    selections_only: false,
                    verify: false,
                    modified: None,
                },
                host,
                &prepared,
            )
    };
    assert!(replay(&current, &Host(true)).errors.is_some());
    assert!(replay(&current, &Host(false)).errors.is_none());
    let changed = CurrentKey {
        source: b"return present()",
        ..current
    };
    assert!(replay(&changed, &Host(true)).errors.is_none());
}
