use super::*;
#[test]
fn cloned_normal_views_charge_one_owner_but_independent_equal_bytes_charge_two() {
    let first = SourceText::from("same ordinary source");
    let shared = first.clone();
    let mut owners = Owners::default();
    owners.text(&first).unwrap();
    let once = owners.totals();
    owners.text(&shared).unwrap();
    assert_eq!(owners.totals(), once);
    let independent = SourceText::from("same ordinary source");
    assert!(!first.same_view(&independent));
    owners.text(&independent).unwrap();
    assert_eq!(owners.totals().payload_capacity, once.payload_capacity * 2);
    assert_eq!(owners.totals().text_backings, 2);
}
#[test]
fn separate_view_wrappers_over_one_arc_charge_each_record_but_payload_once() {
    let payload: Arc<str> = Arc::from("shared payload behind independent SourceText wrappers");
    let a = SourceText::from(Arc::clone(&payload));
    let b = SourceText::from(payload);
    assert!(!a.same_view(&b));
    let mut owners = Owners::default();
    owners.text(&a).unwrap();
    let once = owners.totals();
    owners.text(&b).unwrap();
    assert_eq!(owners.totals().payload_capacity, once.payload_capacity);
    assert!(owners.totals().owner_records > once.owner_records);
    assert_eq!(owners.totals().text_backings, 2);
    assert_eq!(owners.totals().text_payloads, 1);
}
#[test]
fn subranges_charge_the_retained_full_arena_and_memo_once() {
    let source = SourceText::from(String::with_capacity(4096) + "prefix source suffix");
    let view = source.checked_view(7..13).unwrap();
    let mut owners = Owners::default();
    source.span_fingerprint(0..source.len()).unwrap();
    owners.text(&view).unwrap();
    let once = owners.totals();
    owners.text(&source).unwrap();
    assert_eq!(owners.totals(), once);
    assert!(once.payload_capacity >= 4096);
    assert!(once.memo_capacity > 0);
}
#[test]
fn exceptional_bom_and_invalid_utf8_decode_views_are_distinct_and_raw_bytes_count_once() {
    for raw in [
        b"\xef\xbb\xbf/datum/test\n".as_slice(),
        b"/datum/test\n// bad \xff\n".as_slice(),
    ] {
        let original = SharedBytes::from(raw);
        let decoded = SourceText::from(dm_preprocess::decode_source_bytes(raw));
        let analyze = SourceText::from(
            String::from_utf8_lossy(raw)
                .replace("\r\n", "\n")
                .replace('\r', "\n"),
        );
        let mut owners = Owners::default();
        owners.text(&decoded).unwrap();
        owners.text(&analyze).unwrap();
        assert_eq!(owners.totals().text_backings, 2);
        let texts = owners.totals().payload_capacity;
        owners.bytes(&original).unwrap();
        let once = owners.totals();
        assert_eq!(once.payload_capacity, texts + original.capacity());
        owners.bytes(&original.clone()).unwrap();
        assert_eq!(owners.totals(), once);
    }
}
#[test]
fn owner_accounting_never_retains_an_arena_and_equal_config_bytes_are_not_aliases() {
    let text = SourceText::from("temporary source");
    let weak = text.downgrade();
    let mut owners = Owners::default();
    owners.text(&text).unwrap();
    drop(text);
    assert!(weak.upgrade().is_none());
    let a = SharedBytes::from(b"config".as_slice());
    let b = SharedBytes::from(b"config".as_slice());
    owners.bytes(&a).unwrap();
    owners.bytes(&b).unwrap();
    assert_eq!(owners.totals().byte_backings, 2);
}

#[test]
fn memo_growth_is_charged_by_stable_backing_not_reallocated_vector_address() {
    let source = SourceText::from("long enough source for many distinct byte ranges");
    let mut owners = Owners::default();
    source.span_fingerprint(0..1).unwrap();
    owners.text(&source).unwrap();
    let first = owners.totals();
    for end in 2..source.len() {
        source.span_fingerprint(0..end).unwrap();
    }
    owners.text(&source).unwrap();
    let grown = owners.totals();
    assert_eq!(grown.payload_capacity, first.payload_capacity);
    assert_eq!(grown.text_backings, 1);
    assert!(grown.memo_capacity > first.memo_capacity);
    owners.text(&source).unwrap();
    assert_eq!(owners.totals(), grown);
}
