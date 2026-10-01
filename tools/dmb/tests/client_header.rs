use byond_dmb::{
    dmb::Dmb,
    od_emit::emit_with_baseline,
    opendream::OpenDreamProgram,
    rsc::{self, Entry},
};

fn root() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures/translation/client_header_probe")
}
fn pair(name: &str) -> (OpenDreamProgram, Dmb) {
    let root = root();
    (
        OpenDreamProgram::from_path(root.join(format!("{name}.json"))).unwrap(),
        Dmb::from_bytes(&std::fs::read(root.join(format!("{name}.native.bin"))).unwrap()).unwrap(),
    )
}
fn files(dmb: &Dmb) -> Vec<(u8, u32)> {
    dmb.world
        .client_script_files
        .iter()
        .map(|&id| {
            let r = &dmb.resources[id as usize];
            (r.kind, r.id)
        })
        .collect()
}
fn script(dmb: &Dmb) -> Option<Vec<u8>> {
    dmb.string(dmb.world.client_script).map(Vec::from)
}

#[test]
fn all_native_preload_modes_replace_both_header_bits() {
    for base_name in ["preload0", "preload1", "preload2"] {
        let (baseline, template) = pair(base_name);
        for name in ["preload0", "preload1", "preload2"] {
            let (input, native) = pair(name);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(
                output.dmb.header.flags & 0x1800,
                native.header.flags & 0x1800,
                "{base_name} -> {name}"
            );
            assert_eq!(output.dmb.world.unknown_byte, 0);
        }
    }
}

#[test]
fn native_inline_file_and_include_scripts_match_across_source_transitions() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let cases = [
        "script_none",
        "script_inline",
        "script_file",
        "include_only",
        "include_inline",
        "include_file",
        "include_duplicate",
        "include_nested",
    ];
    for names in [cases.to_vec(), cases.iter().rev().copied().collect()] {
        for name in names {
            let (input, native) = pair(name);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(script(&output.dmb), script(&native), "script text {name}");
            assert_eq!(files(&output.dmb), files(&native), "script files {name}");
            assert_eq!(output.dmb.world.unknown_byte, 0);
            output.dmb.validate_references().unwrap();
            let native_archive =
                std::fs::read(root().join(format!("{name}.native.rsc.bin"))).unwrap();
            let native_archive = rsc::read_all(&mut native_archive.as_slice()).unwrap();
            for &id in &output.dmb.world.client_script_files {
                let reference = &output.dmb.resources[id as usize];
                let native_asset = native_archive
                    .iter()
                    .find_map(|entry| match entry {
                        Entry::Named(asset)
                            if asset.id == reference.id && asset.kind == reference.kind =>
                        {
                            Some(asset)
                        }
                        _ => None,
                    })
                    .unwrap();
                let actual_asset = output
                    .resources
                    .iter()
                    .find_map(|entry| match entry {
                        Entry::Named(asset)
                            if asset.id == reference.id && asset.kind == reference.kind =>
                        {
                            Some(asset)
                        }
                        _ => None,
                    })
                    .unwrap();
                assert_eq!(
                    actual_asset.asset_bytes().unwrap(),
                    native_asset.asset_bytes().unwrap()
                );
                assert_eq!(actual_asset.name, native_asset.name);
            }
        }
    }
    let (_, prefix) = pair("script_file");
    assert_eq!(prefix.world.client_script_files, vec![1]);
    assert_ne!(prefix.string(1), Some(b"example.dms".as_slice()));
    let (_, included) = pair("include_file");
    assert_eq!(included.world.client_script_files.len(), 3);
    assert_eq!(
        included.world.client_script_files[0],
        included.world.client_script_files[2]
    );
}

#[test]
fn script_file_vector_requires_real_resource_ids_including_wide_ids() {
    let (_, mut native) = pair("script_file");
    native.validate_references().unwrap();
    native.world.client_script_files[0] = native.resources.len() as u32;
    assert!(native.validate_references().is_err());
    native.world.client_script_files[0] = 0xffff;
    assert!(native.validate_references().is_err());
    native
        .resources
        .resize(0x10000, native.resources[0].clone());
    native.validate_references().unwrap();
}

