use super::*;

#[test]
fn common_resource_kinds_match_paired_dream_maker_fixture() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/resource_kinds/resource_kinds.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation/resource_kinds"),
    )
    .unwrap();
    assert_eq!(
        emitted
            .dmb
            .resources
            .iter()
            .map(|r| r.kind)
            .collect::<Vec<_>>(),
        [3, 6, 2, 14, 0, 0, 0, 0, 0]
    );
    assert_eq!(emitted.resources.len(), 9);
}

#[test]
fn generated_icon_names_and_skin_only_assets_match_native_archive() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    input.resources = vec![
        "icons/gen/icons/test.dmi".into(),
        "icons/gen/icons/copy.dmi".into(),
        "interface/test.dmf".into(),
    ];
    input.interface = Some("interface/test.dmf".into());
    let root = std::env::temp_dir().join(format!("dmb-skin-resource-test-{}", std::process::id()));
    std::fs::create_dir_all(root.join("icons/gen/icons")).unwrap();
    std::fs::create_dir_all(root.join("interface")).unwrap();
    std::fs::create_dir_all(root.join("icons")).unwrap();
    std::fs::write(root.join("icons/gen/icons/test.dmi"), b"same").unwrap();
    std::fs::write(root.join("icons/gen/icons/copy.dmi"), b"same").unwrap();
    std::fs::write(
        root.join("interface/test.dmf"),
        b"icon = 'icons/skin.png'\n",
    )
    .unwrap();
    std::fs::write(root.join("icons/skin.png"), b"skin icon").unwrap();
    let output = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    assert_eq!(output.ids.resources[0], output.ids.resources[1]);
    assert_eq!(output.dmb.resources.len(), 3);
    let names: Vec<_> = output
        .resources
        .iter()
        .filter_map(|entry| match entry {
            Entry::Named(named) => Some(String::from_utf8_lossy(&named.name).into_owned()),
            _ => None,
        })
        .collect();
    assert_eq!(
        names,
        [
            "icons/test.dmi",
            "icons/copy.dmi",
            "interface/test.dmf",
            "icons/skin.png"
        ]
    );
    input.native_resource_archive_order = Some(vec![
        "interface/test.dmf".into(),
        "icons/copy.dmi".into(),
        "icons/test.dmi".into(),
    ]);
    let ordered = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    let names: Vec<_> = ordered
        .resources
        .iter()
        .map(|entry| match entry {
            Entry::Named(named) => named.name.as_slice(),
            _ => panic!("unexpected opaque resource"),
        })
        .collect();
    assert_eq!(
        names,
        [
            b"icons/skin.png".as_slice(),
            b"interface/test.dmf",
            b"icons/copy.dmi",
            b"icons/test.dmi"
        ]
    );
    assert_eq!(ordered.ids.resources, output.ids.resources);
    let hashed =
        emit_diagnostic_hashed_with_baseline_named(&input, Some(&baseline), &template, &root, None)
            .unwrap();
    assert_eq!(hashed.dmb.resources, ordered.dmb.resources);
    input.native_resource_archive_order = Some(vec!["absent.txt".into()]);
    assert!(matches!(
        emit_with_baseline(&input, Some(&baseline), &template, &root),
        Err(EmitError::Invalid(_))
    ));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn unrelated_classes_share_identical_variable_record_like_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/variable_dedupe.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/variable_dedupe.native.bin"
    ))
    .unwrap();
    let shared_id = |dmb: &Dmb, path: &[u8]| -> u32 {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        dmb.class_variable_declarations(class)
            .unwrap()
            .into_iter()
            .map(|(id, _)| id)
            .find(|&id| dmb.string(dmb.variables[id as usize].name) == Some(b"shared"))
            .unwrap()
    };
    assert_eq!(
        shared_id(&native, b"/datum/a"),
        shared_id(&native, b"/datum/b")
    );
    assert_eq!(
        shared_id(&emitted, b"/datum/a"),
        shared_id(&emitted, b"/datum/b")
    );
    let overrides = |dmb: &Dmb, path: &[u8]| -> Vec<(Vec<u8>, Value)> {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        let mut values: Vec<_> = dmb
            .class_builtin_overrides(class)
            .unwrap_or_default()
            .into_iter()
            .map(|entry| {
                (
                    dmb.string(entry.name_string_id).unwrap().to_vec(),
                    entry.value,
                )
            })
            .collect();
        values.sort_by(|left, right| left.0.cmp(&right.0));
        values
    };
    let child = b"/obj/fixture/defaults/child";
    assert_eq!(overrides(&native, child), overrides(&emitted, child));
    let grandchild = b"/datum/a/child/grandchild";
    for dmb in [&native, &emitted] {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(grandchild))
            .unwrap();
        assert!(dmb
            .class_initial_values(class)
            .unwrap_or_default()
            .is_empty());
    }
    let final_access = |dmb: &Dmb| -> (u8, f32) {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/obj/fixture/cash"))
            .unwrap();
        let entry = dmb
            .class_initial_values(class)
            .unwrap()
            .into_iter()
            .find(|item| {
                dmb.string(dmb.variables[item.variable_id as usize].name) == Some(b"access")
            })
            .unwrap();
        (
            dmb.variables[entry.variable_id as usize].kind,
            f32::from_bits(entry.value.number_bits().unwrap()),
        )
    };
    assert_eq!(final_access(&native), (62, 200.0));
    assert_eq!(final_access(&emitted), final_access(&native));
    let mob_settings = |dmb: &Dmb, path: &[u8]| {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        let mob = dmb
            .mobs
            .iter()
            .find(|mob| mob.class == class as u32)
            .unwrap();
        (
            mob.sight_bits(),
            mob.see_in_dark_setting(),
            mob.see_invisible_setting(),
        )
    };
    for path in [b"/mob/fixture/eyes".as_slice(), b"/mob/fixture/eyes/child"] {
        assert_eq!(mob_settings(&emitted, path), mob_settings(&native, path));
    }
    let area = b"/area/fixture/glow";
    assert_eq!(overrides(&native, area), overrides(&emitted, area));
}

