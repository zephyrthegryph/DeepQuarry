use super::*;

#[test]
fn movable_argument_path_restores_native_type_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc = input
        .procs
        .iter_mut()
        .find(|proc| proc.name == "use_animate")
        .unwrap();
    proc.arguments[0].type_path = Some("/atom/movable".to_owned());
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let proc_id = output.ids.procs[input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap()] as usize;
    assert_eq!(output.dmb.proc_arguments(proc_id).unwrap()[0].type_flags, 3);
}

#[test]
fn atom_and_turf_argument_paths_restore_native_type_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc_index = input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap();
    for (path, expected) in [("/atom", 0x123), ("/turf", 0x20)] {
        input.procs[proc_index].arguments[0].type_path = Some(path.to_owned());
        let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
        let proc_id = output.ids.procs[proc_index] as usize;
        assert_eq!(
            output.dmb.proc_arguments(proc_id).unwrap()[0].type_flags,
            expected
        );
    }
}

#[test]
fn explicit_anything_union_preserves_other_argument_type_bits() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc_index = input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap();
    input.procs[proc_index].arguments[0].r#type = 1;
    input.procs[proc_index].arguments[0].explicit_anything = true;
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let proc_id = output.ids.procs[proc_index] as usize;
    assert_eq!(
        output.dmb.proc_arguments(proc_id).unwrap()[0].type_flags,
        0x1080
    );
}

#[test]
fn typed_list_argument_uses_declared_element_path() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc_index = input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap();
    for (path, expected) in [
        ("list/turf/to_add", 0x20),
        ("list/mob/living/targets", 1),
        ("list/area/supply_shuttle_areas", 0x100),
        ("list/items", 0),
    ] {
        input.procs[proc_index].arguments[0].type_path = Some("/list".to_owned());
        input.procs[proc_index].arguments[0].declared_path = Some(path.to_owned());
        let emitted =
            emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
        let proc_id = emitted.ids.procs[proc_index] as usize;
        assert_eq!(
            emitted.dmb.proc_arguments(proc_id).unwrap()[0].type_flags,
            expected,
            "{path}"
        );
    }
}

#[test]
fn declared_list_elements_and_absolute_parameter_omission_match_native() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    for (json, native, paths) in [
        (
            &include_bytes!("../../../../fixtures/translation/list_arg_path.json")[..],
            &include_bytes!("../../../../fixtures/translation/list_arg_path.native.bin")[..],
            &[
                "/proc/list_turf",
                "/proc/list_mob",
                "/proc/list_area",
                "/proc/list_plain",
            ][..],
        ),
        (
            &include_bytes!("../../../../fixtures/translation/absolute_arg.json")[..],
            &include_bytes!("../../../../fixtures/translation/absolute_arg.native.bin")[..],
            &["/datum/symptom/heal/proc/Heal"][..],
        ),
    ] {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(native).unwrap();
        let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap()
            .dmb;
        let args = |dmb: &Dmb, path: &str| {
            let id = dmb
                .procs
                .iter()
                .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            dmb.proc_arguments(id)
                .unwrap()
                .iter()
                .map(|arg| {
                    (
                        dmb.string(dmb.variables[arg.variable_id as usize].name)
                            .unwrap()
                            .to_vec(),
                        arg.type_flags,
                    )
                })
                .collect::<Vec<_>>()
        };
        for &path in paths {
            assert_eq!(args(&emitted, path), args(&native, path), "{path}");
        }
    }
}

#[test]
fn in_world_argument_uses_native_atom_selector_for_datum_or_untyped() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/argument_world.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/argument_world.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in [
        b"datum_world".as_slice(),
        b"obj_world".as_slice(),
        b"turf_world".as_slice(),
        b"atom_world".as_slice(),
        b"any_world".as_slice(),
    ] {
        let path = [b"/proc/".as_slice(), name].concat();
        let emitted_id = emitted
            .procs
            .iter()
            .position(|proc| emitted.string(proc.strings[0]) == Some(path.as_slice()))
            .unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_slice()))
            .unwrap();
        let actual = emitted.proc_arguments(emitted_id).unwrap()[0];
        let expected = native.proc_arguments(native_id).unwrap()[0];
        assert_eq!(
            actual.type_flags,
            expected.type_flags,
            "{}",
            String::from_utf8_lossy(&path)
        );
        assert_eq!(
            actual.value_source,
            expected.value_source,
            "{}",
            String::from_utf8_lossy(&path)
        );
    }
}

