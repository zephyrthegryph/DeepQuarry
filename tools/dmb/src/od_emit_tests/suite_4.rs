use super::*;

#[test]
fn literal_only_global_initializer_becomes_variable_default() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/variables.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.ids.global_init_proc, None);
    assert_eq!(emitted.dmb.world.global_initializer_proc_id(), NONE);
    let calls = emitted
        .dmb
        .variables
        .iter()
        .find(|variable| emitted.dmb.string(variable.name) == Some(&b"calls"[..]))
        .unwrap();
    assert_eq!((calls.kind, calls.value), (42, 0));
}

#[test]
fn authored_static_global_is_declared_on_owning_class() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/list_constants.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let class = emitted
        .dmb
        .classes
        .iter()
        .find(|class| {
            emitted.dmb.string(class.path_string_id()) == Some(&b"/datum/fixture_lists"[..])
        })
        .unwrap();
    let declarations = &emitted.dmb.lists[class.defining_variable_list_id() as usize];
    assert!(declarations.chunks_exact(2).any(|pair| {
        let var = &emitted.dmb.variables[pair[0] as usize];
        emitted.dmb.string(var.name) == Some(&b"shared"[..]) && pair[1] == 1 && var.kind == 62
    }));
}

#[test]
fn temporary_static_annotation_sets_class_declaration_flag_five() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/list_constants.json"
    ))
    .unwrap();
    let id = input
        .types
        .iter()
        .find(|typ| typ.path == "/datum/fixture_lists")
        .unwrap()
        .global_variables["shared"];
    input
        .globals
        .as_mut()
        .unwrap()
        .temporary_global_ids
        .insert(id);
    let dmb = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/fixture_lists"))
        .unwrap();
    let declaration = dmb
        .class_variable_declarations(class_id)
        .unwrap()
        .into_iter()
        .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"shared"))
        .unwrap();
    assert_eq!(declaration.1, 5);
}

#[test]
fn static_const_declaration_uses_native_flag_three() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/static_const.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let class = emitted
        .dmb
        .classes
        .iter()
        .find(|class| {
            emitted.dmb.string(class.path_string_id()) == Some(&b"/datum/static_const"[..])
        })
        .unwrap();
    let declarations = &emitted.dmb.lists[class.defining_variable_list_id() as usize];
    assert_eq!(declarations.len(), 2);
    assert_eq!(declarations[1], 3);
    let variable = &emitted.dmb.variables[declarations[0] as usize];
    assert_eq!(variable.number(), Some(7.0));
}

#[test]
fn class_const_footer_matches_paired_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/class_const.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/class_const.native.bin"
    ))
    .unwrap();
    let summary = |dmb: &Dmb| {
        let class_id = dmb
            .classes
            .iter()
            .position(|class| {
                dmb.string(class.path_string_id()) == Some(b"/obj/class_const_fixture")
            })
            .unwrap();
        let declarations = dmb.class_variable_declarations(class_id).unwrap();
        ["TAG_LOCAL_CONST", "TAG_STATIC_CONST", "TAG_MUTABLE"].map(|name| {
            let (id, flag) = declarations
                .iter()
                .copied()
                .find(|(id, _)| {
                    dmb.string(dmb.variables[*id as usize].name) == Some(name.as_bytes())
                })
                .unwrap();
            let footer = dmb
                .global_variable_flags()
                .unwrap()
                .into_iter()
                .find(|(footer_id, _)| *footer_id == id);
            (flag, footer.map(|(_, flags)| flags))
        })
    };
    assert_eq!(summary(&emitted), summary(&native));
    assert_eq!(summary(&native), [(3, Some(3)), (3, Some(3)), (0, None)]);
}

#[test]
fn proc_local_consts_preserve_duplicate_footer_names() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/proc_const.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/proc_const.native.bin"
    ))
    .unwrap();
    let summary = |dmb: &Dmb| {
        let mut values: Vec<_> = dmb
            .global_variable_flags()
            .unwrap()
            .into_iter()
            .filter_map(|(id, flags)| {
                let variable = &dmb.variables[id as usize];
                let name = dmb.string(variable.name)?;
                if name != b"LOCAL_TEXT" && name != b"LOCAL_ZERO" {
                    return None;
                }
                let value = if variable.kind == 6 {
                    dmb.string(variable.value)?.to_vec()
                } else if variable.kind == 42 {
                    variable.number()?.to_string().into_bytes()
                } else {
                    return None;
                };
                Some((name.to_vec(), flags, value))
            })
            .collect();
        values.sort();
        values
    };
    assert_eq!(summary(&emitted), summary(&native));
    assert_eq!(
        summary(&native),
        vec![
            (b"LOCAL_TEXT".to_vec(), 3, b"a".to_vec()),
            (b"LOCAL_TEXT".to_vec(), 3, b"b".to_vec()),
            (b"LOCAL_ZERO".to_vec(), 3, b"0".to_vec())
        ]
    );
}

