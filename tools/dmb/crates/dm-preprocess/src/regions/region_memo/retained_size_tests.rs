use super::*;

#[test]
fn retained_records_charge_owned_capacity_and_duplicate_shared_backings() {
    let definition = Arc::new(Macro {
        parameters: Some(vec![String::with_capacity(117)]),
        replacement: String::with_capacity(211),
        variadic: false,
    });
    let mut value = ExpansionRecord {
        key: 0,
        source: Arc::from("source"),
        control: Arc::from([1u8]),
        text: Arc::from("expanded"),
        reads: Vec::new(),
        locations: Vec::new(),
        lines: Vec::new(),
        diagnostics: Vec::new(),
        fragments: Vec::new(),
    };
    let before = value.retained_size_bytes();
    value.reads.reserve_exact(2);
    let storage = value.reads.capacity() * std::mem::size_of::<MacroRead>();
    assert_eq!(value.retained_size_bytes() - before, storage);
    let read = MacroRead {
        segment: 0,
        name: Arc::from("NAME"),
        definition: Some(definition),
    };
    let backing = slice::<u8>(read.name.len()) + shared_macro(read.definition.as_ref().unwrap());
    value.reads.push(read.clone());
    value.reads.push(read);
    assert_eq!(value.retained_size_bytes() - before, storage + 2 * backing);
    let fragment = FragmentRecord::new(1, "src", Arc::from([1u8, 2, 3])).unwrap();
    assert_eq!(
        fragment.retained_size_bytes(),
        record::<FragmentRecord>() + slice::<u8>(3) + slice::<u8>(3)
    );
}
