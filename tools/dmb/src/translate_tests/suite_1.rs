use super::*;

#[test]
fn inherited_upward_proc_references_preserve_native_targets_and_names() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/inherited_proc_refs.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/inherited_proc_refs.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("inherited_proc_refs"),
            debug,
        )
        .unwrap();
        for path in [
            "/datum/ref_parent/child/proc/upward_ref",
            "/datum/ref_parent/child/proc/inferred_name",
        ] {
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let left = find(&native);
            let right = find(&output.dmb);
            let differences = crate::compare::compare_proc_code(
                &native,
                left,
                &output.dmb,
                right,
                path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{path}, debug={debug}: {differences:#?}"
            );
            if path.ends_with("upward_ref") {
                for (dmb, id) in [(&native, left), (&output.dmb, right)] {
                    let code = crate::bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
                    let push = code
                        .iter()
                        .find(|instruction| {
                            instruction.opcode == 0x60 && instruction.operands[0] == 38
                        })
                        .unwrap();
                    let target = push.operands[1] as usize;
                    assert_eq!(
                        dmb.string(dmb.procs[target].strings[0]),
                        Some(b"/datum/ref_parent/proc/check".as_slice())
                    );
                    let native_target = native
                        .procs
                        .iter()
                        .position(|proc_| {
                            native.string(proc_.strings[0])
                                == Some(b"/datum/ref_parent/proc/check".as_slice())
                        })
                        .unwrap();
                    assert!(crate::compare::compare_proc_code(
                        &native,
                        native_target,
                        dmb,
                        target,
                        "inherited check",
                        100,
                        true
                    )
                    .is_empty());
                }
            }
        }
    }
}
#[test]
fn procedure_constants_distinguish_original_override_and_native_callback_paths() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/proc_reference_paths.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/proc_reference_paths.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::super::translate_named_debug(
        &input,
        &baseline,
        &template,
        &root,
        Some("proc_reference_paths"),
        false,
    )
    .unwrap();
    for (source, target) in [
        ("/proc/definition_reference", "/datum/ref_owner/proc/check"),
        ("/proc/override_reference", "/datum/ref_owner/check"),
        ("/proc/callback_reference", "/world/Error"),
        ("/proc/ignored_root_reference", "/root_probe"),
        ("/proc/mob_callback_reference", "/mob/Login"),
        ("/proc/client_callback_reference", "/client/Topic"),
        ("/proc/datum_callback_reference", "/datum/Read"),
    ] {
        let referenced = |dmb: &Dmb| {
            let id = dmb
                .procs
                .iter()
                .position(|proc_| dmb.string(proc_.strings[0]) == Some(source.as_bytes()))
                .unwrap();
            let code = crate::bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
            let push = code
                .iter()
                .find(|instruction| instruction.opcode == 0x60)
                .unwrap();
            let value = crate::operands::Value {
                tag_word: push.operands[0],
                data_word: push.operands[1],
                extra_word: None,
            };
            assert_eq!(value.tag(), 38);
            let target_id = value.id() as usize;
            assert_eq!(
                dmb.string(dmb.procs[target_id].strings[0]),
                Some(target.as_bytes()),
                "{source}"
            );
            target_id
        };
        let left = referenced(&native);
        let right = referenced(&output.dmb);
        let differences =
            crate::compare::compare_proc_code(&native, left, &output.dmb, right, target, 100, true);
        assert!(
            differences.is_empty(),
            "callee body {source}: {differences:#?}"
        );
    }
    for dmb in [&native, &output.dmb] {
        let caller = dmb
            .procs
            .iter()
            .position(|proc_| {
                dmb.string(proc_.strings[0]) == Some(b"/proc/named_root_call".as_slice())
            })
            .unwrap();
        let code = crate::bytecode::decode(dmb.proc_code_words(caller).unwrap()).unwrap();
        let call = code
            .iter()
            .find(|instruction| instruction.opcode == 0x30)
            .unwrap();
        let target = call.operands[1] as usize;
        assert_eq!(
            dmb.string(dmb.procs[target].strings[0]),
            Some(b"/proc/root_probe".as_slice())
        );
    }
}
#[test]
fn absolute_var_parameters_create_globals_instead_of_argument_slots() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/global_parameter_declaration.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/global_parameter_declaration.native.bin"
    ))
    .unwrap();
    assert!(!input
        .types
        .iter()
        .any(|typ| typ.path == "/var" || typ.path == "/var/global_parameter_value"));
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::super::translate_named_debug(
        &input,
        &baseline,
        &template,
        &root,
        Some("global_parameter_declaration"),
        false,
    )
    .unwrap();
    let variable = output
        .dmb
        .variables
        .iter()
        .find(|var| output.dmb.string(var.name) == Some(b"global_parameter_value".as_slice()))
        .unwrap();
    assert_eq!((variable.kind, variable.value), (42, 7f32.to_bits()));
    for path in ["/proc/global_parameter", "/proc/global_parameter_read"] {
        let find = |dmb: &Dmb| {
            dmb.procs
                .iter()
                .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                .unwrap()
        };
        let left = find(&native);
        let right = find(&output.dmb);
        assert!(native.proc_arguments(left).unwrap().is_empty());
        assert!(output.dmb.proc_arguments(right).unwrap().is_empty());
        let differences =
            crate::compare::compare_proc_code(&native, left, &output.dmb, right, path, 100, true);
        assert!(differences.is_empty(), "{path}: {differences:#?}");
    }
}
#[test]
fn ordered_procedure_memberships_preserve_override_body_and_arguments() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/procedure_membership_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/procedure_membership_order.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::super::translate_named_debug(
        &input,
        &baseline,
        &template,
        &root,
        Some("procedure_membership_order"),
        false,
    )
    .unwrap();
    let members = |dmb: &Dmb, path: &str| {
        let list = if path == "/world" {
            dmb.world.proc_list_id()
        } else {
            dmb.classes
                .iter()
                .find(|class| dmb.string(class.path_string_id()) == Some(path.as_bytes()))
                .unwrap()
                .proc_list_id()
        };
        dmb.lists[list as usize]
            .iter()
            .copied()
            .map(|id| id as usize)
            .collect::<Vec<_>>()
    };
    for owner in ["/datum/order", "/datum/order/child", "/world"] {
        let expected = members(&native, owner);
        let actual = members(&output.dmb, owner);
        assert_eq!(expected.len(), actual.len(), "{owner}");
        for (left, right) in expected.into_iter().zip(actual) {
            let identity = |dmb: &Dmb, id: usize| {
                let proc_ = &dmb.procs[id];
                let path = dmb.string(proc_.strings[0]).unwrap().to_vec();
                let locals = dmb.lists[proc_.code_locals_args[1] as usize]
                    .iter()
                    .map(|&name| dmb.string(name).unwrap().to_vec())
                    .collect::<Vec<_>>();
                let args = dmb
                    .proc_arguments(id)
                    .unwrap()
                    .iter()
                    .map(|arg| {
                        (
                            dmb.string(dmb.variables[arg.variable_id as usize].name)
                                .unwrap()
                                .to_vec(),
                            arg.type_flags,
                            arg.value_source,
                        )
                    })
                    .collect::<Vec<_>>();
                (path, locals, args)
            };
            assert_eq!(
                identity(&native, left),
                identity(&output.dmb, right),
                "ordered {owner}"
            );
            let differences = crate::compare::compare_proc_code(
                &native,
                left,
                &output.dmb,
                right,
                owner,
                100,
                true,
            );
            assert!(differences.is_empty(), "ordered {owner}: {differences:#?}");
        }
    }
}
#[test]
fn mandatory_global_variable_65535_resolves_and_encodes_normally() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let globals = input.globals.as_mut().unwrap();
    let authored_global_id = globals.names.len();
    globals.names.push("wide_global".into());
    globals.global_count += 1;
    globals
        .globals
        .insert(authored_global_id, serde_json::json!(7));
    let mut output =
        crate::od_emit::emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap();
    let variable = output.dmb.variables[output.ids.globals[authored_global_id] as usize].clone();
    output.dmb.variables.resize(65536, variable.clone());
    output.dmb.variables[65535] = variable;
    let footer = output.dmb.variable_footer as usize;
    let old = output.ids.globals[authored_global_id];
    for record in output.dmb.lists[footer].chunks_exact_mut(2) {
        if record[0] == old {
            record[0] = 65535;
        }
    }
    output.ids.globals[authored_global_id] = 65535;
    output.dmb.header.flags |= 0x4000_0000;
    output.dmb.validate_references().unwrap();
    let resolver = super::super::Resolver {
        program: &input,
        ids: &output.ids,
        mob_ids_by_class: std::collections::HashMap::new(),
        native_sound_string: None,
        native_icon_string: None,
        native_generator_string: None,
        current_owner: std::cell::Cell::new(0),
        current_proc: std::cell::Cell::new(0),
    };
    assert_eq!(
        crate::od_lower::SymbolResolver::global(&resolver, authored_global_id as u32),
        Some(65535)
    );
    let mut code = vec![0x97, 10];
    code.extend((authored_global_id as u32).to_le_bytes());
    let actual = crate::od_lower::lower_proc_bytecode(&code, &resolver).unwrap();
    assert_eq!(actual, [0x33, 0xffdb, 65535, 0x12, 0]);
}
#[test]
fn global_verb_paths_and_constant_resource_initializers_match_native() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for (name, input_bytes, native_bytes) in [
        (
            "global_verb_path",
            include_bytes!("../../fixtures/translation/global_verb_path.json").as_slice(),
            include_bytes!("../../fixtures/translation/global_verb_path.native.bin").as_slice(),
        ),
        (
            "resource_initializers",
            include_bytes!("../../fixtures/translation/resource_initializers.json").as_slice(),
            include_bytes!("../../fixtures/translation/resource_initializers.native.bin")
                .as_slice(),
        ),
    ] {
        let input = OpenDreamProgram::from_slice(input_bytes).unwrap();
        let native = Dmb::from_bytes(native_bytes).unwrap();
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some(name),
            false,
        )
        .unwrap();
        if name == "global_verb_path" {
            let parent = |dmb: &Dmb| {
                dmb.classes
                    .iter()
                    .find(|class| dmb.string(class.path_string_id()) == Some(b"/verb".as_slice()))
                    .unwrap()
                    .initial_ids[1]
            };
            assert_eq!(parent(&native), 0xffff);
            assert_eq!(parent(&output.dmb), 0xffff);
            assert!(output
                .dmb
                .classes
                .iter()
                .any(
                    |class| output.dmb.string(class.path_string_id()) == Some(b"/verb".as_slice())
                ));
            assert!(output
                .dmb
                .procs
                .iter()
                .any(|proc_| output.dmb.string(proc_.strings[0])
                    == Some(b"/verb/foobarverb".as_slice())));
            for path in ["/proc/global_verb_path", "/proc/global_verb_lookup"] {
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
        } else {
            for (field, kind) in [
                ("file_literal", 62),
                ("icon_literal", 62),
                ("static_file_literal", 62),
                ("static_icon_literal", 62),
                ("static_file_dynamic", 0),
                ("static_icon_dynamic", 0),
            ] {
                let get = |dmb: &Dmb| {
                    dmb.variables
                        .iter()
                        .filter(|var| dmb.string(var.name) == Some(field.as_bytes()))
                        .map(|var| var.kind)
                        .collect::<Vec<_>>()
                };
                assert_eq!(get(&native), [kind], "native {field}");
                assert_eq!(get(&output.dmb), [kind], "translated {field}");
            }
        }
    }
}
#[test]
fn implicit_locate_keeps_native_unary_contract() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/locate_forms.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/locate_forms.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("locate_forms"),
            debug,
        )
        .unwrap();
        for name in [
            "implicit_type",
            "explicit_world",
            "implicit_value",
            "explicit_value",
            "explicit_list",
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
            assert!(
                differences.is_empty(),
                "{path} debug={debug}: {differences:#?}"
            );
            let od = input.procs.iter().find(|proc_| proc_.name == name).unwrap();
            assert_eq!(
                od.implicit_locate_offsets.len(),
                usize::from(name.starts_with("implicit_"))
            );
        }
    }
}
#[test]
fn forward_global_and_proc_static_constructors_preserve_native_order() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/global_init_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/global_init_order.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    assert_eq!(
        &input.globals.as_ref().unwrap().names[..5],
        ["trace", "A", "B", "SA", "SB"]
    );
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("global_init_order"),
            debug,
        )
        .unwrap();
        let differences = crate::compare::compare_proc_code(
            &native,
            native.world.global_initializer_proc_id() as usize,
            &output.dmb,
            output.dmb.world.global_initializer_proc_id() as usize,
            "/world::<global-init>",
            100,
            true,
        );
        assert!(
            differences.is_empty(),
            "global/static constructors debug={debug}: {differences:#?}"
        );
    }
}
#[test]
fn forward_type_initializers_preserve_native_constructor_side_effect_order() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/class_init_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/class_init_order.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let holder = input
        .types
        .iter()
        .find(|typ| typ.path == "/datum/holder")
        .unwrap();
    assert_eq!(holder.variable_declaration_order, ["a", "b"]);
    let init = |dmb: &Dmb| {
        dmb.classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(b"/datum/holder".as_slice()))
            .unwrap()
            .initializer_proc_id() as usize
    };
    let ctor = |dmb: &Dmb| {
        dmb.procs
            .iter()
            .position(|proc_| dmb.string(proc_.strings[0]) == Some(b"/datum/value/New".as_slice()))
            .unwrap()
    };
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("class_init_order"),
            debug,
        )
        .unwrap();
        for (expected, actual, path) in [
            (init(&native), init(&output.dmb), "/datum/holder::<init>"),
            (ctor(&native), ctor(&output.dmb), "/datum/value/New"),
        ] {
            let differences = crate::compare::compare_proc_code(
                &native,
                expected,
                &output.dmb,
                actual,
                path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{path} debug={debug}: {differences:#?}"
            );
        }
    }
}
#[test]
fn roman_formats_and_ignored_global_overrides_match_native() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for (fixture, paths) in [
        (
            "roman_format",
            vec!["roman_lower", "roman_upper", "roman_mixed"],
        ),
        (
            "global_shadow",
            vec!["definition_first", "override_first", "shadow_calls"],
        ),
    ] {
        let input = OpenDreamProgram::from_path(root.join(format!("{fixture}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(root.join(format!("{fixture}.native.bin"))).unwrap())
                .unwrap();
        let output =
            super::super::translate_named(&input, &baseline, &template, &root, Some(fixture))
                .unwrap();
        for name in paths {
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
        if fixture == "global_shadow" {
            let ghosts: Vec<_> = input
                .procs
                .iter()
                .enumerate()
                .filter(|(_, proc_)| {
                    proc_.attributes & 2 != 0
                        && matches!(proc_.name.as_str(), "definition_first" | "override_first")
                })
                .collect();
            assert_eq!(ghosts.len(), 2);
            for (id, proc_) in ghosts {
                let emitted = output.ids.procs[id];
                assert_ne!(emitted, 0xffff);
                assert_eq!(
                    output
                        .dmb
                        .string(output.dmb.procs[emitted as usize].strings[0]),
                    Some(format!("/{}", proc_.name).as_bytes())
                );
            }
        }
    }
}
#[test]
fn resource_archive_names_preserve_source_spelling_and_external_disk_paths() {
    use crate::rsc::Entry;
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/resource_archive_names.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/resource_archive_names.native.bin"
    ))
    .unwrap();
    let archive = crate::rsc::read_all(&mut std::io::Cursor::new(include_bytes!(
        "../../fixtures/translation/resource_archive_names.native.rsc"
    )))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let asset_index = input
        .resources
        .iter()
        .position(|path| path.ends_with("/external/ExternalAsset.txt"))
        .unwrap();
    let original = input.resources[asset_index].clone();
    // Git can rewrite small text-like assets (including opaque.bin) between LF
    // and CRLF, unlike the bytes captured in the native receipt. Exercise its exact
    // inputs in an isolated root, without weakening content-ID/payload assertions
    // or changing the checked-out fixtures.
    let fixture_root = root;
    let root = std::env::temp_dir().join(format!(
        "dmb-resource-archive-inputs-{}",
        std::process::id()
    ));
    for path in &input.resources {
        let name = &input.resource_archive_names[path][0];
        let resource = archive
            .iter()
            .find_map(|entry| match entry {
                Entry::Named(resource) if resource.name == name.as_bytes() => Some(resource),
                _ => None,
            })
            .unwrap();
        let expected = resource.asset_bytes().unwrap();
        let checkout = std::fs::read(fixture_root.join(path)).unwrap();
        let normalize = |bytes: &[u8]| -> Vec<u8> {
            bytes
                .iter()
                .enumerate()
                .filter_map(|(at, byte)| {
                    if *byte == b'\r' && bytes.get(at + 1) == Some(&b'\n') {
                        None
                    } else {
                        Some(*byte)
                    }
                })
                .collect()
        };
        assert!(
            checkout == expected || normalize(&checkout) == normalize(expected),
            "resource fixture differs beyond checkout line endings: {path}"
        );
        let target = root.join(path);
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(target, expected).unwrap();
    }
    assert_eq!(
        input.resource_archive_names[&original],
        [
            "ExternalAsset.txt",
            "externalasset.txt",
            "./ExternalAsset.txt"
        ]
    );
    let external =
        std::env::temp_dir().join(format!("dmb-external-resource-{}.txt", std::process::id()));
    std::fs::write(&external, std::fs::read(root.join(&original)).unwrap()).unwrap();
    let physical = external.to_string_lossy().replace('\\', "/");
    input.resources[asset_index] = physical.clone();
    for string in &mut input.strings {
        if *string == original {
            *string = physical.clone();
        }
    }
    for value in input.resource_aliases.values_mut() {
        if *value == original {
            *value = physical.clone();
        }
    }
    let names = input.resource_archive_names.remove(&original).unwrap();
    input.resource_archive_names.insert(physical.clone(), names);
    let output = super::super::translate_named(
        &input,
        &baseline,
        &template,
        &root,
        Some("resource_archive_names"),
    )
    .unwrap();
    let named = |entries: &[Entry]| {
        entries
            .iter()
            .filter_map(|entry| match entry {
                Entry::Named(resource) => Some((
                    (resource.kind, resource.id, resource.name.clone()),
                    resource.asset_bytes().unwrap().to_vec(),
                )),
                _ => None,
            })
            .collect::<std::collections::BTreeMap<_, _>>()
    };
    let expected = named(&archive);
    let actual = named(&output.resources);
    let keys = |entries: &std::collections::BTreeMap<(u8, u32, Vec<u8>), Vec<u8>>| {
        entries
            .keys()
            .map(|(kind, id, name)| (*kind, *id, String::from_utf8_lossy(name).into_owned()))
            .collect::<Vec<_>>()
    };
    assert_eq!(
        keys(&expected),
        keys(&actual),
        "native archive names, kinds and content IDs"
    );
    for (key, bytes) in &expected {
        assert_eq!(
            &actual[key],
            bytes,
            "archive payload {}",
            String::from_utf8_lossy(&key.2)
        );
    }
    for name in ["resource_names", "resource_kinds"] {
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
    // An external physical path needs explicit exporter provenance.
    input.resource_archive_names.remove(&physical);
    assert!(crate::od_emit::emit_with_baseline(&input, Some(&baseline), &template, &root).is_err());
    std::fs::remove_file(external).unwrap();
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn rgb_constants_match_native_channels_alpha_and_hue_normalization() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let input = OpenDreamProgram::from_path(root.join("numeric_rgb_constants.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("../native_template_savefile_5161687.json")).unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("../native_template.bin")).unwrap()).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(root.join("numeric_rgb_constants.native.bin")).unwrap())
            .unwrap();
    let authored = [
        ("/datum/numeric_rgb_probe", 624),
        ("/datum/hue_probe", 29),
        ("/datum/component_probe", 20),
    ];
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("numeric_rgb_constants"),
            debug,
        )
        .unwrap();
        let options = crate::compare::CompareOptions {
            authored_prefixes: authored.iter().map(|(path, _)| (*path).into()).collect(),
            ..Default::default()
        };
        let differences = crate::compare::compare_dmbs(&native, &output.dmb, &options);
        assert!(differences.is_empty(), "debug={debug}: {differences:#?}");
        for (path, count) in authored {
            let class = output
                .dmb
                .classes
                .iter()
                .position(|class| {
                    output.dmb.string(class.path_string_id()) == Some(path.as_bytes())
                })
                .unwrap();
            assert!(
                output.dmb.class_variable_declarations(class).unwrap().len() >= count,
                "missing RGB constants in {path}"
            );
        }
    }
}
