use super::*;

#[test]
fn process_local_owner_versions_are_omitted_from_disk_but_queries_remain() {
    let owner = dm_ir::SymbolId::of("/datum/probe");
    let query = dm_ir::ResolveQuery::Ancestry(owner);
    let read = ResolverRead {
        query,
        answer: dm_ir::ResolvedMeaning::Symbols(vec![owner]),
        domain: query.domain(),
    };
    let versions = [
        (dm_ir::ReadDomain::Tree, 19),
        (dm_ir::ReadDomain::OwnerHierarchy(owner), 1),
    ];
    let bytes = encode_failure(
        b"owner-cert",
        None,
        &[read],
        &versions,
        &[dm_codegen_byond::LowerError {
            statement: "unsupported".into(),
            reason: "fixture refusal".into(),
            span: None,
            kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
        }],
    )
    .unwrap();
    let payload: FailurePayload<'_> =
        dm_wire::decode_borrowed(FAILURE_SCHEMA, &bytes, bytes.len()).unwrap();
    assert_eq!(payload.versions, vec![(dm_ir::ReadDomain::Tree, 19)]);
    assert_eq!(payload.reads[0].query, query);
    assert!(validate_versions(&versions).is_err());
}
