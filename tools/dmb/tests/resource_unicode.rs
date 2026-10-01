use byond_dmb::{
    dmb::Dmb,
    opendream::OpenDreamProgram,
    rsc::{self, Entry},
    translate::translate,
};

#[test]
fn native_utf8_resource_filenames_and_payloads_match_translation() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures/translation/unicode_resources");
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/unicode_resources/probe.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/unicode_resources/native.bin"
    ))
    .unwrap();
    let bytes = include_bytes!("../fixtures/translation/unicode_resources/native.rsc.bin");
    let archive = rsc::read_all(&mut bytes.as_slice()).unwrap();
    let output = translate(&input, &baseline, &template, &root).unwrap();
    let signatures = |entries: &[Entry]| {
        let mut values: Vec<_> = entries
            .iter()
            .map(|entry| {
                let Entry::Named(named) = entry else {
                    panic!("unexpected opaque resource")
                };
                (
                    named.name.clone(),
                    named.kind,
                    named.id,
                    named.declared_size,
                    named.asset_bytes().unwrap().to_vec(),
                )
            })
            .collect();
        values.sort();
        values
    };
    let expected = signatures(&archive);
    assert_eq!(expected.len(), 3);
    let mut names: Vec<_> = ["café.txt", "δείγμα.txt", "资源.txt"]
        .into_iter()
        .map(|s| s.as_bytes().to_vec())
        .collect();
    names.sort();
    assert_eq!(
        expected.iter().map(|v| v.0.clone()).collect::<Vec<_>>(),
        names
    );
    assert_eq!(signatures(&output.resources), expected);
    let mut native_refs: Vec<_> = native.resources.iter().map(|r| (r.kind, r.id)).collect();
    let mut actual_refs: Vec<_> = output
        .dmb
        .resources
        .iter()
        .map(|r| (r.kind, r.id))
        .collect();
    native_refs.sort();
    actual_refs.sort();
    assert_eq!(actual_refs, native_refs);
    let mut roundtrip = Vec::new();
    rsc::write_all(&mut roundtrip, &archive).unwrap();
    assert_eq!(roundtrip, bytes);
}
