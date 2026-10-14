use super::*;
fn rows(bytes: &[u8]) -> Vec<Value> {
    std::str::from_utf8(bytes)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}
#[test]
fn resolver_negatives_and_unknowns_remain_distinct_and_wide_keys_roundtrip() {
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::HasMemberVar { .. } => ResolvedMeaning::Presence(false),
                ResolveQuery::Var { .. } => ResolvedMeaning::Missing,
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    let owner = SymbolId::of("/datum/example");
    let name = SymbolId::of("absent");
    let queries = [
        ResolveQuery::HasMemberVar { owner, name },
        ResolveQuery::Var { owner, name },
        ResolveQuery::ResourceIn {
            path: name,
            search_context: u128::MAX,
        },
    ];
    let mut bytes = Vec::new();
    assert_eq!(
        write_queries_jsonl(
            &SymbolTable::default(),
            &Host,
            queries.into_iter().map(|query| AnalysisQuery {
                subject: None,
                query
            }),
            &mut bytes
        )
        .unwrap(),
        3
    );
    let exported = rows(&bytes);
    assert_eq!(exported[0]["answer"]["status"], "known");
    assert_eq!(exported[0]["answer"]["value"], false);
    assert_eq!(exported[1]["answer"]["status"], "missing");
    assert_eq!(exported[2]["answer"]["status"], "unsupported");
    assert!(exported.iter().all(|row| row["domain_version"].is_null()));
    let decoded: ResolveQuery =
        serde_json::from_str(exported[2]["query_wire"].as_str().unwrap()).unwrap();
    assert_eq!(decoded, queries[2]);
}
#[test]
fn canonical_member_ids_follow_normalized_occurrences_and_queries_use_same_subjects() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/x/read()\n    return 2\n/datum/x/proc/read()\n    return 1\n/datum/x\n    var/static/value = 7\n".into())
        }
    }
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let mut bytes = Vec::new();
    super::super::write_jsonl(&frontend, &mut bytes).unwrap();
    let exported = rows(&bytes);
    assert_eq!(exported[0]["schema"], "dm-tree-analysis-v3");
    for (index, member) in frontend.snapshot.tree.members().iter().enumerate() {
        let tree = &frontend.snapshot.tree;
        let owner = tree.type_node(member.owner).unwrap().path;
        let ordinal = tree
            .member_occurrence(dm_tree::MemberId(index as u32))
            .unwrap();
        let id = format!(
            "member:{:016x}:{}:{:016x}:{ordinal}",
            owner.bits(),
            super::super::kind(member.kind),
            member.name.bits()
        );
        assert!(exported
            .iter()
            .any(|row| row["row"] == "member" && row["id"] == id));
        assert!(exported
            .iter()
            .any(|row| row["row"] == "resolved_query" && row["subject"] == id));
    }
    let storage = exported
        .iter()
        .find(|row| row["row"] == "resolved_query" && row["answer"]["kind"] == "shared_slot")
        .unwrap();
    assert_eq!(storage["answer"]["name"]["text"], "value");
    assert_eq!(storage["domain_version"].as_str().unwrap().len(), 32);
}

#[test]
fn opaque_member_export_keeps_uncertified_flags_distinct_from_authored_zero() {
    use dm_ir::{DeclarationMeaning, DeclaredTypeKnowledge, OpaqueFieldBase};
    use std::sync::Arc;
    let owner = SymbolId::of("/datum/example");
    let name = SymbolId::of("field");
    let mut data = DeclarationMeaning {
        inherited_opaque: Some(OpaqueFieldBase {
            owner,
            name,
            declared_type: DeclaredTypeKnowledge::Unsupported,
        }),
        list_element_type: Some(SymbolId::of("/datum/placeholder")),
        ..Default::default()
    };
    let opaque = answer(
        &SymbolTable::default(),
        &ResolvedMeaning::Member {
            owner,
            name,
            fingerprint: 1,
            data: Arc::new(data.clone()),
        },
    )
    .unwrap();
    assert!(opaque["flags"].is_null());
    assert_eq!(opaque["flags_status"], "unknown");
    assert!(opaque["declared_type"].is_null());
    assert_eq!(opaque["declared_type_status"], "unsupported");
    assert!(opaque["list_element_type"].is_null());
    assert_eq!(opaque["list_element_type_status"], "unknown");
    data.inherited_opaque = None;
    let authored = answer(
        &SymbolTable::default(),
        &ResolvedMeaning::Member {
            owner,
            name,
            fingerprint: 2,
            data: Arc::new(data),
        },
    )
    .unwrap();
    assert_eq!(authored["flags"], 0);
    assert_eq!(authored["flags_status"], "known");
    assert_eq!(authored["declared_type_status"], "known_untyped");
    assert_eq!(authored["list_element_type_status"], "known");
}