#[test]
fn inline_client_script_preserves_utf8_and_does_not_use_unknown_byte() {
    let (input, native) = pair("script_unicode");
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
    assert_eq!(script(&output.dmb), script(&native));
    assert_eq!(
        native.string(native.world.client_script),
        Some("macro/ALT+I return \"say café 资源\"".as_bytes())
    );
    assert_eq!(native.world.unknown_byte, 0);
    assert_eq!(output.dmb.world.unknown_byte, 0);
}

#[test]
fn all_native_perspective_modes_replace_the_header_bit() {
    for base_name in [
        "perspective0",
        "perspective1",
        "perspective2",
        "perspective3",
    ] {
        let (baseline, template) = pair(base_name);
        for name in [
            "perspective0",
            "perspective1",
            "perspective2",
            "perspective3",
        ] {
            let (input, native) = pair(name);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(
                output.dmb.header.flags & 0x0800_0000,
                native.header.flags & 0x0800_0000,
                "{base_name} -> {name}"
            );
            assert_eq!(output.dmb.world.unknown_byte, native.world.unknown_byte);
            output.dmb.validate_references().unwrap();
        }
    }
}

#[test]
fn native_callback_presence_flags_require_atom_or_client_owners() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for name in [
        "handler_Click",
        "handler_DblClick",
        "handler_MouseDown",
        "handler_MouseUp",
        "handler_MouseDrag",
        "handler_MouseDrop",
        "handler_MouseEntered",
        "handler_MouseExited",
        "handler_MouseMove",
        "handler_MouseWheel",
        "handler_Command",
        "handler_IsByondMember",
        "handler_obj_test_MouseEntered",
        "handler_obj_test_MouseExited",
        "handler_obj_test_MouseMove",
        "handler_obj_test_MouseWheel",
        "handler_client_test_MouseEntered",
        "handler_client_test_MouseExited",
        "handler_client_test_MouseMove",
        "handler_client_test_MouseWheel",
        "handler_atom",
        "handler_unrelated",
    ] {
        let (input, native) = pair(name);
        let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
        assert_eq!(
            output.dmb.header.flags & !0x4000_0000,
            native.header.flags,
            "{name}"
        );
        assert_eq!(
            output.dmb.header.extended_flags, native.header.extended_flags,
            "{name}"
        );
        output.dmb.validate_references().unwrap();
    }
}

#[test]
fn native_boolean_client_and_world_settings_replace_header_bits() {
    for (name, mask) in [
        ("authenticate", 0x8000),
        ("show_map", 0x0010_0000),
        ("show_popup_menus", 0x1000_0000),
        ("macro_mode", 0x80),
        ("sleep_offline", 0x20),
        ("lazy_eye", 0x100),
    ] {
        for base in [0, 1] {
            let (baseline, template) = pair(&format!("{name}{base}"));
            for target in [0, 1] {
                let (input, native) = pair(&format!("{name}{target}"));
                let output =
                    emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
                assert_eq!(
                    output.dmb.header.flags & mask,
                    native.header.flags & mask,
                    "{name}{base} -> {target}"
                );
            }
        }
    }
}

