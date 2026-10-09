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
    let bytes = encode_failure(key, None, &[], &[], &errors).unwrap();
    // Legacy owned field roster, including original tuple/struct sequence shape.
    let legacy = (
        key.to_vec(),
        Option::<ProcedureIdentity>::None,
        Vec::<(ResolveQuery, Vec<u8>)>::new(),
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
    assert_eq!(
        borrowed
            .errors
            .into_iter()
            .map(ErrorWire::rehydrate)
            .collect::<Vec<_>>(),
        errors
    );
}
