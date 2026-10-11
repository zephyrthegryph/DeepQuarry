use super::*;
#[test]
fn unaligned_shared_bytes_have_exact_little_endian_words_and_shared_lifetime() {
    let bytes = Arc::new(vec![255, 4, 3, 2, 1, 221, 204, 187, 170, 254]);
    let weak = Arc::downgrade(&bytes);
    let storage = WordStorage::shared(bytes.clone(), 1..9).unwrap();
    let clone = storage.clone();
    let owned = WordStorage::Owned(vec![0x01020304, 0xaabbccdd]);
    assert_eq!(storage, owned);
    assert_eq!(storage.to_vec(), vec![0x01020304, 0xaabbccdd]);
    assert_eq!(storage.word_at(2), None);
    assert_eq!(storage.word_at(usize::MAX), None);
    let mut iterator = storage.iter();
    assert_eq!(iterator.len(), 2);
    assert_eq!(iterator.next_back(), Some(0xaabbccdd));
    assert_eq!(iterator.next(), Some(0x01020304));
    assert_eq!(iterator.next(), None);
    assert_eq!(iterator.next_back(), None);
    assert_eq!(clone.storage(), storage.storage());
    drop(bytes);
    drop(storage);
    assert!(weak.upgrade().is_some());
    assert_eq!(clone.word_at(0), Some(0x01020304));
    drop(clone);
    assert!(weak.upgrade().is_none());
}
#[test]
fn shared_range_rejects_partial_or_outside_words_and_accepts_empty_extent() {
    let bytes = Arc::new(vec![0; 8]);
    assert_eq!(
        WordStorage::shared(bytes.clone(), 0..9).unwrap_err(),
        WordStorageError::InvalidRange
    );
    assert_eq!(
        WordStorage::shared(bytes.clone(), 7..3).unwrap_err(),
        WordStorageError::InvalidRange
    );
    assert_eq!(
        WordStorage::shared(bytes.clone(), 1..8).unwrap_err(),
        WordStorageError::PartialWord
    );
    let empty = WordStorage::shared(bytes, 3..3).unwrap();
    assert!(empty.is_empty());
    assert_eq!(empty, WordStorage::default());
    assert_eq!(empty.iter().next(), None);
}