#[test]
fn native_instruction_features_distinguish_object_calls_from_library_calls() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for name in [
        "feature_dynamic_call",
        "feature_library_call",
        "feature_library_arglist",
        "feature_resource_call",
        "feature_numeric_call",
        "feature_concat_call",
        "feature_const_call",
        "feature_parenthesized_call",
        "feature_local_const_call",
        "feature_load_ext",
        "feature_call_ext",
        "feature_filter",
    ] {
        let (input, native) = pair(name);
        let output =
            byond_dmb::translate::translate(&input, &baseline, &template, &root()).unwrap();
        assert_eq!(
            output.dmb.header.flags & 0x2000_0040,
            native.header.flags & 0x2000_0040,
            "{name}"
        );
        let call_opcodes = |dmb: &Dmb| {
            (0..dmb.procs.len())
                .filter_map(|id| dmb.proc_code_words(id))
                .flat_map(|words| byond_dmb::bytecode::decode(words).unwrap())
                .filter(|inst| {
                    matches!(
                        inst.opcode,
                        0xb5 | 0xcc | 0x116 | 0x117 | 0x179 | 0x17a | 0x17b
                    )
                })
                .map(|inst| inst.opcode)
                .collect::<Vec<_>>()
        };
        assert_eq!(
            call_opcodes(&output.dmb),
            call_opcodes(&native),
            "{name}: call ABI"
        );
        let differences = byond_dmb::compare::compare_dmbs(
            &native,
            &output.dmb,
            &byond_dmb::compare::CompareOptions::default(),
        );
        assert!(
            differences
                .iter()
                .all(|diff| !diff.field.starts_with("header.")),
            "{name}: {differences:?}"
        );
    }
}

#[test]
fn header_comparison_ignores_wire_and_unknown_bits_but_detects_proven_settings() {
    let (_, native) = pair("preload1");
    let options = byond_dmb::compare::CompareOptions::default();
    let mut actual = native.clone();
    actual.header.flags ^= 0x4002_0010;
    let differences = byond_dmb::compare::compare_dmbs(&native, &actual, &options);
    assert!(differences
        .iter()
        .all(|diff| !diff.field.starts_with("header.")));
    actual.header.flags ^= 0x0800_0000;
    let differences = byond_dmb::compare::compare_dmbs(&native, &actual, &options);
    assert!(differences
        .iter()
        .any(|diff| diff.field == "header.semantic_flags"));
    actual.header.extended_flags = Some(2);
    let differences = byond_dmb::compare::compare_dmbs(&native, &actual, &options);
    assert!(differences
        .iter()
        .any(|diff| diff.field == "header.semantic_extended_flags"));
}

#[test]
fn native_graphics_access_metadata_tracks_resolved_builtin_mentions() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let directory = root().parent().unwrap().join("graphics_access");
    for name in [
        "obj",
        "mob",
        "turf",
        "area",
        "atom",
        "image",
        "mutable_appearance",
        "datum_custom",
        "untyped",
        "typed_arg",
        "derived",
        "false_alias",
        "declaration_only",
        "nameof_icon",
        "unused_branch",
        "global_custom",
    ] {
        let input = OpenDreamProgram::from_path(directory.join(format!("{name}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(directory.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        assert_eq!(
            input.native_graphics_access,
            native.header.flags & 0x40 == 0,
            "{name}: metadata"
        );
        let output =
            byond_dmb::translate::translate(&input, &baseline, &template, &directory).unwrap();
        assert_eq!(
            output.dmb.header.flags & 0x40,
            native.header.flags & 0x40,
            "{name}: translated flag"
        );
    }
}

#[test]
fn native_lazy_eye_accepts_signed_fractional_and_large_numeric_values() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for name in ["lazy_eye_two", "lazy_eye_negative", "lazy_eye_fraction"] {
        let (input, native) = pair(name);
        let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
        assert_eq!(
            output.dmb.header.flags & 0x100,
            native.header.flags & 0x100,
            "{name}"
        );
        assert_eq!(
            output.dmb.world.eye, native.world.eye,
            "{name}: lazy_eye byte"
        );
        let differences = byond_dmb::compare::compare_dmbs(
            &native,
            &output.dmb,
            &byond_dmb::compare::CompareOptions::default(),
        );
        assert!(
            differences
                .iter()
                .all(|diff| !diff.field.starts_with("header.")
                    && !diff.field.contains("declaration.lazy_eye")
                    && !diff.field.contains("initial.lazy_eye")),
            "{name}: {differences:?}"
        );
    }
}