#[test]
fn argument_source_companion_receives_preceding_arguments_only() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/argument_source_parameter.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/argument_source_parameter.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in [
        "global_options",
        "member_options",
        "call_options",
        "unused_options",
    ] {
        let path = format!("/proc/{name}");
        let actual_owner = emitted
            .procs
            .iter()
            .position(|proc| emitted.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected_owner = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let actual_argument = *emitted
            .proc_arguments(actual_owner)
            .unwrap()
            .last()
            .unwrap();
        let expected_argument = *native
            .proc_arguments(expected_owner)
            .unwrap()
            .last()
            .unwrap();
        let actual_source = emitted.argument_source_proc_id(&actual_argument).unwrap() as usize;
        let expected_source = native.argument_source_proc_id(&expected_argument).unwrap() as usize;
        let actual_args = emitted.proc_arguments(actual_source).unwrap();
        let expected_args = native.proc_arguments(expected_source).unwrap();
        assert_eq!(actual_args.len(), expected_args.len(), "{name}");
        for (actual, expected) in actual_args.iter().zip(&expected_args) {
            assert_eq!(actual.type_flags, expected.type_flags, "{name}");
            assert_eq!(actual.value_source, expected.value_source, "{name}");
        }
    }
}

#[test]
fn argument_source_companion_includes_current_when_referenced() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/argument_source_self.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/argument_source_self.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let source_args = |dmb: &Dmb| {
        let owner = dmb
            .procs
            .iter()
            .position(|proc| dmb.string(proc.strings[0]) == Some(b"/proc/self_source"))
            .unwrap();
        let argument = dmb.proc_arguments(owner).unwrap()[0];
        let source = dmb.argument_source_proc_id(&argument).unwrap() as usize;
        dmb.proc_arguments(source).unwrap()
    };
    let actual = source_args(&emitted);
    let expected = source_args(&native);
    assert_eq!(actual.len(), expected.len());
    assert_eq!(actual.len(), 1);
    assert_eq!(actual[0].type_flags, expected[0].type_flags);
    assert_eq!(actual[0].value_source, expected[0].value_source);
}

#[test]
fn promotes_to_wide_object_ids_when_string_table_exceeds_u16() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    for id in 0..u16::MAX as usize {
        input.strings.push(format!("wide_{id}"));
    }
    let output = emit_with_baseline(&input, Some(&input), &template, Path::new(".")).unwrap();
    for &id in &output.ids.strings {
        assert!(
            !native_reserved_string_id(id),
            "authored string occupies reserved ID {id:#x}"
        );
        let field = byond_dmb::operands::Variable::Field(id);
        assert_eq!(
            byond_dmb::operands::Variable::decode(&field.encode())
                .unwrap()
                .0,
            field
        );
    }
    assert!(requires_wide_object_ids(&output.dmb));
    assert!(output.dmb.header.uses_large_object_ids());
    let bytes = output.dmb.to_bytes().unwrap();
    let parsed = Dmb::from_bytes(&bytes).unwrap();
    assert_eq!(parsed.strings.len(), output.dmb.strings.len());
    assert_eq!(parsed.world.domain_string_id(), NONE);
}
#[test]
fn client_path_defaults_use_native_singleton_payload() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let client = input
        .types
        .iter()
        .position(|typ| typ.path == "/client")
        .unwrap();
    let datum = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path":"/datum/client_path_holder", "Parent":datum,
            "Variables":{"client_default":{"type":1,"value":client}}
        }))
        .unwrap(),
    );
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let variable = output
        .dmb
        .variables
        .iter()
        .find(|var| output.dmb.string(var.name) == Some(b"client_default"))
        .unwrap();
    assert_eq!((variable.kind, variable.value), (59, 0));
}
#[test]
fn wide_optional_lists_skip_absent_sentinel_id() {
    let mut template =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    template.lists.resize(NONE as usize, Vec::new());
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let datum = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    let own_type = input.types.len();
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path":"/datum/wide_list_holder", "Parent":datum, "Variables":{"list_probe":1}
        }))
        .unwrap(),
    );
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    assert!(output.dmb.lists[NONE as usize].is_empty());
    let declaration_id =
        output.dmb.classes[output.ids.classes[own_type] as usize].lists_and_procs[4];
    assert!(declaration_id > NONE);
    assert!(!output.dmb.lists[declaration_id as usize].is_empty());
    let parsed = Dmb::from_bytes(&output.dmb.to_bytes().unwrap()).unwrap();
    assert_eq!(
        parsed.classes[output.ids.classes[own_type] as usize].lists_and_procs[4],
        declaration_id
    );
}

