use super::*;

#[test]
fn map_rows_follow_dmb_bottom_to_top_order() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let variant =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/variant.json"))
            .unwrap();
    let output = emit_with_baseline(&variant, Some(&native), &template, Path::new(".")).unwrap();
    let path = |turf: u32| {
        let class = output.dmb.instances[turf as usize].class;
        output
            .dmb
            .string(output.dmb.classes[class as usize].path_string_id())
            .unwrap()
            .to_vec()
    };
    assert_eq!(
        output
            .dmb
            .grid
            .iter()
            .map(|run| run.copies)
            .collect::<Vec<_>>(),
        vec![1, 2, 1]
    );
    assert_eq!(path(output.dmb.grid[0].turf), b"/turf/b");
    assert_eq!(path(output.dmb.grid[1].turf), b"/turf/a");
}

#[test]
fn project_name_sets_default_world_name() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/inheritance.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline_named(
        &input,
        Some(&native),
        &template,
        Path::new("."),
        Some("inheritance"),
    )
    .unwrap();
    assert_eq!(
        emitted.dmb.string(emitted.dmb.world.name_string_id()),
        Some(&b"inheritance"[..])
    );
}

#[test]
fn explicit_world_fields_match_paired_dream_maker_settings() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/world_settings.native.bin"
    ))
    .unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/world_settings_annotated.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.dmb.header.flags, reference.header.flags);
    assert_eq!(
        emitted.dmb.header.compatibility_line,
        reference.header.compatibility_line
    );
    assert_eq!(emitted.dmb.world.tick_lag, reference.world.tick_lag);
    assert_eq!(
        emitted.dmb.world.view_dimensions,
        reference.world.view_dimensions
    );
    assert_eq!(
        emitted.dmb.world.icon_dimensions_format,
        reference.world.icon_dimensions_format
    );
    assert_eq!(
        emitted.dmb.string(emitted.dmb.world.name_string_id()),
        reference.string(reference.world.name_string_id())
    );
    for slot in [1, 2] {
        let actual = &emitted.dmb.classes[emitted.dmb.world.ids[slot] as usize];
        let expected = &reference.classes[reference.world.ids[slot] as usize];
        assert_eq!(
            emitted.dmb.string(actual.path_string_id()),
            reference.string(expected.path_string_id())
        );
    }
    let actual = &emitted.dmb.mobs[emitted.dmb.world.ids[0] as usize];
    let expected = &reference.mobs[reference.world.ids[0] as usize];
    assert_eq!(
        emitted
            .dmb
            .string(emitted.dmb.classes[actual.class as usize].path_string_id()),
        reference.string(reference.classes[expected.class as usize].path_string_id())
    );
}

#[test]
fn authored_arguments_reuse_native_variable_names() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/calls.json"))
            .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    // Dream Maker adds `value` and `math`, and reuses its existing `a` and `b` records.
    assert_eq!(output.dmb.variables.len(), template.variables.len() + 2);
    for name in [b"a".as_slice(), b"b".as_slice()] {
        assert_eq!(
            output
                .dmb
                .variables
                .iter()
                .filter(|variable| output.dmb.string(variable.name) == Some(name))
                .count(),
            2
        );
    }
}

#[test]
fn list_initializers_bind_class_and_global_procedures() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/list_constants.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/list_constants.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(output.dmb.procs.len(), reference.procs.len());
    assert_eq!(output.dmb.variables.len(), reference.variables.len());
    assert_eq!(
        output.dmb.classes[0].lists_and_procs[2],
        reference.classes[0].lists_and_procs[2]
    );
    assert_eq!(
        output.dmb.world.global_initializer_proc_id(),
        reference.world.global_initializer_proc_id()
    );
    assert_eq!(
        output.ids.global_init_proc,
        Some(reference.world.global_initializer_proc_id())
    );
    for id in 67..70 {
        assert_eq!(output.dmb.variables[id].kind, 62);
        assert_eq!(
            output.dmb.variables[id].value,
            reference.variables[id].value
        );
    }
}

