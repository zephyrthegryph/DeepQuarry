use byond_dmb::dmb::{Dmb, WordLists};
use std::sync::Arc;

#[test]
fn sharing_preserves_original_during_mutation() {
    let words = Arc::new(vec![7, 9]);
    let mut lists = WordLists::default();
    lists.push_shared(Arc::clone(&words));
    let snapshot = lists.clone();
    assert!(Arc::ptr_eq(lists.shared(0).unwrap(), &words));
    lists[0][0] = 11;
    assert_eq!(words.as_slice(), &[7, 9]);
    assert_eq!(snapshot[0], vec![7, 9]);
    assert_eq!(lists[0], vec![11, 9]);
    assert!(!Arc::ptr_eq(lists.shared(0).unwrap(), &words));
}

#[test]
fn shared_list_owners_preserve_serial_parallel_bytes_and_detach_mutations() {
    use std::sync::Arc;
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let words = Arc::new(vec![0, 7, 65535]);
    let index = dmb.lists.len();
    dmb.lists.push_shared(Arc::clone(&words));
    let bytes = dmb.to_bytes().unwrap();
    let clone = dmb.clone();
    assert!(Arc::ptr_eq(clone.lists.shared(index).unwrap(), &words));
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    assert_eq!(bytes, dmb.to_bytes_on_executor(&executor).unwrap());
    let decoded = Dmb::from_bytes(&bytes).unwrap();
    assert_eq!(decoded.lists[index], *words);
    assert_eq!(decoded.to_bytes().unwrap(), bytes);
    dmb.lists[index][1] = 8;
    assert_eq!(clone.lists[index][1], 7);
    assert_eq!(words[1], 7);
}