#[test]
fn verb_sources_match_paired_dream_maker_metadata() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/verb_source_all.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verb_source_all.native.bin"
    ))
    .unwrap();
    for name in [
        "v_inoview",
        "v_usr",
        "v_inusr",
        "v_usrloc",
        "v_world",
        "v_inworld",
        "v_default",
    ] {
        let metadata = |dmb: &Dmb| {
            let proc = dmb
                .procs
                .iter()
                .find(|proc| {
                    dmb.string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            (
                proc.source_kind,
                proc.source_parameter,
                proc.effective_flags(),
            )
        };
        assert_eq!(metadata(&emitted), metadata(&native), "{name}");
    }
}

#[test]
fn omitted_verb_source_radius_uses_native_parameter_125() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/verb_source_default_range.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verb_source_default_range.native.bin"
    ))
    .unwrap();
    for name in [
        "v_view_default",
        "v_inview_default",
        "v_oview_default",
        "v_inoview_default",
        "v_range_default",
        "v_inrange_default",
    ] {
        let metadata = |dmb: &Dmb| {
            let proc = dmb
                .procs
                .iter()
                .find(|proc| {
                    dmb.string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            (
                proc.source_kind,
                proc.source_parameter,
                proc.effective_flags(),
            )
        };
        assert_eq!(metadata(&emitted), metadata(&native), "{name}");
        assert_eq!(metadata(&native).1, 125);
    }
}

#[test]
fn verb_source_edge_variants_match_paired_native_metadata() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/verb_source_edge.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verb_source_edge.native.bin"
    ))
    .unwrap();
    for name in ["v_usr_group", "v_inorange", "v_orange"] {
        let metadata = |dmb: &Dmb| {
            let proc = dmb
                .procs
                .iter()
                .find(|proc| {
                    dmb.string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            (
                proc.source_kind,
                proc.source_parameter,
                proc.effective_flags(),
            )
        };
        assert_eq!(metadata(&emitted), metadata(&native), "{name}");
    }
}

#[test]
fn inherited_proc_membership_matches_paired_native_classes() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/inheritance.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/inheritance.native.bin"
    ))
    .unwrap();
    let members = |dmb: &Dmb, path: &[u8]| {
        let class = dmb
            .classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        let id = class.proc_list_id();
        if id == NONE {
            return Vec::new();
        }
        dmb.lists[id as usize]
            .iter()
            .filter_map(|&id| dmb.procs.get(id as usize))
            .filter_map(|proc| {
                (proc.strings[0] != NONE)
                    .then(|| dmb.string(proc.strings[0]))
                    .flatten()
            })
            .map(|name| name.to_vec())
            .collect::<Vec<_>>()
    };
    for path in [
        b"/datum/fixture_parent".as_slice(),
        b"/datum/fixture_parent/fixture_child".as_slice(),
    ] {
        assert_eq!(
            members(&emitted, path),
            members(&native, path),
            "{}",
            String::from_utf8_lossy(path)
        );
    }
}

#[test]
fn inherited_verb_override_uses_bare_proc_path() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/inherited_verb_path.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/inherited_verb_path.native.bin"
    ))
    .unwrap();
    for path in [
        b"/mob/child/parent_action".as_slice(),
        b"/mob/child/verb/own_action".as_slice(),
    ] {
        assert!(emitted
            .procs
            .iter()
            .any(|proc| emitted.string(proc.strings[0]) == Some(path)));
        assert!(native
            .procs
            .iter()
            .any(|proc| native.string(proc.strings[0]) == Some(path)));
    }
    for dmb in [&emitted, &native] {
        let class = dmb
            .classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(b"/mob/child"))
            .unwrap();
        let verbs = &dmb.lists[class.verb_list_id() as usize];
        assert!(verbs.iter().any(|&id| {
            dmb.string(dmb.procs[id as usize].strings[0]) == Some(b"/mob/child/parent_action")
        }));
    }
}