#[test]
fn authored_type_field_equal_to_baseline_is_preserved() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/explicit_type_field_annotated.json"
    ))
    .unwrap();
    assert_eq!(
        input
            .types
            .iter()
            .find(|typ| typ.path == "/area")
            .unwrap()
            .explicit_type_fields,
        ["luminosity".to_owned()].into()
    );
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/explicit_type_field.native.bin"
    ))
    .unwrap();
    for path in [b"/area".as_slice(), b"/area/fixture/child"] {
        let defaults = |dmb: &Dmb| {
            let class = dmb
                .classes
                .iter()
                .position(|class| dmb.string(class.path_string_id()) == Some(path))
                .unwrap();
            dmb.class_builtin_overrides(class)
                .unwrap_or_default()
                .into_iter()
                .filter(|field| dmb.string(field.name_string_id) == Some(b"luminosity"))
                .map(|field| field.value)
                .collect::<Vec<_>>()
        };
        assert_eq!(
            defaults(&emitted),
            defaults(&native),
            "{}",
            String::from_utf8_lossy(path)
        );
    }
}

#[test]
fn maptext_geometry_matches_paired_dream_maker_class() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/maptext_geometry.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/maptext_geometry.native.bin"
    ))
    .unwrap();
    let geometry = |dmb: &Dmb| {
        dmb.classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(b"/obj/fixture/maptext"))
            .unwrap()
            .maptext_geometry
    };
    assert_eq!(geometry(&native), [56, 21, (-3i16) as u16, 4]);
    assert_eq!(geometry(&emitted), geometry(&native));
}

#[test]
fn literal_matrix_transform_matches_paired_dream_maker_class() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/transform_default.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/transform_default.native.bin"
    ))
    .unwrap();
    let transform = |dmb: &Dmb| {
        let class = dmb
            .classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(b"/obj/fixture/transform"))
            .unwrap();
        (
            class.transform_flag,
            class.transform,
            dmb.class_builtin_overrides(
                dmb.classes
                    .iter()
                    .position(|candidate| std::ptr::eq(candidate, class))
                    .unwrap(),
            )
            .unwrap_or_default(),
        )
    };
    assert_eq!(transform(&emitted), transform(&native));
}

#[test]
fn explicit_variable_override_gets_class_initial_value() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/explicit_variable_override.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/explicit_variable_override.native.bin"
    ))
    .unwrap();
    let initial = |dmb: &Dmb, path: &[u8]| {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        dmb.class_initial_values(class)
            .unwrap_or_default()
            .into_iter()
            .filter(|item| {
                dmb.string(dmb.variables[item.variable_id as usize].name) == Some(b"value")
            })
            .map(|item| item.value)
            .collect::<Vec<_>>()
    };
    for path in [b"/datum/fixture".as_slice(), b"/datum/fixture/child"] {
        assert_eq!(initial(&emitted, path), initial(&native, path));
    }
}

