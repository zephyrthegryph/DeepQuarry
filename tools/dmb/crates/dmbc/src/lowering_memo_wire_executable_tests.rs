use super::*;
struct Host(bool);
impl Resolver for Host {
    fn resolve(&self, _: ResolveQuery) -> dm_ir::ResolvedMeaning {
        if self.0 {
            dm_ir::ResolvedMeaning::Symbol(SymbolId::of("/datum"))
        } else {
            dm_ir::ResolvedMeaning::Missing
        }
    }
}
#[test]
fn anonymous_executable_roundtrips_and_rechecks_negative_reads() {
    let ast = dm_syntax::parse("/proc/p()\n    return 7\n");
    let body = &ast.items[0].children;
    let recorder = crate::lowering_memo::RecordingResolver::new(&Host(false));
    recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
    let code = dm_codegen_byond::compile_simple_proc_with_resolver(
        body,
        &Default::default(),
        &Default::default(),
        &recorder,
    )
    .unwrap();
    let bytes = encode_executable(
        b"exact typed initializer",
        &recorder.reads(),
        &recorder.domain_receipts(),
        &code,
    )
    .unwrap();
    let restored = decode_executable(&bytes, b"exact typed initializer", &Host(false), 0).unwrap();
    let framed = dm_cache::encode_variants(std::slice::from_ref(&bytes)).unwrap();
    assert_eq!(candidates(&framed).unwrap().0.len(), 1);
    let mut bad = bytes.clone();
    *bad.last_mut().unwrap() ^= 1;
    let bad = dm_cache::encode_variants(&[bytes.clone(), bad]).unwrap();
    assert!(
        candidates(&bad).is_err(),
        "every variant must validate before replay"
    );

    assert_eq!(code.procedure, restored.procedure);
    assert!(decode_executable(&bytes, b"exact typed initializer", &Host(true), 0).is_none());
    assert!(decode_executable(&bytes, b"different initializer", &Host(false), 0).is_none());
    for end in [0, 8, 31, bytes.len() - 1] {
        assert!(
            decode_executable(&bytes[..end], b"exact typed initializer", &Host(false), 0).is_none()
        );
    }
    let mut tampered = bytes.clone();
    *tampered.last_mut().unwrap() ^= 1;
    assert!(decode_executable(&tampered, b"exact typed initializer", &Host(false), 0).is_none());
    assert!(dm_wire::decode::<Payload>(EXECUTABLE_SCHEMA, &bytes, 1).is_err());
    let changed = Payload {
        version: 4,
        key: b"other key".to_vec(),
        identity: None,
        effective: false,
        reads: vec![],
        versions: vec![],
        body: CodeWire::capture(&code),
        debug: vec![],
        relative_debug: vec![],
        abi: None,
        helpers: vec![],
        selected_references: None,
    };
    let changed = dm_wire::encode(EXECUTABLE_SCHEMA, &changed).unwrap();
    assert!(decode_executable(&changed, b"exact typed initializer", &Host(false), 0).is_none());
}
#[test]
fn binary_failure_wire_preserves_optional_spans_and_rechecks_answers() {
    let errors = vec![
        dm_codegen_byond::LowerError {
            statement: "first".into(),
            reason: "unknown".into(),
            span: None,
            kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
        },
        dm_codegen_byond::LowerError {
            statement: "second".into(),
            reason: "duplicate".into(),
            span: Some(dm_codegen_byond::LowerSpan { start: 3, end: 4 }),
            kind: dm_codegen_byond::LowerErrorKind::SourceError,
        },
    ];
    let recorder = crate::lowering_memo::RecordingResolver::new(&Host(false));
    recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
    let bytes = encode_failure(
        b"failure",
        None,
        &recorder.reads(),
        &recorder.domain_receipts(),
        &errors,
    )
    .unwrap();
    assert_eq!(
        decode_failure(&bytes, b"failure", None, &Host(false)).unwrap(),
        errors
    );
    assert!(decode_failure(&bytes, b"failure", None, &Host(true)).is_none());
    assert!(decode_failure(&bytes, b"other", None, &Host(false)).is_none());
    let mut invalid = bytes;
    *invalid.last_mut().unwrap() ^= 1;
    assert!(validate(&invalid).is_err());
}
#[test]
fn domain_receipts_apply_to_anonymous_success_and_failure_wire() {
    struct Versioned {
        version: Option<u128>,
        calls: std::sync::atomic::AtomicUsize,
        changed: bool,
    }
    impl Resolver for Versioned {
        fn domain_version(&self, _: dm_ir::ReadDomain) -> Option<u128> {
            self.version
        }
        fn resolve(&self, _: ResolveQuery) -> dm_ir::ResolvedMeaning {
            self.calls
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            if self.changed {
                dm_ir::ResolvedMeaning::Symbol(SymbolId::of("changed"))
            } else {
                dm_ir::ResolvedMeaning::Missing
            }
        }
    }
    let host = |version, changed| Versioned {
        version,
        changed,
        calls: Default::default(),
    };
    let original = host(Some(9), false);
    let recorder = crate::lowering_memo::RecordingResolver::new(&original);
    recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
    let ast = dm_syntax::parse("/proc/p()\n    return 7\n");
    let code = dm_codegen_byond::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &Default::default(),
        &Default::default(),
        &recorder,
    )
    .unwrap();
    let success = encode_executable(
        b"versioned",
        &recorder.reads(),
        &recorder.domain_receipts(),
        &code,
    )
    .unwrap();
    let failure = encode_failure(
        b"versioned",
        None,
        &recorder.reads(),
        &recorder.domain_receipts(),
        &[dm_codegen_byond::LowerError {
            statement: "bad".into(),
            reason: "unsupported".into(),
            span: None,
            kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
        }],
    )
    .unwrap();
    let same = host(Some(9), false);
    assert!(decode_executable(&success, b"versioned", &same, 0).is_some());
    assert!(decode_failure(&failure, b"versioned", None, &same).is_some());
    assert_eq!(same.calls.load(std::sync::atomic::Ordering::Relaxed), 0);
    let unknown = host(None, false);
    assert!(decode_executable(&success, b"versioned", &unknown, 0).is_some());
    assert!(decode_failure(&failure, b"versioned", None, &unknown).is_some());
    assert!(unknown.calls.load(std::sync::atomic::Ordering::Relaxed) >= 2);
    let changed = host(Some(10), true);
    assert!(decode_executable(&success, b"versioned", &changed, 0).is_none());
    assert!(decode_failure(&failure, b"versioned", None, &changed).is_none());
    assert!(
        validate_versions(&[(dm_ir::ReadDomain::Tree, 1), (dm_ir::ReadDomain::Tree, 2)]).is_err()
    );
}
#[test]
fn unified_anonymous_lookup_preserves_failure_priority_and_exact_read_invalidation() {
    let ast = dm_syntax::parse("/proc/p()\n    return 7\n");
    let recorder = crate::lowering_memo::RecordingResolver::new(&Host(false));
    recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
    let code = dm_codegen_byond::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &Default::default(),
        &Default::default(),
        &recorder,
    )
    .unwrap();
    let success = encode_executable(
        b"anonymous",
        &recorder.reads(),
        &recorder.domain_receipts(),
        &code,
    )
    .unwrap();
    let errors = vec![dm_codegen_byond::LowerError {
        statement: "unsupported".into(),
        reason: "captured failure".into(),
        span: None,
        kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
    }];
    let failure = encode_failure(
        b"anonymous",
        None,
        &recorder.reads(),
        &recorder.domain_receipts(),
        &errors,
    )
    .unwrap();
    let success_only = dm_cache::encode_variants(std::slice::from_ref(&success)).unwrap();
    let replay = candidates(&success_only)
        .unwrap()
        .anonymous(b"anonymous", &Host(false), 0);
    assert_eq!(replay.code.unwrap().procedure, code.procedure);
    let mixed = dm_cache::encode_variants(&[failure, success]).unwrap();
    let replay = candidates(&mixed)
        .unwrap()
        .anonymous(b"anonymous", &Host(false), 0);
    assert_eq!(replay.errors, Some(errors));
    assert!(
        replay.code.is_none(),
        "failure priority preserved even when success is newer"
    );
    let changed = candidates(&mixed)
        .unwrap()
        .anonymous(b"anonymous", &Host(true), 0);
    assert!(changed.code.is_none() && changed.errors.is_none());
    let other = candidates(&mixed)
        .unwrap()
        .anonymous(b"other", &Host(false), 0);
    assert!(other.code.is_none() && other.errors.is_none());
}