#[test]
fn modified_type_values_use_instance_ids() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/modified_type.json"
    ))
    .unwrap();
    let dmb = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let owner = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder"))
        .unwrap();
    let declaration = dmb
        .class_variable_declarations(owner)
        .unwrap()
        .into_iter()
        .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"tag_modified"))
        .unwrap();
    let variable = &dmb.variables[declaration.0 as usize];
    assert_eq!(variable.kind, 41);
    let instance = &dmb.instances[variable.value as usize];
    assert_eq!(instance.kind, 9);
    assert_eq!(
        dmb.string(dmb.classes[instance.class as usize].path_string_id()),
        Some(b"/obj/tagged".as_slice())
    );
    assert_ne!(instance.initializer, NONE);
    let child = dmb
        .classes
        .iter()
        .position(|class| {
            dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder/child")
        })
        .unwrap();
    let initial = dmb
        .class_initial_values(child)
        .unwrap()
        .into_iter()
        .find(|value| {
            dmb.string(dmb.variables[value.variable_id as usize].name) == Some(b"tag_modified")
        })
        .unwrap();
    assert_eq!(initial.value.tag(), 41);
    assert_ne!(initial.value.id(), variable.value);
}

#[test]
fn declaration_provenance_keeps_original_default_and_final_override() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/modified_type.json"
    ))
    .unwrap();
    let typ = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum/modified_holder")
        .unwrap();
    typ.variables.insert("tag_plain".into(), JsonValue::from(6));
    typ.variable_declaration_values
        .insert("tag_plain".into(), JsonValue::from(0));
    typ.explicit_type_fields.insert("tag_plain".into());
    typ.variable_override_order.push("tag_plain".into());
    let dmb = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder"))
        .unwrap();
    let var_id = dmb
        .class_variable_declarations(class_id)
        .unwrap()
        .into_iter()
        .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"tag_plain"))
        .unwrap()
        .0;
    let variable = &dmb.variables[var_id as usize];
    assert_eq!(variable.kind, 42);
    assert_eq!(variable.value, 0);
    let override_value = dmb
        .class_initial_values(class_id)
        .unwrap()
        .into_iter()
        .find(|entry| entry.variable_id == var_id)
        .unwrap()
        .value;
    assert_eq!(override_value.number_bits(), Some(6f32.to_bits()));
}

#[test]
fn inline_modified_datum_allocates_native_kind_32_instance() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_nativeconstruct_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/constructor_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/constructor_order.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let type_id = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum/ctor")
        .unwrap();
    let json = input
        .strings
        .iter()
        .find(|value| value.as_str() == "{\"foo\":3}")
        .unwrap();
    let id = emitted.ids.modified_instances[&(type_id, json.clone())];
    let instance = &emitted.dmb.instances[id as usize];
    assert_eq!(instance.kind, 32);
    assert_eq!(instance.class, emitted.ids.classes[type_id]);
    assert_ne!(instance.initializer, NONE);
    assert_eq!(
        emitted
            .dmb
            .instances
            .iter()
            .filter(|record| record.kind == 32)
            .count(),
        native
            .instances
            .iter()
            .filter(|record| record.kind == 32)
            .count()
    );
}
#[test]
fn inline_modified_new_allocates_instance_for_lowerer() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/modified_type.json"
    ))
    .unwrap();
    let type_id = input
        .types
        .iter()
        .position(|typ| typ.path == "/obj/tagged")
        .unwrap();
    let json = r#"{"amount":99}"#.to_owned();
    let string_id = input.strings.len() as u32;
    input.strings.push(json.clone());
    let code = input
        .procs
        .iter_mut()
        .find_map(|proc| proc.bytecode.as_mut())
        .unwrap();
    code.push(0x03);
    code.extend(string_id.to_le_bytes());
    code.push(0x02);
    code.extend((type_id as u32).to_le_bytes());
    code.extend([0x2e, 0, 0, 0, 0, 0]);
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let id = emitted.ids.modified_instances[&(type_id, json)];
    let instance = &emitted.dmb.instances[id as usize];
    assert_eq!(instance.kind, 9);
    assert_ne!(instance.initializer, NONE);
}