#[test]
fn native_cpu_access_metadata_preserves_expression_use_distinctions() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let directory = root().parent().unwrap().join("cpu_access");
    for name in [
        "dead",
        "discard_computed",
        "discard_initial",
        "discard_sum",
        "issaved",
        "nameof",
        "return_computed",
        "return_dynamic",
        "discard",
        "discard_dynamic",
        "local_cpu",
        "obj_cpu",
        "world_cpu_string",
        "world_cpu_arg",
        "world_cpu_safe",
        "world_cpu",
    ] {
        let input = OpenDreamProgram::from_path(directory.join(format!("{name}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(directory.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        assert_eq!(
            input.native_cpu_access,
            native.header.flags & 1 != 0,
            "{name}: metadata"
        );
        let output =
            byond_dmb::translate::translate(&input, &baseline, &template, &directory).unwrap();
        assert_eq!(
            output.dmb.header.flags & 1,
            native.header.flags & 1,
            "{name}: translated flag"
        );
    }
}

#[test]
fn native_world_view_restores_implicit_default_on_override_removal() {
    for base in ["view_default", "view_explicit_default", "view_changed"] {
        let (baseline, template) = pair(base);
        for name in ["view_default", "view_explicit_default", "view_changed"] {
            let (input, native) = pair(name);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(
                output.dmb.header.flags & 0x200,
                native.header.flags & 0x200,
                "{base} -> {name}"
            );
            assert_eq!(
                output.dmb.world.view_dimensions, native.world.view_dimensions,
                "{base} -> {name}"
            );
        }
    }
}

#[test]
fn legacy_implicit_null_client_settings_use_native_defaults_but_authored_null_is_invalid() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let (mut input, _) = pair("preload1");
    input.native_client_settings.clear();
    let client = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/client")
        .unwrap();
    for name in ["show_map", "macro_mode"] {
        client
            .variables
            .insert(name.into(), serde_json::Value::Null);
        client.explicit_type_fields.remove(name);
    }
    let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
    assert_eq!(output.dmb.header.flags & 0x0010_0080, 0);
    for name in ["show_map", "macro_mode"] {
        let (mut authored, _) = pair("preload1");
        authored.native_client_settings.clear();
        authored
            .types
            .iter_mut()
            .find(|typ| typ.path == "/client")
            .unwrap()
            .variables
            .insert(name.into(), serde_json::Value::Null);
        authored
            .types
            .iter_mut()
            .find(|typ| typ.path == "/client")
            .unwrap()
            .explicit_type_fields
            .insert(name.into());
        let error = emit_with_baseline(&authored, Some(&baseline), &template, &root())
            .err()
            .unwrap();
        assert!(error
            .to_string()
            .contains(&format!("client.{name} must be 0 or 1")));
    }
}

#[test]
fn native_client_subtype_settings_follow_native_class_postorder() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for name in [
        "subtype_show_map",
        "subtype_macro_mode",
        "subtype_lazy_eye",
        "subtype_preload_rsc",
        "subtype_perspective",
        "subtype_authenticate",
        "subtype_show_popup_menus",
        "subtype_show_verb_panel",
        "subtype_control_freak",
        "subtype_order_a",
        "subtype_order_b",
        "subtype_sibling_a",
        "subtype_sibling_b",
        "subtype_depth",
        "subtype_depthreverse",
        "subtype_reopen",
        "subtype_proc_first",
        "subtype_empty_first",
        "subtype_script_text",
        "subtype_script_file",
    ] {
        let (input, native) = pair(name);
        let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
        assert_eq!(
            output.dmb.header.flags & 0x3bf4_ffef,
            native.header.flags & 0x3bf4_ffef,
            "{name}: flags"
        );
        assert_eq!(output.dmb.world.eye, native.world.eye, "{name}: lazy_eye");
        assert_eq!(
            output.dmb.world.control, native.world.control,
            "{name}: control_freak"
        );
        assert_eq!(script(&output.dmb), script(&native), "{name}: script");
        assert_eq!(
            files(&output.dmb),
            files(&native),
            "{name}: script resources"
        );
        let differences = byond_dmb::compare::compare_dmbs(
            &native,
            &output.dmb,
            &byond_dmb::compare::CompareOptions::default(),
        );
        assert!(
            differences
                .iter()
                .all(|diff| !diff.field.contains("declaration.")
                    && !diff.field.contains("initial.")
                    && !diff.field.contains("builtin_override.")),
            "{name}: class fields {differences:?}"
        );
    }
    for name in [
        "subtype_preload_rsc",
        "subtype_order_a",
        "subtype_sibling_a",
    ] {
        let (baseline, template) = pair(name);
        for target in ["preload0", "preload1", "preload2", "subtype_sibling_b"] {
            let (input, native) = pair(target);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(
                output.dmb.header.flags & 0x1800,
                native.header.flags & 0x1800,
                "{name} -> {target}"
            );
        }
    }
}

