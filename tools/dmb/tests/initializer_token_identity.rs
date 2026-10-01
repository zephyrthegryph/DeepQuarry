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
fn hidden_initializer_defaults_preserve_native_identity_partitions() {
    check_default_tokens("probe");
}

fn check_default_tokens(stem: &str) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/initializer_token_identity");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join(format!("{stem}.json"))).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{stem}.native.bin"))).unwrap())
            .unwrap();
    let expected = marker_defaults(&native);
    assert_eq!(
        expected.len(),
        22,
        "all native list/new/sound/matrix declaration, override, global and static defaults"
    );
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &fixtures, Some(stem), debug)
                .unwrap();
        let actual = marker_defaults(&output.dmb);
        assert_eq!(
            expected.keys().collect::<Vec<_>>(),
            actual.keys().collect::<Vec<_>>(),
            "debug={debug}: missing kind62 identity defaults"
        );
        for (left, left_token) in &expected {
            for (right, right_token) in &expected {
                assert_eq!(
                    left_token == right_token,
                    actual[left] == actual[right],
                    "debug={debug}: native Initial equality partition {left} vs {right}"
                );
            }
        }
    }
}

#[test]
fn folded_constructor_keys_preserve_native_identity_partitions() {
    check_all_tokens("folding", &["/obj/fold"], 14);
}

#[test]
fn repeated_initializers_keep_each_native_token_before_clear() {
    check_all_tokens("cleared", &["/obj/token_clear"], 6);
}

#[test]
fn additional_constructor_families_preserve_native_identity_partitions() {
    check_all_tokens(
        "families",
        &["/obj/token_families", "/particles/token_families"],
        13,
    );
}

fn check_all_tokens(stem: &str, prefixes: &[&str], count: usize) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/initializer_token_identity");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join(format!("{stem}.json"))).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{stem}.native.bin"))).unwrap())
            .unwrap();
    let tokens = |dmb: &Dmb| {
        let mut result = BTreeMap::new();
        for (id, class) in dmb.classes.iter().enumerate() {
            let path =
                String::from_utf8_lossy(dmb.string(class.path_string_id()).unwrap_or_default());
            if !prefixes.iter().any(|prefix| path.starts_with(prefix)) {
                continue;
            }
            for (var, _) in dmb.class_variable_declarations(id).unwrap_or_default() {
                let v = &dmb.variables[var as usize];
                if v.kind == 62 {
                    result.insert(
                        format!(
                            "{path}|decl|{}",
                            String::from_utf8_lossy(dmb.string(v.name).unwrap())
                        ),
                        v.value,
                    );
                }
            }
            let mut occurrences = BTreeMap::<Vec<u8>, usize>::new();
            for value in dmb.class_initial_values(id).unwrap_or_default() {
                if value.value.tag() != 62 {
                    continue;
                }
                let name = dmb
                    .string(dmb.variables[value.variable_id as usize].name)
                    .unwrap();
                let occurrence = occurrences.entry(name.to_vec()).or_default();
                result.insert(
                    format!("{path}|init|{}|{occurrence}", String::from_utf8_lossy(name)),
                    value.value.id(),
                );
                *occurrence += 1;
            }
        }
        result
    };
    let expected = tokens(&native);
    assert_eq!(expected.len(), count, "native {stem} marker coverage");
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &fixtures, Some(stem), debug)
                .unwrap();
        let actual = tokens(&output.dmb);
        assert_eq!(
            expected.keys().collect::<Vec<_>>(),
            actual.keys().collect::<Vec<_>>(),
            "{stem} debug={debug}: all marker records"
        );
        for (left, a) in &expected {
            for (right, b) in &expected {
                assert_eq!(
                    a == b,
                    actual[left] == actual[right],
                    "{stem} debug={debug}: {left} vs {right}"
                );
            }
        }
    }
}
