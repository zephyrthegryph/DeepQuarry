use byond_dmb::{
    compare::{compare_dmbs, CompareOptions},
    dmb::Dmb,
    opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn native_name_and_raw_display_text_defaults() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let f = root.join("fixtures/translation/name_text_defaults");
    let input = OpenDreamProgram::from_path(f.join("probe.json")).unwrap();
    let base =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native = Dmb::from_bytes(&std::fs::read(f.join("probe.native.bin")).unwrap()).unwrap();
    let paths: Vec<_> = std::fs::read_to_string(f.join("probe.dm"))
        .unwrap()
        .lines()
        .filter(|s| s.starts_with('/'))
        .map(str::to_owned)
        .collect();
    assert_eq!(paths.len(), 28);
    let find = |d: &Dmb, p: &str| {
        d.classes
            .iter()
            .find(|c| d.string(c.initial_ids[0]) == Some(p.as_bytes()))
            .unwrap()
            .clone()
    };
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &base, &template, &f, Some("probe"), debug).unwrap();
        for p in &paths {
            let a = find(&native, p);
            let b = find(&actual.dmb, p);
            assert_eq!(
                native.string(a.initial_ids[2]),
                actual.dmb.string(b.initial_ids[2]),
                "name {p} debug={debug}"
            );
            assert_eq!(
                native.string(a.text),
                actual.dmb.string(b.text),
                "text {p} debug={debug}"
            );
        }
        let differences = compare_dmbs(
            &native,
            &actual.dmb,
            &CompareOptions {
                authored_prefixes: vec!["/datum/named".into()],
                compare_bytecode: false,
                max_discrepancies: 1000,
            },
        );
        let defaults: Vec<_> = differences
            .iter()
            .filter(|d| {
                matches!(
                    d.field.as_str(),
                    "class.default.name" | "class.default.text"
                )
            })
            .collect();
        assert!(
            defaults.is_empty(),
            "ordinary datum defaults debug={debug}: {defaults:?}"
        );
    }
    let unicode = find(&native, "/obj/unicode");
    assert_eq!(native.string(unicode.text), Some([0xc3].as_slice()));
    let proper = find(&native, "/obj/named");
    assert_eq!(native.string(proper.text), Some(b"A".as_slice()));
}

#[test]
fn null_atom_name_reset_preserves_string_ids_above_u16() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let f = root.join("fixtures/translation/inherited_builtin_appearance");
    let base =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native = Dmb::from_bytes(&std::fs::read(f.join("probe.native.bin")).unwrap()).unwrap();
    for debug in [false, true] {
        let mut input = OpenDreamProgram::from_path(f.join("probe.json")).unwrap();
        input
            .strings
            .extend((0..65_540).map(|i| format!("null_reset_wide_padding_{i}")));
        let actual =
            translate_named_debug(&input, &base, &template, &f, Some("probe"), debug).unwrap();
        for path in [
            "/obj/appearance_base/null_name",
            "/obj/appearance_base/null_name/child",
        ] {
            let n = native
                .classes
                .iter()
                .find(|c| native.string(c.path_string_id()) == Some(path.as_bytes()))
                .unwrap();
            let a = actual
                .dmb
                .classes
                .iter()
                .find(|c| actual.dmb.string(c.path_string_id()) == Some(path.as_bytes()))
                .unwrap();
            assert!(
                a.name_string_id() > u16::MAX as u32,
                "fixture must exercise a wide name ID"
            );
            assert_eq!(
                native.string(n.name_string_id()),
                actual.dmb.string(a.name_string_id()),
                "{path} debug={debug}"
            );
            assert_eq!(
                native.string(n.text),
                actual.dmb.string(a.text),
                "{path} debug={debug}"
            );
        }
    }
}
