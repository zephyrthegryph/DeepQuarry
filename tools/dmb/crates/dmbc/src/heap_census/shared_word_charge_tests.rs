use super::*;
use dm_ir::{ByteOwnerStorage, ImmutableByteOwner, SymbolicCode, WordStorage};
struct Unknown(Vec<u8>);
impl ImmutableByteOwner for Unknown {
    fn bytes(&self) -> &[u8] {
        &self.0
    }
    fn storage(&self) -> ByteOwnerStorage {
        ByteOwnerStorage {
            address: self.0.as_ptr() as usize,
            bytes: self.0.capacity(),
            memory_mapped: false,
        }
    }
}
#[test]
fn shared_heap_word_owners_require_complete_nested_storage() {
    let known = WordStorage::shared(Arc::new(vec![0u8; 4]), 0..4).unwrap();
    let known = Arc::new(SymbolicCode::from_word_storage(known, vec![]).unwrap());
    let mut charge = HeapCensus::compact_symbolic_charge(1024);
    charge.symbolic_code(&known);
    assert!(charge.finish_compact_symbolic_charge().is_some());
    let unknown = WordStorage::shared(Arc::new(Unknown(vec![0; 4])), 0..4).unwrap();
    let unknown = Arc::new(SymbolicCode::from_word_storage(unknown, vec![]).unwrap());
    let mut charge = HeapCensus::compact_symbolic_charge(1024);
    charge.symbolic_code(&unknown);
    assert!(charge.finish_compact_symbolic_charge().is_none());
}
#[test]
fn file_backed_extent_never_enters_heap_retention_budget() {
    let mut charge = HeapCensus::compact_symbolic_charge(1024);
    charge.file_backed("mapped", 123, 1024 * 1024 * 1024);
    charge.file_backed("mapped_again", 123, 1024 * 1024 * 1024);
    assert_eq!(charge.finish_compact_symbolic_charge(), Some(0));
    let mut report = HeapCensus::new("mapping-accounting");
    report.file_backed("mapped", 123, 1024 * 1024 * 1024);
    report.file_backed("mapped_again", 123, 1024 * 1024 * 1024);
    let report = report.finish();
    assert_eq!(report.unique_file_backed_bytes, 1024 * 1024 * 1024);
    assert_eq!(report.unique_known_capacity_bytes, 0);
}
