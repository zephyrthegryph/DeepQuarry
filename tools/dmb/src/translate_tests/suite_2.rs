use super::*;

#[test]
fn numeric_constants_round_after_native_trigonometric_calculations() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let input =
        crate::opendream::OpenDreamProgram::from_path(root.join("numeric_constants.json")).unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_path(
        root.join("../native_template_savefile_5161687.json"),
    )
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(&std::fs::read(root.join("../native_template.bin")).unwrap())
            .unwrap();
    let native = crate::dmb::Dmb::from_bytes(
        &std::fs::read(root.join("numeric_constants.native.bin")).unwrap(),
    )
    .unwrap();
    let output = super::super::translate_named(
        &input,
        &baseline,
        &template,
        &root,
        Some("numeric_constants"),
    )
    .unwrap();
    let options = crate::compare::CompareOptions {
        authored_prefixes: vec![
            "/datum/native_numeric_constants".into(),
            "/proc/native_numeric_tan_90".into(),
            "/proc/native_numeric_tan_270".into(),
            "/proc/native_numeric_tan_negative_90".into(),
        ],
        ..Default::default()
    };
    let differences = crate::compare::compare_dmbs(&native, &output.dmb, &options);
    assert!(differences.is_empty(), "{differences:#?}");
    let class = output
        .dmb
        .classes
        .iter()
        .position(|class| {
            output.dmb.string(class.path_string_id()) == Some(b"/datum/native_numeric_constants")
        })
        .unwrap();
    assert!(output.dmb.class_variable_declarations(class).unwrap().len() >= 50);
}