#[test]
fn optional_verb_arguments_have_native_nullable_prompt_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_nativeordered_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/null_default.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/null_default.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    for (id, proc) in native.procs.iter().enumerate() {
        let Some(path) = native.string(proc.strings[0]) else {
            continue;
        };
        if !path.windows(12).any(|part| part == b"default_arg_") {
            continue;
        }
        let emitted_id = output
            .dmb
            .procs
            .iter()
            .position(|item| output.dmb.string(item.strings[0]) == Some(path))
            .unwrap();
        let expected = native.proc_arguments(id).unwrap()[0].type_flags;
        let actual = output.dmb.proc_arguments(emitted_id).unwrap()[0].type_flags;
        assert_eq!(actual, expected, "{}", String::from_utf8_lossy(path));
    }
}
#[test]
fn proc_local_compile_time_consts_do_not_occupy_native_local_slots() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/proc_const.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/proc_const.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    for name in [b"/proc/alpha".as_slice(), b"/proc/beta".as_slice()] {
        let emitted_id = output
            .dmb
            .procs
            .iter()
            .position(|proc| output.dmb.string(proc.strings[0]) == Some(name))
            .unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(name))
            .unwrap();
        let emitted_locals = output.dmb.procs[emitted_id].code_locals_args[1];
        let native_locals = native.procs[native_id].code_locals_args[1];
        assert_eq!(
            output.dmb.lists[emitted_locals as usize].len(),
            native.lists[native_locals as usize].len(),
            "{}",
            String::from_utf8_lossy(name)
        );
    }
}

#[test]
fn lexical_local_metadata_order_matches_native_branch_declarations() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/lexical_locals.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/lexical_locals.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let local_names = |dmb: &Dmb| {
        let proc = dmb
            .procs
            .iter()
            .find(|proc| dmb.string(proc.strings[0]) == Some(b"/proc/branch_locals"))
            .unwrap();
        dmb.lists[proc.code_locals_args[1] as usize]
            .iter()
            .map(|&variable| {
                dmb.string(dmb.variables[variable as usize].name)
                    .unwrap()
                    .to_vec()
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(local_names(&emitted), local_names(&native));
    assert_eq!(
        local_names(&emitted),
        vec![b"first".to_vec(), b"second".to_vec()]
    );
}

#[test]
fn inherited_proc_metadata_matches_explicit_set_provenance() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    for (json, native) in [
        (
            &include_bytes!("../../fixtures/translation/inherited_verb_flags.json")[..],
            &include_bytes!("../../fixtures/translation/inherited_verb_flags.native.bin")[..],
        ),
        (
            &include_bytes!("../../fixtures/translation/inherited_proc_flags.json")[..],
            &include_bytes!("../../fixtures/translation/inherited_proc_flags.native.bin")[..],
        ),
    ] {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(native).unwrap();
        let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap()
            .dmb;
        for expected in &native.procs {
            let Some(path) = native.string(expected.strings[0]) else {
                continue;
            };
            if !(path
                .windows(b"hidden_parent".len())
                .any(|part| part == b"hidden_parent")
                || path
                    .windows(b"popup_parent".len())
                    .any(|part| part == b"popup_parent")
                || path
                    .windows(b"flagged".len())
                    .any(|part| part == b"flagged"))
            {
                continue;
            }
            let actual = emitted
                .procs
                .iter()
                .find(|proc| emitted.string(proc.strings[0]) == Some(path))
                .unwrap();
            assert_eq!(
                actual.effective_flags(),
                expected.effective_flags(),
                "{}",
                String::from_utf8_lossy(path)
            );
            for slot in 1..4 {
                let actual_string = (actual.strings[slot] != NONE)
                    .then(|| emitted.string(actual.strings[slot]))
                    .flatten();
                let expected_string = (expected.strings[slot] != NONE)
                    .then(|| native.string(expected.strings[slot]))
                    .flatten();
                assert_eq!(
                    actual_string,
                    expected_string,
                    "{} slot {slot}",
                    String::from_utf8_lossy(path)
                );
            }
        }
    }
}

#[test]
fn authored_verb_category_and_view_radius_match_native() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/verb_metadata.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verb_metadata.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for path in [
        b"/obj/verb/action".as_slice(),
        b"/obj/sub/action".as_slice(),
    ] {
        let actual = emitted
            .procs
            .iter()
            .find(|proc| emitted.string(proc.strings[0]) == Some(path))
            .unwrap();
        let expected = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(path))
            .unwrap();
        assert_eq!(actual.source_kind, expected.source_kind);
        assert_eq!(actual.source_parameter, expected.source_parameter);
        assert_eq!(
            emitted.string(actual.strings[3]),
            native.string(expected.strings[3]),
        );
    }
}

