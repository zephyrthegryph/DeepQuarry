use super::*;
#[test]
fn borrowed_failure_is_legacy_byte_identical_and_points_inside_frame() {
    let key = b"exact-key";
    let errors = [dm_codegen_byond::LowerError {
        statement: "return Ω".into(),
        reason: "unsupported exact model".into(),
        span: None,
        kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
    }];
    let query = ResolveQuery::Ancestry(SymbolId::of("/datum/Ω"));
    let reads = [
        ResolverRead {
            query,
            domain: query.domain(),
            answer: dm_ir::ResolvedMeaning::Symbols(vec![
                SymbolId::of("/datum"),
                SymbolId::of("/datum/Ω"),
            ]),
        },
        ResolverRead {
            query: ResolveQuery::GlobalVar(SymbolId::of("missing")),
            domain: ResolveQuery::GlobalVar(SymbolId::of("missing")).domain(),
            answer: dm_ir::ResolvedMeaning::Missing,
        },
    ];
    let bytes = encode_failure(key, None, &reads, &[], &errors).unwrap();
    // Legacy owned field roster, including original tuple/struct sequence shape.
    let legacy = (
        key.to_vec(),
        Option::<ProcedureIdentity>::None,
        reads
            .iter()
            .map(|r| (r.query, r.answer.canonical_bytes()))
            .collect::<Vec<_>>(),
        Vec::<(dm_ir::ReadDomain, u128)>::new(),
        vec![(
            errors[0].statement.clone(),
            errors[0].reason.clone(),
            errors[0].span,
            errors[0].kind,
        )],
    );
    assert_eq!(bytes, dm_wire::encode(FAILURE_SCHEMA, &legacy).unwrap());
    let borrowed: FailurePayload =
        dm_wire::decode_borrowed(FAILURE_SCHEMA, &bytes, bytes.len()).unwrap();
    assert!(matches!(borrowed.key, Cow::Borrowed(_)));
    assert!(matches!(borrowed.errors[0].statement, Cow::Borrowed(_)));
    assert!(matches!(borrowed.errors[0].reason, Cow::Borrowed(_)));
    for (wire, original) in borrowed.reads.iter().zip(&reads) {
        assert_eq!(wire.query, original.query);
        assert_eq!(wire.answer.as_ref(), original.answer.canonical_bytes());
        assert!(matches!(wire.answer, Cow::Borrowed(_)));
    }
    struct Current<'a>(&'a [ResolverRead], bool);
    impl Resolver for Current<'_> {
        fn resolve(&self, query: ResolveQuery) -> dm_ir::ResolvedMeaning {
            if self.1 {
                return dm_ir::ResolvedMeaning::Missing;
            }
            self.0
                .iter()
                .find(|r| r.query == query)
                .unwrap()
                .answer
                .clone()
        }
    }
    assert_eq!(
        decode_failure(&bytes, key, None, &Current(&reads, false)).unwrap(),
        errors
    );
    assert!(decode_failure(&bytes, key, None, &Current(&reads, true)).is_none());
    let start = bytes.as_ptr() as usize;
    let end = start + bytes.len();
    for (pointer, length) in [
        (borrowed.key.as_ptr() as usize, borrowed.key.len()),
        (
            borrowed.errors[0].statement.as_ptr() as usize,
            borrowed.errors[0].statement.len(),
        ),
        (
            borrowed.errors[0].reason.as_ptr() as usize,
            borrowed.errors[0].reason.len(),
        ),
    ] {
        assert!(pointer >= start && pointer + length <= end);
    }
    for read in &borrowed.reads {
        let pointer = read.answer.as_ptr() as usize;
        assert!(pointer >= start && pointer + read.answer.len() <= end);
    }
    assert_eq!(
        borrowed
            .errors
            .into_iter()
            .map(ErrorWire::rehydrate)
            .collect::<Vec<_>>(),
        errors
    );
}
