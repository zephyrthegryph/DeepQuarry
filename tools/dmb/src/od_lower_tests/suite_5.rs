use super::*;

#[test]
fn run_file_output_fuses_to_native_output_run() {
    // Paired run-output fixture: src << run(file("foo.txt")).
    let od = [
        0x03, 0x50, 0x01, 0, 0, 0x0a, 0x0b, 18, 0, 0, 0, 1, 1, 0, 0, 0, 0x0a, 0x0b, 144, 0, 0, 0,
        1, 1, 0, 0, 0, 0x4e, 1,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 336).then_some(437)
        }
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            match old {
                18 => Some(0x172),
                144 => Some(0x09),
                _ => None,
            }
        }
    }
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = crate::bytecode::decode(&words)
        .unwrap()
        .iter()
        .map(|item| item.name)
        .collect();
    assert_eq!(
        names,
        ["GetVar", "PushVal", "PushVal", "New", "OutputRun", "End"]
    );
}
#[test]
fn load_ext_overlay_call_uses_native_intrinsic() {
    // Paired global initializer: load_ext("lib", "func").
    let od = [
        0x8c, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 0x0a, 0x0b, 0, 0, 0, 0, 1, 2, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(old + 434)
        }
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 0).then_some(0x179)
        }
    }
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    assert_eq!(&words[6..7], &[0x179]);
}
#[test]
fn augmented_local_followed_by_method_call_uses_local_receiver() {
    // Paired _addtimer: hashlist += callback.arguments; hashlist.Join(...).
    let od = [
        0x38, 0, 0, 0x80, 0x3f, 0x1a, 9, 1, 0x03, 7, 0, 0, 0, 0x6a, 8, 0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(old + 100)
        }
    }
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    let names: Vec<_> = decoded.iter().map(|item| item.name).collect();
    assert!(!names.contains(&"PushEval"));
    assert!(names.contains(&"Call"));
}
#[test]
fn assigned_call_result_is_receiver_for_following_method() {
    // Paired _queue_verb: var/L = args.Copy(); L.Cut(2,4).
    let od = [
        0x06, 4, 0x6a, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0x09, 9, 2, 0x88, 2, 0, 0, 0, 0, 0, 0, 0x40, 0,
        0, 0x80, 0x40, 0x6a, 2, 0, 0, 0, 1, 2, 0, 0, 0, 0x51,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(if old == 1 { 25 } else { 26 })
        }
    }
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = crate::bytecode::decode(&words)
        .unwrap()
        .iter()
        .map(|item| item.name)
        .collect();
    assert!(names.windows(2).any(|seq| seq == ["Call", "SetVar"]));
    assert!(names.windows(2).any(|seq| seq == ["CallStatement", "Pop"]));
}
#[test]
fn six_coordinate_block_uses_native_coordinate_opcode() {
    // Paired urange calls block(x1,y1,z1,x2,y2,z2).
    let mut od = Vec::new();
    for _ in 0..6 {
        od.extend([0x38, 0, 0, 0, 0]);
    }
    od.extend([0x0a, 0x0b, 9, 0, 0, 0, 1, 6, 0, 0, 0, 0x10]);
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old != 9).then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 9).then_some(0x1f)
        }
    }
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = crate::bytecode::decode(&out).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.name == "BlockCoordinates"));
}
#[test]
fn safe_index_with_computed_key_restores_receiver_cache() {
    // DeepQuarry ___TraitAdd indexes a nullable list by a formatted key.
    let od = [
        0x06, 8, 0, 0x65, 21, 0, 0, 0, 0x06, 8, 1, 0x04, 4, 0, 0, 0, 1, 0, 0, 0, 0x69, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            Some(old)
        }
    }
    let lowered = lower_proc_bytecode(&od, &Ids).unwrap();
    let instructions = crate::bytecode::decode(&lowered).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.name == "SetCacheJmpIfNull"));
    assert!(instructions.iter().any(|item| item.name == "ListGet"));
    assert!(instructions.iter().any(|item| item.name == "PopCache"));
    let direct_key = [0x06, 8, 0, 0x65, 12, 0, 0, 0, 0x06, 8, 1, 0x69, 0x10];
    let lowered = lower_proc_bytecode(&direct_key, &Ids).unwrap();
    let instructions = crate::bytecode::decode(&lowered).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.name == "SetCacheJmpIfNull"));
    assert!(instructions.iter().any(|item| item.name == "PopCache"));
}
#[test]
fn legal_loop_lvalues_and_empty_named_catches_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/flow_legal_loops.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/flow_legal_loops.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, old: u32) -> Option<u32> {
            let name = &self.0.procs.get(old as usize)?.name;
            self.1
                .procs
                .iter()
                .position(|proc_| {
                    self.1.string(proc_.strings[0]) == Some(format!("/proc/{name}").as_bytes())
                })
                .map(|id| id as u32)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (self.0.types.get(old as usize)?.path == "/obj").then_some(9)
        }
        fn type_id(&self, old: u32) -> Option<u32> {
            (self.0.types.get(old as usize)?.path == "/obj").then_some(4)
        }
        fn string(&self, old: u32) -> Option<u32> {
            let value = self.0.strings.get(old as usize)?;
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(value.as_bytes()))
                .map(|id| id as u32)
        }
    }
    let canonical = |words: &[u32]| {
        let instructions = crate::bytecode::decode(words).unwrap();
        instructions
            .iter()
            .map(|item| {
                let mut operands = item.operands.clone();
                let opcode = if item.opcode == 0x50 {
                    let bits = (operands[0] as f32).to_bits();
                    operands = vec![42, bits >> 16, bits & 0xffff];
                    0x60
                } else {
                    item.opcode
                };
                if matches!(
                    opcode,
                    0x0b | 0x0c
                        | 0x0f
                        | 0x11
                        | 0xb2
                        | 0xb3
                        | 0xf8
                        | 0xfa
                        | 0xfd
                        | 0xff
                        | 0x12c
                        | 0x12e
                        | 0x13e
                ) {
                    operands[0] = instructions
                        .iter()
                        .position(|target| target.offset == operands[0] as usize)
                        .unwrap() as u32;
                }
                (opcode, operands)
            })
            .collect::<Vec<_>>()
    };
    for proc_ in input
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("flow_"))
    {
        let actual = lower_proc_bytecode_with_local_events_and_order(
            proc_.bytecode.as_deref().unwrap(),
            &Ids(&input, &native),
            proc_.max_variable_id,
            &proc_.locals,
            &proc_.lexical_local_add_indices,
        )
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|p| {
                native.string(p.strings[0]) == Some(format!("/proc/{}", proc_.name).as_bytes())
            })
            .unwrap();
        let expected = native.proc_code_words(id).unwrap();
        if proc_.name == "flow_constant_range" {
            let actual = crate::bytecode::decode(&actual).unwrap();
            let membership = actual
                .iter()
                .position(|item| item.opcode == 0xa9 && item.operands == [11])
                .unwrap();
            assert_eq!(actual[membership - 1].opcode, 0x35);
            assert_eq!(actual[membership - 2].opcode, 0x60);
            assert_eq!(actual[membership - 2].operands, [42, 0x4000, 0]);
            assert_eq!(actual[membership - 3].operands, [42, 0x41a0, 0]);
            assert_eq!(actual[membership - 4].operands, [42, 0x3f80, 0]);
        } else {
            assert_eq!(canonical(&actual), canonical(expected), "{}", proc_.name);
        }
    }
}
#[test]
fn typed_loop_masks_match_native_before_assigning_exposed_lvalues() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/flow_filter_masks.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/flow_filter_masks.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let bytes = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(bytes))
                .map(|id| id as u32)
        }
        fn iterator_type_mask(&self, old: u32) -> Option<u32> {
            self.0.types.get(old as usize)?;
            Some(if self.0.type_inherits_path(old as usize, "/mob") {
                1
            } else if self.0.type_inherits_path(old as usize, "/obj") {
                2
            } else if self.0.type_inherits_path(old as usize, "/atom/movable") {
                3
            } else if self.0.type_inherits_path(old as usize, "/turf") {
                32
            } else if self.0.type_inherits_path(old as usize, "/area") {
                256
            } else if self.0.type_inherits_path(old as usize, "/atom") {
                291
            } else {
                0
            })
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            match self.0.types.get(old as usize)?.path.as_str() {
                "/list" => return Some(40),
                "/savefile" => return Some(36),
                "/image" => return Some(63),
                "/client" => return Some(59),
                _ => {}
            }
            Some(match self.iterator_type_mask(old)? {
                1 => 8,
                2 => 9,
                3 | 32 | 291 => 10,
                256 => 11,
                _ => 32,
            })
        }
    }
    let mut count = 0;
    for proc_ in input
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("filter_"))
    {
        count += 1;
        let actual = lower_proc_bytecode_with_local_events_and_order(
            proc_.bytecode.as_deref().unwrap(),
            &Ids(&input, &native),
            proc_.max_variable_id,
            &proc_.locals,
            &proc_.lexical_local_add_indices,
        )
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|native_proc| {
                native.string(native_proc.strings[0])
                    == Some(format!("/proc/{}", proc_.name).as_bytes())
            })
            .unwrap();
        let expected = native.proc_code_words(id).unwrap();
        let expected = crate::bytecode::decode(expected).unwrap();
        let actual = crate::bytecode::decode(&actual).unwrap();
        let native_load = expected.iter().find(|item| item.opcode == 0x52).unwrap();
        let load = actual.iter().position(|item| item.opcode == 0x52).unwrap();
        assert_eq!(
            actual[load].operands, native_load.operands,
            "{}",
            proc_.name
        );
        assert_eq!(actual[load + 1].opcode, 0x53);
        assert_eq!(actual[load + 2].opcode, 0x34);
        assert_eq!(actual[load + 2].operands, [0xffda, 0]);
        for items in [&actual, &expected] {
            let ret = items.iter().position(|item| item.opcode == 0x12).unwrap();
            assert_eq!(items[ret - 1].opcode, 0x33);
            assert_eq!(items[ret - 1].operands, [0xffda, 0]);
            if proc_.name.ends_with("_child") {
                assert!(
                    items.iter().any(|item| item.opcode == 0x7d),
                    "{}",
                    proc_.name
                );
            }
            if proc_.name == "filter_explicit_anything" {
                assert_eq!(native_load.operands, [5, 0x1000]);
                assert!(!items.iter().any(|item| item.opcode == 0x7d));
            }
            if proc_.name.starts_with("filter_annotation_") {
                let mask = match proc_.name.as_str() {
                    "filter_annotation_anything" => 0x1000,
                    "filter_annotation_obj" => 2,
                    "filter_annotation_num" => 8,
                    "filter_annotation_union" => 10,
                    _ => unreachable!(),
                };
                assert_eq!(native_load.operands, [5, mask]);
                assert!(!items.iter().any(|item| item.opcode == 0x7d));
            }
        }
    }
    assert_eq!(count, 32);
    // Legacy exports can retain CreateFilteredListEnumerator even when
    // explicit `as anything` overrides the lvalue's declared subtype.
    let mut legacy = [
        0x06, 8, 0, 0xab, 0, 0x10, 0, 0, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0x3b, 0, 0, 0, 0, 9, 0, 33,
        0, 0, 0, 0x0e, 17, 0, 0, 0, 0x3c, 0, 0, 0, 0, 0x97, 9, 0,
    ];
    let subtype = input
        .types
        .iter()
        .position(|type_| type_.path == "/obj/filter_child")
        .unwrap() as u32;
    legacy[13..17].copy_from_slice(&subtype.to_le_bytes());
    let words = lower_proc_bytecode(&legacy, &Ids(&input, &native)).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    assert_eq!(
        items
            .iter()
            .find(|item| item.opcode == 0x52)
            .unwrap()
            .operands,
        [5, 0x1000]
    );
    assert!(!items.iter().any(|item| item.opcode == 0x7d));
    legacy[4..8].copy_from_slice(&0u32.to_le_bytes());
    let words = lower_proc_bytecode(&legacy, &Ids(&input, &native)).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    assert_eq!(
        items
            .iter()
            .find(|item| item.opcode == 0x52)
            .unwrap()
            .operands,
        [5, 2]
    );
    assert!(items.iter().any(|item| item.opcode == 0x7d));
}
#[test]
fn crash_call_preserves_common_pop_for_passing_assertion_branch() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/flow_void_join.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/lowering/flow_void_join.bin"))
            .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram);
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, old: u32) -> Option<u32> {
            self.builtin_proc(old).is_none().then_some(old)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (self.0.procs.get(old as usize)?.name == "CRASH").then_some(0xc7)
        }
    }
    let passing_stack = |words: &[u32]| {
        let instructions = crate::bytecode::decode(words).unwrap();
        let mut stack = Vec::new();
        let mut flag = false;
        let mut pc = 0;
        for _ in 0..instructions.len() * 2 {
            let item = &instructions[pc];
            pc += 1;
            let mut branch = None;
            match item.opcode {
                0x33 => {
                    assert_eq!(item.operands, [0xffd9, 0]);
                    stack.push(1.0);
                }
                0x0e => {
                    let value = stack.pop().unwrap();
                    stack.push(if value == 0.0 { 1.0 } else { 0.0 });
                }
                0x0d => flag = stack.pop().unwrap() != 0.0,
                0x11 if !flag => branch = Some(item.operands[0]),
                0x11 => {}
                0x0f => branch = Some(item.operands[0]),
                0x50 => stack.push(item.operands[0] as f32),
                0x60 => stack.push(match item.operands[0] {
                    0 => 0.0,
                    42 => f32::from_bits((item.operands[1] << 16) | item.operands[2]),
                    _ => panic!("unexpected passing literal"),
                }),
                0x51 => {
                    stack.pop().expect("common Pop must have a passing value");
                }
                0x12 => return stack,
                _ => panic!("unexpected passing opcode {:x}", item.opcode),
            }
            if let Some(target) = branch {
                pc = instructions
                    .iter()
                    .position(|item| item.offset == target as usize)
                    .unwrap();
            }
        }
        panic!("passing assertion never returned")
    };
    let proc_ = input
        .procs
        .iter()
        .find(|proc_| proc_.name == "flow_assertion")
        .unwrap();
    let actual = lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &Ids(&input)).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc_| native.string(proc_.strings[0]) == Some(b"/proc/flow_assertion"))
        .unwrap();
    let expected = native.proc_code_words(id).unwrap();
    assert_eq!(passing_stack(expected), vec![1.0]);
    assert_eq!(passing_stack(&actual), passing_stack(expected));
    let direct = input
        .procs
        .iter()
        .find(|proc_| proc_.name == "flow_direct_crash")
        .unwrap();
    let direct = lower_proc_bytecode(direct.bytecode.as_deref().unwrap(), &Ids(&input)).unwrap();
    assert!(!crate::bytecode::decode(&direct)
        .unwrap()
        .iter()
        .any(|item| item.opcode == 0x51));
}
#[test]
fn native_void_operations_materialize_opendream_null_results() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/flow_void_join.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/lowering/flow_void_join.bin"))
            .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let bytes = self.0.strings.get(old as usize)?.as_bytes();
            Some(
                (0..self.1.strings.len())
                    .find(|id| self.1.string(*id as u32) == Some(bytes))
                    .map_or(old, |id| id as u32),
            )
        }
        fn proc_id(&self, old: u32) -> Option<u32> {
            if self.builtin_proc(old).is_some() {
                return None;
            }
            let name = &self.0.procs.get(old as usize)?.name;
            Some(
                self.1
                    .procs
                    .iter()
                    .position(|proc_| {
                        self.1.string(proc_.strings[0]) == Some(format!("/proc/{name}").as_bytes())
                    })
                    .map_or(old, |id| id as u32),
            )
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            Some(match self.0.procs.get(old as usize)?.name.as_str() {
                "flick" => 0x5c,
                "walk" => 0x8b,
                "walk_to" => 0x8c,
                "walk_towards" => 0x8e,
                "walk_away" => 0x125,
                "walk_rand" => 0x127,
                "winset" => 0x10c,
                "winshow" => 0x10f,
                "winclone" => 0x10e,
                "sleep" => 0x24,
                "rand_seed" => 0xda,
                _ => return None,
            })
        }
    }
    let canonical = |words: &[u32]| {
        crate::bytecode::decode(words)
            .unwrap()
            .into_iter()
            .flat_map(|item| match (item.opcode, item.operands.as_slice()) {
                (0x50, [value]) => {
                    let bits = (*value as f32).to_bits();
                    vec![(0x60, vec![42, bits >> 16, bits & 0xffff])]
                }
                (0x33, [0xffe6]) => vec![(0x60, vec![0, 0])],
                (0x35, _) => vec![(0x34, item.operands.clone()), (0x33, item.operands)],
                _ => vec![(item.opcode, item.operands)],
            })
            .collect::<Vec<_>>()
    };
    let mut count = 0;
    for proc_ in input.procs.iter().filter(|proc_| {
        proc_.name.starts_with("void_value_") || proc_.name == "void_argument_sleep"
    }) {
        count += 1;
        let actual = lower_proc_bytecode_with_local_events_and_order(
            proc_.bytecode.as_deref().unwrap(),
            &Ids(&input, &native),
            proc_.max_variable_id,
            &proc_.locals,
            &proc_.lexical_local_add_indices,
        )
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|p| {
                native.string(p.strings[0]) == Some(format!("/proc/{}", proc_.name).as_bytes())
            })
            .unwrap();
        assert_eq!(
            canonical(&actual),
            canonical(native.proc_code_words(id).unwrap()),
            "{}",
            proc_.name
        );
    }
    assert_eq!(count, 21);
    // Both arms of a conditional statement reach the common Pop. Native
    // has no void value; OD's sleep arm must expose null before that Pop.
    let proc_ = input
        .procs
        .iter()
        .find(|proc_| proc_.name == "void_conditional_sleep")
        .unwrap();
    let actual =
        lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &Ids(&input, &native)).unwrap();
    let id = native
        .procs
        .iter()
        .position(|p| native.string(p.strings[0]) == Some(b"/proc/void_conditional_sleep"))
        .unwrap();
    let expected = native.proc_code_words(id).unwrap();
    let run = |words: &[u32], input_flag: f32| {
        let items = crate::bytecode::decode(words).unwrap();
        let mut stack = Vec::new();
        let mut flag = false;
        let mut pc = 0;
        for _ in 0..items.len() * 2 {
            let item = &items[pc];
            pc += 1;
            let mut branch = None;
            match item.opcode {
                0x33 => {
                    assert_eq!(item.operands[0], 0xffd9);
                    stack.push(if item.operands[1] == 0 {
                        input_flag
                    } else {
                        2.0
                    });
                }
                0x0e => {
                    let value = stack.pop().unwrap();
                    stack.push(if value == 0.0 { 1.0 } else { 0.0 });
                }
                0x0d => flag = stack.pop().unwrap() != 0.0,
                0x11 if !flag => branch = Some(item.operands[0]),
                0x11 => {}
                0x0f => branch = Some(item.operands[0]),
                0x50 => stack.push(item.operands[0] as f32),
                0x60 => stack.push(match item.operands[0] {
                    0 => 0.0,
                    42 => f32::from_bits((item.operands[1] << 16) | item.operands[2]),
                    _ => panic!("unexpected literal"),
                }),
                0x24 | 0x51 => {
                    stack.pop().expect("void argument/common result missing");
                }
                0x12 => return stack,
                _ => panic!("unexpected opcode {:x}", item.opcode),
            }
            if let Some(target) = branch {
                pc = items
                    .iter()
                    .position(|item| item.offset == target as usize)
                    .unwrap();
            }
        }
        panic!("conditional void result did not return")
    };
    for flag in [0.0, 1.0] {
        assert_eq!(run(expected, flag), vec![1.0]);
        assert_eq!(run(&actual, flag), run(expected, flag));
    }
}
#[test]
fn indexed_virtual_joins_preserve_nested_iterator_and_try_scopes() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/flow_indexed_join.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/flow_indexed_join.bin"
    ))
    .unwrap();
    let proc_ = input
        .procs
        .iter()
        .find(|proc_| proc_.name == "flow_indexed_join_loops")
        .unwrap();
    let actual = lower_proc_bytecode_with_local_events_and_order(
        proc_.bytecode.as_deref().unwrap(),
        &(),
        proc_.max_variable_id,
        &proc_.locals,
        &proc_.lexical_local_add_indices,
    )
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|p| native.string(p.strings[0]) == Some(b"/proc/flow_indexed_join_loops"))
        .unwrap();
    let expected = crate::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
    let actual = crate::bytecode::decode(&actual).unwrap();
    assert_eq!(
        expected.iter().filter(|item| item.opcode == 0x55).count(),
        1
    );
    for opcode in [0x54, 0x55, 0x52, 0xf8] {
        assert_eq!(
            actual.iter().filter(|item| item.opcode == opcode).count(),
            expected.iter().filter(|item| item.opcode == opcode).count(),
            "opcode {opcode:x}"
        );
    }
    let mut words = [0x0f, 0];
    restore_try_branch_exits(
        &mut words,
        &[0x0e, 0, 0, 0, 0],
        &[Fixup {
            at: 1,
            source: 0,
            target: u32::MAX,
        }],
        &[(0, 5)],
    );
    assert_eq!(words[0], 0x0f);
}
#[test]
fn protected_loop_exits_and_gotos_match_native_cleanup() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/flow_try_exits.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../../fixtures/lowering/flow_try_exits.bin"))
            .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let value = self.0.strings.get(old as usize)?.as_bytes();
            (0..self.1.strings.len())
                .find(|id| self.1.string(*id as u32) == Some(value))
                .map(|id| id as u32)
        }
    }
    let exits = |words: &[u32]| {
        let items = crate::bytecode::decode(words).unwrap();
        items
            .iter()
            .filter(|item| matches!(item.opcode, 0x12e | 0x12f))
            .map(|item| {
                let mut at = item.operands[0] as usize;
                let mut seen = std::collections::HashSet::new();
                let mut destination = String::new();
                loop {
                    assert!(seen.insert(at), "unexpected cycle in exception exit");
                    let target = items
                        .iter()
                        .find(|target| target.offset >= at && !matches!(target.opcode, 0x84 | 0x85))
                        .unwrap();
                    if matches!(target.opcode, 0x0f | 0xf8 | 0x12e | 0x12f) {
                        destination.push_str(&format!("{:x}->", target.opcode));
                        at = target.operands[0] as usize;
                    } else {
                        let (opcode, operands) = if target.opcode == 0x50 {
                            let bits = (target.operands[0] as f32).to_bits();
                            (0x60, vec![42, bits >> 16, bits & 0xffff])
                        } else {
                            (target.opcode, target.operands.clone())
                        };
                        destination.push_str(&format!("{opcode:x}{operands:?}"));
                        break;
                    }
                }
                (item.opcode, destination)
            })
            .collect::<Vec<_>>()
    };
    for proc_ in input
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("flow_"))
    {
        let id = native
            .procs
            .iter()
            .position(|native_proc| {
                native.string(native_proc.strings[0])
                    == Some(format!("/proc/{}", proc_.name).as_bytes())
            })
            .unwrap();
        let expected = native.proc_code_words(id).unwrap();
        let actual = lower_proc_bytecode_with_local_events_and_order(
            proc_.bytecode.as_deref().unwrap(),
            &Ids(&input, &native),
            proc_.max_variable_id,
            &proc_.locals,
            &proc_.lexical_local_add_indices,
        )
        .unwrap();
        assert_eq!(
            exits(&actual),
            exits(expected),
            "{} exception exits",
            proc_.name
        );
        let expected_items = crate::bytecode::decode(expected).unwrap();
        let actual_items = crate::bytecode::decode(&actual).unwrap();
        for opcode in [0x0f, 0xf8, 0x12, 0x12c, 0x12d, 0x25] {
            assert_eq!(
                actual_items
                    .iter()
                    .filter(|item| item.opcode == opcode)
                    .count(),
                expected_items
                    .iter()
                    .filter(|item| item.opcode == opcode)
                    .count(),
                "{} opcode {opcode:x}",
                proc_.name
            );
        }
    }
}
#[test]
fn spawn_body_and_sleep_match_paired_compilers() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, _old: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            (old == 95).then_some(0x24)
        }
    }
    let sleep = [
        0x06, 8, 0, 0x0a, 11, 95, 0, 0, 0, 1, 1, 0, 0, 0, 0x51, 0x98, 0, 0, 0x80, 0x3f,
    ];
    let lowered = lower_proc_bytecode(&sleep, &Ids).unwrap();
    assert_eq!(&lowered[..4], &[0x33, 0xffd9, 0, 0x24]);
    assert!(!lowered.contains(&0x51));
    let spawn = [
        0x38, 0, 0, 0, 0x40, 0x4d, 25, 0, 0, 0, 0x06, 5, 0x03, 41, 1, 0, 0, 0x4e, 12, 42, 1, 0, 0,
        0x11, 0x10, 0x98, 0, 0, 0x80, 0x3f,
    ];
    let lowered = lower_proc_bytecode(&spawn, &()).unwrap();
    let instructions = crate::bytecode::decode(&lowered).unwrap();
    assert_eq!(instructions[1].name, "Spawn");
    assert_eq!(instructions[1].operands, [instructions[6].offset as u32]);
    assert_eq!(instructions[5].name, "End");
}
