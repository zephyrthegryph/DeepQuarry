use super::*;

#[test]
fn packed_string_switch_accepts_a_trailing_null_case() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(old - 49)
        }
    }
    // Paired switch_trailing_null: "b" and null share a return target.
    let od = [
        0x06, 8, 0, 0x93, 0x28, 1, 0, 0, 38, 0, 0, 0, 0x93, 0x29, 1, 0, 0, 48, 0, 0, 0, 0x11, 0x32,
        48, 0, 0, 0, 0x51, 0x98, 0, 0, 0x40, 0x40, 0x0e, 53, 0, 0, 0, 0x98, 0, 0, 0x80, 0x3f, 0x0e,
        53, 0, 0, 0, 0x98, 0, 0, 0, 0x40,
    ];
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = crate::bytecode::decode(&words).unwrap();
    assert_eq!(instructions[1].name, "Switch");
    assert_eq!(
        instructions[1].operands,
        [3, 6, 247, 22, 6, 248, 29, 0, 0, 29, 15]
    );
}
#[test]
fn indexed_logical_and_prefix_operations_match_native() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/indexed_logical.json"
    ))
    .unwrap();
    for (name, tail) in [
        (
            "indexed_or",
            vec![0x33, 0xffe4, 0xb2, 19, 0x33, 0xffd9, 2, 0x35, 0xffe4],
        ),
        (
            "indexed_and",
            vec![0x33, 0xffe4, 0xb3, 19, 0x33, 0xffd9, 2, 0x35, 0xffe4],
        ),
        ("indexed_preincrement", vec![0x62, 0xffe4]),
        ("indexed_predecrement", vec![0x64, 0xffe4]),
    ] {
        let proc = program.procs.iter().find(|proc| proc.name == name).unwrap();
        let mut expected = vec![0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x34, 0xffe3, 0x34, 0xffd8];
        expected.extend(tail);
        expected.extend([0x12, 0]);
        assert_eq!(
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &()).unwrap(),
            expected,
            "{name}"
        );
    }
}
#[test]
fn logical_assignment_reference_branches_match_native() {
    for (od_branch, byond_branch) in [(0x66, 0x10), (0x67, 0x11)] {
        let od = [
            od_branch, 8, 0, 13, 0, 0, 0, // branch around assignment
            0x06, 8, 1, 0x09, 8, 0, // x = y
            0x51, 0x06, 8, 0, 0x10,
        ];
        let words = lower_proc_bytecode(&od, &()).unwrap();
        let decoded = crate::bytecode::decode(&words).unwrap();
        assert_eq!(decoded[0].name, "GetVar");
        assert_eq!(decoded[1].name, "Test");
        assert_eq!(decoded[2].opcode, byond_branch);
        assert_eq!(decoded[4].name, "SetVar");
    }
}
#[test]
fn gradient_and_simple_animate_match_native_shapes() {
    let gradient = [
        0x38, 0, 0, 0x80, 0x3f, 0x38, 0, 0, 0, 0x40, 0x38, 0, 0, 0, 0x3f, 0x73, 1, 3, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&gradient, &()).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    assert_eq!(decoded[3].name, "NewList");
    assert_eq!(decoded[4].name, "Gradient");

    let animate = [0x06, 8, 0, 0x9c, 1, 1, 0, 0, 0, 0x51];
    let words = lower_proc_bytecode(&animate, &()).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    assert_eq!(decoded[1].name, "NullAnimate");
}
#[test]
fn astype_uses_native_no_operand_opcode() {
    let ids = MockResolver::default().with_type(26, 9, 4);
    let od = [0x06, 8, 0, 0x02, 26, 0, 0, 0, 0x48, 0x10];
    let words = lower_proc_bytecode(&od, &ids).unwrap();
    assert_eq!(words, [0x33, 0xffd9, 0, 0x60, 9, 4, 0x185, 0x12, 0]);
}
#[test]
fn dynamic_constructor_reorders_type_before_arguments() {
    let one = [0x06, 8, 1, 0x11, 0x06, 8, 0, 0x2e, 1, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&one, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x01, 1, 0x12, 0]
    );
    let zero = [0x11, 0x06, 8, 0, 0x2e, 0, 0, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&zero, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x01, 0, 0x12, 0]
    );
    // Paired DuplicateObject: new original.type(locate(0,0,0)).
    let locate_argument = [
        0x88, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x4a, 0x11, 0x06, 8, 0, 0x2e, 1, 1,
        0, 0, 0, 0x10,
    ];
    let out = lower_proc_bytecode(&locate_argument, &()).unwrap();
    let instructions = crate::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[0].name, "GetVar");
    assert!(instructions.iter().any(|item| item.name == "LocatePos"));
    assert!(instructions.iter().any(|item| item.name == "New"));
}
#[test]
fn constructor_argument_can_end_with_short_circuit_and() {
    // Paired _addtimer: new(..., file && "[file]:[line]"). The final
    // argument's JmpAnd crosses its two value-producing branches.
    let od = [
        0x06, 8, 0, 0x15, 11, 0, 0, 0, 0x06, 8, 1, 0x11, 0x02, 5, 0, 0, 0, 0x2e, 1, 1, 0, 0, 0,
        0x10,
    ];
    let ids = MockResolver::default().with_type(5, 9, 1);
    let words = lower_proc_bytecode(&od, &ids).unwrap();
    let names: Vec<_> = crate::bytecode::decode(&words)
        .unwrap()
        .iter()
        .map(|item| item.name)
        .collect();
    assert!(names.contains(&"JmpAnd"));
    assert!(names.contains(&"New"));
}
#[test]
fn modified_constructor_uses_native_instance_prototype() {
    // Paired get_tgui_plane_masters: `new /plane_master{plane=11}`.
    let od = [
        0x03, 4, 0, 0, 0, 0x02, 5, 0, 0, 0, 0x2e, 0, 0, 0, 0, 0, 0x10,
    ];
    let ids = MockResolver::default().with_modified_instance(5, 4, 69);
    assert_eq!(
        lower_proc_bytecode(&od, &ids).unwrap(),
        [0x60, 41, 69, 0x01, 0, 0x12, 0]
    );
}
#[test]
fn modified_type_constant_uses_native_instance_prototype() {
    // Paired modified_constant_value: var/T = /obj/modified_constant{amount=22}.
    let od = [0x9f, 3, 0, 0, 0, 0x28, 1, 0, 0, 0x09, 9, 0, 0x10];
    let ids = MockResolver::default().with_modified_instance(3, 296, 2);
    let words = lower_proc_bytecode(&od, &ids).unwrap();
    assert_eq!(words[..3], [0x60, 41, 2]);
}
#[test]
fn named_dynamic_constructor_uses_native_arglist() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            match old {
                297 => Some(438),
                298 => Some(437),
                _ => None,
            }
        }
    }
    let od = [
        0x8e, 2, 0, 0, 0, 0x29, 1, 0, 0, 0, 0, 0, 0x40, 0x2a, 1, 0, 0, 0, 0, 0x80, 0x3f, 0x11,
        0x06, 8, 0, 0x2e, 2, 4, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    assert_eq!(decoded[0].name, "GetVar");
    assert_eq!(decoded[5].name, "NewAssocList");
    assert_eq!(decoded[6].name, "NewArgList");
}
#[test]
fn constructor_arglist_reorders_type_and_list() {
    let od = [0x06, 8, 1, 0x11, 0x06, 8, 0, 0x2e, 3, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xcf, 0x12, 0]
    );
}
#[test]
fn arglist_calls_use_dedicated_native_opcodes() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old == 0).then_some(7)
        }
    }
    let global = [0x06, 8, 0, 0x0a, 11, 0, 0, 0, 0, 3, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&global, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0xcd, 7, 0x12, 0]
    );
    let parent = [0x06, 8, 0, 0x0a, 6, 3, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&parent, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0xc9, 0x12, 0]
    );
}
#[test]
fn self_proc_call_uses_src_dynamic_proc_reference() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 0).then_some(438)
        }
    }
    let direct = [0x06, 8, 0, 0x0a, 14, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&direct, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x29, 0xffdc, 0xffce, 0xffdd, 438, 1, 0x12, 0]
    );
}
#[test]
fn output_target_precedes_literal_rhs() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 0).then_some(438)
        }
    }
    let od = [0x03, 0, 0, 0, 0, 0x4e, 8, 0];
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x60, 6, 438, 0x03, 0]
    );
}
#[test]
fn output_src_usr_world_targets_are_direct_references() {
    for (od_target, byond_target) in [(1, 0xffce), (3, 0xffcd), (5, 0xffe5)] {
        let od = [0x38, 0, 0, 0xa0, 0x40, 0x4e, od_target];
        let words = lower_proc_bytecode(&od, &()).unwrap();
        assert_eq!(&words[..3], &[0x33, byond_target, 0x60]);
        assert_eq!(words[6], 0x03);
    }
}
#[test]
fn direct_initial_and_issaved_debug_markers_preserve_owner_and_literal() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(if old == 900 { 901 } else { 0x12345 })
        }
    }
    // Paired direct Initial/IsSaved with a wide field StringID. Both
    // boundaries previously disrupted the raw instruction-tail checks.
    let source = [
        crate::opendream::OpenDreamSourceInfo {
            offset: 3,
            file: Some(900),
            line: 30,
        },
        crate::opendream::OpenDreamSourceInfo {
            offset: 8,
            file: None,
            line: 31,
        },
    ];
    for (operation, native_kind) in [(0x47, 0xffe7), (0x53, 0xffe8)] {
        let code = [0x06, 8, 0, 0x03, 44, 1, 0, 0, operation, 0x10];
        let plain = lower_proc_bytecode(&code, &Ids).unwrap();
        assert_eq!(
            plain,
            [0x33, 0xffdc, 0xffd9, 0, native_kind, 0x12345, 0x12, 0]
        );
        let debug = lower_proc_bytecode_with_debug_info(&code, &Ids, 0, &[], &source).unwrap();
        let instructions = crate::bytecode::decode(&debug).unwrap();
        assert!(instructions
            .iter()
            .any(|item| item.opcode == 0x84 && item.operands == [901]));
        for line in [30, 31] {
            assert!(instructions
                .iter()
                .any(|item| item.opcode == 0x85 && item.operands == [line]));
        }
        let stripped: Vec<_> = instructions
            .into_iter()
            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
            .flat_map(|item| std::iter::once(item.opcode).chain(item.operands))
            .collect();
        assert_eq!(stripped, plain, "operation {operation:#x}");
        assert!(
            !stripped.contains(&0x34),
            "direct receiver must stay nested, not cached eagerly"
        );
    }
}