#[test]
fn native_text_preload_and_fractional_control_settings_preserve_both_representations() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for name in [
        "preload_text",
        "preload_url",
        "preload_empty_text",
        "preload_fraction",
        "preload_three_halves",
        "control_fraction",
        "control_three_fraction",
        "control_seven",
    ] {
        let (input, native) = pair(name);
        let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
        assert_eq!(
            output.dmb.header.flags & 0x1800,
            native.header.flags & 0x1800,
            "{name}"
        );
        assert_eq!(output.dmb.world.control, native.world.control, "{name}");
        let builtin_preload = |dmb: &Dmb| {
            let class = dmb
                .classes
                .iter()
                .position(|class| dmb.string(class.path_string_id()) == Some(b"/client"))
                .unwrap();
            dmb.class_builtin_overrides(class)
                .unwrap_or_default()
                .into_iter()
                .find(|field| dmb.string(field.name_string_id) == Some(b"preload_rsc"))
                .map(|field| dmb.string(field.value.id()).unwrap().to_vec())
        };
        assert_eq!(
            builtin_preload(&output.dmb),
            builtin_preload(&native),
            "{name}: preload builtin"
        );
    }
    for base in ["preload_text", "preload_url", "preload2"] {
        let (baseline, template) = pair(base);
        for name in [
            "preload_text",
            "preload_url",
            "preload0",
            "preload1",
            "preload2",
        ] {
            let (input, native) = pair(name);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(
                output.dmb.header.flags & 0x1800,
                native.header.flags & 0x1800,
                "{base} -> {name}"
            );
            let differences = byond_dmb::compare::compare_dmbs(
                &native,
                &output.dmb,
                &byond_dmb::compare::CompareOptions::default(),
            );
            assert!(
                differences
                    .iter()
                    .all(|diff| !diff.field.contains("preload_rsc")),
                "{base} -> {name}: {differences:?}"
            );
        }
    }
    for value in [
        serde_json::json!(-1),
        serde_json::json!(7.5),
        serde_json::json!(8),
        serde_json::Value::Null,
        serde_json::json!("text"),
    ] {
        let (mut invalid, _) = pair("control_seven");
        let client = invalid
            .types
            .iter_mut()
            .find(|typ| typ.path == "/client")
            .unwrap();
        client
            .native_client_settings
            .insert("control_freak".into(), value.clone());
        client.variables.insert("control_freak".into(), value);
        assert!(emit_with_baseline(&invalid, Some(&baseline), &template, &root()).is_err());
    }
}