#[test]
fn inherited_list_initializers_bind_child_then_parent() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/list_init_chain.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/list_init_chain.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    for class in 0..2 {
        assert_eq!(
            output.dmb.classes[class].parent_class_id(),
            reference.classes[class].parent_class_id()
        );
        assert_eq!(
            output.dmb.classes[class].lists_and_procs[2],
            reference.classes[class].lists_and_procs[2]
        );
    }
}

#[test]
fn verb_source_and_display_match_dreammaker() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/verbs.json"))
            .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verbs.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let actual = &output.dmb.procs[0];
    let expected = &reference.procs[0];
    assert_eq!(actual.source_location(), expected.source_location());
    assert_eq!(actual.flags, expected.flags);
    for field in 0..4 {
        assert_eq!(
            output.dmb.string(actual.strings[field]),
            reference.string(expected.strings[field])
        );
    }
}

#[test]
fn verb_invisibility_has_native_extended_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/verb_invisibility.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verb_invisibility.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(output.dmb.procs[0].flags, reference.procs[0].flags);
    assert_eq!(
        output.dmb.procs[0].extended_flags,
        reference.procs[0].extended_flags
    );
    input
        .procs
        .iter_mut()
        .find(|proc| proc.name == "fixture_hidden")
        .unwrap()
        .invisibility = -1;
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(_))
    ));
}

#[test]
fn explicit_zero_invisibility_matches_paired_dream_maker_proc() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/explicit_invisibility_annotated.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/explicit_invisibility.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    for name in ["default_visibility", "explicit_zero", "explicit_seven"] {
        let path = format!("/mob/verb/{name}");
        let actual = output
            .dmb
            .procs
            .iter()
            .find(|proc| output.dmb.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = reference
            .procs
            .iter()
            .find(|proc| reference.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            (actual.flags, actual.extended_flags),
            (expected.flags, expected.extended_flags)
        );
    }
}

#[test]
fn native_type_can_add_tmp_declaration_without_changing_scaffold_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let datum = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum")
        .unwrap();
    datum
        .variables
        .insert("fixture_tmp".into(), JsonValue::Null);
    datum.tmp_variables.insert("fixture_tmp".into());
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let class = output
        .dmb
        .classes
        .iter()
        .find(|class| output.dmb.string(class.path_string_id()) == Some(b"/datum"))
        .unwrap();
    let declarations = &output.dmb.lists[class.defining_variable_list_id() as usize];
    assert!(declarations.chunks_exact(2).any(|pair| {
        let var = &output.dmb.variables[pair[0] as usize];
        output.dmb.string(var.name) == Some(b"fixture_tmp") && pair[1] == 4
    }));

    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum")
        .unwrap()
        .tmp_variables
        .remove("type");
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(message)) if message.contains("removes or reclassifies")
    ));
}

#[test]
fn explicit_client_datum_parent_rebinds_native_class() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let datum_od = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    let client_od = input
        .types
        .iter()
        .position(|typ| typ.path == "/client")
        .unwrap();
    input.types[client_od].parent = Some(datum_od);
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let client = output.ids.classes[client_od] as usize;
    assert_eq!(
        output.dmb.classes[client].parent_class_id(),
        output.ids.classes[datum_od]
    );
}

#[test]
fn user_classes_resolve_later_parent_type() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let datum = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    let child = input.types.len();
    let parent = child + 1;
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path": "/datum/later_parent/early_child", "Parent": parent
        }))
        .unwrap(),
    );
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path": "/datum/later_parent", "Parent": datum
        }))
        .unwrap(),
    );
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let child_class = output.ids.classes[child] as usize;
    assert_eq!(
        output.dmb.classes[child_class].parent_class_id(),
        output.ids.classes[parent]
    );
    input.types[parent].parent = Some(child);
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Invalid(message)) if message.contains("cyclic parent")
    ));
}

#[test]
fn diagnostic_emission_reserves_resources_without_asset_io() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/assets.json"))
            .unwrap();
    let output = emit_diagnostic_with_baseline_named(
        &input,
        Some(&native),
        &template,
        Path::new("intentionally-missing-resource-root"),
        None,
    )
    .unwrap();
    assert_eq!(output.ids.resources.len(), input.resources.len());
    assert_eq!(output.dmb.resources.len(), input.resources.len());
    assert!(output.resources.is_empty());
}

