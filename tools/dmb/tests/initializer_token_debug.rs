use byond_dmb::{dmb::Dmb, opendream::OpenDreamProgram, translate::translate_named_debug};
use std::{collections::BTreeMap, path::Path};
fn marker_defaults(dmb: &Dmb) -> BTreeMap<String, u32> {
    let mut result = BTreeMap::new();
    for (id, class) in dmb.classes.iter().enumerate() {
        let Some(path) = dmb.string(class.path_string_id()) else {
            continue;
        };
        let path = String::from_utf8_lossy(path);
        if !path.starts_with("/obj/first") && path != "/obj/second" {
            continue;
        }
        if let Some(declarations) = dmb.class_variable_declarations(id) {
            for (var, _) in declarations {
                let v = &dmb.variables[var as usize];
                if v.kind == 62 {
                    let name = String::from_utf8_lossy(dmb.string(v.name).unwrap());
                    result.insert(format!("{path}|{name}"), v.value);
                }
            }
        }
        if let Some(overrides) = dmb.class_initial_values(id) {
            for value in overrides {
                let v = &dmb.variables[value.variable_id as usize];
                let name = String::from_utf8_lossy(dmb.string(v.name).unwrap());
                let key = format!("{path}|{name}");
                if value.value.tag() == 62 {
                    result.insert(key, value.value.id());
                } else {
                    result.remove(&key);
                }
            }
        }
    }
    if let Some(globals) = dmb.lists.get(dmb.variable_footer as usize) {
        for pair in globals.chunks_exact(2) {
            let variable = &dmb.variables[pair[0] as usize];
            let name = dmb.string(variable.name).unwrap();
            if variable.kind == 62 && matches!(name, b"global_one" | b"a" | b"b") {
                result.insert(
                    format!("global|{}", String::from_utf8_lossy(name)),
                    variable.value,
                );
            }
        }
    }
    result
}
#[test]
fn debug_initializer_defaults_preserve_unique_native_identities() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let f = root.join("fixtures/translation/initializer_token_identity");
    let input = OpenDreamProgram::from_path(f.join("debug.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native = Dmb::from_bytes(&std::fs::read(f.join("debug.native.bin")).unwrap()).unwrap();
    let expected = marker_defaults(&native);
    assert_eq!(expected.len(), 22);
    assert_eq!(
        expected
            .values()
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        22
    );
    for debug_lines in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &f, Some("debug"), debug_lines)
                .unwrap();
        let actual = marker_defaults(&output.dmb);
        assert_eq!(
            expected.keys().collect::<Vec<_>>(),
            actual.keys().collect::<Vec<_>>()
        );
        for (ka, va) in &expected {
            for (kb, vb) in &expected {
                assert_eq!(
                    va == vb,
                    actual[ka] == actual[kb],
                    "{ka} vs {kb}, debuglines={debug_lines}"
                );
            }
        }
    }
}