#[test]
fn native_perspective_fractions_and_float_boolean_constants_preserve_numeric_contracts() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let perspective = |dmb: &Dmb| {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/client"))
            .unwrap();
        dmb.class_builtin_overrides(class)
            .unwrap_or_default()
            .into_iter()
            .find(|field| dmb.string(field.name_string_id) == Some(b"perspective"))
            .and_then(|field| field.value.number_bits())
    };
    for name in [
        "perspective_fraction_0p5",
        "perspective_fraction_1p5",
        "perspective_fraction_2p5",
    ] {
        let (input, native) = pair(name);
        let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
        assert_eq!(
            output.dmb.header.flags & 0x0800_0000,
            native.header.flags & 0x0800_0000,
            "{name}"
        );
        assert_eq!(
            perspective(&output.dmb),
            perspective(&native),
            "{name}: authored numeric value"
        );
        let (baseline, template) = pair(name);
        for target in [
            "perspective0",
            "perspective1",
            "perspective2",
            "perspective3",
        ] {
            let (input, native) = pair(target);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(
                output.dmb.header.flags & 0x0800_0000,
                native.header.flags & 0x0800_0000,
                "{name} -> {target}"
            );
            assert_eq!(
                perspective(&output.dmb),
                perspective(&native),
                "{name} -> {target}: value"
            );
        }
    }
    for (name, mask) in [
        ("show_verb_panel", 0x400),
        ("authenticate", 0x8000),
        ("show_popup_menus", 0x1000_0000),
        ("show_map", 0x0010_0000),
        ("macro_mode", 0x80),
    ] {
        let (mut input, native) = pair(&format!("{name}1"));
        let client = input
            .types
            .iter_mut()
            .find(|typ| typ.path == "/client")
            .unwrap();
        client
            .native_client_settings
            .insert(name.into(), serde_json::json!(1.0));
        client.variables.insert(name.into(), serde_json::json!(1.0));
        let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
        assert_eq!(
            output.dmb.header.flags & mask,
            native.header.flags & mask,
            "{name}: float1.0"
        );
        for value in [
            serde_json::json!(0.5),
            serde_json::json!(1.5),
            serde_json::Value::Null,
        ] {
            let (mut invalid, _) = pair(&format!("{name}1"));
            let client = invalid
                .types
                .iter_mut()
                .find(|typ| typ.path == "/client")
                .unwrap();
            client
                .native_client_settings
                .insert(name.into(), value.clone());
            client.variables.insert(name.into(), value);
            assert!(
                emit_with_baseline(&invalid, Some(&baseline), &template, &root()).is_err(),
                "{name}: invalid fractional/null"
            );
        }
    }
}

#[test]
fn native_client_import_handler_presence_is_typed_and_replaces_baseline_state() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for name in [
        "import_handler_import",
        "import_handler_empty",
        "import_handler_export",
        "import_handler_subtype",
        "import_handler_unrelated",
        "import_handler_parent",
        "import_handler_override",
    ] {
        let (input, native) = pair(name);
        let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
        assert_eq!(
            output.dmb.world.has_client_import_handler(),
            native.world.has_client_import_handler(),
            "{name}"
        );
        assert_eq!(
            output.dmb.world.unknown_byte, native.world.unknown_byte,
            "{name}: canonical byte"
        );
        let reparsed = Dmb::from_bytes(&output.dmb.to_bytes().unwrap()).unwrap();
        assert_eq!(
            reparsed.world.has_client_import_handler(),
            native.world.has_client_import_handler()
        );
    }
    for base in [
        "import_handler_import",
        "import_handler_empty",
        "import_handler_subtype",
        "import_handler_unrelated",
    ] {
        let (baseline, template) = pair(base);
        for name in [
            "import_handler_import",
            "import_handler_empty",
            "import_handler_subtype",
            "import_handler_unrelated",
            "import_handler_export",
        ] {
            let (input, native) = pair(name);
            let output = emit_with_baseline(&input, Some(&baseline), &template, &root()).unwrap();
            assert_eq!(
                output.dmb.world.unknown_byte, native.world.unknown_byte,
                "{base} -> {name}"
            );
        }
    }
    let (_, native) = pair("import_handler_import");
    let mut changed = native.clone();
    changed.world.set_client_import_handler(false);
    let differences = byond_dmb::compare::compare_dmbs(
        &native,
        &changed,
        &byond_dmb::compare::CompareOptions::default(),
    );
    assert!(differences
        .iter()
        .any(|diff| diff.field == "client_import_handler"));
}
