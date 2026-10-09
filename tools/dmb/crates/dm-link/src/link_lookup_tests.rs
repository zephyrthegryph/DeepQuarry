use super::*;
use dm_ir::{Relocation, RelocationEncoding};

fn code(references: &[SymRef]) -> SymbolicCode {
    SymbolicCode::new(
        vec![0; references.len()],
        references
            .iter()
            .enumerate()
            .map(|(offset, &reference)| Relocation {
                offset: offset as u32,
                reference,
                encoding: RelocationEncoding::Direct,
            })
            .collect(),
    )
    .unwrap()
}

#[test]
fn repeated_typed_references_share_resolution_without_changing_first_missing_order() {
    let symbol = SymbolId::of("payload");
    let key = Key::String(symbol);
    let tables = LinkTables::build(LinkInventory {
        spellings: vec![(symbol, Arc::from(b"payload".as_slice()))],
        entries: vec![Entry {
            key,
            content: b"payload".as_slice().into(),
        }],
        fixed: vec![(key, 9)],
        ..Default::default()
    })
    .unwrap();
    let reference = SymRef::String(symbol);
    let source = SourceBindings {
        first_line: 20,
        ..Default::default()
    };
    let valid = code(&[
        reference,
        reference,
        SymRef::LineDelta(3),
        SymRef::LineDelta(3),
    ]);
    let linked = tables.link(&valid, &source).unwrap();
    assert_eq!(linked.words.as_slice(), &[9, 9, 23, 23]);
    assert_eq!(valid.words(), &[0, 0, 0, 0]);
    let first_missing = SymRef::String(SymbolId::of("z_missing"));
    let second_missing = SymRef::String(SymbolId::of("a_missing"));
    let invalid = code(&[reference, reference, first_missing, second_missing]);
    assert_eq!(
        tables.link(&invalid, &source).unwrap_err(),
        LinkError::UnknownReference(first_missing)
    );
}