#[test]
fn null_and_empty_verb_categories_have_distinct_native_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/verb_category_nil.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verb_category_nil.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in ["cat_null", "cat_empty", "cat_regular"] {
        let path = format!("/mob/verb/{name}");
        let actual = emitted
            .procs
            .iter()
            .find(|proc| emitted.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            actual.effective_flags(),
            expected.effective_flags(),
            "{name}"
        );
        let actual_category = (actual.strings[3] != NONE)
            .then(|| emitted.string(actual.strings[3]))
            .flatten();
        let expected_category = (expected.strings[3] != NONE)
            .then(|| native.string(expected.strings[3]))
            .flatten();
        assert_eq!(actual_category, expected_category, "{name}");
    }
}

#[test]
fn equal_and_in_verb_source_keywords_have_distinct_native_flags() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/verb_source_keyword.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/verb_source_keyword.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in ["equal_source", "in_source"] {
        let path = format!("/obj/verb/{name}");
        let actual = emitted
            .procs
            .iter()
            .find(|proc| emitted.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(actual.source_kind, expected.source_kind, "{name}");
        assert_eq!(actual.source_parameter, expected.source_parameter, "{name}");
        assert_eq!(
            actual.effective_flags(),
            expected.effective_flags(),
            "{name}"
        );
    }
}

#[test]
fn waitfor_defaults_follow_original_declaration_and_nested_background_is_emitted() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    for (json, native) in [
        (
            &include_bytes!("../../fixtures/translation/waitfor_chain.json")[..],
            &include_bytes!("../../fixtures/translation/waitfor_chain.native.bin")[..],
        ),
        (
            &include_bytes!("../../fixtures/translation/nested_set_flags.json")[..],
            &include_bytes!("../../fixtures/translation/nested_set_flags.native.bin")[..],
        ),
    ] {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(native).unwrap();
        let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap()
            .dmb;
        for expected in &native.procs {
            let Some(path) = native.string(expected.strings[0]) else {
                continue;
            };
            if !(path.ends_with(b"/p") || path.ends_with(b"/nested_background")) {
                continue;
            }
            let actual = emitted
                .procs
                .iter()
                .find(|proc| emitted.string(proc.strings[0]) == Some(path))
                .unwrap();
            assert_eq!(
                actual.effective_flags(),
                expected.effective_flags(),
                "{}",
                String::from_utf8_lossy(path)
            );
        }
    }
}

#[test]
fn mixed_map_list_assigns_positional_keys() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/translation/map_mixed.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(&code[..5], &[0x50, 1, 0x50, 9, 0x60]);
    assert_eq!(&code[7..11], &[0x50, 1, 0xc8, 2]);
}

#[test]
fn typed_argument_bits_match_paired_compilers() {
    let template = Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../fixtures/native_template.json"))
            .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/argument_types.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/argument_types.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let actual = output.dmb.proc_arguments(0).unwrap();
    let expected = reference.proc_arguments(0).unwrap();
    assert_eq!(actual.len(), expected.len());
    for index in (0..actual.len()).filter(|&index| index != 7) {
        assert_eq!(actual[index].type_flags, expected[index].type_flags);
    }
    assert_eq!(actual[0].type_flags, crate::dmb::argument_type::MOB);
    assert_eq!(actual[1].type_flags, crate::dmb::argument_type::OBJ);
    // OpenDream JSON does not distinguish explicit `as anything` from
    // an untyped argument (both have Type=0), so index 7 stays untyped.
    assert_eq!(actual[7].type_flags, 0);
    assert_eq!(expected[7].type_flags, crate::dmb::argument_type::ANYTHING);
    input
        .procs
        .iter_mut()
        .find(|proc| proc.name == "fixture_arg_types")
        .unwrap()
        .arguments[7]
        .explicit_anything = true;
    let annotated = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        annotated.dmb.proc_arguments(0).unwrap()[7].type_flags,
        expected[7].type_flags
    );
}