#[test]
fn hashed_diagnostic_matches_materialized_resource_table() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/assets.json"))
            .unwrap();
    let root = Path::new("fixtures/translation");
    let full = emit_with_baseline(&input, Some(&native), &template, root).unwrap();
    let hashed =
        emit_diagnostic_hashed_with_baseline_named(&input, Some(&native), &template, root, None)
            .unwrap();
    assert_eq!(hashed.dmb.resources, full.dmb.resources);
    assert_eq!(hashed.ids.resources, full.ids.resources);
    assert!(hashed.resources.is_empty());
}

#[test]
fn observed_hub_and_null_password_match_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/hub_settings.native.bin"
    ))
    .unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    world.variables.insert(
        "hub".into(),
        JsonValue::String("Exadv1.spacestation13".into()),
    );
    world
        .variables
        .insert("hub_password".into(), JsonValue::String("null".into()));
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        output.dmb.string(output.dmb.world.hub_channel_skin[0]),
        reference.string(reference.world.hub_channel_skin[0])
    );
    assert_eq!(
        output.dmb.string(output.dmb.world.hub_password),
        reference.string(reference.world.hub_password)
    );
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap()
        .variables
        .insert("hub_password".into(), JsonValue::String("other".into()));
    let other = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        other.dmb.string(other.dmb.world.hub_password),
        Some(crate::hash::hub_password_hash(b"other").as_bytes()),
    );
}

#[test]
fn world_cache_lifespan_matches_dream_maker_scalar() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/world_cache.native.bin"
    ))
    .unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    world
        .variables
        .insert("cache_lifespan".into(), JsonValue::from(43));
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        output.dmb.world.cache_lifespan,
        reference.world.cache_lifespan
    );
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap()
        .variables
        .insert("cache_lifespan".into(), JsonValue::from(0));
    let zero = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(zero.dmb.world.cache_lifespan, 0);
}

#[test]
fn world_fps_uses_native_integer_millisecond_tick_lag() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    for (fps, reference_bytes) in [
        (
            40,
            &include_bytes!("../../fixtures/translation/world_fps40.native.bin")[..],
        ),
        (
            59,
            &include_bytes!("../../fixtures/translation/world_fps59.native.bin")[..],
        ),
    ] {
        input
            .types
            .iter_mut()
            .find(|typ| typ.path == "/world")
            .unwrap()
            .variables
            .insert("fps".into(), JsonValue::from(fps));
        let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
        let reference = Dmb::from_bytes(reference_bytes).unwrap();
        assert_eq!(output.dmb.world.tick_lag, reference.world.tick_lag);
    }
}

#[test]
fn world_view_width_by_height_matches_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    for (view, bytes) in [
        (
            "7x11",
            &include_bytes!("../../fixtures/translation/world_view_7x11.native.bin")[..],
        ),
        (
            "15x15",
            &include_bytes!("../../fixtures/translation/world_view_15x15.native.bin")[..],
        ),
    ] {
        input
            .types
            .iter_mut()
            .find(|typ| typ.path == "/world")
            .unwrap()
            .variables
            .insert("view".into(), JsonValue::String(view.into()));
        let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
        let reference = Dmb::from_bytes(bytes).unwrap();
        assert_eq!(output.dmb.world.view_size(), reference.world.view_size());
        assert_eq!(
            output.dmb.header.flags & 0x200,
            reference.header.flags & 0x200
        );
    }
}

#[test]
fn proc_set_attributes_match_paired_dream_maker_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/proc_attributes.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/proc_attributes.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    for name in [
        "fixture_default",
        "fixture_waitfor",
        "fixture_background",
        "fixture_hidden",
        "fixture_popup",
        "fixture_instant",
        "fixture_all",
        "fixture_background_nowait",
    ] {
        let actual = output
            .dmb
            .procs
            .iter()
            .find(|proc| {
                output
                    .dmb
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(name.as_bytes()))
            })
            .unwrap();
        let expected = reference
            .procs
            .iter()
            .find(|proc| {
                reference
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(name.as_bytes()))
            })
            .unwrap();
        assert_eq!(
            (actual.flags, actual.extended_flags),
            (expected.flags, expected.extended_flags),
            "{name}"
        );
    }
}

