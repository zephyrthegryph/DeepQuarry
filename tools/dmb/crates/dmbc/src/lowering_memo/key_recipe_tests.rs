use super::*;
fn metadata(variadic: bool) -> Arc<dm_ir::ProcedureMetadata> {
    Arc::new(dm_ir::ProcedureMetadata {
        signature: dm_ir::ProcedureSignature {
            parameters: Arc::from([]),
            variadic,
            return_annotation: None,
        },
        settings: Arc::from([]),
    })
}
#[test]
fn resident_recipe_exact_inputs_and_issued_tail_match_legacy_bytes() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/test/proc/run()\n    return 7\n".into())
        }
    }
    let frontend = dm_tree::frontend::build_with_config(
        std::path::Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let body = &frontend.bodies[0];
    let unit = crate::procedure_policy::PreparedUnit::local_only(
        Default::default(),
        &dm_syntax::Item {
            kind: dm_syntax::ItemKind::Proc,
            header: "run()".into(),
            span: dm_syntax::Span { start: 0, end: 0 },
            header_span: dm_syntax::Span { start: 0, end: 0 },
            indent: 0,
            children: Vec::new(),
        },
    );
    let prepared = PreparedKey::issued(&unit).unwrap();
    let mut old_tail = Vec::new();
    crate::lowering_memo::prepared_replay_key(&mut old_tail, &unit).unwrap();
    assert!(prepared.matches(&old_tail));
    for references in [false, true] {
        for selections in [false, true] {
            let input = CurrentKey::new(&frontend, body, 73, references, selections).unwrap();
            let mut legacy = crate::lowering_memo::key(&frontend, body, 73).unwrap();
            if references {
                legacy.push(0);
                legacy.extend_from_slice(dm_ir::SELECTED_REFERENCES_POLICY);
            }
            if selections {
                legacy.extend_from_slice(b"selected-facts-only-v1");
            }
            prepared.append(&mut legacy);
            assert_eq!(input.materialize(&prepared), legacy);
            let recipe = KeyRecipe::new(&legacy, Arc::clone(input.metadata)).unwrap();
            assert!(input.matches(&legacy, Some(&recipe), &prepared));
            assert!(input.matches(&legacy, None, &prepared));
            assert!(!input.matches(
                &legacy,
                Some(&recipe),
                &PreparedKey::Issued(Arc::from(b"changed-prepared".as_slice()))
            ));
            assert!(
                !CurrentKey::new(&frontend, body, 74, references, selections)
                    .unwrap()
                    .matches(&legacy, Some(&recipe), &prepared)
            );
        }
    }
}
#[test]
fn distinct_equal_metadata_falls_back_to_exact_equality_and_changes_decline() {
    let metadata = metadata(false);
    let input = CurrentKey {
        prefix: [0; 41],
        metadata: &metadata,
        source: b"return 1",
        termination: dm_syntax::BodyTermination::ExhaustedInput.canonical_tag(),
        references: false,
        selections: false,
    };
    let tail = PreparedKey::Parsed(vec![1, 2, 3]);
    let bytes = input.materialize(&tail);
    for previous_prefix in [
        b"dmbc-procedure-memo-v7-diagnostic-anchors\0".as_slice(),
        b"dmbc-procedure-memo-v8-certified-missing-calls\0".as_slice(),
        b"dmbc-procedure-memo-v9-formal-scope\0".as_slice(),
        b"dmbc-procedure-memo-v10-typed-missing-member\0".as_slice(),
        b"dmbc-procedure-memo-v11-member-call-namespace\0".as_slice(),
        b"dmbc-procedure-memo-v12-safe-member-catch-provenance\0".as_slice(),
        b"dmbc-procedure-memo-v13-local-member-call-proof\0".as_slice(),
    ] {
        let mut previous = previous_prefix.to_vec();
        previous.extend_from_slice(&bytes[PREFIX.len()..]);
        assert!(KeyRecipe::new(&previous, Arc::clone(&metadata)).is_none());
        assert!(!input.matches(&previous, None, &tail));
    }
    let equal = KeyRecipe::new(&bytes, Arc::new((*metadata).clone())).unwrap();
    assert!(!Arc::ptr_eq(&equal.metadata, &metadata));
    assert!(input.matches(&bytes, Some(&equal), &tail));
    let changed = self::metadata(true);
    let changed_input = CurrentKey {
        metadata: &changed,
        ..input
    };
    assert!(!changed_input.matches(&bytes, Some(&equal), &tail));
    let changed_body = CurrentKey {
        source: b"return 2",
        ..changed_input
    };
    assert!(!changed_body.matches(&bytes, Some(&equal), &tail));
    assert!(!changed_body.matches(&bytes[..bytes.len() - 1], Some(&equal), &tail));
}

#[test]
fn borrowed_key_occurrence_matches_independent_inherited_reopen_chain() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/base/proc/run()\n    return 1\n/datum/child\n    parent_type = /datum/base\n/datum/child/proc/run()\n    return 2\n/datum/child/run()\n    return 3\n".into())
        }
    }
    let frontend = dm_tree::frontend::build_with_config(
        std::path::Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let tree = &frontend.snapshot.tree;
    let mut child_ordinals = Vec::new();
    for body in frontend.bodies.iter() {
        let member = tree.member(body.member).unwrap();
        // Independent reference: original full override vector includes inherited
        // entries; only matching local declarations consume this owner's ordinal.
        let expected = tree
            .override_chain(body.member)
            .iter()
            .filter(|id| {
                let prior = tree.member(**id).unwrap();
                prior.owner == member.owner
                    && prior.name == member.name
                    && prior.kind == member.kind
            })
            .count()
            - 1;
        let input = CurrentKey::new(&frontend, body, 1, false, false).unwrap();
        assert_eq!(&input.prefix[33..41], &(expected as u64).to_le_bytes());
        if tree.type_node(member.owner).unwrap().path == dm_ir::SymbolId::of("/datum/child") {
            child_ordinals.push(expected);
        }
    }
    assert_eq!(child_ordinals, [0, 1]);
}

