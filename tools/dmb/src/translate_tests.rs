use super::{Dmb, OpenDreamProgram};
use std::path::Path;
#[test]
fn inherited_upward_proc_references_preserve_native_targets_and_names() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/inherited_proc_refs.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/inherited_proc_refs.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/proc_reference_paths.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/proc_reference_paths.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/global_parameter_declaration.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/global_parameter_declaration.native.bin"
    ))
    .unwrap();
    assert!(!input
        .types
        .iter()
        .any(|typ| typ.path == "/var" || typ.path == "/var/global_parameter_value"));
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/procedure_membership_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/procedure_membership_order.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::translate_named_debug(
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
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
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
    let resolver = super::Resolver {
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for (name, input_bytes, native_bytes) in [
        (
            "global_verb_path",
            include_bytes!("../fixtures/translation/global_verb_path.json").as_slice(),
            include_bytes!("../fixtures/translation/global_verb_path.native.bin").as_slice(),
        ),
        (
            "resource_initializers",
            include_bytes!("../fixtures/translation/resource_initializers.json").as_slice(),
            include_bytes!("../fixtures/translation/resource_initializers.native.bin").as_slice(),
        ),
    ] {
        let input = OpenDreamProgram::from_slice(input_bytes).unwrap();
        let native = Dmb::from_bytes(native_bytes).unwrap();
        let output =
            super::translate_named_debug(&input, &baseline, &template, &root, Some(name), false)
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/locate_forms.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/locate_forms.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/global_init_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/global_init_order.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    assert_eq!(
        &input.globals.as_ref().unwrap().names[..5],
        ["trace", "A", "B", "SA", "SB"]
    );
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/class_init_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/class_init_order.native.bin"
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
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
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
            super::translate_named(&input, &baseline, &template, &root, Some(fixture)).unwrap();
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/resource_archive_names.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/resource_archive_names.native.bin"
    ))
    .unwrap();
    let archive = crate::rsc::read_all(&mut std::io::Cursor::new(include_bytes!(
        "../fixtures/translation/resource_archive_names.native.rsc"
    )))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let asset_index = input
        .resources
        .iter()
        .position(|path| path.ends_with("/external/ExternalAsset.txt"))
        .unwrap();
    let original = input.resources[asset_index].clone();
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
    std::fs::write(
        &external,
        include_bytes!(
            "../fixtures/translation/resource_archive_assets/external/ExternalAsset.txt"
        ),
    )
    .unwrap();
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
    let output = super::translate_named(
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
        let output = super::translate_named_debug(
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
    let output = super::translate_named(
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
            super::translate_named(&input, &baseline, &template, &root, Some(fixture)).unwrap();
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
    let output = super::translate_named(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/lowering/gradient_forms.json"))
            .unwrap();
    let native =
        Dmb::from_bytes(include_bytes!("../fixtures/lowering/gradient_forms.bin")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/lowering/text_builtins.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!("../fixtures/lowering/text_builtins.bin")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let names: Vec<_> = input
        .procs
        .iter()
        .filter(|p| p.name.starts_with("text_") && p.name != "text_probe")
        .map(|p| format!("/proc/{}", p.name))
        .collect();
    assert_eq!(names.len(), 29);
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/call_frames.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/call_frames.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output =
        super::translate_named(&input, &baseline, &template, &root, Some("call_frames")).unwrap();
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/dynamic_call_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/dynamic_call_order.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/type_category_alias.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/type_category_alias.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::translate_named(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/global_vars_value.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/global_vars_value.native.bin"
    ))
    .unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let output = super::translate_named(
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
    let output = super::translate_named(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/receiver_field_argument.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/receiver_field_argument.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let emitted = super::translate_named_debug(
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
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/self_call_names.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/self_call_names.bin"))
            .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let output =
        super::translate_named(&input, &baseline, &template, &root, Some("self_call_names"))
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
        "../fixtures/native_template_nativemethods_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for (name, json, native_bytes) in [
        (
            "method_names",
            include_bytes!("../fixtures/translation/method_names.json").as_slice(),
            include_bytes!("../fixtures/translation/method_names.native.bin").as_slice(),
        ),
        (
            "method_names_reversed",
            include_bytes!("../fixtures/translation/method_names_reversed.json").as_slice(),
            include_bytes!("../fixtures/translation/method_names_reversed.native.bin").as_slice(),
        ),
    ] {
        let input = crate::opendream::OpenDreamProgram::from_slice(json).unwrap();
        let native = crate::dmb::Dmb::from_bytes(native_bytes).unwrap();
        let output =
            super::translate_named(&input, &baseline, &template, &root, Some(name)).unwrap();
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
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    dmb.header.flags &= !0x4000_0000;
    dmb.lists.resize(0xffff, Vec::new());
    let id = super::append_code_list(&mut dmb, vec![0x50, 7, 0x12, 0]);
    assert_eq!(id, 0x10000);
    assert!(dmb.lists[0xffff].is_empty());
    dmb.procs[0].code_locals_args[0] = id;
    let decoded = crate::dmb::Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
    assert_eq!(decoded.proc_code_words(0).unwrap(), vec![0x50, 7, 0x12, 0]);
    assert!(decoded.header.flags & 0x4000_0000 != 0);
}

#[test]
fn adversarial_cache_mutations_match_native_receiver_order() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/cache_adversarial.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/cache_adversarial.bin"))
            .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    // These enumerate authored procedures explicitly: a missing match must
    // fail instead of silently selecting zero records. Six additional
    // fixture procedures document known equivalent cache materialization
    // layouts; this gate checks exact semantic instruction parity for the
    // mutation/order cases below, including every guarded field mutation.
    let names = [
        "change_values",
        "change_child",
        "mutate_key",
        "index_post_key",
        "index_post_rhs",
        "index_assign_rhs",
        "index_append_rhs",
        "index_two_mutations",
        "index_nested_post",
        "index_conditional_post",
        "method_argument_post",
        "method_argument_receiver",
        "method_safe_argument_receiver",
        "index_post_nested_calls",
        "get_box",
        "get_values",
        "index_call_receiver",
        "index_double_rhs",
        "field_assign_rhs",
        "field_safe_postfix",
        "index_conditional_receiver_call",
        "index_rhs_nested_postfix",
        "field_rhs_nested_postfix",
        "index_logical_rhs",
        "index_logical_key_mutation",
        "field_logical_rhs",
        "field_safe_preinc",
        "field_safe_postdec",
        "field_safe_statement",
        "field_safe_append_rhs",
        "field_inner_safe_postfix",
        "field_safe_rhs_safe",
        "field_safe_indexed_owner",
        "field_safe_chain_assign",
        "field_safe_nested_guard",
        "field_safe_indexed_append",
        "field_safe_indexed_preinc",
        "field_safe_indexed_postdec",
        "field_safe_nested_append",
        "field_safe_indexed_append_field_rhs",
        "field_safe_indexed_nested_guard",
        "field_safe_indexed_conditional_key",
        "field_safe_indexed_mutating_key",
        "field_safe_rhs_safe_postfix",
        "field_safe_rhs_safe_prefix",
        "field_safe_rhs_safe_compound",
        "field_safe_triple_postfix",
        "field_safe_triple_append",
        "field_safe_triple_nested",
        "field_safe_rhs_safe_logical",
        "field_safe_indexed_logical",
        "field_safe_indexed_logical_constant",
        "field_safe_nested_indexed_logical",
        "field_safe_assign_into",
        "field_safe_indexed_assign_into",
        "field_safe_direct_assign_into",
        "field_safe_nested_assign_into",
        "field_safe_statement_assign_into",
        "field_safe_direct_assign_into_conditional",
        "field_safe_indexed_assign_into_conditional",
    ];
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("cache_adversarial"),
            debug,
        )
        .unwrap();
        for name in names {
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
                &output.dmb,
                find(&output.dmb),
                &path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
        for name in ["/datum/cache_box", "/datum/cache_leaf"] {
            assert!(native
                .classes
                .iter()
                .any(|class| native.string(class.path_string_id()) == Some(name.as_bytes())));
            assert!(output
                .dmb
                .classes
                .iter()
                .any(|class| output.dmb.string(class.path_string_id()) == Some(name.as_bytes())));
        }
    }
}

#[test]
fn declaration_blocks_preserve_owners_without_phantom_runtime_types() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/declaration_namespaces.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/declaration_namespaces.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let expected_paths = vec![
        "/datum/declaration_owner".to_string(),
        "/datum/declaration_owner/list".to_string(),
    ];
    let mut exported_paths: Vec<_> = input
        .types
        .iter()
        .filter(|typ| typ.path.starts_with("/datum/declaration_owner"))
        .map(|typ| typ.path.clone())
        .collect();
    exported_paths.sort();
    assert_eq!(exported_paths, expected_paths);
    for forbidden in [
        "/proc",
        "/datum/declaration_owner/var",
        "/datum/declaration_owner/var/tmp",
        "/datum/declaration_owner/var/list",
        "/datum/declaration_owner/proc",
        "/datum/declaration_owner/verb",
    ] {
        assert!(
            !input.types.iter().any(|typ| typ.path == forbidden),
            "{forbidden}"
        );
    }
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("declaration_namespaces"),
            debug,
        )
        .unwrap();
        let paths = |dmb: &crate::dmb::Dmb| {
            let mut paths: Vec<_> = dmb
                .classes
                .iter()
                .filter_map(|class| dmb.string(class.path_string_id()))
                .filter(|path| path.starts_with(b"/datum/declaration_owner"))
                .map(|path| String::from_utf8(path.to_vec()).unwrap())
                .collect();
            paths.sort();
            paths
        };
        assert_eq!(paths(&native), expected_paths);
        assert_eq!(paths(&output.dmb), expected_paths);
        let differences: Vec<_> = crate::compare::compare_class_tables(&native, &output.dmb, 1000)
            .into_iter()
            .filter(|difference| difference.path.starts_with("/datum/declaration_owner"))
            .collect();
        assert!(differences.is_empty(), "debug={debug}: {differences:#?}");
        for path in [
            "/datum/declaration_owner/proc/declaration_method",
            "/datum/declaration_owner/verb/declaration_verb",
            "/proc/declaration_global",
            "/proc/declaration_values",
        ] {
            for dmb in [&native, &output.dmb] {
                assert!(
                    dmb.procs
                        .iter()
                        .any(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes())),
                    "debug={debug} missing {path}"
                );
            }
        }
    }
}

#[test]
fn conditional_initial_saved_index_operands_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/initial_saved_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/initial_saved_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("initial_saved_branches"),
            debug,
        )
        .unwrap();
        for name in [
            "initial_key",
            "initial_owner",
            "initial_both",
            "initial_short",
            "saved_key",
            "saved_owner",
            "saved_both",
            "saved_short",
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
                &output.dmb,
                find(&output.dmb),
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
fn repeated_root_receivers_preserve_native_frozen_binding_values() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/cache_binding_freeze/probe.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/cache_binding_freeze/probe.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures/translation/cache_binding_freeze");
    for debug in [false, true] {
        let output =
            super::translate_named_debug(&input, &baseline, &template, &root, Some("probe"), debug)
                .unwrap();
        for path in [
            "/proc/global_binding",
            "/proc/argument_binding",
            "/proc/global_binding_statements",
            "/proc/global_explicit_rebind",
            "/proc/argument_explicit_rebind",
            "/proc/local_binding",
            "/proc/local_explicit_rebind",
            "/proc/field_mutation",
            "/proc/nested_argument",
            "/proc/branch_owner",
            "/proc/world_calls",
            "/proc/argument_index_rebind",
            "/proc/global_index_rebind",
            "/proc/local_unrelated_write",
            "/proc/field_read",
            "/proc/field_write",
            "/proc/field_compound",
            "/proc/index_access",
            "/proc/branch_same_owner",
            "/proc/global_nested_other",
            "/proc/replace_global",
            "/proc/unrelated_helper",
            "/proc/global_helper_replace",
            "/proc/global_helper_unrelated",
            "/proc/branch_replacement",
            "/proc/branch_before_after",
            "/proc/switch_replacement",
            "/proc/branch_write",
            "/proc/branch_existing_write",
            "/proc/new_boundary",
            "/datum/cache_binding/proc/self_boundary",
            "/datum/cache_binding/proc/parent_boundary",
            "/datum/cache_binding/sub/parent_boundary",
            "/datum/cache_binding/sub/New",
            "/datum/cache_binding/proc/src_calls",
        ] {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}

#[test]
fn null_equality_preserves_native_eval_cleanup() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/null_equality_ownership/probe.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/null_equality_ownership/probe.native.bin"
    ))
    .unwrap();
    let managed_id = native
        .procs
        .iter()
        .position(|proc| {
            native.string(proc.strings[0]) == Some(b"/datum/null_scratch/proc/managed".as_slice())
        })
        .unwrap();
    let managed_body =
        crate::bytecode::decode(native.proc_code_words(managed_id).unwrap()).unwrap();
    assert_eq!(
        managed_body
            .iter()
            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
            .map(|item| item.opcode)
            .collect::<Vec<_>>(),
        [0x50, 0x1a, 0x12, 0]
    );
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures/translation/null_equality_ownership");
    for debug in [false, true] {
        let output =
            super::translate_named_debug(&input, &baseline, &template, &root, Some("probe"), debug)
                .unwrap();
        for name in [
            "equal_null",
            "builtin_null",
            "global_equal_null",
            "global_not_equal_null",
            "field_equal_null",
            "variable_equal_null",
            "negated_equal_null",
            "branch_equal_null",
            "literal_null",
            "literal_not_null",
            "const_alias_equal_null",
            "local_const_alias_equal_null",
            "parenthesized_literal_null",
            "null_sound",
            "null_image",
            "null_icon",
            "null_new",
            "global_managed",
            "reversed_equal_null",
            "reversed_not_equal_null",
            "conditional_equal_null",
            "conditional_left_null",
            "ordinary_null_return",
            "parenthesized_equal_null",
            "assigned_null",
            "local_assigned_null",
            "field_assigned_null",
            "list_null",
            "argument_null",
            "interpolation_null",
            "switched_null",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            for dmb in [&native, &output.dmb] {
                let items =
                    crate::bytecode::decode(dmb.proc_code_words(find(dmb)).unwrap()).unwrap();
                if name == "builtin_null" {
                    assert!(items.iter().any(|item| item.opcode == 0x9e));
                    assert!(!items.iter().any(|item| matches!(item.opcode, 0x37 | 0x38)));
                } else if name.contains("equal_null")
                    || matches!(
                        name,
                        "conditional_left_null"
                            | "literal_null"
                            | "literal_not_null"
                            | "parenthesized_literal_null"
                    )
                {
                    let comparison = if matches!(
                        name,
                        "global_not_equal_null" | "reversed_not_equal_null" | "literal_not_null"
                    ) {
                        0x38
                    } else {
                        0x37
                    };
                    assert!(
                        items.iter().any(|item| item.opcode == comparison),
                        "missing authored comparison debug={debug} {path}"
                    );
                    assert!(
                        !items.iter().any(|item| item.opcode == 0x9e),
                        "authored comparison became IsNull debug={debug} {path}"
                    );
                }
            }
            let null_reads = |dmb: &crate::dmb::Dmb| {
                crate::bytecode::decode(dmb.proc_code_words(find(dmb)).unwrap())
                    .unwrap()
                    .iter()
                    .filter(|item| item.opcode == 0x33 && item.operands == [0xffe6])
                    .count()
            };
            let expected_reads = null_reads(&native);
            assert_eq!(
                null_reads(&output.dmb),
                expected_reads,
                "native Null reader count debug={debug} {path}"
            );
            if !matches!(name, "builtin_null" | "global_managed" | "switched_null") {
                assert!(expected_reads > 0, "missing authored null load {path}");
            }
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
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}

#[test]
fn self_call_discard_preserves_native_managed_result_ownership() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/self_call_ownership.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/self_call_ownership.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("self_call_ownership"),
            debug,
        )
        .unwrap();
        for name in [
            "discard",
            "named",
            "with_args",
            "value",
            "choice",
            "reverse",
            "multiline",
        ] {
            let path = format!("/datum/ownership/proc/{name}");
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let call_modes = |dmb: &crate::dmb::Dmb| {
                let items =
                    crate::bytecode::decode(dmb.proc_code_words(find(dmb)).unwrap()).unwrap();
                for pair in items.windows(2) {
                    if pair[0].opcode == 0x2a {
                        assert_eq!(
                            pair[1].opcode, 0x51,
                            "raw CallStatement skip marker debug={debug} {path}"
                        );
                    }
                }
                items
                    .into_iter()
                    .filter(|item| matches!(item.opcode, 0x29 | 0x2a))
                    .map(|item| item.opcode)
                    .collect::<Vec<_>>()
            };
            let native_modes = call_modes(&native);
            assert!(!native_modes.is_empty(), "missing authored call {path}");
            assert_eq!(
                native_modes,
                call_modes(&output.dmb),
                "debug={debug} {path}"
            );
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
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}