#[test]
fn dynamic_initial_and_issaved_debug_markers_preserve_executable_tail() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/client_iterator.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/client_iterator.native.bin"
    ))
    .unwrap();
    let proc_ = input
        .procs
        .iter()
        .find(|proc_| proc_.name == "dynamic_initial")
        .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            self.1
                .strings
                .iter()
                .position(|string| string.data == text)
                .map(|id| id as u32)
                .or(Some(900))
        }
    }
    let ids = Ids(&input, &native);
    let original = proc_.bytecode.as_ref().unwrap();
    let native_id = native
        .procs
        .iter()
        .position(|proc_| native.string(proc_.strings[0]) == Some(b"/proc/dynamic_initial"))
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(original, &ids).unwrap(),
        native.proc_code_words(native_id).unwrap()
    );
    assert_eq!(proc_.source_info[0].offset, 14);
    for (operation, field_kind) in [(0x47, 0xffe7), (0x53, 0xffe8)] {
        let mut code = original.clone();
        assert_eq!(code[14], 0x47);
        code[14] = operation;
        let plain = lower_proc_bytecode(&code, &ids).unwrap();
        let debug = lower_proc_bytecode_with_debug_info(
            &code,
            &ids,
            proc_.max_variable_id,
            &proc_.locals,
            &proc_.source_info,
        )
        .unwrap();
        let instructions = crate::bytecode::decode(&debug).unwrap();
        assert!(instructions.iter().any(|item| item.opcode == 0x84));
        assert!(instructions
            .iter()
            .any(|item| item.opcode == 0x85 && item.operands == [5]));
        let stripped: Vec<_> = instructions
            .into_iter()
            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
            .flat_map(|item| std::iter::once(item.opcode).chain(item.operands))
            .collect();
        assert_eq!(stripped, plain, "operation {operation:#x}");
        assert!(stripped
            .windows(3)
            .any(|words| words == [0x33, field_kind, 0xffe4]));
    }
}

