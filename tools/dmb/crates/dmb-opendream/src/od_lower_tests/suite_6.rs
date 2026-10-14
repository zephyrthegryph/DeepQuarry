use super::*;

#[test]
fn heterogeneous_literal_switch_tables_match_native_cases_and_destinations() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/flow_switch_mixed.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/flow_switch_mixed.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let value = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(value))
                .map(|id| id as u32)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            match self.0.types.get(old as usize)?.path.as_str() {
                "/datum" => Some(32),
                "/mob" => Some(8),
                _ => None,
            }
        }
        fn type_id(&self, _: u32) -> Option<u32> {
            Some(0)
        }
    }
    let signature = |words: &[u32]| {
        let items = byond_dmb::bytecode::decode(words).unwrap();
        assert_eq!(items[0].opcode, 0x33);
        assert_eq!(items[0].operands, [0xffd9, 0]);
        assert!(!items.iter().any(|item| item.opcode == 0x51));
        let switch = &items[1];
        let destination = |offset: u32| {
            let item = items
                .iter()
                .find(|item| item.offset == offset as usize)
                .unwrap();
            let bits = if item.opcode == 0x50 {
                (item.operands[0] as f32).to_bits()
            } else {
                assert_eq!(item.opcode, 0x60);
                Value::decode(&item.operands)
                    .unwrap()
                    .0
                    .number_bits()
                    .unwrap()
            };
            assert_eq!(
                items
                    .iter()
                    .find(|next| next.offset == item.offset + 1 + item.operands.len())
                    .unwrap()
                    .opcode,
                0x12
            );
            bits
        };
        let mut at = 1;
        let mut ranges = Vec::new();
        let cases_count = if switch.opcode == 0x7a {
            for _ in 0..switch.operands[0] {
                let (low, used) = Value::decode(&switch.operands[at..]).unwrap();
                at += used;
                let (high, used) = Value::decode(&switch.operands[at..]).unwrap();
                at += used;
                let target = switch.operands[at];
                at += 1;
                ranges.push((format!("{low:?}"), format!("{high:?}"), destination(target)));
            }
            let count = switch.operands[at];
            at += 1;
            count
        } else {
            assert_eq!(switch.opcode, 0x78);
            switch.operands[0]
        };
        let mut cases = Vec::new();
        for _ in 0..cases_count {
            let (value, used) = Value::decode(&switch.operands[at..]).unwrap();
            at += used;
            let target = switch.operands[at];
            at += 1;
            cases.push((format!("{value:?}"), destination(target)));
        }
        cases.sort();
        ranges.sort();
        (cases, ranges, destination(switch.operands[at]))
    };
    for proc_ in input
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("flow_switch_"))
    {
        let id = native
            .procs
            .iter()
            .position(|p| {
                native.string(p.strings[0]) == Some(format!("/proc/{}", proc_.name).as_bytes())
            })
            .unwrap();
        let actual =
            lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &Ids(&input, &native)).unwrap();
        assert_eq!(
            signature(&actual),
            signature(native.proc_code_words(id).unwrap()),
            "{}",
            proc_.name
        );
    }
}
#[test]
fn switch_ranges_lower_to_native_table() {
    let od = [
        0x06, 8, 0, 0x88, 2, 0, 0, 0, 0, 0, 0x80, 0x3f, 0, 0, 0x40, 0x40, 0x05, 45, 0, 0, 0, 0x88,
        2, 0, 0, 0, 0, 0, 0xa0, 0x40, 0, 0, 0xe0, 0x40, 0x05, 55, 0, 0, 0, 0x51, 0x0e, 60, 0, 0, 0,
        0x98, 0, 0, 0x20, 0x41, 0x0e, 60, 0, 0, 0, 0x98, 0, 0, 0xa0, 0x41, 0x98, 0, 0, 0, 0,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[1].name, "SwitchRange");
    assert_eq!(instructions[1].operands[0], 2);
    assert_eq!(instructions[1].operands[15], 0); // no exact cases
}
#[test]
fn interleaved_switch_range_and_exact_cases_share_native_table() {
    // Paired reject_bad_name uses range, exact, then another range. Native
    // SwitchRange stores two separate case tables in one instruction.
    let od = [
        0x06, 8, 0, 0x88, 2, 0, 0, 0, 0, 0, 0x80, 0x3f, 0, 0, 0x40, 0x40, 0x05, 54, 0, 0, 0, 0x8d,
        0, 0, 0xa0, 0x40, 54, 0, 0, 0, 0x88, 2, 0, 0, 0, 0, 0, 0xc0, 0x40, 0, 0, 0xe0, 0x40, 0x05,
        54, 0, 0, 0, 0x51, 0x0e, 54, 0, 0, 0, 0x11, 0x10,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[1].name, "SwitchRange");
    assert_eq!(instructions[1].operands[0], 2);
    assert_eq!(instructions[1].operands[15], 1);
}
#[test]
fn exact_first_switch_interleaves_range_batches() {
    // chat_progress_bar's native table starts with nineteen ranges and
    // two exact cases even though OD starts with its exact 100 case.
    let od = [
        0x06, 8, 0, 0x8d, 0, 0, 0xc8, 0x42, 63, 0, 0, 0, 0x88, 2, 0, 0, 0, 0, 0, 0xbe, 0x42, 0, 0,
        0xc6, 0x42, 0x05, 63, 0, 0, 0, 0x8d, 0, 0, 0, 0, 63, 0, 0, 0, 0x88, 2, 0, 0, 0, 0, 0, 0xb4,
        0x42, 0, 0, 0xbc, 0x42, 0x05, 63, 0, 0, 0, 0x51, 0x0e, 63, 0, 0, 0, 0x11, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = byond_dmb::bytecode::decode(&words).unwrap();
    let table = &instructions[1];
    assert_eq!(table.name, "SwitchRange");
    assert_eq!(table.operands[0], 2);
    assert_eq!(table.operands[15], 2);
    assert_eq!(table.operands[1..7], [42, 0x42be, 0, 42, 0x42c6, 0]);
    assert_eq!(table.operands[16..19], [42, 0x42c8, 0]);
    let default = *table.operands.last().unwrap();
    for index in [7, 14, 19, 23] {
        assert_eq!(table.operands[index], default);
    }
    assert_eq!(default, instructions[2].offset as u32);
}
#[test]
fn type_path_switch_preserves_native_case_value_tags() {
    // Paired type2top switches over /datum, /atom, /obj, /mob, ... .
    let od = [
        0x06, 8, 0, 0x02, 1, 0, 0, 0, 0x32, 29, 0, 0, 0, 0x02, 2, 0, 0, 0, 0x32, 29, 0, 0, 0, 0x51,
        0x0e, 29, 0, 0, 0, 0x11, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_tag(&self, old: u32) -> Option<u8> {
            Some(if old == 1 { 32 } else { 10 })
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[1].name, "Switch");
    assert_eq!(instructions[1].operands[0], 2);
    assert_eq!(instructions[1].operands[1], 32);
    assert_eq!(instructions[1].operands[4], 10);
}
#[test]
fn try_catch_throw_matches_paired_compiler_shape() {
    let od = [
        0x6f, 31, 0, 0, 0, 9, 0, 0x8b, 8, 0, 20, 0, 0, 0, 0x03, 41, 1, 0, 0, 0x5a, 0x98, 0, 0,
        0x80, 0x3f, 0x71, 0x0e, 34, 0, 0, 0, 0x97, 9, 0,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[0].name, "Try");
    assert_eq!(instructions[5].name, "Throw");
    assert_eq!(instructions[8].name, "Catch");
    assert_eq!(instructions[9].name, "SetVar");
    assert_eq!(instructions[0].operands[0], instructions[9].offset as u32);
}
#[test]
fn augmented_reference_statements_match_dreammaker() {
    let od = [
        0x06, 8, 1, 0x0b, 8, 0, 0x51, 0x06, 8, 1, 0x17, 8, 0, 0x51, 0x06, 8, 1, 0x39, 8, 0, 0x51,
        0x06, 8, 1, 0x33, 8, 0, 0x51, 0x06, 8, 1, 0x2d, 8, 0, 0x51, 0x06, 8, 1, 0x29, 8, 0, 0x51,
        0x38, 0, 0, 0x80, 0x3f, 0x6d, 8, 0, 0x51, 0x38, 0, 0, 0x80, 0x3f, 0x6e, 8, 0, 0x51, 0x97,
        8, 0,
    ];
    let lowered = lower_proc_bytecode(&od, &()).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&lowered)
        .unwrap()
        .iter()
        .map(|instruction| instruction.name)
        .collect();
    assert_eq!(
        names,
        [
            "GetVar",
            "AugMul",
            "GetVar",
            "AugDiv",
            "GetVar",
            "AugMod",
            "GetVar",
            "AugBand",
            "GetVar",
            "AugBor",
            "GetVar",
            "AugXor",
            "PushVal",
            "AugLShift",
            "PushVal",
            "AugRShift",
            "GetVar",
            "Ret",
            "End"
        ]
    );
}
#[test]
fn rgb_three_and_four_component_forms_match_dreammaker() {
    let rgb = [
        0x87, 3, 0, 0, 0, 8, 0, 8, 1, 8, 2, 0x07, 1, 3, 0, 0, 0, 0x10,
    ];
    let rgba = [
        0x87, 4, 0, 0, 0, 8, 0, 8, 1, 8, 2, 8, 3, 0x07, 1, 4, 0, 0, 0, 0x10,
    ];
    let rgb_out = lower_proc_bytecode(&rgb, &()).unwrap();
    let rgba_out = lower_proc_bytecode(&rgba, &()).unwrap();
    assert_eq!(rgb_out[rgb_out.len() - 3..], [0xbb, 0x12, 0]);
    assert_eq!(rgba_out[rgba_out.len() - 3..], [0x113, 0x12, 0]);
}
#[test]
fn rgb_colorspace_and_native_animate_forms_match_paired_opcodes() {
    let rgb = [
        0x87, 5, 0, 0, 0, 8, 0, 8, 1, 8, 2, 8, 3, 8, 4, 0x07, 1, 5, 0, 0, 0, 0x10,
    ];
    let output = lower_proc_bytecode(&rgb, &()).unwrap();
    assert_eq!(output[output.len() - 3..], [0x161, 0x12, 0]);
    let keyed = [
        0x38, 0, 0, 128, 63, 0x38, 0, 0, 0, 64, 0xa7, 2, 2, 0, 0, 0, 0x10,
    ];
    let output = lower_proc_bytecode(&keyed, &()).unwrap();
    assert_eq!(output[output.len() - 5..], [0xc8, 1, 0x128, 0x12, 0]);
    let direct = [0x38, 0, 0, 128, 63, 0xa7, 1, 1, 0, 0, 0, 0x10];
    let output = lower_proc_bytecode(&direct, &()).unwrap();
    assert_eq!(output[output.len() - 3..], [0x129, 0x12, 0]);
}
#[test]
fn addtext_mass_concatenation_matches_dreammaker() {
    let od = [0x87, 3, 0, 0, 0, 8, 0, 8, 1, 8, 2, 0x5c, 3, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x6c, 3, 0x12, 0]
    );
}
#[test]
fn guarded_append_debug_branch_markers_match_native() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/guarded_append_debug.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/guarded_append_debug.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let name = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(name))
                .map(|id| id as u32)
        }
    }
    let proc_ = program
        .procs
        .iter()
        .find(|p| p.name == "debug_conditional_append")
        .unwrap();
    let actual = lower_proc_bytecode_with_debug_info(
        proc_.bytecode.as_deref().unwrap(),
        &Ids(&program, &native),
        proc_.max_variable_id,
        &proc_.locals,
        &proc_.source_info,
    )
    .unwrap();
    fn normalized(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
        let instructions = byond_dmb::bytecode::decode(words).unwrap();
        let executable: Vec<_> = instructions
            .iter()
            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
            .collect();
        executable
            .iter()
            .map(|item| {
                let mut opcode = item.opcode;
                let mut operands = item.operands.clone();
                if opcode == 0x50 {
                    operands = vec![(operands[0] as i32 as f32).to_bits()];
                } else if opcode == 0x60 && operands[0] == 42 {
                    opcode = 0x50;
                    operands = vec![(operands[1] << 16) | operands[2]];
                } else if matches!(opcode, 0x0f | 0x11) {
                    operands[0] = executable
                        .iter()
                        .position(|target| target.offset >= operands[0] as usize)
                        .unwrap() as u32;
                }
                (opcode, operands)
            })
            .collect()
    }
    let id = native
        .procs
        .iter()
        .position(|p| native.string(p.strings[0]) == Some(b"/proc/debug_conditional_append"))
        .unwrap();
    assert_eq!(
        normalized(&actual),
        normalized(native.proc_code_words(id).unwrap())
    );
    assert!(byond_dmb::bytecode::decode(&actual)
        .unwrap()
        .iter()
        .any(|item| item.opcode == 0x84));
}
#[test]
fn indexed_append_debug_markers_preserve_native_expression_semantics() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/indexed_append_debug.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/indexed_append_debug.bin"
    ))
    .unwrap();
    let proc_ = program
        .procs
        .iter()
        .find(|p| p.name == "debug_indexed_append")
        .unwrap();
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(if old == 295 { 440 } else { old })
        }
    }
    let actual = lower_proc_bytecode_with_debug_info(
        proc_.bytecode.as_deref().unwrap(),
        &Ids,
        proc_.max_variable_id,
        &proc_.locals,
        &proc_.source_info,
    )
    .unwrap();
    let instructions = byond_dmb::bytecode::decode(&actual).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.opcode == 0x84 && item.operands == [440]));
    assert!(instructions
        .iter()
        .any(|item| item.opcode == 0x85 && item.operands == [2]));
    fn normalized(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
        byond_dmb::bytecode::decode(words)
            .unwrap()
            .into_iter()
            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
            .map(|item| match item.opcode {
                0x50 => (0x50, vec![(item.operands[0] as i32 as f32).to_bits()]),
                0x60 if item.operands[0] == 42 => {
                    (0x50, vec![(item.operands[1] << 16) | item.operands[2]])
                }
                opcode => (opcode, item.operands),
            })
            .collect()
    }
    assert_eq!(
        normalized(&actual),
        normalized(native.proc_code_words(0).unwrap())
    );
    assert_eq!(
        constructor_argument_start(
            &[0x33, 0xffd9, 0, 0x85, 9, 0x34, 0xffd8, 0x85, 10, 0x33, 123],
            1
        ),
        Some(0)
    );
    assert_eq!(
        constructor_argument_start(
            &[0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x37, 0x85, 11, 0x51, 0x36, 0x85, 12],
            1
        ),
        Some(0)
    );
    // A marker at the receiver boundary must not change a deferred direct
    // method receiver into an eagerly evaluated cached receiver.
    let call = [
        0x06, 8, 0, 0xa3, 0x06, 8, 1, 0x6a, 77, 0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    let source = [crate::opendream::OpenDreamSourceInfo {
        offset: 3,
        file: Some(9),
        line: 10,
    }];
    let plain = lower_proc_bytecode(&call, &()).unwrap();
    let debug = lower_proc_bytecode_with_debug_info(&call, &(), 0, &[], &source).unwrap();
    assert_eq!(normalized(&plain), normalized(&debug));
    let debug = byond_dmb::bytecode::decode(&debug).unwrap();
    assert_eq!(debug[0].opcode, 0x84);
    assert_eq!(debug[1].opcode, 0x85);
    assert!(!debug
        .iter()
        .any(|item| matches!(item.opcode, 0x142 | 0x143)));
    let condition = [0x06, 8, 0, 0x06, 8, 1, 0x0f, 0x0c, 12, 0, 0, 0, 0x10];
    let source = [crate::opendream::OpenDreamSourceInfo {
        offset: 7,
        file: Some(9),
        line: 11,
    }];
    let debug = lower_proc_bytecode_with_debug_info(&condition, &(), 0, &[], &source).unwrap();
    let instructions = byond_dmb::bytecode::decode(&debug).unwrap();
    let semantic: Vec<_> = instructions
        .iter()
        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
        .map(|item| item.opcode)
        .collect();
    assert_eq!(semantic, [0x33, 0x33, 0x37, 0x51, 0x11, 0x12, 0]);
}
#[test]
fn bare_self_call_names_match_native_owner_binding() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/self_call_names.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/self_call_names.bin"
    ))
    .unwrap();
    struct Ids<'a> {
        program: &'a crate::opendream::OpenDreamProgram,
        native: &'a byond_dmb::dmb::Dmb,
        owner: usize,
    }
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let name = self.program.strings.get(old as usize)?.as_bytes();
            (0..self.native.strings.len())
                .find(|id| self.native.string(*id as u32) == Some(name))
                .map(|id| id as u32)
        }
        fn self_call_name(&self, field: u32) -> Option<u32> {
            let name = self.program.strings.get(field as usize)?;
            let mut owner = self.owner;
            loop {
                let type_ = self.program.types.get(owner)?;
                if self
                    .program
                    .procs
                    .iter()
                    .any(|proc_| proc_.owning_type_id == owner && proc_.name == *name)
                {
                    let paths = [
                        format!("{}/proc/{name}", type_.path),
                        format!("{}/{name}", type_.path),
                    ];
                    return self
                        .native
                        .procs
                        .iter()
                        .find(|proc_| {
                            paths.iter().any(|path| {
                                self.native.string(proc_.strings[0]) == Some(path.as_bytes())
                            })
                        })
                        .map(|proc_| proc_.strings[1]);
                }
                owner = type_.parent?;
            }
        }
    }
    for proc_ in program
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("call_"))
    {
        let owner = &program.types[proc_.owning_type_id].path;
        let path = format!("{owner}/proc/{}", proc_.name);
        let native_id = native
            .procs
            .iter()
            .position(|p| native.string(p.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let words = lower_proc_bytecode(
            proc_.bytecode.as_deref().unwrap(),
            &Ids {
                program: &program,
                native: &native,
                owner: proc_.owning_type_id,
            },
        )
        .unwrap();
        assert_eq!(words, native.proc_code_words(native_id).unwrap(), "{path}");
    }
}
#[test]
fn method_search_and_display_names_match_native_calls() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/call_selectors.json"
    ))
    .unwrap();
    let native =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/lowering/call_selectors.bin"))
            .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let name = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(name))
                .map(|id| id as u32)
        }
        fn method_call_name(&self, target: u32, field: u32) -> Option<u32> {
            if target == u32::MAX {
                return self.string(field);
            }
            let proc_ = self.0.procs.get(target as usize)?;
            let owner = &self.0.types.get(proc_.owning_type_id)?.path;
            let paths = [
                format!("{owner}/proc/{}", proc_.name),
                format!("{owner}/{}", proc_.name),
            ];
            self.1
                .procs
                .iter()
                .find(|proc_| {
                    paths
                        .iter()
                        .any(|path| self.1.string(proc_.strings[0]) == Some(path.as_bytes()))
                })
                .map(|proc_| proc_.strings[1])
        }
    }
    for name in [
        "typed_call",
        "child_call",
        "final_call",
        "final_safe_call",
        "typed_safe_call",
        "dynamic_call",
        "typed_dynamic_call",
    ] {
        let proc_ = program
            .procs
            .iter()
            .find(|proc_| proc_.name == name)
            .unwrap();
        let actual =
            lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &Ids(&program, &native))
                .unwrap();
        let id = native
            .procs
            .iter()
            .position(|p| native.string(p.strings[0]) == Some(format!("/proc/{name}").as_bytes()))
            .unwrap();
        assert_eq!(actual, native.proc_code_words(id).unwrap(), "{name}");
    }
}
#[test]
fn comparison_results_match_native_compiler() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/lowering/comparison_results.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/lowering/comparison_results.bin"
    ))
    .unwrap();
    for name in [
        "equality_result",
        "inequality_result",
        "equality_condition",
        "inequality_condition",
        "equality_and",
        "equality_or",
        "equality_not",
        "equality_sum",
        "equality_list",
        "equivalent_result",
        "not_equivalent_result",
        "condition_eq_or",
        "condition_eq_and",
        "condition_type_or",
        "condition_type_and",
        "condition_nested",
        "condition_membership_or",
        "condition_membership_and",
    ] {
        let proc_ = program.procs.iter().find(|p| p.name == name).unwrap();
        let actual = lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &()).unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|p| native.string(p.strings[0]) == Some(format!("/proc/{name}").as_bytes()))
            .unwrap();
        let expected = native.proc_code_words(native_id).unwrap();
        assert_eq!(actual, expected, "{name}");
    }
    // The scanner must retain both equality arguments when the result
    // becomes an argument to a constructor or other built-in.
    assert_eq!(
        constructor_argument_start(&[0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x37, 0x51, 0x36], 1),
        Some(0)
    );
    // An argument index equal to the Teq opcode is still a value, not
    // a comparison flag. Inspect instruction boundaries, not tail words.
    assert_eq!(
        lower_proc_bytecode(&[0x06, 8, 0x37, 0x0c, 8, 0, 0, 0, 0x10], &()).unwrap(),
        [0x33, 0xffd9, 0x37, 0x0d, 0x11, 6, 0x12, 0]
    );
}
#[test]
fn issaved_and_equivalent_match_paired_compilers() {
    let saved = [0x06, 8, 0, 0x03, 41, 1, 0, 0, 0x53, 0x10];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 297).then_some(39)
        }
    }
    assert_eq!(
        lower_proc_bytecode(&saved, &Ids).unwrap(),
        [0x33, 0xffdc, 0xffd9, 0, 0xffe8, 39, 0x12, 0]
    );
    let equiv = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x58, 0x10];
    assert_eq!(
        lower_proc_bytecode(&equiv, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x140, 0x12, 0]
    );
    let not_equiv = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x59, 0x10];
    assert_eq!(
        lower_proc_bytecode(&not_equiv, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x141, 0x12, 0]
    );
}
#[test]
fn safe_indexed_assignment_and_append_match_native_value_order() {
    for op in [0x09, 0x1a] {
        let od = [
            0x06, 8, 0, 0x65, 19, 0, 0, 0, 0x87, 2, 0, 0, 0, 8, 1, 8, 2, op, 7, 0x51,
        ];
        let mut native = vec![
            0x33,
            0xffd9,
            0,
            0x13e,
            if op == 0x09 { 16 } else { 21 },
            0x142,
            0x33,
            0xffd9,
            2,
            0x143,
            0x33,
            0xffd8,
            0x33,
            0xffd9,
            1,
        ];
        native.extend(if op == 0x09 {
            vec![0x7c, 0]
        } else {
            vec![0x34, 0xffe3, 0x34, 0xffd8, 0x45, 0xffe4, 0]
        });
        assert_eq!(lower_proc_bytecode(&od, &()).unwrap(), native);
    }
}
#[test]
fn safe_computed_and_nested_indices_match_native_cache_unwind() {
    let computed = [
        0x06, 8, 0, 0x65, 16, 0, 0, 0, 0x86, 8, 1, 41, 1, 0, 0, 0x69, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&computed, &()).unwrap(),
        [
            0x33, 0xffd9, 0, 0x13d, 15, 0x142, 0x33, 0xffd8, 0x33, 0xffdc, 0xffd9, 1, 297, 0x7b,
            0x143, 0x12, 0
        ]
    );
    let nested = [
        0x06, 8, 0, 0x65, 21, 0, 0, 0, 0x06, 8, 1, 0x69, 0x65, 21, 0, 0, 0, 0x06, 8, 2, 0x69, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&nested, &()).unwrap(),
        [
            0x33, 0xffd9, 0, 0x13d, 23, 0x142, 0x33, 0xffd8, 0x33, 0xffd9, 1, 0x7b, 0x13d, 22,
            0x142, 0x33, 0xffd8, 0x33, 0xffd9, 2, 0x7b, 0x143, 0x143, 0x12, 0
        ]
    );
}
#[test]
fn safe_method_named_and_arglist_calls_preserve_cached_receiver() {
    let named = [
        0x06, 8, 0, 0x65, 26, 0, 0, 0, 0x03, 44, 1, 0, 0, 0x06, 8, 1, 0x6a, 45, 1, 0, 0, 2, 2, 0,
        0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&named, &()).unwrap(),
        [
            0x33, 0xffd9, 0, 0x13d, 19, 0x142, 0x60, 6, 300, 0x33, 0xffd9, 1, 0xc8, 1, 0x143, 0x29,
            0xffdd, 301, 0xffff, 0x12, 0
        ]
    );
    let arglist = [
        0x06, 8, 0, 0x65, 21, 0, 0, 0, 0x06, 8, 1, 0x6a, 45, 1, 0, 0, 3, 1, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&arglist, &()).unwrap(),
        [
            0x33, 0xffd9, 0, 0x13d, 14, 0x142, 0x33, 0xffd9, 1, 0x143, 0x29, 0xffdd, 301, 0xffff,
            0x12, 0
        ]
    );
}
#[test]
fn nested_safe_lvalue_restores_each_receiver_on_null_exit() {
    let od = [
        0x06, 8, 0, 0x65, 27, 0, 0, 0, 0x68, 44, 1, 0, 0, 0x65, 27, 0, 0, 0, 0x06, 8, 1, 0x09, 12,
        43, 1, 0, 0, 0x51,
    ];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [
            0x33, 0xffd9, 0, 0x13e, 18, 0x142, 0x33, 300, 0x13e, 17, 0x142, 0x33, 0xffd9, 1, 0x143,
            0x34, 299, 0x143, 0
        ]
    );
}
#[test]
fn safe_lvalue_expression_and_postincrement_match_native_null_result() {
    let assign = [
        0x06, 8, 0, 0x65, 17, 0, 0, 0, 0x06, 8, 1, 0x09, 12, 43, 1, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&assign, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x13d, 12, 0x142, 0x33, 0xffd9, 1, 0x143, 0x35, 299, 0x12, 0]
    );
    for (od_op, native_op) in [(0x1a, 0x45), (0x1f, 0x46)] {
        let mut augmented = assign;
        augmented[11] = od_op;
        assert_eq!(
            lower_proc_bytecode(&augmented, &()).unwrap(),
            [
                0x33, 0xffd9, 0, 0x13d, 13, 0x142, 0x33, 0xffd9, 1, 0x143, native_op, 299, 0x13f,
                0x12, 0
            ]
        );
    }
    for (od_op, native_op) in [(0x56, 0x63), (0x57, 0x65), (0x62, 0x62), (0x63, 0x64)] {
        let increment = [0x06, 8, 0, 0x65, 14, 0, 0, 0, od_op, 12, 43, 1, 0, 0, 0x10];
        assert_eq!(
            lower_proc_bytecode(&increment, &()).unwrap(),
            [0x33, 0xffd9, 0, 0x13d, 9, 0x142, 0x143, native_op, 299, 0x12, 0]
        );
    }
}
#[test]
fn safe_lvalue_assignments_preserve_receiver_and_null_exit() {
    for (od_op, native_op) in [
        (0x09, 0x34),
        (0x1a, 0x45),
        (0x1f, 0x46),
        (0x0b, 0x47),
        (0x17, 0x48),
        (0x39, 0x49),
        (0x33, 0x4a),
        (0x2d, 0x4b),
        (0x29, 0x4c),
        (0x6d, 0x4d),
        (0x6e, 0x4e),
    ] {
        let od = [
            0x06, 8, 0, 0x65, 17, 0, 0, 0, 0x06, 8, 1, od_op, 12, 43, 1, 0, 0, 0x51,
        ];
        assert_eq!(
            lower_proc_bytecode(&od, &()).unwrap(),
            [0x33, 0xffd9, 0, 0x13e, 12, 0x142, 0x33, 0xffd9, 1, 0x143, native_op, 299, 0]
        );
    }
}
#[test]
fn single_safe_field_access_matches_dreammaker() {
    let od = [0x06, 8, 0, 0x65, 13, 0, 0, 0, 0x68, 41, 1, 0, 0, 0x10];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 297).then_some(39)
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x13d, 7, 0x33, 39, 0x12, 0]
    );
}
#[test]
fn nested_safe_fields_preserve_dreammaker_cache_stack() {
    // Paired safe_nested fixture: `a?.loc?.name`.
    let od = [
        0x06, 8, 0, 0x65, 23, 0, 0, 0, 0x68, 40, 1, 0, 0, 0x65, 23, 0, 0, 0, 0x68, 41, 1, 0, 0,
        0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            match old {
                296 => Some(50),
                297 => Some(39),
                _ => None,
            }
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x13d, 13, 0x142, 0x33, 50, 0x13d, 12, 0x33, 39, 0x143, 0x12, 0]
    );
}
#[test]
fn deep_safe_fields_unwind_each_cache_level() {
    // Paired safe_deep fixture: `a?.loc?.loc?.name`.
    let od = [
        0x06, 8, 0, 0x65, 33, 0, 0, 0, 0x68, 40, 1, 0, 0, 0x65, 33, 0, 0, 0, 0x68, 40, 1, 0, 0,
        0x65, 33, 0, 0, 0, 0x68, 41, 1, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            match old {
                296 => Some(50),
                297 => Some(39),
                _ => None,
            }
        }
    }
    assert_eq!(
        lower_proc_bytecode(&od, &Ids).unwrap(),
        [
            0x33, 0xffd9, 0, 0x13d, 19, 0x142, 0x33, 50, 0x13d, 18, 0x142, 0x33, 50, 0x13d, 17,
            0x33, 39, 0x143, 0x143, 0x12, 0
        ]
    );
}
#[test]
fn range_membership_reorders_operands_like_dreammaker() {
    let od = [
        0x06, 8, 0, 0x88, 2, 0, 0, 0, 0, 0, 0x80, 0x3f, 0, 0, 0x40, 0x40, 0x5b, 0x10,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&out)
        .unwrap()
        .iter()
        .map(|instruction| instruction.name)
        .collect();
    assert_eq!(
        names,
        ["PushVal", "PushVal", "GetVar", "IsIn", "GetFlag", "Ret", "End"]
    );
    assert_eq!(out[out.len() - 5..], [0xa9, 11, 0x36, 0x12, 0]);
}
#[test]
fn multidimensional_list_uses_native_new_list_path() {
    let od = [
        0x88, 2, 0, 0, 0, 0, 0, 0, 0x40, 0, 0, 0x40, 0x40, 0x30, 2, 0, 0, 0, 0x09, 9, 0, 0x10,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = byond_dmb::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[0].name, "PushVal");
    assert_eq!(instructions[0].operands, [40, 0]);
    assert_eq!(instructions[3].name, "New");
    assert_eq!(instructions[3].operands, [2]);
}