#[test]
fn datum_verb_uses_is_verb_even_without_type_verbs_entry() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/datum_verb.json"))
            .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/datum_verb.native.bin"
    ))
    .unwrap();
    let owner = input
        .types
        .iter()
        .find(|typ| typ.path == "/datum/fixture")
        .unwrap();
    assert!(!owner.verbs.contains("fixture_action"));
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let path = b"/datum/fixture/verb/fixture_action";
    assert!(output
        .dmb
        .procs
        .iter()
        .any(|proc| output.dmb.string(proc.strings[0]) == Some(path)));
    assert!(reference
        .procs
        .iter()
        .any(|proc| reference.string(proc.strings[0]) == Some(path)));
}

#[test]
fn rejects_untranslated_program_metadata_and_world_fields() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/calls.json"))
            .unwrap();
    input.interface = Some("custom.dmf".into());
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Invalid(_))
    ));
    input.interface = None;
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    let original_build = world
        .variables
        .insert("byond_build".into(), JsonValue::from(1687));
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(message)) if message.contains("same BYOND version")
    ));
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    world
        .variables
        .insert("byond_build".into(), original_build.unwrap());
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap()
        .variables
        .insert("host".into(), JsonValue::String("changed".into()));
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(_))
    ));
}

#[test]
fn rejects_semantic_json_fields_that_cannot_be_emitted() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut calls =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/calls.json"))
            .unwrap();
    let authored = calls
        .procs
        .iter()
        .position(|proc| proc.name == "fixture_double")
        .unwrap();
    calls.procs[authored].bytecode = None;
    assert!(matches!(
        emit_with_baseline(
            &calls,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/obj")
        .unwrap()
        .parent = Some(2);
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/variables.json"))
            .unwrap();
    let north = input
        .globals
        .as_ref()
        .unwrap()
        .names
        .iter()
        .position(|name| name == "NORTH")
        .unwrap();
    input
        .globals
        .as_mut()
        .unwrap()
        .globals
        .insert(north, serde_json::json!(999));
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/maps.json"))
            .unwrap();
    input.maps[0]
        .cell_definitions
        .values_mut()
        .next()
        .unwrap()
        .name = "mismatch".into();
    let native_maps = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native_maps),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Invalid(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/calls.json"))
            .unwrap();
    input
        .optional_errors
        .insert("Example".into(), serde_json::json!(true));
    assert!(matches!(
        emit(&input, &template, Path::new("fixtures/translation")),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/calls.json"))
            .unwrap();
    input.procs[authored]
        .source_info
        .push(crate::opendream::OpenDreamSourceInfo {
            offset: 0,
            file: Some(input.strings.len()),
            line: 1,
        });
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Invalid(_))
    ));
}

#[test]
fn multiple_map_sections_fill_skipped_levels_with_world_defaults() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/multi_maps.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.dmb.dimensions, [1, 1, 3]);
    let paths: Vec<_> = emitted
        .dmb
        .grid
        .iter()
        .map(|run| {
            let instance = &emitted.dmb.instances[run.turf as usize];
            let class = &emitted.dmb.classes[instance.class as usize];
            emitted.dmb.string(class.path_string_id()).unwrap().to_vec()
        })
        .collect();
    assert_eq!(
        paths,
        [
            b"/turf/first".to_vec(),
            b"/turf".to_vec(),
            b"/turf/second".to_vec()
        ]
    );
    emitted.dmb.validate_references().unwrap();
}

#[test]
fn interface_resource_sets_native_skin_field() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/skin_simple.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.dmb.resources.len(), 1);
    assert_eq!(emitted.resources.len(), 1);
    assert_eq!(emitted.dmb.world.hub_channel_skin[2], 0);
    emitted.dmb.validate_references().unwrap();
}