#[test]
fn field_output_debug_markers_preserve_direct_owner_and_rhs() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(match old {
                296 => 438,
                297 => 69,
                900 => 901,
                _ => old,
            })
        }
    }
    // Paired field_output_resolves_owner_before_rhs expression: Arg0.field << "literal".
    let code = [0x06, 8, 0, 0x03, 0x28, 1, 0, 0, 0x4e, 12, 0x29, 1, 0, 0];
    let plain = lower_proc_bytecode(&code, &Ids).unwrap();
    assert_eq!(plain, [0x33, 0xffdc, 0xffd9, 0, 69, 0x60, 6, 438, 0x03, 0]);
    // A line boundary after the owner, immediately before the RHS, used
    // to hide that owner from the instruction-tail lookup.
    let source = [
        crate::opendream::OpenDreamSourceInfo {
            offset: 3,
            file: Some(900),
            line: 20,
        },
        crate::opendream::OpenDreamSourceInfo {
            offset: 8,
            file: None,
            line: 21,
        },
    ];
    let debug = lower_proc_bytecode_with_debug_info(&code, &Ids, 0, &[], &source).unwrap();
    let instructions = crate::bytecode::decode(&debug).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.opcode == 0x84 && item.operands == [901]));
    for line in [20, 21] {
        assert!(instructions
            .iter()
            .any(|item| item.opcode == 0x85 && item.operands == [line]));
    }
    let stripped: Vec<_> = instructions
        .into_iter()
        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
        .flat_map(|item| std::iter::once(item.opcode).chain(item.operands))
        .collect();
    assert_eq!(stripped, plain);
}

