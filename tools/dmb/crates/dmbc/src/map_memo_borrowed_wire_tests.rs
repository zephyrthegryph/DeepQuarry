use super::*;
#[test]
fn mapped_source_is_borrowed_with_legacy_bytes_and_current_owner_admission() {
    let captured = CapturedMap {
        path: Arc::new("fixture.dmm".into()),
        include_occurrence: 0,
        source: Arc::from("\"a\"=(/turf,/area)\n(1,1,1)={\"a\"}\n// Ω source\n"),
    };
    let plan = dm_tree::maps::plan(captured.clone()).unwrap();
    let key = b"exact-map-key";
    let bytes = encode_parse(key, &plan).unwrap();
    let (stored, frame) = envelope(&bytes).unwrap();
    let decoded: Parse<'_> = dm_wire::decode_borrowed(1, frame, frame.len()).unwrap();
    assert_eq!(stored, key);
    assert!(matches!(decoded.source, Cow::Borrowed(_)));
    let pointer = decoded.source.as_ptr() as usize;
    let begin = bytes.as_ptr() as usize;
    assert!(pointer >= begin && pointer + decoded.source.len() <= begin + bytes.len());
    // Independent legacy owned envelope roster, including original field order.
    // The nested DTOs are unchanged; only the full source field now borrows.
    let legacy = (
        decoded.version,
        decoded.source.to_string(),
        decoded.semantic,
        decoded.symbols,
        decoded.templates,
        decoded.blocks,
        decoded.records,
        decoded.key_width,
    );
    assert_eq!(frame, dm_wire::encode(1, &legacy).unwrap());
    validate_parse(&bytes).unwrap();
    let current = admit_parse(&bytes, key, captured.clone()).unwrap().unwrap();
    assert!(Arc::ptr_eq(&current.captured.source, &captured.source));
    assert_eq!(
        current.model.canonical_bytes(),
        plan.model.canonical_bytes()
    );
    let shifted = CapturedMap {
        source: Arc::from(format!("// moved\n{}", captured.source)),
        ..captured
    };
    assert!(admit_parse(&bytes, key, shifted).unwrap().is_none());
    assert!(admit_parse(&bytes, b"other-key", current.captured)
        .unwrap()
        .is_none());
}
