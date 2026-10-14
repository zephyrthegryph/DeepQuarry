#[test]
fn prompt_branch_arguments_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/prompt_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/prompt_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
            let find = |dmb: &byond_dmb::dmb::Dmb| {
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
        "../../../../fixtures/lowering/range_pick_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/range_pick_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
            let find = |dmb: &byond_dmb::dmb::Dmb| {
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
        "../../../../fixtures/lowering/output_branches.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/output_branches.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("output_branches"),
            debug,
        )
        .unwrap();
        for path in ["/proc/out_field", "/proc/out_index", "/proc/out_receiver"] {
            let find = |dmb: &byond_dmb::dmb::Dmb| {
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
        "../../../../fixtures/lowering/self_arglist.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/lowering/self_arglist.bin"))
            .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
            let find = |dmb: &byond_dmb::dmb::Dmb| {
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
        "../../../../fixtures/translation/arglist_builtin_forms.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/arglist_builtin_forms.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
            let find = |dmb: &byond_dmb::dmb::Dmb| {
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
        "../../../../fixtures/translation/arglist_file.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/arglist_file.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("arglist_file"),
            debug,
        )
        .unwrap();
        let path = "/proc/probe";
        let find = |dmb: &byond_dmb::dmb::Dmb| {
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
        "../../../../fixtures/translation/database_constructor_arguments.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/database_constructor_arguments.native.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/translation");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
                let find = |dmb: &byond_dmb::dmb::Dmb| {
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
                    byond_dmb::bytecode::decode(output.dmb.proc_code_words(find(&output.dmb)).unwrap())
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
        "../../../../fixtures/lowering/prompt_type_unions.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/prompt_type_unions.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/lowering");
    let paths = (0..132)
        .map(|i| format!("/proc/prompt_union_{i}"))
        .chain((0..4).map(|i| format!("/proc/prompt_null_choices_{i}")))
        .chain((0..8).map(|i| format!("/proc/prompt_special_{i}")))
        .collect::<Vec<_>>();
    assert_eq!(paths.len(), 144);
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
            &input,
            &baseline,
            &template,
            &root,
            Some("prompt_type_unions"),
            debug,
        )
        .unwrap();
        for path in &paths {
            let find = |dmb: &byond_dmb::dmb::Dmb| {
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
    use byond_dmb::bytecode::Operand;
    use byond_dmb::operands::Variable;
    fn prove_and_canonicalize(dmb: &byond_dmb::dmb::Dmb, proc_id: usize) -> byond_dmb::dmb::Dmb {
        let instructions = byond_dmb::bytecode::decode(dmb.proc_code_words(proc_id).unwrap()).unwrap();
        fn visit(
            dmb: &byond_dmb::dmb::Dmb,
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
                    fn time(dmb: &byond_dmb::dmb::Dmb, variable: &Variable) -> bool {
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
        "../../../../fixtures/lowering/reordered_cache.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/reordered_cache.bin"
    ))
    .unwrap();
    let root = std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/lowering");
    for debug in [false, true] {
        let output = super::super::translate_named_debug(
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
            let find = |dmb: &byond_dmb::dmb::Dmb| {
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
