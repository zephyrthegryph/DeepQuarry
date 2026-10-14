use super::*;
#[test]
fn shared_arc_payload_is_counted_once_across_owners() {
    let text: Arc<str> = Arc::from("payload");
    let alias = Arc::clone(&text);
    let mut census = HeapCensus::new("test");
    census.arc_text("source", &text);
    census.arc_text("expanded", &alias);
    let report = census.finish();
    assert_eq!(report.unique_known_capacity_bytes, 7);
    assert_eq!(
        report
            .owners
            .iter()
            .find(|owner| owner.owner == "expanded")
            .unwrap()
            .shared_encounters,
        1
    );
}
#[test]
fn vector_descriptors_and_nested_strings_are_distinct_allocations() {
    let mut values = Vec::with_capacity(4);
    let mut string = String::with_capacity(32);
    string.push_str("abc");
    values.push(string);
    let mut census = HeapCensus::new("test");
    census.strings("strings", &values);
    census.strings("alias", &values);
    let report = census.finish();
    assert_eq!(
        report.unique_known_capacity_bytes,
        (values.capacity() * size_of::<String>() + values[0].capacity()) as u64
    );
    assert_eq!(
        report
            .owners
            .iter()
            .map(|owner| owner.unique_allocations)
            .sum::<u64>(),
        2
    );
}
#[test]
fn inaccessible_slice_capacity_and_unknown_owners_are_explicit() {
    let values = vec![1_u32, 2, 3];
    let mut census = HeapCensus::new("test");
    census.slice("private_vec", &values, false);
    census.unknown("indexes", "private HashMap buckets");
    let report = census.finish();
    let bytes = serde_json::to_vec(&report).unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        parsed["scope"],
        "retained_accessible_container_payload_and_capacity_not_total_heap"
    );
    assert!(!report
        .owners
        .iter()
        .find(|owner| owner.owner == "private_vec")
        .unwrap()
        .unknown
        .is_empty());
    assert_eq!(report.unique_known_capacity_bytes, 0);
    assert_eq!(report.unknown_capacity_payload_bytes, 12);
}