#[test]
fn modified_type_constants_emit_tag_41_for_class_global_and_proc() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/modified_constant.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
    )
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/modified_constant.native.bin"
    ))
    .unwrap();
    let class_default = |dmb: &Dmb| {
        let class_id = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder"))
            .unwrap();
        let id = dmb
            .class_variable_declarations(class_id)
            .unwrap()
            .into_iter()
            .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"object_type"))
            .unwrap()
            .0;
        let var = &dmb.variables[id as usize];
        assert_eq!(var.kind, 41);
        assert_eq!(dmb.instances[var.value as usize].kind, 9);
        assert_ne!(dmb.instances[var.value as usize].initializer, NONE);
    };
    class_default(&emitted.dmb);
    class_default(&native);
    let global = |dmb: &Dmb| {
        let id = dmb
            .global_variable_flags()
            .unwrap()
            .into_iter()
            .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"type_reference"))
            .unwrap()
            .0;
        let var = &dmb.variables[id as usize];
        assert_eq!(var.kind, 41);
        assert_ne!(dmb.instances[var.value as usize].initializer, NONE);
    };
    global(&emitted.dmb);
    global(&native);
    let type_id = input
        .types
        .iter()
        .position(|typ| typ.path == "/obj/modified_constant")
        .unwrap();
    let json = input
        .strings
        .iter()
        .find(|text| text.contains("\"amount\":22"))
        .unwrap();
    let proc_instance = emitted.ids.modified_instances[&(type_id, json.clone())];
    assert_ne!(
        emitted.dmb.instances[proc_instance as usize].initializer,
        NONE
    );
}

#[test]
fn preserved_native_procedure_references_survive_authored_prefix() {
    use byond_dmb::bytecode::Operand;
    use byond_dmb::operands::Variable;
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/selector_alias_collision.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let output = crate::translate::translate_named_debug(
        &input,
        &baseline,
        &template,
        Path::new("../../fixtures/lowering"),
        Some("selector_alias_collision"),
        false,
    )
    .unwrap();
    let find = |dmb: &Dmb, name: &[u8]| {
        dmb.procs
            .iter()
            .position(|p| dmb.string(p.strings[0]) == Some(name))
            .unwrap()
    };
    for dmb in [&template, &output.dmb] {
        let code =
            byond_dmb::bytecode::decode(dmb.proc_code_words(find(dmb, b"/database/New")).unwrap())
                .unwrap();
        let call = code.iter().find(|i| i.opcode == 0x2a).unwrap();
        let operands = call.typed_operands().unwrap();
        let Operand::Variable(Variable::SetCache(_, right)) = &operands[0] else {
            panic!("database selector")
        };
        let Variable::StaticProc(id) = **right else {
            panic!("database static selector")
        };
        assert_eq!(
            dmb.string(dmb.procs[id as usize].strings[0]),
            Some(&b"/database/proc/Open"[..])
        );
        let sound = byond_dmb::bytecode::decode(dmb.proc_code_words(find(dmb, b"/sound/New")).unwrap())
            .unwrap();
        assert!(sound
            .iter()
            .any(|i| i.opcode == 0x60 && i.operands == [40, 0]));
    }
}

#[test]
fn scaffold_global_call_count_and_nested_verb_selector_relocate_independently() {
    use byond_dmb::bytecode::Operand;
    use byond_dmb::operands::Variable;
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/selector_alias_collision.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let mut template =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let owner = template
        .procs
        .iter()
        .position(|p| template.string(p.strings[0]) == Some(b"/database/New"))
        .unwrap();
    let target = template
        .procs
        .iter()
        .position(|p| template.string(p.strings[0]) == Some(b"/database/proc/Open"))
        .unwrap() as u32;
    let mut words = vec![0x30, 2, target, 0x33];
    words.extend(
        Variable::SetCache(
            Box::new(Variable::Src),
            Box::new(Variable::StaticVerb(target)),
        )
        .encode(),
    );
    words.push(0);
    template.procs[owner].code_locals_args[0] = template.lists.len() as u32;
    template.lists.push(words);
    let output = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/lowering"),
    )
    .unwrap();
    let owner = output
        .dmb
        .procs
        .iter()
        .position(|p| output.dmb.string(p.strings[0]) == Some(b"/database/New"))
        .unwrap();
    let target = output
        .dmb
        .procs
        .iter()
        .position(|p| output.dmb.string(p.strings[0]) == Some(b"/database/proc/Open"))
        .unwrap() as u32;
    let instructions = byond_dmb::bytecode::decode(output.dmb.proc_code_words(owner).unwrap()).unwrap();
    assert_eq!(instructions[0].operands, [2, target]);
    assert_eq!(
        instructions[1].typed_operands().unwrap(),
        vec![Operand::Variable(Variable::SetCache(
            Box::new(Variable::Src),
            Box::new(Variable::StaticVerb(target))
        ))]
    );
}
