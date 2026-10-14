use super::*;
#[test]
fn shared_sequence_canonical_bytes_match_legacy_tags_and_framing() {
    let first = SymbolId::of("/first");
    let second = SymbolId::of("/second");
    let mut symbols = b"dm-resolved-meaning-v1\0".to_vec();
    symbols.push(8);
    symbols.extend_from_slice(&2u64.to_le_bytes());
    symbols.extend_from_slice(&first.bits().to_le_bytes());
    symbols.extend_from_slice(&second.bits().to_le_bytes());
    let actual = ResolvedMeaning::Symbols(Arc::from([first, second]));
    assert_eq!(actual.canonical_bytes(), symbols);
    let mut missing = b"dm-resolved-meaning-v1\0".to_vec();
    missing.push(0);
    let mut members = b"dm-resolved-meaning-v1\0".to_vec();
    members.push(9);
    members.extend_from_slice(&2u64.to_le_bytes());
    for child in [&symbols, &missing] {
        members.extend_from_slice(&(child.len() as u64).to_le_bytes());
        members.extend_from_slice(child);
    }
    let values = ResolvedMeaning::Members(Arc::from([actual, ResolvedMeaning::Missing]));
    assert_eq!(values.canonical_bytes(), members);
    assert_eq!(ResolvedMeaning::Symbols(Arc::from([])).canonical_bytes(), {
        let mut bytes = b"dm-resolved-meaning-v1\0".to_vec();
        bytes.push(8);
        bytes.extend_from_slice(&0u64.to_le_bytes());
        bytes
    });
}
