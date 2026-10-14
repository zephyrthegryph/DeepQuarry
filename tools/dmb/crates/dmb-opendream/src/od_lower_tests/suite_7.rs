use super::*;

#[test]
fn filtered_iterator_does_not_use_declared_locals_as_filter_mask() {
    let od = [
        0x9a, 0, 0, 0, 0, 9, 0, 0x96, 9, 1, 0x06, 5, 0x41, 0, 0, 0, 0, 26, 0, 0, 0, 0x3b, 0, 0, 0,
        0, 9, 1, 41, 0, 0, 0, 0x56, 9, 0, 0x51, 0x0e, 21, 0, 0, 0, 0x3c, 0, 0, 0, 0, 0x97, 9, 0,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 26).then_some(4)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 26).then_some(9)
        }
    }
    let out = lower_proc_bytecode_with_locals(&od, &Ids, 2).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    let iter = instructions.iter().find(|i| i.name == "IterLoad").unwrap();
    assert_eq!(iter.operands, [5, 0]);
    assert!(instructions.iter().any(|i| i.name == "JzLoop"));
    assert!(instructions.iter().any(|i| i.name == "IsType"));
}
#[test]
fn type_iterator_uses_native_typed_world_enumeration() {
    let od = [
        0x9a, 0, 0, 0, 0, 9, 0, 0x96, 9, 1, 0x02, 26, 0, 0, 0, 0x5d, 0, 0, 0, 0, 0x06, 9, 1, 0x51,
        0x3b, 0, 0, 0, 0, 9, 1, 44, 0, 0, 0, 0x56, 9, 0, 0x51, 0x0e, 24, 0, 0, 0, 0x3c, 0, 0, 0, 0,
        0x97, 9, 0,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 26).then_some(4)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 26).then_some(9)
        }
    }
    let out = lower_proc_bytecode_with_locals(&od, &Ids, 2).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    let iter = instructions.iter().find(|i| i.name == "IterLoad").unwrap();
    assert_eq!(iter.operands, [5, 0x4000]);
    assert!(instructions
        .iter()
        .any(|i| i.name == "PushVal" && i.operands == [9, 4]));
    assert!(!instructions.iter().any(|i| i.name == "IsType"));
    let source = [crate::opendream::OpenDreamSourceInfo {
        offset: 15,
        file: Some(9),
        line: 13,
    }];
    let debug = lower_proc_bytecode_with_debug_info(&od, &Ids, 2, &[], &source).unwrap();
    let debug = byond_dmb::bytecode::decode(&debug).unwrap();
    assert!(debug
        .iter()
        .any(|item| item.opcode == 0x85 && item.operands == [13]));
    assert_eq!(
        debug
            .iter()
            .find(|item| item.name == "IterLoad")
            .unwrap()
            .operands,
        [5, 0x4000]
    );
}
#[test]
fn unit_step_range_loop_uses_for_range_and_pop_n() {
    let od = [
        0x9a, 0, 0, 0, 0, 9, 0, 0x96, 9, 1, 0x88, 3, 0, 0, 0, 0, 0, 0x80, 0x3f, 0, 0, 0x40, 0x40,
        0, 0, 0x80, 0x3f, 0x1b, 0, 0, 0, 0, 0x3b, 0, 0, 0, 0, 9, 1, 54, 0, 0, 0, 0x06, 9, 1, 0x84,
        9, 0, 0x0e, 32, 0, 0, 0, 0x3c, 0, 0, 0, 0, 0x97, 9, 0,
    ];
    let out = lower_proc_bytecode_with_locals(&od, &(), 2).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert!(instructions.iter().any(|i| i.name == "Check2Numbers"));
    assert!(instructions.iter().any(|i| i.name == "ForRange"));
    assert!(instructions
        .iter()
        .any(|i| i.name == "PopN" && i.operands == [2]));
}
#[test]
fn stepped_range_loop_uses_for_range_step_and_three_stack_values() {
    // Paired stepped_range fixture: `for(var/i in 1 to 5 step 2)`.
    let od = [
        0x9a, 0, 0, 0, 0, 9, 0, 0x96, 9, 1, 0x88, 3, 0, 0, 0, 0, 0, 0x80, 0x3f, 0, 0, 0xa0, 0x40,
        0, 0, 0, 0x40, 0x1b, 0, 0, 0, 0, 0x3b, 0, 0, 0, 0, 9, 1, 54, 0, 0, 0, 0x06, 9, 1, 0x84, 9,
        0, 0x0e, 32, 0, 0, 0, 0x3c, 0, 0, 0, 0, 0x97, 9, 0,
    ];
    let out = lower_proc_bytecode_with_locals(&od, &(), 2).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert!(instructions.iter().any(|i| i.name == "Check3Numbers"));
    assert!(instructions.iter().any(|i| i.name == "ForRangeStep"));
    assert!(instructions
        .iter()
        .any(|i| i.name == "PopN" && i.operands == [3]));
}
#[test]
fn forward_continue_to_increment_tail_uses_jump_loop() {
    let od = [
        0x11, // loop body marker
        0x0e, 6, 0, 0, 0, // forward continue to increment tail
        0x56, 9, 0, 0x51, // local increment and discarded result
        0x0e, 0, 0, 0, 0, // backward edge to loop start
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    assert_eq!(out[3], 0xf8);
    assert_eq!(out.iter().filter(|word| **word == 0xf8).count(), 2);
}
#[test]
fn local_lifetimes_remap_reused_opendream_slot() {
    use crate::opendream::OpenDreamLocal;
    let od = [0x96, 9, 0, 0x96, 9, 1, 0x06, 9, 1, 0x06, 9, 1];
    let events = [
        OpenDreamLocal {
            offset: 0,
            add: Some("total".into()),
            remove: None,
        },
        OpenDreamLocal {
            offset: 3,
            add: Some("i".into()),
            remove: None,
        },
        OpenDreamLocal {
            offset: 6,
            add: None,
            remove: Some(1),
        },
        OpenDreamLocal {
            offset: 6,
            add: Some("status".into()),
            remove: None,
        },
    ];
    let out = lower_proc_bytecode_with_local_events(&od, &(), 2, &events).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[1].operands, [0xffda, 0]);
    assert_eq!(instructions[3].operands, [0xffda, 1]);
    assert_eq!(instructions[4].operands, [0xffda, 2]);
    assert_eq!(instructions[5].operands, [0xffda, 2]);
}
#[test]
fn current_opendream_smoke_world_new_lowers() {
    let od = [
        10, 6, 4, 0, 0, 0, 0, 81, 6, 5, 3, 41, 1, 0, 0, 78, 12, 42, 1, 0, 0, 6, 5, 136, 2, 0, 0, 0,
        0, 0, 0, 64, 0, 0, 64, 64, 10, 11, 2, 0, 0, 0, 1, 2, 0, 0, 0, 78, 12, 42, 1, 0, 0,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(match old {
                298 => 78,
                297 => 438,
                _ => old,
            })
        }
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old == 2).then_some(1)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .map(|i| i.name)
        .collect();
    assert_eq!(
        names,
        [
            "CallParent",
            "Pop",
            "GetVar",
            "PushVal",
            "Output",
            "GetVar",
            "PushVal",
            "PushVal",
            "CallGlob",
            "Output",
            "End"
        ]
    );
}
#[test]
fn current_opendream_get_value_matches_dreammaker_code() {
    // ReturnReferenceValue(SrcField("value")); OpenDream string 299,
    // DreamMaker field name string 441 in the smoke build.
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 299).then_some(441)
        }
    }
    let od = [0x97, 13, 43, 1, 0, 0];
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffdc, 0xffce, 441, 0x12, 0]
    );
}
#[test]
fn native_isfile_call_lowers_to_builtin_opcode() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, _old: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 47).then_some(0xe4)
        }
    }
    // Push arg 0; Call(GlobalProc(47), FromStack, 1); Return.
    let od = [0x06, 9, 0, 0x0a, 11, 47, 0, 0, 0, 1, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffda, 0, 0xe4, 0x12, 0]
    );
}
#[test]
fn flow_fixture_lowers_loop_and_augmented_assignment() {
    // /proc/flow(n) from both compilers: while(n > 0) { x += n; n-- }
    let od = [
        154, 0, 0, 0, 0, 9, 0, 6, 8, 0, 56, 0, 0, 0, 0, 20, 12, 36, 0, 0, 0, 6, 8, 0, 132, 9, 0,
        87, 8, 0, 81, 14, 7, 0, 0, 0, 151, 9, 0,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .map(|i| i.name)
        .collect();
    assert_eq!(
        names,
        [
            "PushVal", "SetVar", "GetVar", "PushVal", "Tg", "Test", "Jz", "GetVar", "AugAdd",
            "Dec", "JmpLoop", "GetVar", "Ret", "End"
        ]
    );
}
#[test]
fn switcher_fixture_lowers_case_chain_to_native_switch() {
    let od = [
        6, 8, 0, 141, 0, 0, 128, 63, 27, 0, 0, 0, 141, 0, 0, 0, 64, 37, 0, 0, 0, 81, 14, 42, 0, 0,
        0, 152, 0, 0, 32, 65, 14, 42, 0, 0, 0, 152, 0, 0, 160, 65, 152, 0, 0, 0, 0,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .map(|i| i.name)
        .collect();
    assert_eq!(
        names,
        ["GetVar", "Switch", "PushVal", "Ret", "Jmp", "PushVal", "Ret", "PushVal", "Ret", "End"]
    );
}
#[test]
fn iterate_fixture_lowers_list_enumerator() {
    let od = [
        154, 0, 0, 0, 0, 9, 0, 150, 9, 1, 6, 8, 0, 58, 0, 0, 0, 0, 59, 0, 0, 0, 0, 9, 1, 40, 0, 0,
        0, 6, 9, 1, 132, 9, 0, 14, 18, 0, 0, 0, 60, 0, 0, 0, 0, 151, 9, 0,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .map(|i| i.name)
        .collect();
    assert_eq!(
        names,
        [
            "PushVal", "SetVar", "PushVal", "SetVar", "GetVar", "IterLoad", "IterNext", "SetVar",
            "Jz", "GetVar", "AugAdd", "JmpLoop", "GetVar", "Ret", "End"
        ]
    );
}
#[test]
fn current_opendream_object_world_new_lowers() {
    let od = [
        10, 6, 4, 0, 0, 0, 0, 81, 17, 2, 4, 0, 0, 0, 46, 0, 0, 0, 0, 0, 133, 9, 0, 6, 5, 134, 9, 0,
        40, 1, 0, 0, 78, 12, 41, 1, 0, 0, 135, 2, 0, 0, 0, 5, 9, 0, 106, 1, 0, 0, 0, 0, 0, 0, 0, 0,
        78, 12, 41, 1, 0, 0,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 4).then_some(0)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 4).then_some(9)
        }
        fn string(&self, old: u32) -> Option<u32> {
            Some(match old {
                297 => 78,
                296 => 438,
                1 => 440,
                _ => old,
            })
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .map(|i| i.name)
        .collect();
    assert_eq!(
        names,
        [
            "CallParent",
            "Pop",
            "PushVal",
            "New",
            "SetVar",
            "GetVar",
            "GetVar",
            "Output",
            "GetVar",
            "Call",
            "Output",
            "End"
        ]
    );
}
#[test]
fn instance_call_stays_after_its_arguments() {
    let od = [
        0x06, 9, 0, 0x88, 2, 0, 0, 0, 0, 0, 64, 64, 0, 0, 160, 64, 0x6a, 2, 0, 0, 0, 1, 2, 0, 0, 0,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 2).then_some(441)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .map(|i| i.name)
        .collect();
    assert_eq!(names, ["PushVal", "PushVal", "Call", "End"]);
}
#[test]
fn constructor_with_one_literal_argument_matches_dreammaker_shape() {
    // OpenDream /proc/newit(): return new /obj/item(5)
    let od = [
        0x38, 0, 0, 160, 64, 0x11, 0x02, 3, 0, 0, 0, 0x2e, 1, 1, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 3).then_some(0)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 3).then_some(9)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .map(|i| i.name)
        .collect();
    assert_eq!(names, ["PushVal", "PushVal", "New", "Ret", "End"]);
}
#[test]
fn constructor_with_two_direct_args_matches_dreammaker_shape() {
    // fixtures/lowering/constructor_arguments.dm, paired compiler output.
    let od = [
        0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x11, 0x02, 3, 0, 0, 0, 0x2e, 1, 2, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 3).then_some(0)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 3).then_some(9)
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x60, 9, 0, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x01, 2, 0x12, 0]
    );
}
#[test]
fn constructor_accepts_arithmetic_argument_expressions() {
    let od = [
        0x06, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x08, 0x06, 8, 1, 0x38, 0, 0, 0, 0x40, 0x28, 0x11,
        0x02, 3, 0, 0, 0, 0x2e, 1, 2, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 3).then_some(0)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 3).then_some(9)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .iter()
        .map(|instruction| instruction.name)
        .collect();
    assert_eq!(
        names,
        ["PushVal", "GetVar", "PushVal", "Add", "GetVar", "PushVal", "Mul", "New", "Ret", "End"]
    );
}
#[test]
fn unsupported_opcode_is_explicit() {
    let err = lower_proc_bytecode(&[0xfe], &()).unwrap_err();
    assert_eq!(err.offset, 0);
    assert!(err.reason.contains("0xfe"));
}
#[test]
fn direct_stack_opcodes_are_unique_and_native_zero_operand() {
    let mut seen = std::collections::BTreeSet::new();
    for source in 0..=u8::MAX {
        if let Some(target) = direct_stack_opcode(source) {
            assert!(seen.insert(source));
            let decoded = byond_dmb::bytecode::decode(&[target]).unwrap();
            assert_eq!(decoded.len(), 1);
            assert!(decoded[0].operands.is_empty());
        }
    }
}
