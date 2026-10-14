use super::*;
fn frontend() -> dm_tree::frontend::ColdFrontend {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/base\n    var/value = 1\n/datum/child\n    parent_type = /datum/base\n    value = 2\n".into())
        }
    }
    dm_tree::frontend::build_with_config(
        std::path::Path::new("pages.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap()
}
#[test]
fn semantic_pages_pin_current_rosters_without_source_snapshot() {
    let frontend = frontend();
    let tree = &frontend.snapshot.tree;
    let mut request:QueryRequest=serde_json::from_value(serde_json::json!({"project":"pages.dme","defines":{},"engine_template":null,"bootstrap_catalog":false,"expected_revision":format!("{:032x}",tree.identity()),"queries":[],"source_queries":[{"SemanticTypesPage":{"start":0,"limit":2}},{"SemanticMembersPage":{"start":0,"limit":128}}]})).unwrap();
    let reply = super::super::evaluate(&request, tree).unwrap();
    assert!(reply.source_revision.is_none());
    assert!(!reply.complete);
    validate_requested(&reply, &request.source_queries).unwrap();
    let rows: Vec<serde_json::Value> = reply
        .jsonl
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    for row in &rows {
        validate(row, &reply.revision).unwrap();
    }
    assert_eq!(rows[0]["returned"], 2);
    assert_eq!(
        rows[1]["total"].as_u64().unwrap(),
        tree.members().len() as u64
    );
    assert!(rows[1]["items"]
        .as_array()
        .unwrap()
        .iter()
        .any(|item| !item["previous_ordinal"].is_null()));
    request.expected_revision = None;
    assert!(request.validate().is_err());
    request.expected_revision = Some("0".repeat(32));
    assert!(super::super::evaluate(&request, tree).is_err());
}
#[test]
fn semantic_page_client_rejects_wrong_order_cursor_and_missing_rows() {
    let tree = frontend();
    let tree = &tree.snapshot.tree;
    let mut bytes = Vec::new();
    write(
        &SourceQuery::SemanticTypesPage { start: 0, limit: 1 },
        tree,
        &mut bytes,
    )
    .unwrap();
    let mut row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let revision = format!("{:032x}", tree.identity());
    validate(&row, &revision).unwrap();
    row["items"][0]["ordinal"] = 99.into();
    assert!(validate(&row, &revision).is_err());
    row["items"][0]["ordinal"] = 0.into();
    row["next_cursor"] = serde_json::Value::Null;
    assert!(validate(&row, &revision).is_err());
}

#[test]
fn intrinsic_pages_expose_engine_only_rows_and_exact_completeness_storage_proofs() {
    let build = |complete| {
        let mut symbols = dm_ir::SymbolTable::default();
        let name = symbols.intern("engine_only").unwrap();
        let tree = dm_tree::build(symbols, &[]).unwrap();
        let hierarchy = dm_tree::EngineHierarchy {
            schema: 1,
            parents: tree
                .types()
                .iter()
                .map(|node| {
                    (
                        node.path,
                        node.parent.map(|id| tree.types()[id.0 as usize].path),
                    )
                })
                .collect(),
        };
        let intrinsic = dm_tree::IntrinsicMember {
            owner: dm_ir::SymbolId::of("/"),
            name,
            kind: dm_tree::MemberKind::Var,
            shared_owner: None,
            instance_storage_proven: true,
        };
        if complete {
            tree.with_complete_intrinsics(hierarchy, vec![intrinsic])
                .unwrap()
        } else {
            tree.with_engine_intrinsics(hierarchy, vec![intrinsic])
                .unwrap()
        }
    };
    for complete in [false, true] {
        let tree = build(complete);
        assert!(tree.members().is_empty());
        assert_eq!(
            tree.intrinsic_members().as_ptr(),
            tree.intrinsic_members().as_ptr()
        );
        let mut bytes = Vec::new();
        write(
            &SourceQuery::SemanticIntrinsicMembersPage {
                start: 0,
                limit: 128,
            },
            &tree,
            &mut bytes,
        )
        .unwrap();
        let mut row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        validate(&row, &format!("{:032x}", tree.identity())).unwrap();
        assert_eq!(row["total"], 1);
        assert_eq!(row["intrinsic_inventory_complete"], complete);
        assert_eq!(row["hierarchy_certified"], true);
        assert_eq!(row["items"][0]["name"], "engine_only");
        assert_eq!(row["items"][0]["storage_status"], "instance");
        assert_eq!(
            row["items"][0]["provenance"],
            "captured_engine_intrinsic_inventory"
        );
        row["intrinsic_inventory_complete"] = serde_json::Value::Null;
        assert!(validate(&row, &format!("{:032x}", tree.identity())).is_err());
    }
}

#[test]
fn intrinsic_unknown_spelling_keeps_exact_symbol_selector_without_forging_a_name() {
    let tree = dm_tree::build(dm_ir::SymbolTable::default(), &[]).unwrap();
    let name = dm_ir::SymbolId::of("uncaptured_intrinsic_spelling");
    let hierarchy = dm_tree::EngineHierarchy {
        schema: 1,
        parents: vec![(dm_ir::SymbolId::of("/"), None)],
    };
    let tree = tree
        .with_engine_intrinsics(
            hierarchy,
            vec![dm_tree::IntrinsicMember {
                owner: dm_ir::SymbolId::of("/"),
                name,
                kind: dm_tree::MemberKind::Proc,
                shared_owner: None,
                instance_storage_proven: false,
            }],
        )
        .unwrap();
    let mut bytes = Vec::new();
    write(
        &SourceQuery::SemanticIntrinsicMembersPage { start: 0, limit: 1 },
        &tree,
        &mut bytes,
    )
    .unwrap();
    let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    validate(&row, &format!("{:032x}", tree.identity())).unwrap();
    assert!(row["items"][0]["name"].is_null());
    assert_eq!(row["items"][0]["name_spelling_known"], false);
    assert_eq!(
        row["items"][0]["name_symbol"],
        format!("{:016x}", name.bits())
    );
    assert_eq!(row["items"][0]["storage_status"], "unknown");
}
