use super::*;

#[test]
fn weighted_pick_literals_match_dreammaker_pick_switch() {
    // Paired weighted_pick fixture: pick(10; "a", 20; "b", 70; "c").
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (296..=298).contains(&old).then_some(old - 49)
        }
    }
    let od = [
        0x38, 0, 0, 0x20, 0x41, 0x8e, 2, 0, 0, 0, 0x28, 1, 0, 0, 0, 0, 0xa0, 0x41, 0x29, 1, 0, 0,
        0, 0, 0x8c, 0x42, 0x03, 0x2a, 1, 0, 0, 0x55, 3, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [
            0x79, 2, 6553, 7, 19660, 12, 17, 0x60, 6, 247, 0x0f, 20, 0x60, 6, 248, 0x0f, 20, 0x60,
            6, 249, 0x12, 0,
        ]
    );
}
#[test]
fn browser_output_families_match_paired_dreammaker_opcodes() {
    // Paired browse fixture: browse_rsc, output(), and link().
    let owner = [0x06, 8, 0];
    for (od, byond) in [(0x3d, 0xab), (0x3e, 0x27), (0x3f, 0x10b), (0x44, 0x07)] {
        let mut source = owner.to_vec();
        source.extend([0x11, 0x11, od]);
        let out = lower_proc_bytecode(&source, &()).unwrap();
        assert_eq!(*out.iter().rev().nth(1).unwrap(), byond);
    }
}
#[test]
fn input_operator_reads_into_destination_reference() {
    // Paired input_op fixture: `C >> x`.
    let od = [0x1c, 8, 0, 9, 0];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffd9, 0, 0xaf, 0x34, 0xffda, 0, 0]
    );
}
#[test]
fn computed_field_owner_uses_native_cache_after_list_lookup_or_constructor() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, _: u32) -> Option<u32> {
            Some(39)
        }
        fn type_id(&self, _: u32) -> Option<u32> {
            Some(4)
        }
        fn type_tag(&self, _: u32) -> Option<u8> {
            Some(9)
        }
    }
    // Paired computed_field and computed_field_new native procedures.
    let list = [
        0x06, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x69, 0x68, 0x29, 1, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&list, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x60, 0x2a, 0x3f80, 0, 0x7b, 0x34, 0xffd8, 0x33, 39, 0x12, 0]
    );
    let new = [
        0x11, 0x02, 26, 0, 0, 0, 0x2e, 0, 0, 0, 0, 0, 0x68, 0x29, 1, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&new, &Ids).unwrap(),
        [0x60, 9, 4, 0x01, 0, 0x34, 0xffd8, 0x33, 39, 0x12, 0]
    );
    let conditional = [
        0x8b, 8, 0, 15, 0, 0, 0, 0x06, 8, 1, 0x0e, 18, 0, 0, 0, 0x06, 8, 2, 0x68, 42, 1, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&conditional, &Ids).unwrap(),
        [
            0x33, 0xffd9, 0, 0x0d, 0x11, 11, 0x33, 0xffd9, 1, 0x0f, 14, 0x33, 0xffd9, 2, 0x34,
            0xffd8, 0x33, 39, 0x12, 0
        ]
    );
}
#[test]
fn null_ref_index_stores_null_before_list_and_key() {
    // Native null_list_slot evaluates null, list, key, then ListSet.
    // NullRef is the compact OD form of the same null assignment.
    let od = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x96, 7];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x60, 0, 0, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x7c, 0]
    );
    let field = [0x06, 8, 0, 0x96, 12, 39, 0, 0, 0];
    assert_eq!(
        lower_proc_bytecode(&field, &()).unwrap(),
        [0x60, 0, 0, 0x34, 0xffdc, 0xffd9, 0, 39, 0]
    );
}
#[test]
fn indexed_decrement_and_packed_float_assignment_match_native() {
    for (tail, native) in [
        (vec![0x57, 7, 0x10], vec![0x65, 0xffe4, 0x12, 0]),
        (vec![0x57, 7, 0x51], vec![0x67, 0xffe4, 0]),
    ] {
        let mut od = vec![0x87, 2, 0, 0, 0, 8, 0, 8, 1];
        od.extend(tail);
        let mut expected = vec![0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x34, 0xffe3, 0x34, 0xffd8];
        expected.extend(native);
        assert_eq!(lower_proc_bytecode(&od, &()).unwrap(), expected);
    }
    let packed = [
        0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x9b, 1, 0, 0, 0, 0, 0, 0, 0, 7,
    ];
    assert_eq!(
        lower_proc_bytecode(&packed, &()).unwrap(),
        [0x60, 0x2a, 0, 0, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x7c, 0]
    );
}
#[test]
fn computed_field_rhs_reorders_with_its_cached_owner() {
    // Paired computed_field_store: the field's owner lookup and Cache
    // setter belong to the RHS and must move before the destination.
    let od = [
        0x06, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x06, 8, 1, 0x38, 0, 0, 0, 0x40, 0x69, 0x68, 39, 0, 0,
        0, 0x85, 7,
    ];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [
            0x33, 0xffd9, 1, 0x60, 0x2a, 0x4000, 0, 0x7b, 0x34, 0xffd8, 0x33, 39, 0x33, 0xffd9, 0,
            0x60, 0x2a, 0x3f80, 0, 0x7c, 0
        ]
    );
}
#[test]
fn savefile_index_read_preserves_native_receiver_and_destination_order() {
    // Paired savefile_index: a savefile slot uses Index + Read, whereas
    // reading into an ordinary list emits Read before destination ListSet.
    let direct = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x1c, 7, 8, 2, 0x97, 8, 2];
    assert_eq!(
        lower_proc_bytecode(&direct, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xb0, 0xaf, 0x34, 0xffd9, 2, 0x33, 0xffd9, 2, 0x12, 0]
    );
    let indexed = [0x87, 4, 0, 0, 0, 8, 2, 8, 3, 8, 0, 8, 1, 0x1c, 7, 7];
    assert_eq!(
        lower_proc_bytecode(&indexed, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xb0, 0xaf, 0x33, 0xffd9, 2, 0x33, 0xffd9, 3, 0x7c, 0]
    );
    let field = [0x87, 3, 0, 0, 0, 8, 2, 8, 0, 8, 1, 0x1c, 7, 12, 39, 0, 0, 0];
    assert_eq!(
        lower_proc_bytecode(&field, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xb0, 0xaf, 0x34, 0xffdc, 0xffd9, 2, 39, 0]
    );
}
#[test]
fn savefile_index_output_constructs_receiver_before_value() {
    // Paired savefile_write(file,key,value): Index, then RHS, then Output.
    let od = [0x87, 3, 0, 0, 0, 8, 0, 8, 1, 8, 2, 0x4e, 7];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xb0, 0x33, 0xffd9, 2, 0x03, 0]
    );
}
#[test]
fn assign_into_index_uses_cache_key_and_cache_index() {
    // Paired assign_into fixture: `L[1] := x` in statement position.
    let od = [
        0x06, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x06, 8, 1, 0x74, 7, 0x51,
    ];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [
            0x33, 0xffd9, 1, 0x33, 0xffd9, 0, 0x60, 0x2a, 0x3f80, 0, 0x34, 0xffe3, 0x34, 0xffd8,
            0x15a, 0xffe4, 0
        ]
    );
}
#[test]
fn strict_associative_list_uses_native_alist_constructor() {
    let od = [0x0d, 2, 0, 0, 0];
    assert_eq!(lower_proc_bytecode(&od, &()).unwrap(), [0x17c, 2, 0]);
}
#[test]
fn append_expression_pushes_native_eval_result() {
    let od = [0x38, 0, 0, 0x80, 0x3f, 0x1a, 8, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x60, 0x2a, 0x3f80, 0, 0x45, 0xffd9, 0, 0x13f, 0x12, 0]
    );
}
#[test]
fn double_percent_operators_match_paired_native_opcodes() {
    let value = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x60, 0x10];
    assert_eq!(
        lower_proc_bytecode(&value, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x176, 0x12, 0]
    );
    let augmented = [0x06, 8, 1, 0x61, 8, 0, 0x51, 0x97, 8, 0];
    assert_eq!(
        lower_proc_bytecode(&augmented, &()).unwrap(),
        [0x33, 0xffd9, 1, 0x177, 0xffd9, 0, 0x33, 0xffd9, 0, 0x12, 0]
    );
}
#[test]
fn associative_iterator_uses_native_pair_value() {
    // Paired assoc_iter fixture: `for(var/k, v in L)`.
    let od = [
        0x06, 8, 0, 0x3a, 0, 0, 0, 0, 0x43, 0, 0, 0, 0, 9, 2, 9, 1, 21, 0, 0, 0, 0x3c, 0, 0, 0, 0,
    ];
    let out = lower_proc_bytecode_with_locals(&od, &(), 3).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    let load = instructions
        .iter()
        .find(|item| item.name == "IterLoad")
        .unwrap();
    assert_eq!(load.operands, [20, 0]);
    let pair = instructions
        .iter()
        .find(|item| item.name == "IterPairValue")
        .unwrap();
    assert_eq!(pair.operands, [0xffda, 2]);
}
#[test]
fn debug_source_events_emit_paired_file_and_line_markers() {
    use crate::opendream::OpenDreamSourceInfo;
    // DreamMaker DEBUG fixture starts DbgFile(437), DbgLine(2), then
    // inserts DbgLine(3) at the next statement.
    let od = [
        0x06, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x08, 0x85, 9, 0, 0x38, 0, 0, 0, 0x40, 0x0b, 9, 0,
        0x51, 0x97, 9, 0,
    ];
    let source = [
        OpenDreamSourceInfo {
            offset: 0,
            file: Some(295),
            line: 2,
        },
        OpenDreamSourceInfo {
            offset: 12,
            file: None,
            line: 3,
        },
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 295).then_some(437)
        }
    }
    let out = lower_proc_bytecode_with_debug_info(&od, &Ids, 1, &[], &source).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[0].name, "DbgFile");
    assert_eq!(instructions[0].operands, [437]);
    assert_eq!(instructions[1].name, "DbgLine");
    assert_eq!(instructions[1].operands, [2]);
    let line3 = instructions
        .iter()
        .position(|item| item.name == "DbgLine" && item.operands == [3])
        .unwrap();
    assert_eq!(instructions[line3 + 1].name, "PushVal");
}
#[test]
fn debug_initializers_use_paired_marker_order() {
    use crate::opendream::OpenDreamSourceInfo;
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 295).then_some(437)
        }
    }
    let class = [0x0a, 6, 0, 0, 0, 0, 0, 0x11];
    let class_source = [OpenDreamSourceInfo {
        offset: 7,
        file: Some(295),
        line: 2,
    }];
    let out = lower_class_init_bytecode_with_debug_info(&class, &Ids, &class_source).unwrap();
    assert_eq!(&out[..4], &[0x85, 2, 0x84, 437]);
    let global_source = [OpenDreamSourceInfo {
        offset: 0,
        file: Some(295),
        line: 1,
    }];
    let out = lower_global_init_bytecode_with_debug_info(&[0x11], &Ids, &global_source).unwrap();
    assert_eq!(&out[..4], &[0x84, 437, 0x85, 1]);
}
#[test]
fn dynamic_calls_place_targets_before_arguments() {
    // Paired dynamic_call and dynamic_call_path fixtures.
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 297).then_some(438)
        }
    }
    let argument = [0x38, 0, 0, 0x80, 0x40]; // 4.0
    let mut path = argument.to_vec();
    path.extend([0x03, 41, 1, 0, 0, 0x9e, 1, 1, 0, 0, 0, 0x10]);
    assert_eq!(
        lower_proc_bytecode(&path, &Ids).unwrap(),
        [0x60, 6, 438, 0x60, 0x2a, 0x4080, 0, 0x2b, 1, 0x12, 0]
    );
    let mut name = argument.to_vec();
    name.extend([0x03, 41, 1, 0, 0, 0x06, 8, 0, 0x9e, 1, 1, 0, 0, 0, 0x10]);
    assert_eq!(
        lower_proc_bytecode(&name, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x60, 6, 438, 0x60, 0x2a, 0x4080, 0, 0xb5, 1, 0x12, 0]
    );
}
#[test]
fn stock_ambiguous_dynamic_call_is_rejected() {
    let error = lower_proc_bytecode(&[0x23, 0, 0, 0, 0, 0], &()).unwrap_err();
    assert!(error.reason.contains("conflates call() and call_ext()"));
}
#[test]
fn repeated_direct_method_call_reuses_receiver_cache() {
    let od = [
        0x06, 9, 0, 0x6a, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0x06, 9, 0, 0x6a, 1, 0, 0, 0, 0, 0, 0, 0, 0,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 1).then_some(39)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let calls: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .into_iter()
        .filter(|item| item.name == "Call")
        .collect();
    assert_eq!(calls.len(), 2);
    assert_eq!(calls[0].operands, [0xffdc, 0xffda, 0, 0xffdd, 39, 0]);
    assert_eq!(calls[1].operands, [0xffdd, 39, 0]);
}
#[test]
fn prompt_text_reorders_arguments_like_dreammaker() {
    // Paired input fixture: input(M, "Question", "Title", "Default") as text.
    let od = [
        0x8c, 3, 0, 0, 0, 40, 1, 0, 0, 41, 1, 0, 0, 42, 1, 0, 0, 0x06, 8, 0, 0x11, 0x45, 2, 0, 0,
        0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (296..=298).contains(&old).then_some(old + 142)
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x60, 6, 440, 0x60, 6, 439, 0x60, 6, 438, 0xc1, 4, 0, 0, 0xba, 0x12, 0]
    );
    // DeepQuarry stripped_multiline_input uses the same argument shape
    // with `as message|null`; native Input carries mask 2176.
    let mut message_or_null = od;
    let type_at = message_or_null.len() - 5;
    message_or_null[type_at] = 0x41;
    let mut expected = lower_proc_bytecode(&od, &Ids).unwrap();
    let native_type_at = expected.len() - 6;
    expected[native_type_at] = 2176;
    assert_eq!(
        lower_proc_bytecode(&message_or_null, &Ids).unwrap(),
        expected
    );
}
#[test]
fn indexed_assignment_after_local_capture_reloads_list_after_value() {
    // Paired DeepQuarry ___TraitAdd: OD retains the captured list on the
    // stack, while DreamMaker stores and reloads it after NewList(source).
    let od = [
        0x06, 8, 0, // list
        0x09, 9, 0, // capture into Local0, retain list
        0x06, 8, 1, // key
        0x06, 8, 2, // source
        0x22, 1, 0, 0, 0, // list(source)
        0x85, 7, // list[key] = value, discard
        0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {}
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [
            0x33, 0xffd9, 0, 0x34, 0xffda, 0, 0x33, 0xffd9, 2, 0x1a, 1, 0x33, 0xffda, 0, 0x33,
            0xffd9, 1, 0x7c, 0x12, 0,
        ]
    );
}
#[test]
fn indexed_assignment_with_preincrement_key_moves_value_first() {
    // Paired add_verb uses output_list[++output_list.len] = list(...).
    let od = [
        0x06, 9, 0, // destination list
        0x62, 9, 1, // preincremented index
        0x38, 0, 0, 0x80, 0x3f, // value
        0x85, 7, 0x10,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    assert_eq!(
        out,
        [0x60, 0x2a, 0x3f80, 0, 0x33, 0xffda, 0, 0x62, 0xffda, 1, 0x7c, 0x12, 0]
    );
}
#[test]
fn compact_float_field_assignment_consumes_its_owner() {
    // Paired float_field: owner.value = 0/1 becomes one native SetCache
    // operand instead of leaving the OpenDream owner below the scalar.
    for bits in [0, 1.0f32.to_bits()] {
        for packed in [false, true] {
            let mut od = vec![0x06, 8, 0, if packed { 0x9b } else { 0x9a }];
            if packed {
                od.extend(1u32.to_le_bytes());
            }
            od.extend(bits.to_le_bytes());
            od.push(12);
            od.extend(300u32.to_le_bytes());
            assert_eq!(
                lower_proc_bytecode(&od, &()).unwrap(),
                [
                    0x60,
                    0x2a,
                    bits >> 16,
                    bits & 0xffff,
                    0x34,
                    0xffdc,
                    0xffd9,
                    0,
                    300,
                    0
                ]
            );
        }
    }
}
#[test]
fn guarded_indexed_augmented_rhs_matches_paired_compilers() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/indexed_aug.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/indexed_aug.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram);
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (self.0.procs.get(old as usize)?.name != "round").then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (self.0.procs.get(old as usize)?.name == "round").then_some(0x43)
        }
    }
    fn normalized(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
        let instructions = byond_dmb::bytecode::decode(words).unwrap();
        instructions
            .iter()
            .map(|item| {
                let mut opcode = item.opcode;
                let mut operands = item.operands.clone();
                if opcode == 0x50 {
                    operands = vec![(operands[0] as i32 as f32).to_bits()];
                } else if opcode == 0x60 && operands[0] == 0x2a {
                    opcode = 0x50;
                    operands = vec![(operands[1] << 16) | operands[2]];
                } else if matches!(opcode, 0x0f | 0x11) {
                    operands[0] = instructions
                        .iter()
                        .position(|target| target.offset == operands[0] as usize)
                        .unwrap() as u32;
                }
                (opcode, operands)
            })
            .collect()
    }
    for name in ["ia_append", "ia_subtract", "ia_multiply"] {
        let proc_ = program
            .procs
            .iter()
            .find(|proc_| proc_.name == name)
            .unwrap();
        let actual = lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &Ids(&program))
            .unwrap_or_else(|error| panic!("{name}: {error:?}"));
        let native_id = native
            .procs
            .iter()
            .position(|proc_| {
                native.string(proc_.strings[0]) == Some(format!("/proc/{name}").as_bytes())
            })
            .unwrap();
        assert_eq!(
            normalized(&actual),
            normalized(native.proc_code_words(native_id).unwrap()),
            "{name}"
        );
    }
}
#[test]
fn guarded_indexed_assignment_rhs_matches_paired_nested_and_call_expressions() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/indexed_conditional_legacy.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/indexed_conditional.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram);
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (self.0.procs.get(old as usize)?.name != "round").then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (self.0.procs.get(old as usize)?.name == "round").then_some(0x43)
        }
    }
    fn normalized(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
        let instructions = byond_dmb::bytecode::decode(words).unwrap();
        instructions
            .iter()
            .map(|item| {
                let mut opcode = item.opcode;
                let mut operands = item.operands.clone();
                if opcode == 0x50 {
                    operands = vec![(operands[0] as i32 as f32).to_bits()];
                } else if opcode == 0x60 && operands[0] == 0x2a {
                    opcode = 0x50;
                    operands = vec![(operands[1] << 16) | operands[2]];
                } else if matches!(opcode, 0x0f | 0x11) {
                    operands[0] = instructions
                        .iter()
                        .position(|target| target.offset == operands[0] as usize)
                        .unwrap() as u32;
                }
                (opcode, operands)
            })
            .collect()
    }
    for name in ["ic_round", "ic_nested", "ic_effect", "ic_two"] {
        let proc_ = program
            .procs
            .iter()
            .find(|proc_| proc_.name == name)
            .unwrap();
        let actual = lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &Ids(&program))
            .unwrap_or_else(|error| panic!("{name}: {error:?}"));
        let native_id = native
            .procs
            .iter()
            .position(|proc_| {
                native.string(proc_.strings[0]) == Some(format!("/proc/{name}").as_bytes())
            })
            .unwrap();
        assert_eq!(
            normalized(&actual),
            normalized(native.proc_code_words(native_id).unwrap()),
            "{name}"
        );
    }
}
#[test]
fn initial_field_matches_dreammaker_operand_nesting() {
    let od = [0x06, 8, 0, 0x03, 44, 1, 0, 0, 0x47, 0x10];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 300).then_some(39)
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffdc, 0xffd9, 0, 0xffe7, 39, 0x12, 0]
    );
}
#[test]
fn initial_and_issaved_computed_owner_match_native_cache_pop() {
    for (od_op, native_op) in [(0x47, 0xffe7), (0x53, 0xffe8)] {
        let od = [
            0x11, 0x02, 2, 0, 0, 0, 0x2e, 0, 0, 0, 0, 0, 0x03, 41, 1, 0, 0, od_op, 0x10,
        ];
        assert_eq!(
            lower_proc_bytecode(&od, &()).unwrap(),
            [0x60, 32, 2, 0x01, 0, 0x34, 0xffd8, 0x33, native_op, 297, 0x12, 0]
        );
    }
}
#[test]
fn initial_and_issaved_preserve_wide_string_ids() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, _: u32) -> Option<u32> {
            Some(0x12345)
        }
    }
    for (od_op, native_op) in [(0x47, 0xffe7), (0x53, 0xffe8)] {
        let od = [0x06, 8, 0, 0x03, 44, 1, 0, 0, od_op, 0x10];
        assert_eq!(
            lower_proc_bytecode(&od, &Ids).unwrap(),
            [0x33, 0xffdc, 0xffd9, 0, native_op, 0x12345, 0x12, 0]
        );
    }
}
#[test]
fn nested_dereference_field_matches_dreammaker_variable() {
    // list_constants /world/New: fixture.entry.len.
    let od = [
        0x86, 9, 0, 40, 1, 0, 0, // local0.field296
        0x68, 41, 1, 0, 0, // .field297
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(match old {
                296 => 440,
                297 => 57,
                _ => old,
            })
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffdc, 0xffda, 0, 0xffdc, 440, 57, 0]
    );
    let source = [crate::opendream::OpenDreamSourceInfo {
        offset: 7,
        file: Some(900),
        line: 40,
    }];
    let debug = lower_proc_bytecode_with_debug_info(&od, &Ids, 1, &[], &source).unwrap();
    let instructions = byond_dmb::bytecode::decode(&debug).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.opcode == 0x84 && item.operands == [900]));
    assert!(instructions
        .iter()
        .any(|item| item.opcode == 0x85 && item.operands == [40]));
    let stripped: Vec<_> = instructions
        .into_iter()
        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
        .flat_map(|item| std::iter::once(item.opcode).chain(item.operands))
        .collect();
    assert_eq!(stripped, lower_proc_bytecode(&od, &Ids).unwrap());
    assert!(
        !stripped.contains(&0x34),
        "debug marker must not force an eager receiver cache"
    );
}
#[test]
fn synthetic_initializer_omits_only_its_leading_super_call() {
    let od = [0x0a, 6, 0, 0, 0, 0, 0];
    assert_eq!(lower_init_bytecode(&od, &()).unwrap(), [0]);
    assert!(lower_proc_bytecode(&od, &()).is_err());
}
#[test]
fn class_initializer_field_uses_dreammaker_nested_src_cache() {
    let od = [
        0x0a, 6, 0, 0, 0, 0, 0, // synthetic super init
        0x8f, 2, 0, 0, 0, 0, 0, 0x80, 0x40, 0, 0, 0xa0, 0x40, 0x85, 13, 40, 1, 0, 0,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 296).then_some(440)
        }
    }
    let out = lower_init_bytecode(&od, &Ids).unwrap();
    assert!(out
        .windows(6)
        .any(|words| { words == [0x34, 0xffdc, 0xffce, 0xffdc, 0xffce, 440] }));
}
#[test]
fn list_mutation_matches_paired_compilers() {
    let list_ops = [
        0x06, 8, 1, 0x84, 8, 0, 0x06, 8, 1, 0x1f, 8, 0, 0x51, 0x97, 8, 0,
    ];
    assert_eq!(
        lower_proc_bytecode(&list_ops, &()).unwrap(),
        [
            0x33, 0xffd9, 1, 0x45, 0xffd9, 0, 0x33, 0xffd9, 1, 0x46, 0xffd9, 0, 0x33, 0xffd9, 0,
            0x12, 0
        ]
    );
    let index_set = [
        0x87, 3, 0, 0, 0, 8, 0, 8, 1, 8, 2, 0x85, 7, 0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x69, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&index_set, &()).unwrap(),
        [
            0x33, 0xffd9, 2, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x7c, 0x33, 0xffd9, 0, 0x33, 0xffd9,
            1, 0x7b, 0x12, 0
        ]
    );
}
#[test]
fn positional_associative_entries_get_numeric_keys() {
    let od = [
        0x11, 0x38, 0, 0, 0x80, 0x3f, // null key, 1
        0x11, 0x38, 0, 0, 0, 0x40, // null key, 2
        0x1e, 2, 0, 0, 0, 0x10,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    assert_eq!(
        out,
        [0x50, 1, 0x60, 0x2a, 0x3f80, 0, 0x50, 2, 0x60, 0x2a, 0x4000, 0, 0xc8, 2, 0x12, 0]
    );
}
#[test]
fn computed_single_dimension_list_uses_empty_list() {
    // Native add_leading computes max(charcount + 1, 0), then EmptyList.
    let od = [0x38, 0, 0, 0x40, 0x40, 0x30, 1, 0, 0, 0, 0x10];
    let lowered = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = byond_dmb::bytecode::decode(&lowered).unwrap();
    assert_eq!(instructions[1].name, "EmptyList");
}
#[test]
fn unary_num2text_uses_native_general_conversion() {
    // Paired stationdate2text uses Num2Text (0x77) for num2text(x).
    let od = [
        0x38, 0, 0, 0x80, 0x3f, 0x0a, 0x0b, 9, 0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old != 9).then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0x159)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[1].name, "Num2Text");
}
#[test]
fn time2text_with_timezone_uses_native_three_argument_form() {
    // Paired time_stamp uses Time2TextTZ [3].
    let od = [
        0x38, 0, 0, 0x80, 0x3f, 0x03, 4, 0, 0, 0, 0x38, 0, 0, 0, 0, 0x0a, 0x0b, 9, 0, 0, 0, 1, 3,
        0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(old)
        }
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old != 9).then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0xc0)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.name == "Time2TextTZ" && item.operands == [3]));
}
#[test]
fn findlasttext_two_arguments_supplies_native_defaults() {
    // Paired get_end_section_of_type emits PushInt0, PushInt1,
    // FindLastText after its two source arguments.
    let od = [
        0x03, 4, 0, 0, 0, 0x03, 5, 0, 0, 0, 0x0a, 0x0b, 9, 0, 0, 0, 1, 2, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(old)
        }
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old != 9).then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0x132)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    let names = instructions
        .iter()
        .map(|item| item.name)
        .collect::<Vec<_>>();
    assert!(names
        .windows(3)
        .any(|items| items == ["PushInt", "PushInt", "FindLastText"]));
}
#[test]
fn get_step_towards_uses_native_binary_opcode() {
    // Paired can_see uses GetStepTowards with two arguments.
    let od = [
        0x06, 8, 0, 0x06, 8, 1, 0x0a, 0x0b, 9, 0, 0, 0, 1, 2, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old != 9).then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0x93)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[2].name, "GetStepTowards");
}
#[test]
fn list2params_uses_native_unary_opcode() {
    // Paired topic_link calls list2params(params).
    let od = [0x06, 8, 0, 0x0a, 0x0b, 9, 0, 0, 0, 1, 1, 0, 0, 0, 0x10];
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old != 9).then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0xb7)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[1].name, "List2Params");
}
#[test]
fn isloc_materializes_native_flag_value() {
    // Paired get_flat_icon: isloc(appearancelike) feeds a condition.
    let od = [0x06, 8, 0, 0x0a, 0x0b, 9, 0, 0, 0, 1, 1, 0, 0, 0, 0x10];
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old != 9).then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0x13)
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x13, 0x36, 0x12, 0]
    );
}
#[test]
fn runtime_stub_shell_and_walk_away_use_native_opcodes() {
    // Paired runtime-stubs fixture: these OD runtime stubs remain native
    // builtins in a DMB, despite warnings in OpenDream's standard library.
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            match old {
                151 => Some(0x98),
                168 => Some(0x125),
                _ => None,
            }
        }
    }
    let shell = [
        0x03, 48, 1, 0, 0, 0x0a, 0x0b, 151, 0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    let shell_words = lower_proc_bytecode(&shell, &Ids).unwrap();
    assert_eq!(&shell_words[3..4], &[0x98]);
    let mut walk = vec![0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x88, 3, 0, 0, 0];
    walk.extend([0, 0, 0xa0, 0x40, 0, 0, 0, 0x40, 0, 0, 0, 0]);
    walk.extend([0x0a, 0x0b, 168, 0, 0, 0, 1, 5, 0, 0, 0, 0x51]);
    let walk_words = lower_proc_bytecode(&walk, &Ids).unwrap();
    assert!(walk_words.contains(&0x125));
}
#[test]
fn ref_builtin_uses_native_unary_opcode() {
    // Paired qdel line 477: GLOB.gc_queue[ref(to_delete)] = TRUE.
    let od = [0x06, 8, 0, 0x0a, 0x0b, 9, 0, 0, 0, 1, 1, 0, 0, 0, 0x10];
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0x148)
        }
    }
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    assert_eq!(&words[..4], &[0x33, 0xffd9, 0, 0x148]);
}