#[test]
fn field_output_resolves_owner_before_rhs() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            match old {
                296 => Some(438),
                297 => Some(69),
                _ => None,
            }
        }
    }
    let od = [0x06, 8, 0, 0x03, 0x28, 1, 0, 0, 0x4e, 12, 0x29, 1, 0, 0];
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffdc, 0xffd9, 0, 69, 0x60, 6, 438, 0x03, 0]
    );
}
#[test]
fn dynamic_range_reorders_value_after_bounds() {
    let od = [0x87, 3, 0, 0, 0, 8, 0, 8, 1, 8, 2, 0x5b, 0x10];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x33, 0xffd9, 0, 0xa9, 11, 0x36, 0x12, 0,]
    );
}
#[test]
fn dot_reference_maps_to_native_dot_variable() {
    let od = [0x38, 0, 0, 0x80, 0x3f, 0x85, 2, 0x97, 2];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    assert!(words.windows(2).any(|pair| pair == [0x34, 0xffd0]));
    assert_eq!(&words[words.len() - 2..], &[0, 0]);
}
#[test]
fn augmented_reference_expression_pushes_eval_result() {
    let od = [0x06, 8, 1, 0x0b, 8, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffd9, 1, 0x47, 0xffd9, 0, 0x13f, 0x12, 0]
    );
}
#[test]
fn nullable_prompt_preserves_list_constraint_and_argument_order() {
    // Paired prompt_nullable_list and prompt_null_only.
    let od_list = [
        0x87, 5, 0, 0, 0, 8, 3, 8, 2, 8, 1, 8, 0, 8, 4, 0x45, 1, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&od_list, &()).unwrap(),
        [
            0x33, 0xffd9, 4, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x33, 0xffd9, 3,
            0xc1, 128, 0, 64, 0xba, 0x12, 0
        ]
    );
    let od_no_list = [
        0x87, 4, 0, 0, 0, 8, 3, 8, 2, 8, 1, 8, 0, 0x11, 0x45, 1, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&od_no_list, &()).unwrap(),
        [
            0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x33, 0xffd9, 3, 0xc1, 128, 0, 0,
            0xba, 0x12, 0
        ]
    );
}
#[test]
fn nullable_file_and_color_prompts_match_native() {
    for (mask, prefix, input) in [
        (0x200u32, vec![], vec![0xc1, 16, 0, 0, 0xba]),
        (0x21u32, vec![], vec![0xc1, 136, 0, 0, 0xba]),
        (0x201u32, vec![], vec![0xc1, 144, 0, 0, 0xba]),
        (
            0x101u32,
            vec![0x60, 42, 18432, 8192],
            vec![0xc6, 0, 0, 0, 0xba],
        ),
    ] {
        let mut od = vec![0x87, 4, 0, 0, 0, 8, 3, 8, 2, 8, 1, 8, 0, 0x11, 0x45];
        od.extend(mask.to_le_bytes());
        od.push(0x10);
        let mut expected = prefix;
        expected.extend([
            0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x33, 0xffd9, 3,
        ]);
        expected.extend(input);
        expected.extend([0x12, 0]);
        assert_eq!(lower_proc_bytecode(&od, &()).unwrap(), expected);
    }
    // Paired prompt_computed keeps the full uppertext expression together.
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/prompt_file_color.json"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram);
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (self.0.procs.get(old as usize)?.name != "uppertext").then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (self.0.procs.get(old as usize)?.name == "uppertext").then_some(0x74)
        }
    }
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "prompt_computed")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&program)).unwrap(),
        [
            0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x74, 0x33, 0xffd9, 2, 0x33, 0xffd9, 3, 0xc1, 132, 0,
            0, 0xba, 0x12, 0
        ]
    );
}
#[test]
fn computed_prompt_selection_matches_native_order() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/prompt_file_color.json"
    ))
    .unwrap();
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "prompt_computed_selection")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &()).unwrap(),
        [
            0x33, 0xffd9, 4, 0x60, 0x2a, 0x3f80, 0, 0x7b, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33,
            0xffd9, 2, 0x33, 0xffd9, 3, 0xc1, 128, 0, 64, 0xba, 0x12, 0
        ]
    );
}
#[test]
fn mob_prompt_selection_matches_native() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/prompt_file_color.json"
    ))
    .unwrap();
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "prompt_mob_selection")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &()).unwrap(),
        [
            0x33, 0xffd9, 4, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x33, 0xffd9, 3,
            0xc1, 1, 0, 64, 0xba, 0x12, 0
        ]
    );
}
#[test]
fn output_named_constructors_match_native() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/output_constructors.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/output_constructors.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(text))
                .map(|id| id as u32)
        }
        fn proc_id(&self, old: u32) -> Option<u32> {
            (!matches!(
                self.0.procs.get(old as usize)?.name.as_str(),
                "image" | "sound"
            ))
            .then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            match self.0.procs.get(old as usize)?.name.as_str() {
                "image" => Some(0x173),
                "sound" => Some(0x170),
                _ => None,
            }
        }
        fn sound_type_string(&self) -> Option<u32> {
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(b"/sound"))
                .map(|id| id as u32)
        }
    }
    let normalize = |words: &[u32]| {
        crate::bytecode::decode(words)
            .unwrap()
            .into_iter()
            .map(|item| {
                if item.opcode == 0x50 {
                    let bits = (item.operands[0] as f32).to_bits();
                    (0x60, vec![42, bits >> 16, bits & 0xffff])
                } else if item.opcode == 0x33 && item.operands == [0xffe6] {
                    (0x60, vec![0, 0])
                } else {
                    (item.opcode, item.operands)
                }
            })
            .collect::<Vec<_>>()
    };
    for name in [
        "output_named_image",
        "output_named_sound",
        "output_field_sound",
    ] {
        let proc = program.procs.iter().find(|proc| proc.name == name).unwrap();
        let index = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(format!("/proc/{name}").as_bytes())
            })
            .unwrap();
        let words =
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&program, &native)).unwrap();
        assert_eq!(
            normalize(&words),
            normalize(native.proc_code_words(index).unwrap()),
            "{name}"
        );
    }
}
#[test]
fn complex_indexed_increment_matches_native() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/indexed_increment_complex.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/indexed_increment_complex.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(text))
                .map(|id| id as u32)
        }
    }
    for name in [
        "increment_call",
        "increment_conditional_key",
        "increment_conditional_list",
    ] {
        let proc = program.procs.iter().find(|proc| proc.name == name).unwrap();
        let index = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(format!("/proc/{name}").as_bytes())
            })
            .unwrap();
        assert_eq!(
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&program, &native)).unwrap(),
            native.proc_code_words(index).unwrap(),
            "{name}"
        );
    }
}
#[test]
fn range_first_switch_keeps_null_string_and_numeric_targets() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/switch_range_null.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/switch_range_null.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(text))
                .map(|id| id as u32)
        }
    }
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "range_first_null")
        .unwrap();
    let words =
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&program, &native)).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    let table = &decoded
        .iter()
        .find(|item| item.opcode == 0x7a)
        .unwrap()
        .operands;
    let native_words = native.proc_code_words(0).unwrap();
    let native_decoded = crate::bytecode::decode(native_words).unwrap();
    let native_table = &native_decoded
        .iter()
        .find(|item| item.opcode == 0x7a)
        .unwrap()
        .operands;
    assert_eq!(&table[..7], &native_table[..7]);
    assert_eq!(table[8], 3);
    assert_eq!(&table[9..11], &native_table[9..11]);
    assert_eq!(&table[12..15], &native_table[12..15]);
    assert_eq!(&table[16..18], &native_table[16..18]);
    for (at, label) in [
        (7, "negative"),
        (11, "null"),
        (15, "zero"),
        (18, "text"),
        (19, "other"),
    ] {
        let target = table[at] as usize;
        assert_eq!(&words[target..target + 2], &[0x60, 6]);
        assert_eq!(native.string(words[target + 2]), Some(label.as_bytes()));
    }
}
#[test]
fn dynamic_weighted_pick_uses_pick_prob() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            match old {
                296 => Some(247),
                297 => Some(248),
                _ => None,
            }
        }
    }
    let od = [
        0x38, 0, 0, 0x20, 0x41, 0x03, 0x28, 1, 0, 0, 0x06, 8, 0, 0x03, 0x29, 1, 0, 0, 0x55, 2, 0,
        0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    assert_eq!(decoded[2].name, "PickProb");
    assert_eq!(decoded[3].name, "PushVal");
    assert_eq!(decoded[5].name, "PushVal");
}
#[test]
fn weighted_pick_defers_computed_candidates_until_selected() {
    // Paired weighted_values: native evaluates w and 2, then PickProb
    // branches to x+1 or x*2; candidate arithmetic follows the table.
    let od = [
        0x87, 2, 0, 0, 0, 8, 1, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x08, 0x38, 0, 0, 0, 0x40, 0x06, 8,
        0, 0x38, 0, 0, 0, 0x40, 0x28, 0x55, 2, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = crate::bytecode::decode(&words).unwrap();
    assert_eq!(
        instructions
            .iter()
            .map(|item| item.name)
            .collect::<Vec<_>>(),
        [
            "GetVar", "PushVal", "PickProb", "GetVar", "PushVal", "Add", "Jmp", "GetVar",
            "PushVal", "Mul", "Ret", "End"
        ]
    );
    assert_eq!(
        instructions[2].operands,
        [
            2,
            instructions[3].offset as u32,
            instructions[7].offset as u32
        ]
    );
    assert_eq!(instructions[6].operands, [instructions[10].offset as u32]);
}
#[test]
fn weighted_pick_more_than_thirty_two_candidates_matches_native_thresholds() {
    // Paired weighted_many has forty candidates. Native's first threshold
    // is 79 (floor(1/820*65535)); the last is 62318, the sum of
    // individually truncated normalized weights 1 through 39.
    let mut od = Vec::new();
    for value in 1..=40 {
        for _ in 0..2 {
            od.push(0x38);
            od.extend((value as f32).to_le_bytes());
        }
    }
    od.push(0x55);
    od.extend(40u32.to_le_bytes());
    od.push(0x10);
    let words = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = crate::bytecode::decode(&words).unwrap();
    let table = &instructions[0];
    assert_eq!(table.name, "PickSwitch");
    assert_eq!(table.operands[0], 39);
    assert_eq!(table.operands[1], 79);
    assert_eq!(table.operands[77], 62318);
    assert_eq!(table.operands[2], instructions[1].offset as u32);
    assert_eq!(
        *table.operands.last().unwrap(),
        instructions[79].offset as u32
    );
}
#[test]
fn computed_weighted_pick_keeps_weight_expression_before_probability_table() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            match old {
                296 => Some(247),
                297 => Some(248),
                _ => None,
            }
        }
    }
    // Paired weighted_computed fixture: pick(w + 1; "a", 2; "b").
    let od = [
        0x06, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x08, 0x8a, 0x28, 1, 0, 0, 0, 0, 0, 0x40, 0x03, 0x29,
        1, 0, 0, 0x55, 2, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = crate::bytecode::decode(&words)
        .unwrap()
        .iter()
        .map(|instruction| instruction.name)
        .collect();
    assert_eq!(
        &names[..6],
        &["GetVar", "PushVal", "Add", "PushVal", "PickProb", "PushVal"]
    );
}
#[test]
fn paired_builtin_overloads_preserve_native_stack_shape() {
    struct Ids(u32);
    impl SymbolResolver for Ids {
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, _: u32) -> Option<u32> {
            Some(self.0)
        }
        fn sound_type_string(&self) -> Option<u32> {
            Some(400)
        }
    }
    let regex = [
        0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x0a, 11, 1, 0, 0, 0, 1, 2, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&regex, &Ids(0x13a)).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x13a, 2, 0x12, 0]
    );
    let orange = [0x0a, 11, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&orange, &Ids(0x1000e)).unwrap(),
        [0x60, 0, 0, 0x60, 0, 0, 0xad, 174, 0x12, 0]
    );
    let mut sound = Vec::new();
    for arg in 0..8u8 {
        sound.extend([0x06, 8, arg]);
    }
    sound.extend([0x0a, 11, 1, 0, 0, 0, 2, 8, 0, 0, 0, 0x10]);
    let result = lower_proc_bytecode(&sound, &Ids(0x170)).unwrap();
    assert_eq!(&result[..3], &[0x60, 6, 400]);
    assert_eq!(&result[result.len() - 5..], &[0xc8, 4, 0xcf, 0x12, 0]);
}
#[test]
fn cached_method_result_span_includes_its_receiver() {
    let words = [
        0x33, 0xffd9, 0, 0x30, 1, 1, 0x34, 0xffd8, 0x142, 0x33, 0xffd9, 1, 0x143, 0x29, 0xffdd,
        438, 1,
    ];
    assert_eq!(constructor_argument_start(&words, 1), Some(0));
    let nested = [
        0x33, 0xffd9, 0, 0x30, 1, 1, 0x34, 0xffd8, 0x142, 0x33, 0xffd9, 1, 0x30, 1, 1, 0x34,
        0xffd8, 0x142, 0x33, 0xffd9, 2, 0x143, 0x29, 0xffdd, 438, 1, 0x143, 0x29, 0xffdd, 438, 1,
    ];
    assert_eq!(constructor_argument_start(&nested, 1), Some(0));
}