#[test]
fn arithmetic_and_bitwise_constants_match_native_float_bits() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let baseline =
        OpenDreamProgram::from_path(root.join("../native_template_savefile_5161687.json")).unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("../native_template.bin")).unwrap()).unwrap();
    for (fixture, prefix) in [
        (
            "numeric_operator_constants",
            "/datum/numeric_operator_probe",
        ),
        ("numeric_bitwise_constants", "/datum/bitwise_expanded"),
        ("numeric_unary_constants", "/datum/numeric_unary_probe"),
        ("numeric_shift_counts", "/datum/bit_shift_counts"),
        ("numeric_modulo_bounds", "/datum/numeric_modulo_bounds"),
    ] {
        let input = OpenDreamProgram::from_path(root.join(format!("{fixture}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(root.join(format!("{fixture}.native.bin"))).unwrap())
                .unwrap();
        let output =
            super::super::translate_named(&input, &baseline, &template, &root, Some(fixture))
                .unwrap();
        let differences = crate::compare::compare_dmbs(
            &native,
            &output.dmb,
            &crate::compare::CompareOptions {
                authored_prefixes: vec![prefix.into()],
                ..Default::default()
            },
        );
        assert!(differences.is_empty(), "{fixture}: {differences:#?}");
    }
}

#[test]
fn logarithm_square_root_and_power_constants_match_native_float_bits() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let input = OpenDreamProgram::from_path(root.join("numeric_math_constants.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("../native_template_savefile_5161687.json")).unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("../native_template.bin")).unwrap()).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(root.join("numeric_math_constants.native.bin")).unwrap())
            .unwrap();
    let output = super::super::translate_named(
        &input,
        &baseline,
        &template,
        &root,
        Some("numeric_math_constants"),
    )
    .unwrap();
    let options = crate::compare::CompareOptions {
        authored_prefixes: vec!["/datum/numeric_log_probe".into()],
        ..Default::default()
    };
    let differences = crate::compare::compare_dmbs(&native, &output.dmb, &options);
    assert!(differences.is_empty(), "{differences:#?}");
    let class = output
        .dmb
        .classes
        .iter()
        .position(|class| {
            output.dmb.string(class.path_string_id()) == Some(b"/datum/numeric_log_probe")
        })
        .unwrap();
    assert_eq!(
        output.dmb.class_variable_declarations(class).unwrap().len(),
        168
    );
}

#[test]
fn logarithms_preserve_native_arity_and_argument_evaluation_order() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let input = OpenDreamProgram::from_path(root.join("log_arguments.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(root.join("log_arguments.bin")).unwrap()).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("log_arguments"),
            debug,
        )
        .unwrap();
        for name in [
            "log_natural",
            "log_binary",
            "log_effects",
            "log_base_branch",
            "log_value_branch",
            "log_both_branch",
            "log_shortcircuit",
            "log_loop",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let diffs = crate::compare::compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                usize::MAX,
                true,
            );
            assert!(diffs.is_empty(), "debug={debug} {path}: {diffs:#?}");
        }
    }
}
#[test]
fn native_length_mutations_and_extension_loading_preserve_references() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let input = OpenDreamProgram::from_path(root.join("length_lvalue.json")).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(root.join("length_lvalue.native.bin")).unwrap()).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("length_lvalue"),
            debug,
        )
        .unwrap();
        for name in [
            "length_pre",
            "length_post",
            "length_add",
            "length_field",
            "length_index",
            "length_global",
            "load_native_ext",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let diffs = crate::compare::compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                usize::MAX,
                true,
            );
            assert!(diffs.is_empty(), "debug={debug} {path}: {diffs:#?}");
        }
        let path = b"/proc/length_statement";
        let words = |dmb: &Dmb| {
            let id = dmb
                .procs
                .iter()
                .position(|p| dmb.string(p.strings[0]) == Some(path))
                .unwrap();
            crate::bytecode::decode(dmb.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                .collect::<Vec<_>>()
        };
        let native = words(&native);
        let actual = words(&output.dmb);
        assert_eq!(native[0].opcode, 0x67);
        assert_eq!(actual[0].opcode, 0x64);
        assert_eq!(native[0].operands, actual[0].operands);
        assert_eq!(actual[1].opcode, 0x51);
        assert_eq!(
            native[1..]
                .iter()
                .map(|i| (i.opcode, &i.operands))
                .collect::<Vec<_>>(),
            actual[2..]
                .iter()
                .map(|i| (i.opcode, &i.operands))
                .collect::<Vec<_>>()
        );
    }
}
#[test]
fn native_gradient_argument_forms_preserve_keys_and_dispatch() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/gradient_forms.json"
    ))
    .unwrap();
    let native =
        Dmb::from_bytes(include_bytes!("../../fixtures/lowering/gradient_forms.bin")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("gradient_forms"),
            debug,
        )
        .unwrap();
        for name in [
            "gradient_variable",
            "gradient_seven",
            "gradient_named",
            "gradient_arglist",
            "gradient_literal",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let diffs = crate::compare::compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                usize::MAX,
                true,
            );
            assert!(diffs.is_empty(), "debug={debug} {path}: {diffs:#?}");
        }
    }
}
#[test]
fn native_text_builtins_materialize_flags_and_preserve_lazy_arguments() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/lowering/text_builtins.json"))
            .unwrap();
    let native =
        Dmb::from_bytes(include_bytes!("../../fixtures/lowering/text_builtins.bin")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let names: Vec<_> = input
        .procs
        .iter()
        .filter(|p| p.name.starts_with("text_") && p.name != "text_probe")
        .map(|p| format!("/proc/{}", p.name))
        .collect();
    assert_eq!(names.len(), 29);
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("text_builtins"),
            debug,
        )
        .unwrap();
        for path in &names {
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let diffs = crate::compare::compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                path,
                usize::MAX,
                true,
            );
            assert!(diffs.is_empty(), "debug={debug} {path}: {diffs:#?}");
        }
    }
}
#[test]
fn caller_and_callee_use_native_frame_references_and_builtin_class_paths() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/call_frames.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/call_frames.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output =
        super::super::translate_named(&input, &baseline, &template, &root, Some("call_frames"))
            .unwrap();
    for name in [
        "frame_callee",
        "frame_caller",
        "frame_type",
        "frame_alist_type",
        "frame_builtin_types",
    ] {
        let path = format!("/proc/{name}");
        let find = |dmb: &Dmb| {
            dmb.procs
                .iter()
                .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                .unwrap()
        };
        let differences = crate::compare::compare_proc_code(
            &native,
            find(&native),
            &output.dmb,
            find(&output.dmb),
            &path,
            100,
            true,
        );
        assert!(differences.is_empty(), "{path}: {differences:#?}");
    }
    for path in ["/alist", "/callee", "/vector"] {
        let old = input.types.iter().position(|typ| typ.path == path).unwrap();
        assert_eq!(input.native_type_tag(old), Some(89));
        assert_ne!(output.ids.classes[old], 0xffff);
        assert_eq!(output.ids.instances[old], 0xffff);
    }
    // Exercise property reads, argument-list writes and a typed frame alias.
    // They may differ in cache reuse or local-store fusion; every frame
    // owner must still decode as an intrinsic, never as StringID 0xfff0/1.
    fn contains_frame(variable: &crate::operands::Variable) -> bool {
        use crate::operands::Variable;
        match variable {
            Variable::Caller | Variable::Callee => true,
            Variable::SetCache(lhs, rhs) => contains_frame(lhs) || contains_frame(rhs),
            _ => false,
        }
    }
    for name in ["frame_names", "frame_arguments", "frame_alias"] {
        let path = format!("/proc/{name}");
        for dmb in [&native, &output.dmb] {
            let proc_id = dmb
                .procs
                .iter()
                .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let instructions =
                crate::bytecode::decode(dmb.proc_code_words(proc_id).unwrap()).unwrap();
            assert!(instructions.iter().any(|instruction| instruction.typed_operands().unwrap().iter()
                    .any(|operand| matches!(operand,crate::bytecode::Operand::Variable(variable) if contains_frame(variable)))), "{path}: missing frame owner");
            if name == "frame_arguments" {
                assert!(instructions
                    .iter()
                    .any(|instruction| instruction.opcode == 0x7c));
                assert!(instructions
                    .iter()
                    .any(|instruction| instruction.opcode == 0x7b));
            }
        }
    }
}
#[test]
fn dynamic_call_targets_precede_mutating_arguments() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/dynamic_call_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/dynamic_call_order.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("dynamic_call_order"),
            debug,
        )
        .unwrap();
        for name in [
            "dynamic_path_mutation",
            "dynamic_owner_mutation",
            "dynamic_computed_targets",
            "dynamic_path_arglist_mutation",
            "dynamic_owner_arglist_mutation",
            "dynamic_named_arguments",
            "dynamic_external_mutation",
            "dynamic_external_arglist",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let diffs = crate::compare::compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                usize::MAX,
                true,
            );
            assert!(diffs.is_empty(), "debug={debug} {path}: {diffs:#?}");
        }
    }
}
#[test]
fn cross_root_parent_types_preserve_native_categories_and_payloads() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/type_category_alias.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/type_category_alias.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::super::translate_named(
        &input,
        &baseline,
        &template,
        &root,
        Some("type_category_alias"),
    )
    .unwrap();
    for (path, tag) in [
        ("/datum/obj_alias", 9),
        ("/datum/mob_alias", 8),
        ("/datum/area_alias", 11),
        ("/datum/turf_alias", 10),
        ("/obj/datum_alias", 32),
        ("/client/tagged", 32),
        ("/datum/image_alias", 63),
    ] {
        let old = input.types.iter().position(|typ| typ.path == path).unwrap();
        assert_eq!(input.native_type_tag(old), Some(tag));
        if matches!(tag, 8 | 9 | 10 | 11 | 63) {
            let prototype = &output.dmb.instances[output.ids.instances[old] as usize];
            assert_eq!(prototype.kind, tag);
            let class = if tag == 8 {
                output.dmb.mobs[prototype.class as usize].class
            } else {
                prototype.class
            };
            assert_eq!(
                class, output.ids.classes[old],
                "{path}: prototype payload target"
            );
        } else {
            assert_eq!(output.ids.instances[old], 0xffff);
        }
    }
    for dmb in [&native, &output.dmb] {
        let holder = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/holder"))
            .unwrap();
        let field = dmb
            .class_variable_declarations(holder)
            .unwrap()
            .into_iter()
            .map(|(id, _)| &dmb.variables[id as usize])
            .find(|variable| dmb.string(variable.name) == Some(b"type_value"))
            .unwrap();
        assert_eq!(field.kind, 41);
        let instance = &dmb.instances[field.value as usize];
        assert_eq!(instance.kind, 9);
        assert_eq!(
            dmb.string(dmb.classes[instance.class as usize].path_string_id()),
            Some(b"/datum/obj_alias".as_slice())
        );
        assert_ne!(instance.initializer, 0xffff);
    }
    for path in ["/proc/aliases", "/proc/primitive_aliases"] {
        let find = |dmb: &Dmb| {
            dmb.procs
                .iter()
                .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                .unwrap()
        };
        let differences = crate::compare::compare_proc_code(
            &native,
            find(&native),
            &output.dmb,
            find(&output.dmb),
            path,
            100,
            true,
        );
        assert!(differences.is_empty(), "{path}: {differences:#?}");
    }
    assert!(!native.grid.is_empty());
    let map_differences = crate::compare::compare_maps_semantic(&native, &output.dmb, 100);
    assert!(map_differences.is_empty(), "{map_differences:#?}");
    let differences = crate::compare::compare_dmbs(
        &native,
        &output.dmb,
        &crate::compare::CompareOptions {
            authored_prefixes: vec!["/datum/holder".into(), "/proc/alias_args".into()],
            ..Default::default()
        },
    );
    assert!(differences.is_empty(), "{differences:#?}");
}
#[test]
fn global_vars_uses_native_intrinsic_record_and_prunes_operand_byte_hints() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/global_vars_value.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/global_vars_value.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::super::translate_named(
        &input,
        &baseline,
        &template,
        &root,
        Some("global_vars_value"),
    )
    .unwrap();
    let id = output.ids.global_vars.unwrap();
    assert_eq!(output.dmb.variables[id as usize].kind, 82);
    assert_eq!(output.dmb.variables[id as usize].value, 0);
    assert!(!output
        .dmb
        .global_variable_flags()
        .unwrap_or_default()
        .iter()
        .any(|(variable, _)| *variable == id));
    let names: Vec<_> = input
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("global_vars_"))
        .map(|proc_| format!("/proc/{}", proc_.name))
        .collect();
    assert_eq!(names.len(), 5);
    for path in names {
        let find = |dmb: &Dmb| {
            dmb.procs
                .iter()
                .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                .unwrap()
        };
        for dmb in [&native, &output.dmb] {
            let instructions =
                crate::bytecode::decode(dmb.proc_code_words(find(dmb)).unwrap()).unwrap();
            let getters: Vec<_> = instructions
                .iter()
                .filter_map(|instruction| {
                    if instruction.opcode != 0x33 {
                        return None;
                    }
                    match instruction.typed_operands().unwrap().as_slice() {
                        [crate::bytecode::Operand::Variable(crate::operands::Variable::Global(
                            variable,
                        ))] if dmb.variables[*variable as usize].kind == 82 => Some(*variable),
                        _ => None,
                    }
                })
                .collect();
            assert_eq!(
                getters.len(),
                1,
                "{path}: expected exactly one intrinsic getter"
            );
            let record = &dmb.variables[getters[0] as usize];
            assert_eq!(record.value, 0);
            assert_eq!(dmb.string(record.name), Some(b"vars".as_slice()));
            assert!(!instructions.iter().any(|instruction| instruction.typed_operands().unwrap().iter()
                    .any(|operand| matches!(operand, crate::bytecode::Operand::Value(value) if value.tag() == 82))),
                    "{path}: intrinsic must be materialized through its variable record");
        }
        if path == "/proc/global_vars_alias" {
            // OD fuses `alias = global.vars; return alias` into a returned
            // assignment. The native local store/load pair is equivalent.
            let opcodes = |dmb: &Dmb| {
                crate::bytecode::decode(dmb.proc_code_words(find(dmb)).unwrap())
                    .unwrap()
                    .into_iter()
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>()
            };
            assert_eq!(opcodes(&native), [0x33, 0x34, 0x33, 0x12, 0]);
            assert_eq!(opcodes(&output.dmb), [0x33, 0x35, 0x12, 0]);
            let actual =
                crate::bytecode::decode(output.dmb.proc_code_words(find(&output.dmb)).unwrap())
                    .unwrap();
            assert_eq!(actual[1].operands, [0xffda, 0]);
        } else {
            let differences = crate::compare::compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                100,
                true,
            );
            assert!(differences.is_empty(), "{path}: {differences:#?}");
        }
    }
    for proc_ in &mut input.procs {
        if proc_.name.starts_with("global_vars_") {
            // Float operand contains 0x5f but is not PushGlobalVars.
            proc_.bytecode = Some(vec![0x38, 0x5f, 0, 0, 0, 0x10]);
        }
    }
    let output = super::super::translate_named(
        &input,
        &baseline,
        &template,
        &root,
        Some("global_vars_value"),
    )
    .unwrap();
    assert_eq!(output.ids.global_vars, None);
    assert!(!output.dmb.variables.iter().any(|record| record.kind == 82));
}
#[test]
fn field_receivers_preserve_native_argument_evaluation_timing() {
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/receiver_field_argument.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/receiver_field_argument.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let emitted = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("receiver_field_argument"),
            debug,
        )
        .unwrap();
        for name in [
            "receiver_field_argument",
            "receiver_field_safe_argument",
            "receiver_field_expression_argument",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let differences = crate::compare::compare_proc_code(
                &native,
                find(&native),
                &emitted.dmb,
                find(&emitted.dmb),
                &path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn bare_self_names_resolve_in_current_owner_and_ancestors() {
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/self_call_names.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/self_call_names.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let output =
        super::super::translate_named(&input, &baseline, &template, &root, Some("self_call_names"))
            .unwrap();
    let prefixes = input
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("call_"))
        .map(|proc_| {
            format!(
                "{}/proc/{}",
                input.types[proc_.owning_type_id].path, proc_.name
            )
        })
        .collect();
    let options = crate::compare::CompareOptions {
        authored_prefixes: prefixes,
        ..Default::default()
    };
    let differences = crate::compare::compare_dmbs(&native, &output.dmb, &options);
    assert!(differences.is_empty(), "{differences:#?}");
}
#[test]
fn typed_and_untyped_method_names_follow_native_definitions_and_source_order() {
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_nativemethods_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for (name, json, native_bytes) in [
        (
            "method_names",
            include_bytes!("../../fixtures/translation/method_names.json").as_slice(),
            include_bytes!("../../fixtures/translation/method_names.native.bin").as_slice(),
        ),
        (
            "method_names_reversed",
            include_bytes!("../../fixtures/translation/method_names_reversed.json").as_slice(),
            include_bytes!("../../fixtures/translation/method_names_reversed.native.bin")
                .as_slice(),
        ),
    ] {
        let input = crate::opendream::OpenDreamProgram::from_slice(json).unwrap();
        let native = crate::dmb::Dmb::from_bytes(native_bytes).unwrap();
        let output =
            super::super::translate_named(&input, &baseline, &template, &root, Some(name)).unwrap();
        let prefixes = input
            .procs
            .iter()
            .filter(|proc| proc.name.starts_with("name_"))
            .map(|proc| format!("/proc/{}", proc.name))
            .collect();
        let options = crate::compare::CompareOptions {
            authored_prefixes: prefixes,
            ..Default::default()
        };
        let differences = crate::compare::compare_dmbs(&native, &output.dmb, &options);
        assert!(differences.is_empty(), "{name}: {differences:#?}");
    }
}
#[test]
fn body_append_skips_optional_list_sentinel_and_promotes_width() {
    let mut dmb =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    dmb.header.flags &= !0x4000_0000;
    dmb.lists.resize(0xffff, Vec::new());
    let id = super::super::append_code_list(&mut dmb, vec![0x50, 7, 0x12, 0]);
    assert_eq!(id, 0x10000);
    assert!(dmb.lists[0xffff].is_empty());
    dmb.procs[0].code_locals_args[0] = id;
    let decoded = crate::dmb::Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
    assert_eq!(decoded.proc_code_words(0).unwrap(), vec![0x50, 7, 0x12, 0]);
    assert!(decoded.header.flags & 0x4000_0000 != 0);
}