#[test]
fn computed_call_discard_preserves_native_managed_result_ownership() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/computed_call_ownership.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/computed_call_ownership.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("computed_call_ownership"),
            debug,
        )
        .unwrap();
        for name in [
            "computed_empty",
            "computed_positional",
            "computed_named",
            "computed_arglist",
            "computed_conditional",
            "computed_short",
            "computed_value",
            "computed_safe",
            "direct_child",
            "direct_owner",
            "direct_multiline",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let call_modes = |dmb: &crate::dmb::Dmb| {
                let items =
                    crate::bytecode::decode(dmb.proc_code_words(find(dmb)).unwrap()).unwrap();
                for pair in items.windows(2) {
                    if pair[0].opcode == 0x2a {
                        assert_eq!(
                            pair[1].opcode, 0x51,
                            "raw CallStatement skip marker debug={debug} {path}"
                        );
                    }
                }
                items
                    .into_iter()
                    .filter(|item| matches!(item.opcode, 0x29 | 0x2a))
                    .map(|item| item.opcode)
                    .collect::<Vec<_>>()
            };
            let native_modes = call_modes(&native);
            assert!(!native_modes.is_empty(), "missing authored call {path}");
            assert_eq!(
                native_modes,
                call_modes(&output.dmb),
                "debug={debug} {path}"
            );
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
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}

