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

#[test]
fn primary_declaration_cursor_storage_is_charged_once_without_a_cap_increase() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/probe\n    var/first\n    var/second\n".into())
        }
    }
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("probe.dm"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let mapping = frontend.source_export_mapping().unwrap();
    let (_, count, bytes) = mapping.declaration_anchor_storage();
    assert_eq!(bytes, count * std::mem::size_of::<u32>());
    let mut census = HeapCensus::new("primary-declaration-cursor");
    census.source_export_mapping(mapping);
    census.source_export_mapping(mapping);
    let report = census.finish();
    let owner = report
        .owners
        .iter()
        .find(|row| row.owner == "query_snapshot.declaration_anchors")
        .unwrap();
    assert_eq!(owner.unique_known_capacity_bytes, bytes as u64);
    assert_eq!(owner.unique_allocations, 1);
    assert_eq!(owner.observed_items, count as u64);
}
