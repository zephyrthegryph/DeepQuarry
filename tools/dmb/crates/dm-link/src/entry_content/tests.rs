use super::*;
use crate::{Entry, Key, LinkError, LinkInventory, LinkTables};

fn symbolic(words: Vec<u32>, prefix: &[u8], suffix: &[u8]) -> EntryContent {
    EntryContent::symbolic(
        prefix.into(),
        Arc::new(SymbolicCode::new(words, Vec::new()).unwrap()),
        suffix.into(),
    )
}
fn inventory(contents: Vec<EntryContent>) -> LinkInventory {
    LinkInventory {
        entries: contents
            .into_iter()
            .map(|content| Entry {
                key: Key::List(71),
                content,
            })
            .collect(),
        ..Default::default()
    }
}

#[test]
fn equal_structural_entries_and_size_do_not_materialize_code() {
    let first = symbolic(vec![1, 2, 3], b"frame", b"metadata");
    let same = symbolic(vec![1, 2, 3], b"frame", b"metadata");
    let expected_len = b"frame".len()
        + SymbolicCode::new(vec![1, 2, 3], Vec::new())
            .unwrap()
            .canonical_len()
        + b"metadata".len();
    assert_eq!(first.byte_len(), expected_len);
    assert_eq!(first, same);
    assert!(first.materialized_bytes().is_none());
    assert!(same.materialized_bytes().is_none());
    let tables = LinkTables::build(inventory(vec![first.clone(), same.clone()])).unwrap();
    assert!(tables
        .content_value(Key::List(71))
        .unwrap()
        .materialized_bytes()
        .is_none());
    assert!(matches!(
        LinkTables::build(inventory(vec![
            first.clone(),
            symbolic(vec![1, 2, 4], b"frame", b"metadata")
        ])),
        Err(LinkError::ContentCollision(Key::List(71)))
    ));
    assert!(matches!(
        LinkTables::build(inventory(vec![
            first.clone(),
            symbolic(vec![1, 2, 3], b"frame", b"changed")
        ])),
        Err(LinkError::ContentCollision(Key::List(71)))
    ));
    // Same-length, structurally different inputs require the exact canonical
    // fallback. The independently equal entry still needs no encoding.
    assert!(first.materialized_bytes().is_some());
    assert!(same.materialized_bytes().is_none());
}

#[test]
fn mixed_content_uses_exact_canonical_bytes_and_shared_lazy_storage() {
    let structured = symbolic(vec![9, 8], b"prefix", b"suffix");
    let mut expected = b"prefix".to_vec();
    expected.extend(
        SymbolicCode::new(vec![9, 8], Vec::new())
            .unwrap()
            .canonical_bytes(),
    );
    expected.extend_from_slice(b"suffix");
    let tables =
        LinkTables::build(inventory(vec![structured.clone(), expected.clone().into()])).unwrap();
    assert_eq!(tables.content(Key::List(71)).unwrap(), expected);
    assert_eq!(structured.as_ref(), expected);
    let bytes = structured.shared_bytes();
    let cloned = structured.clone().shared_bytes();
    assert!(Arc::ptr_eq(&bytes, &cloned));
    let EntryContent::Symbolic(retained) = &structured else {
        panic!("structured content");
    };
    let (_, code, _) = retained.parts();
    assert_eq!(code.words(), &[9, 8]);
    assert!(retained.materialized_bytes().is_some());
    expected[0] ^= 1;
    assert!(matches!(
        LinkTables::build(inventory(vec![structured, expected.into()])),
        Err(LinkError::ContentCollision(Key::List(71)))
    ));
}

#[test]
fn byte_contents_share_original_allocation_without_new_encoding() {
    let bytes: Arc<[u8]> = b"unchanged".as_slice().into();
    let content = EntryContent::from(Arc::clone(&bytes));
    assert_eq!(content.byte_len(), bytes.len());
    assert!(Arc::ptr_eq(&content.shared_bytes(), &bytes));
}

#[test]
fn canonical_equality_is_transitive_across_different_symbolic_segmentation() {
    let first = Arc::new(SymbolicCode::new(vec![1], Vec::new()).unwrap());
    let second = Arc::new(SymbolicCode::new(vec![2], Vec::new()).unwrap());
    let left = EntryContent::symbolic(
        Arc::from([]),
        Arc::clone(&first),
        second.canonical_bytes().into(),
    );
    let right = EntryContent::symbolic(
        first.canonical_bytes().into(),
        Arc::clone(&second),
        Arc::from([]),
    );
    let mut bytes = first.canonical_bytes();
    bytes.extend(second.canonical_bytes());
    let encoded = EntryContent::from(bytes);
    assert_eq!(left, right);
    assert_eq!(left, encoded);
    assert_eq!(encoded, right);
    LinkTables::build(inventory(vec![left, encoded, right])).unwrap();
}

#[test]
fn unequal_canonical_lengths_reject_without_materialization() {
    let left = symbolic(vec![1], b"prefix", b"suffix");
    let right = symbolic(vec![1, 2], b"prefix", b"suffix");
    assert_ne!(left, right);
    assert!(left.materialized_bytes().is_none());
    assert!(right.materialized_bytes().is_none());
}
