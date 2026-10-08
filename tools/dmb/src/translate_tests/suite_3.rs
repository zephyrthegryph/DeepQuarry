#[test]
fn adversarial_cache_mutations_match_native_receiver_order() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/cache_adversarial.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/cache_adversarial.bin"
    ))
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
        let output = super::super::translate_named_debug(
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
        "../../fixtures/lowering/declaration_namespaces.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/declaration_namespaces.bin"
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
        let output = super::super::translate_named_debug(
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
        "../../fixtures/lowering/initial_saved_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/initial_saved_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
        "../../fixtures/translation/cache_binding_freeze/probe.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/cache_binding_freeze/probe.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fixtures/translation/cache_binding_freeze");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("probe"),
            debug,
        )
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
        "../../fixtures/translation/null_equality_ownership/probe.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/null_equality_ownership/probe.native.bin"
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
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("probe"),
            debug,
        )
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
        "../../fixtures/lowering/self_call_ownership.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/self_call_ownership.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
        "../../fixtures/lowering/computed_call_ownership.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/computed_call_ownership.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
        "../../fixtures/lowering/operator_probe.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/lowering/operator_probe.bin"))
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
        let output = super::super::translate_named_debug(
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
        "../../fixtures/lowering/multidimensional_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/native_template.bin")).unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/multidimensional_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