#[test]
fn identical_body_bytes_cannot_replay_across_pending_body_context_change() {
    struct Source(String);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    let make = |suffix: &str| {
        dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source(format!(
                "/proc/probe()\n    for(var/key, value in list(\"a\" = 2)){suffix}\n"
            )),
            &Default::default(),
            1,
        )
        .unwrap()
    };
    let invalid = make("");
    let valid = make(";");
    let invalid_key = CurrentKey::new(&invalid, &invalid.bodies[0], 73, false, false).unwrap();
    let valid_key = CurrentKey::new(&valid, &valid.bodies[0], 73, false, false).unwrap();
    assert_eq!(
        invalid_key.source, valid_key.source,
        "delimiter context lies outside the envelope"
    );
    let tail = PreparedKey::Parsed(vec![19, 7, 3, 1]);
    let failure = invalid_key.materialize(&tail);
    let success = valid_key.materialize(&tail);
    assert!(!valid_key.matches(&failure, None, &tail));
    assert!(!invalid_key.matches(&success, None, &tail));
    // Exercise the actual disk owner, including both success and failure payloads.
    struct Host;
    impl dm_ir::Resolver for Host {
        fn resolve(&self, _: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            dm_ir::ResolvedMeaning::Missing
        }
    }
    let root = if cfg!(windows) {
        std::path::PathBuf::from("E:/dq-cache/dmb-protocol-checks")
    } else {
        std::env::temp_dir()
    };
    let directory = root.join(format!(
        "pending-body-disk-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&directory).unwrap();
    let cache = dm_cache::Cache::open(&directory, dm_cache::Limits::default()).unwrap();
    let ast = dm_syntax::parse("/proc/result()\n    return 7\n");
    let code = dm_codegen_byond::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &Default::default(),
        &Default::default(),
        &Host,
    )
    .unwrap();
    let diagnostic = dm_codegen_byond::LowerError {
        statement: String::new(),
        reason: ": invalid expression".into(),
        kind: dm_codegen_byond::LowerErrorKind::SourceError,
        span: None,
        primary_anchor: None,
        related: Vec::new(),
    };
    let errors =
        crate::lowering_memo_wire::encode_failure(&failure, None, &[], &[], &[diagnostic]).unwrap();
    let executable =
        crate::lowering_memo_wire::encode_executable(&success, &[], &[], &code).unwrap();
    // One locator deliberately carries both typed candidates: full key admission
    // must select the proper outcome rather than trusting the physical record.
    let variants = dm_cache::encode_variants(&[errors, executable]).unwrap();
    for key in [&failure, &success] {
        cache
            .publish(&[dm_cache::Record {
                key: crate::lowering_memo::ProcedureMemo::record_key(key),
                symbols: Vec::new(),
                payload: Arc::from(variants.clone()),
            }])
            .unwrap();
    }
    let memo =
        crate::lowering_memo::ProcedureMemo::with_disk(73, Arc::new(cache.snapshot().unwrap()));
    let failure_hit = memo.lookup_anonymous(&failure, &Host, 0);
    assert!(failure_hit.code.is_none());
    assert_eq!(
        failure_hit.errors.unwrap()[0].reason,
        ": invalid expression"
    );
    let success_hit = memo.lookup_anonymous(&success, &Host, 0);
    assert!(success_hit.errors.is_none() && success_hit.code.is_some());
    drop(memo);
    drop(cache);
    let resolved_directory = directory.canonicalize().unwrap();
    assert!(resolved_directory.starts_with(root.canonicalize().unwrap()));
    std::fs::remove_dir_all(&resolved_directory).unwrap();
    let renamed_a = make("\n/proc/next_a()\n    return 7");
    let renamed_b = make("\n/proc/next_b()\n    return 8");
    let a = CurrentKey::new(&renamed_a, &renamed_a.bodies[0], 73, false, false).unwrap();
    let b = CurrentKey::new(&renamed_b, &renamed_b.bodies[0], 73, false, false).unwrap();
    assert!(b.matches(&a.materialize(&tail), None, &tail));
    for suffix in [
        "\n/datum/proc/after()\n    return 1",
        "\n/datum/after\n    var/value = 1",
    ] {
        let declaration = make(suffix);
        let key = CurrentKey::new(&declaration, &declaration.bodies[0], 73, false, false).unwrap();
        assert_eq!(
            key.termination,
            dm_syntax::BodyTermination::DeclarationBoundary.canonical_tag()
        );
        let arena = dm_tree::frontend::BodyArena::new_typed(
            &declaration,
            dm_codegen_byond::typed_statements_supported,
        );
        arena
            .with_parsed(&declaration.bodies[0], |body| {
                let statements = body.shared_statement_body().unwrap();
                assert_eq!(
                    statements.parsed().pending_bodies[0].termination,
                    dm_syntax::BodyTermination::DeclarationBoundary
                );
            })
            .unwrap();
    }
}