#[test]
fn dynamic_initializer_markers_match_paired_declarations_and_overrides() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/dynamic_initializer_fields.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/dynamic_initializer_fields.native.bin"
    ))
    .unwrap();
    let markers = |dmb: &Dmb| {
        let class = dmb
            .classes
            .iter()
            .position(|class| {
                dmb.string(class.path_string_id()) == Some(b"/datum/dynamic_initializer_probe")
            })
            .unwrap();
        let declaration = dmb
            .class_variable_declarations(class)
            .unwrap()
            .into_iter()
            .find_map(|(id, _)| {
                (dmb.string(dmb.variables[id as usize].name) == Some(b"items"))
                    .then_some(dmb.variables[id as usize].hidden_initializer_marker())
                    .flatten()
            })
            .unwrap();
        let initial: Vec<_> = dmb
            .class_initial_values(class)
            .unwrap()
            .into_iter()
            .filter(|entry| entry.value.tag() == 62)
            .map(|entry| {
                (
                    dmb.string(dmb.variables[entry.variable_id as usize].name)
                        .unwrap()
                        .to_vec(),
                    entry.value.id(),
                )
            })
            .collect();
        (declaration, initial)
    };
    assert_eq!(
        markers(&native),
        (
            0,
            vec![
                (b"items".to_vec(), 2),
                (b"items".to_vec(), 3),
                (b"created".to_vec(), 4)
            ]
        )
    );
    assert_eq!(markers(&emitted), markers(&native));
    let particle_marker = |dmb: &Dmb| {
        let class = dmb
            .classes
            .iter()
            .position(|class| {
                dmb.string(class.path_string_id()) == Some(b"/particles/dynamic_initializer_probe")
            })
            .unwrap();
        dmb.class_initial_values(class)
            .unwrap()
            .into_iter()
            .filter(|entry| entry.value.tag() == 62)
            .map(|entry| {
                (
                    dmb.string(dmb.variables[entry.variable_id as usize].name)
                        .unwrap()
                        .to_vec(),
                    entry.value.id(),
                )
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(particle_marker(&native), vec![(b"drift".to_vec(), 1)]);
    assert_eq!(particle_marker(&emitted), particle_marker(&native));
}
#[test]
fn later_null_keeps_dynamic_marker_before_final_class_value() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/dynamic_initializer_fields.json"
    ))
    .unwrap();
    let typ = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum/dynamic_initializer_probe")
        .unwrap();
    typ.dynamic_initializer_fields.remove("created");
    typ.constant_initializer_fields
        .insert("created".into(), JsonValue::Null);
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class = emitted
        .classes
        .iter()
        .position(|class| {
            emitted.string(class.path_string_id()) == Some(b"/datum/dynamic_initializer_probe")
        })
        .unwrap();
    let values: Vec<_> = emitted
        .class_initial_values(class)
        .unwrap()
        .into_iter()
        .filter(|entry| {
            emitted.string(emitted.variables[entry.variable_id as usize].name) == Some(b"created")
        })
        .map(|entry| entry.value.tag())
        .collect();
    assert_eq!(values, [62, 0]);
}

#[test]
fn hidden_initializer_variable_markers_have_scoped_allocator_ids() {
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/static_marker_kinds.native.bin"
    ))
    .unwrap();
    let marker = |name: &[u8]| {
        native.variables.iter().find_map(|variable| {
            (native.string(variable.name) == Some(name))
                .then_some((variable.kind, variable.hidden_initializer_marker()))
        })
    };
    assert_eq!(marker(b"global_list"), Some((62, Some(0))));
    assert_eq!(marker(b"items"), Some((62, Some(0))));
    assert_eq!(marker(b"proc_list"), Some((62, Some(0))));
    assert_eq!(marker(b"proc_icon"), Some((62, Some(2))));
    assert_eq!(marker(b"proc_image"), Some((0, None)));
    assert_eq!(marker(b"proc_number"), Some((0, None)));
    assert_eq!(marker(b"global_number"), Some((0, None)));
    let class = native
        .classes
        .iter()
        .position(|class| native.string(class.path_string_id()) == Some(b"/datum/marker_scope"))
        .unwrap();
    let initial = native.class_initial_values(class).unwrap();
    assert_eq!(
        initial
            .iter()
            .filter(|entry| entry.value.tag() == 62)
            .map(|entry| entry.value.id())
            .collect::<Vec<_>>(),
        vec![1]
    );
}

