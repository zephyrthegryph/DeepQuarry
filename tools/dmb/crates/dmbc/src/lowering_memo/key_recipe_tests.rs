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
        references: false,
        selections: false,
    };
    let tail = PreparedKey::Parsed(vec![1, 2, 3]);
    let bytes = input.materialize(&tail);
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