#[test]
fn assignment_into_and_dynamic_initial_saved_match_native_forms() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/operator_probe.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/operator_probe.bin"))
            .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let code = |dmb: &crate::dmb::Dmb, name: &str| {
        let path = if name.starts_with('/') {
            name.to_string()
        } else {
            format!("/proc/{name}")
        };
        let id = dmb
            .procs
            .iter()
            .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        crate::bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap()
    };
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("operator_probe"),
            debug,
        )
        .unwrap();
        for name in [
            "world_cache_src_assignment",
            "world_cache_index_mutation",
            "world_cache_chain_mutation",
            "world_cache_call",
            "world_cache_join",
            "world_cache_short_circuit",
            "world_cache_loop",
            "/datum/op_probe/proc/world_cache_own_assignment",
        ] {
            for dmb in [&native, &output.dmb] {
                let world_time_reads = code(dmb, name).iter().filter(|item| {
                        item.opcode == 0x33 && item.typed_operands().unwrap().iter().any(|operand| {
                            let crate::bytecode::Operand::Variable(crate::operands::Variable::SetCache(owner, field)) = operand else { return false; };
                            **owner == crate::operands::Variable::World && matches!(field.as_ref(),
                                crate::operands::Variable::Field(id) if dmb.string(*id) == Some(b"time"))
                        })
                    }).count();
                assert_eq!(world_time_reads, 2, "debug={debug} {name} must explicitly restore world after other receiver writes");
            }
        }
        for name in [
            "assign_into_local",
            "assign_into_field",
            "assign_into_index",
        ] {
            for dmb in [&native, &output.dmb] {
                let instructions = code(dmb, name);
                assert_eq!(
                    instructions
                        .iter()
                        .filter(|item| item.opcode == 0x15a)
                        .count(),
                    2,
                    "debug={debug} {name}"
                );
                let executable: Vec<_> = instructions
                    .iter()
                    .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .collect();
                let retained = executable
                    .iter()
                    .position(|item| item.opcode == 0x13f)
                    .unwrap();
                assert_eq!(executable[retained - 1].opcode, 0x15a);
                assert_eq!(executable[retained + 1].opcode, 0x12);
            }
        }
        for name in [
            "initial_index",
            "initial_args_index",
            "saved_index",
            "logical_field",
            "logical_safe",
            "shared_pop_aug",
            "shared_pop_sub",
            "shared_pop_post",
            "shared_pop_pre",
            "shared_pop_index",
            "shared_pop_assign_into",
            "shared_pop_assign",
            "shared_pop_logical_or",
            "shared_pop_logical_and",
            "shared_pop_logical_reverse",
            "shared_pop_logical_index",
            "nested_safe_rhs_aug",
            "nested_safe_rhs_into",
            "single_safe_index_rhs_aug",
            "single_safe_index_rhs_into",
            "assign_into_local_branch",
            "assign_into_field_branch",
            "assign_into_index_branch",
            "assign_into_index_key",
            "assign_into_index_owner",
            "assign_into_index_logical",
            "assign_into_nested_rhs",
            "world_cache_bare_world",
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
                &output.dmb,
                find(&output.dmb),
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
fn multidimensional_short_circuit_sizes_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/multidimensional_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/multidimensional_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("multidimensional_branches"),
            debug,
        )
        .unwrap();
        for path in ["/proc/md_short", "/proc/md_nested"] {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn prompt_branch_arguments_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/prompt_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/prompt_branches.bin"))
            .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("prompt_branches"),
            debug,
        )
        .unwrap();
        for path in [
            "/proc/prompt_cond",
            "/proc/prompt_short",
            "/proc/prompt_nested",
            "/proc/prompt_omitted",
            "/proc/prompt_text",
        ] {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn range_and_weighted_pick_branch_operands_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/range_pick_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/range_pick_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("range_pick_branches"),
            debug,
        )
        .unwrap();
        for path in [
            "/proc/range_cond",
            "/proc/range_short",
            "/proc/pick_cond",
            "/proc/pick_value",
        ] {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn output_branch_operands_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/output_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/output_branches.bin"))
            .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("output_branches"),
            debug,
        )
        .unwrap();
        for path in ["/proc/out_field", "/proc/out_index", "/proc/out_receiver"] {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn current_and_parent_arglist_calls_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/self_arglist.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/self_arglist.bin"))
            .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("self_arglist"),
            debug,
        )
        .unwrap();
        for path in [
            "/proc/self_arglist",
            "/proc/sound_arglist",
            "/proc/image_arglist",
            "/datum/self_base/child/parent_arglist",
        ] {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn direct_builtin_and_root_arglist_calls_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/arglist_builtin_forms.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/arglist_builtin_forms.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("arglist_builtin_forms"),
            debug,
        )
        .unwrap();
        for path in [
            "/proc/arglist_sound",
            "/proc/arglist_image",
            "/proc/arglist_self",
            "/proc/arglist_root_super",
        ] {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn file_arglist_constructor_matches_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/arglist_file.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/arglist_file.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("arglist_file"),
            debug,
        )
        .unwrap();
        let path = "/proc/probe";
        let find = |dmb: &crate::dmb::Dmb| {
            dmb.procs
                .iter()
                .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
        assert!(
            differences.is_empty(),
            "debug={debug} {path}: {differences:#?}"
        );
    }
}
#[test]
fn database_constructors_ignore_authored_arguments_like_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/database_constructor_arguments.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/database_constructor_arguments.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("database_constructor_arguments"),
            debug,
        )
        .unwrap();
        for kind in ["con", "query"] {
            for form in ["empty", "positional", "named", "arglist", "two"] {
                let path = format!("/proc/db_{kind}_{form}");
                let find = |dmb: &crate::dmb::Dmb| {
                    dmb.procs
                        .iter()
                        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
                    "debug={debug} {path}: {differences:#?}"
                );
                let instructions =
                    crate::bytecode::decode(output.dmb.proc_code_words(find(&output.dmb)).unwrap())
                        .unwrap();
                assert!(
                    !instructions
                        .iter()
                        .any(|item| matches!(item.opcode, 0x29 | 0x30 | 0x1a)),
                    "ignored arguments must not evaluate db_effect"
                );
            }
        }
    }
}
#[test]
fn comprehensive_prompt_type_unions_and_choices_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/prompt_type_unions.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/prompt_type_unions.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    let paths = (0..132)
        .map(|i| format!("/proc/prompt_union_{i}"))
        .chain((0..4).map(|i| format!("/proc/prompt_null_choices_{i}")))
        .chain((0..8).map(|i| format!("/proc/prompt_special_{i}")))
        .collect::<Vec<_>>();
    assert_eq!(paths.len(), 144);
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("prompt_type_unions"),
            debug,
        )
        .unwrap();
        for path in &paths {
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap_or_else(|| panic!("missing {path}"))
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
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
#[test]
fn reordered_arguments_keep_world_receivers_on_every_path() {
    use crate::bytecode::Operand;
    use crate::operands::Variable;
    fn prove_and_canonicalize(dmb: &crate::dmb::Dmb, proc_id: usize) -> crate::dmb::Dmb {
        let instructions = crate::bytecode::decode(dmb.proc_code_words(proc_id).unwrap()).unwrap();
        fn visit(
            dmb: &crate::dmb::Dmb,
            variable: &Variable,
            cache: &mut Option<String>,
        ) -> Option<String> {
            match variable {
                Variable::World => Some("world".into()),
                Variable::Src => Some("src".into()),
                Variable::SetCache(owner, selector) => {
                    *cache = visit(dmb, owner, cache);
                    visit(dmb, selector, cache)
                }
                Variable::Field(id) => {
                    if dmb.string(*id) == Some(b"time") {
                        assert_eq!(
                            cache.as_deref(),
                            Some("world"),
                            "time must resolve on World on every incoming path"
                        );
                    }
                    None
                }
                _ => None,
            }
        }
        let mut pending = std::collections::VecDeque::from([(0usize, None::<String>)]);
        let mut seen = std::collections::HashSet::new();
        let mut time_reads = std::collections::HashSet::new();
        while let Some((index, mut cache)) = pending.pop_front() {
            if index >= instructions.len() || !seen.insert((index, cache.clone())) {
                continue;
            }
            let instruction = &instructions[index];
            for operand in instruction.typed_operands().unwrap() {
                if let Operand::Variable(variable) = operand {
                    let before = cache.clone();
                    visit(dmb, &variable, &mut cache);
                    fn time(dmb: &crate::dmb::Dmb, variable: &Variable) -> bool {
                        match variable {
                            Variable::Field(id) => dmb.string(*id) == Some(b"time"),
                            Variable::SetCache(_, selector) => time(dmb, selector),
                            _ => false,
                        }
                    }
                    if time(dmb, &variable) {
                        time_reads.insert(index);
                    }
                    if instruction.opcode == 0x34 && variable == Variable::Cache {
                        cache = None;
                    }
                    if matches!(instruction.opcode, 0x29 | 0x2a)
                        && !matches!(cache.as_deref(), Some("src" | "world"))
                    {
                        cache = before.filter(|root| root == "src" || root == "world");
                    }
                }
            }
            for target in instruction.branch_targets().unwrap() {
                let destination = instructions
                    .iter()
                    .position(|item| item.offset == target as usize)
                    .expect("branch boundary");
                pending.push_back((destination, cache.clone()));
            }
            if !matches!(instruction.opcode, 0 | 0x12 | 0xf | 0x79 | 0xb1) {
                pending.push_back((index + 1, cache));
            }
        }
        assert!(
            time_reads.len() >= 3,
            "receiver proof must cover several authored World accesses"
        );
        // Only after proving receiver identity on every path, remove the
        // optional repeated World selector for structural comparison.
        let mut canonical = instructions.clone();
        for instruction in &mut canonical {
            if instruction.opcode == 0x33 {
                if let Ok((Variable::SetCache(owner, selector), _)) =
                    Variable::decode(&instruction.operands)
                {
                    if *owner == Variable::World && matches!(*selector, Variable::Field(_)) {
                        instruction.operands = selector.encode();
                    }
                }
            }
        }
        let mut positions = std::collections::HashMap::new();
        let mut length = 0;
        for (old, new) in instructions.iter().zip(&canonical) {
            positions.insert(old.offset as u32, length as u32);
            length += 1 + new.operands.len();
        }
        for instruction in &mut canonical {
            let slots: Vec<usize> = match instruction.opcode {
                0xf | 0x10 | 0x11 | 0xb2 | 0xb3 => vec![0],
                0x79 => (0..instruction.operands[0] as usize)
                    .map(|i| 2 + 2 * i)
                    .chain(std::iter::once(instruction.operands.len() - 1))
                    .collect(),
                0xb1 => (1..instruction.operands.len()).collect(),
                _ => {
                    assert!(
                        instruction.branch_targets().unwrap().is_empty(),
                        "unmodeled fixture branch"
                    );
                    vec![]
                }
            };
            for slot in slots {
                instruction.operands[slot] = positions[&instruction.operands[slot]];
            }
        }
        let words = canonical
            .into_iter()
            .flat_map(|instruction| std::iter::once(instruction.opcode).chain(instruction.operands))
            .collect();
        let mut copy = dmb.clone();
        let list = copy.procs[proc_id].code_locals_args[0] as usize;
        copy.lists[list] = words;
        copy
    }
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/reordered_cache.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/reordered_cache.bin"))
            .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("reordered_cache"),
            debug,
        )
        .unwrap();
        for name in [
            "prompt_before",
            "prompt_after",
            "prompt_conditional",
            "prompt_getter",
            "range_world",
            "range_conditional",
            "pick_world_weights",
            "pick_world_literals",
        ] {
            let path = format!("/datum/reordered_cache/proc/{name}");
            let find = |dmb: &crate::dmb::Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let expected_id = find(&native);
            let actual_id = find(&output.dmb);
            let expected = prove_and_canonicalize(&native, expected_id);
            let actual = prove_and_canonicalize(&output.dmb, actual_id);
            let differences = crate::compare::compare_proc_code(
                &expected,
                expected_id,
                &actual,
                actual_id,
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