#[test]
fn argument_in_expression_uses_anonymous_proc_reference() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/argument_defaults.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/argument_defaults.native.bin"
    ))
    .unwrap();
    let emitted = emit_diagnostic_with_baseline_named(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
        None,
    )
    .unwrap();
    let owner = input
        .procs
        .iter()
        .position(|proc| proc.name == "argument_in_probe")
        .unwrap();
    let companion = input.procs[owner].arguments[0]
        .possible_values_proc
        .unwrap();
    let dmb_owner = emitted.ids.procs[owner] as usize;
    let dmb_companion = emitted.ids.procs[companion];
    let argument = emitted.dmb.proc_arguments(dmb_owner).unwrap()[0];
    assert_eq!(argument.value_source, 0x40);
    assert_eq!(
        emitted.dmb.argument_source_proc_id(&argument),
        Some(dmb_companion)
    );
    assert!(emitted.ids.argument_source_procs.contains(&companion));
    assert_eq!(emitted.dmb.procs[dmb_companion as usize].strings, [NONE; 4]);
    let native_owner = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/argument_in_probe"))
        .unwrap();
    let native_arg = native.proc_arguments(native_owner).unwrap()[0];
    assert_eq!(native_arg.value_source, argument.value_source);
    assert_eq!(
        native.proc_references.len(),
        emitted.dmb.proc_references.len()
    );
}

#[test]
fn direct_argument_sources_match_paired_native_codes() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/argument_sources.json"
    ))
    .unwrap();
    let emitted = emit_diagnostic_with_baseline_named(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
        None,
    )
    .unwrap();
    for (name, expected) in [
        ("in_view", 0x7d01),
        ("in_oview", 0x7d02),
        ("in_range", 0x0505),
        ("in_usr_contents", 0x7f08),
        ("in_world", 0x7f10),
    ] {
        let owner = input
            .procs
            .iter()
            .position(|proc| proc.name == name)
            .unwrap();
        let companion = input.procs[owner].arguments[0]
            .possible_values_proc
            .unwrap();
        assert_eq!(emitted.ids.procs[companion], NONE, "{name}");
        let argument = emitted
            .dmb
            .proc_arguments(emitted.ids.procs[owner] as usize)
            .unwrap()[0];
        assert_eq!(argument.value_source, expected, "{name}");
    }
}

#[test]
fn movable_glide_size_uses_builtin_override() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/atom/movable")
        .unwrap()
        .variables
        .insert("glide_size".into(), JsonValue::from(8));
    let output = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class = output
        .classes
        .iter()
        .position(|class| output.string(class.path_string_id()) == Some(b"/atom/movable"))
        .unwrap();
    assert!(output
        .class_builtin_overrides(class)
        .unwrap_or_default()
        .iter()
        .any(|value| output.string(value.name_string_id) == Some(b"glide_size")));
}

#[test]
fn map_list_override_uses_native_constructor_bytecode() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/map_list.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(&code[..7], &[0x50, 1, 0x50, 2, 0x1a, 2, 0x34]);
}

#[test]
fn map_associative_list_override_uses_native_constructor_bytecode() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/map_assoc.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(code[0], 0x60);
    assert_eq!(&code[3..7], &[0x50, 1, 0x60, 6]);
    assert_eq!(&code[8..12], &[0x50, 2, 0xc8, 2]);
}

#[test]
fn map_proc_reference_override_uses_native_value_tag() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/map_proc.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(&code[..3], &[0x60, 38, emitted.ids.procs[0]]);
}

#[test]
fn default_proc_display_name_replaces_underscores() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/map_proc.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let proc = &emitted.dmb.procs[emitted.ids.procs[0] as usize];
    assert_eq!(
        emitted.dmb.string(proc.strings[1]),
        Some(&b"fixture target"[..])
    );
}

#[test]
fn class_proc_reference_default_resolves_after_proc_allocation() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/proc_constant.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let variable = emitted
        .dmb
        .variables
        .iter()
        .find(|variable| emitted.dmb.string(variable.name) == Some(&b"target"[..]))
        .unwrap();
    assert_eq!(variable.kind, 38);
    assert_eq!(variable.value, emitted.ids.procs[0]);
    emitted.dmb.validate_references().unwrap();
}

#[test]
fn inherited_proc_reference_override_remaps_class_list() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/proc_inherited.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let class = emitted
        .dmb
        .classes
        .iter()
        .find(|class| {
            emitted.dmb.string(class.path_string_id()) == Some(&b"/datum/proc_parent/child"[..])
        })
        .unwrap();
    let initial = &emitted.dmb.lists[class.lists_and_procs[3] as usize];
    assert_eq!(initial.len(), 3);
    assert_eq!(initial[1..], [38, emitted.ids.procs[0]]);
    emitted.dmb.validate_references().unwrap();
}

#[test]
fn infinity_constant_tags_match_dream_maker_numeric_bits() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/infinity.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    for (name, expected) in [
        (b"positive".as_slice(), f32::INFINITY.to_bits()),
        (b"negative".as_slice(), f32::NEG_INFINITY.to_bits()),
    ] {
        let variable = emitted
            .dmb
            .variables
            .iter()
            .find(|variable| emitted.dmb.string(variable.name) == Some(name))
            .unwrap();
        assert_eq!((variable.kind, variable.value), (42, expected));
    }
}
