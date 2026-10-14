use super::*;

#[test]
fn computed_method_receiver_matches_native_cache_preservation() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            Some(if old == 2 { 1 } else { old })
        }
        fn string(&self, old: u32) -> Option<u32> {
            Some(if old == 1 { 438 } else { old })
        }
    }
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/computed_method.json"
    ))
    .unwrap();
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "computed_method")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids).unwrap(),
        [
            0x33, 0xffd9, 0, 0x30, 1, 1, 0x34, 0xffd8, 0x142, 0x33, 0xffd9, 1, 0x143, 0x29, 0xffdd,
            438, 1, 0x12, 0
        ]
    );
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "conditional_method")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids).unwrap(),
        [
            0x33, 0xffd9, 0, 0x0d, 0x11, 11, 0x33, 0xffd9, 1, 0x0f, 14, 0x33, 0xffd9, 2, 0x34,
            0xffd8, 0x142, 0x33, 0xffd9, 3, 0x143, 0x29, 0xffdd, 438, 1, 0x12, 0
        ]
    );
}
#[test]
fn safe_indexed_rhs_matches_native_reference() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            Some(if old == 2 { 1 } else { old })
        }
        fn string(&self, old: u32) -> Option<u32> {
            Some(if old == 299 {
                437
            } else if old == 1 {
                439
            } else {
                old
            })
        }
    }
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/safe_indexed_value.json"
    ))
    .unwrap();
    let global = program
        .procs
        .iter()
        .find(|proc| proc.name == "siv_global")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(global.bytecode.as_ref().unwrap(), &Ids).unwrap(),
        [
            0x33, 0xffd9, 2, 0x30, 1, 1, 0x13d, 10, 0x33, 437, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1,
            0x7c, 0x33, 0xffd9, 0, 0x12, 0
        ]
    );
    let method = program
        .procs
        .iter()
        .find(|proc| proc.name == "siv_method")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(method.bytecode.as_ref().unwrap(), &Ids).unwrap(),
        [
            0x33, 0xffd9, 2, 0x13d, 11, 0x142, 0x143, 0x29, 0xffdd, 439, 0, 0x33, 0xffd9, 0, 0x33,
            0xffd9, 1, 0x7c, 0x33, 0xffd9, 0, 0x12, 0
        ]
    );
}
#[test]
fn safe_indexed_extended_rhs_matches_native_reference() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/safe_rhs_extended.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/safe_rhs_extended.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            self.1
                .strings
                .iter()
                .position(|candidate| candidate.data.as_slice() == text)
                .map(|i| i as u32)
        }
    }
    for name in ["sre_nested", "sre_index"] {
        let proc = program.procs.iter().find(|proc| proc.name == name).unwrap();
        let path = format!("/proc/{name}");
        let index = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .strings
                    .get(proc.strings[0] as usize)
                    .is_some_and(|s| s.data.as_slice() == path.as_bytes())
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
fn empty_catch_matches_native_join() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/try_empty.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/try_empty.native.bin"
    ))
    .unwrap();
    let proc = input
        .procs
        .iter()
        .find(|proc| proc.name == "try_empty")
        .unwrap();
    let index = native
        .procs
        .iter()
        .position(|proc| {
            native
                .strings
                .get(proc.strings[0] as usize)
                .is_some_and(|s| s.data == b"/proc/try_empty")
        })
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &()).unwrap(),
        native.proc_code_words(index).unwrap()
    );
}
#[test]
fn client_iterator_and_computed_initial_key_match_native() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/client_iterator.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/client_iterator.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            self.1
                .strings
                .iter()
                .position(|s| s.data == text)
                .map(|id| id as u32)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            Some(if self.0.types.get(old as usize)?.path == "/client" {
                59
            } else {
                32
            })
        }
        fn type_id(&self, _: u32) -> Option<u32> {
            Some(0)
        }
    }
    for name in ["client_iterator", "dynamic_initial"] {
        let proc = input.procs.iter().find(|proc| proc.name == name).unwrap();
        let path = format!("/proc/{name}");
        let index = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .strings
                    .get(proc.strings[0] as usize)
                    .is_some_and(|s| s.data == path.as_bytes())
            })
            .unwrap();
        assert_eq!(
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&input, &native)).unwrap(),
            native.proc_code_words(index).unwrap(),
            "{name}"
        );
    }
}
#[test]
fn field_logical_assignments_preserve_native_receiver_timing() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/logical_fields.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/logical_fields.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            self.1
                .strings
                .iter()
                .position(|s| s.data == text)
                .map(|id| id as u32)
        }
        fn proc_id(&self, old: u32) -> Option<u32> {
            let path = format!("/proc/{}", self.0.procs.get(old as usize)?.name);
            self.1
                .procs
                .iter()
                .position(|proc| self.1.string(proc.strings[0]) == Some(path.as_bytes()))
                .map(|id| id as u32)
        }
    }
    for name in [
        "logical_or_arg",
        "logical_or_field",
        "logical_and_field",
        "logical_direct_mutation",
        "logical_computed_mutation",
        "logical_property_mutation",
        "field_expr_arg",
        "field_expr_arg_mutate",
        "field_expr_call_mutate",
        "field_expr_both_calls",
    ] {
        let proc = input.procs.iter().find(|proc| proc.name == name).unwrap();
        let path = format!("/proc/{name}");
        let index = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&input, &native)).unwrap(),
            native.proc_code_words(index).unwrap(),
            "{name}"
        );
    }
    let ordered = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/logical_fields_nativeordered.json"
    ))
    .unwrap();
    for name in [
        "field_expr_call_mutate",
        "field_expr_both_calls",
        "field_statement_call_mutate",
    ] {
        let proc = ordered.procs.iter().find(|proc| proc.name == name).unwrap();
        let path = format!("/proc/{name}");
        let index = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&ordered, &native)).unwrap(),
            native.proc_code_words(index).unwrap(),
            "native-ordered {name}"
        );
    }
}
#[test]
fn safe_field_list_assignment_matches_native_cache_lifetime() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/safe_field_list.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/safe_field_list.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let bytes = self.0.strings.get(old as usize)?.as_bytes();
            self.1
                .strings
                .iter()
                .position(|value| value.data == bytes)
                .map(|id| id as u32)
        }
    }
    let proc = input
        .procs
        .iter()
        .find(|proc| proc.name == "assign")
        .unwrap();
    let native_id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/assign".as_slice()))
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&input, &native)).unwrap(),
        native.proc_code_words(native_id).unwrap()
    );
}
#[test]
fn nested_safe_method_index_preserves_outer_receiver() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/safe_method_index.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/safe_method_index.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a byond_dmb::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let bytes = self.0.strings.get(old as usize)?.as_bytes();
            self.1
                .strings
                .iter()
                .position(|value| value.data == bytes)
                .or_else(|| {
                    let normalized = String::from_utf8_lossy(bytes).replace('_', " ");
                    self.1
                        .strings
                        .iter()
                        .position(|value| value.data == normalized.as_bytes())
                })
                .map(|id| id as u32)
        }
        fn type_id(&self, _: u32) -> Option<u32> {
            self.1
                .classes
                .iter()
                .position(|class| {
                    self.1.string(class.initial_ids[0]) == Some(b"/datum/probe".as_slice())
                })
                .map(|id| id as u32)
        }
    }
    for name in ["nested", "nested_typed"] {
        let proc = input.procs.iter().find(|proc| proc.name == name).unwrap();
        let path = format!("/proc/{name}");
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&input, &native)).unwrap(),
            native.proc_code_words(native_id).unwrap(),
            "{name}"
        );
    }
}
#[test]
fn legacy_field_statement_rejects_unsafe_receiver_order() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, id: u32) -> Option<u32> {
            Some(id)
        }
    }
    let code = [0x06, 8, 0, 0x06, 8, 1, 0x85, 12, 1, 0, 0, 0];
    let error = lower_proc_bytecode(&code, &Ids).unwrap_err();
    assert!(error.reason.contains("native-ordered A8 exporter"));
}
#[test]
fn associative_iterator_can_reuse_destroyed_filtered_iterator_id() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/assoc_after_filter.json"
    ))
    .unwrap();
    let proc = input
        .procs
        .iter()
        .find(|proc| proc.name == "assoc_after_filter")
        .unwrap();
    let words = lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&words).unwrap();
    assert!(decoded
        .iter()
        .any(|item| item.opcode == 0x52 && item.operands.first() == Some(&20)));
    assert!(decoded.iter().any(|item| item.opcode == 0x17e));
}
#[test]
fn indexed_effectful_operands_follow_native_evaluation_order() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/indexed_order.json"
    ))
    .unwrap();
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "indexed_order")
        .unwrap();
    assert_eq!(
        lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &()).unwrap(),
        [
            0x33, 0xffd9, 2, 0x30, 1, 2, 0x33, 0xffd9, 0, 0x30, 1, 0, 0x33, 0xffd9, 1, 0x30, 1, 1,
            0x7c, 0x33, 0xffd9, 0, 0x12, 0
        ]
    );
}
#[test]
fn remaining_builtin_pairs_match_native_code() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/builtin_last.json"
    ))
    .unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/builtin_last.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram);
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            match self.0.procs.get(old as usize)?.name.as_str() {
                "winexists" => Some(0x118),
                "roll" => Some(0x57),
                "ckeyEx" => Some(0xb9),
                "get_step_rand" => Some(0x94),
                "rand_seed" => Some(0xda),
                _ => None,
            }
        }
    }
    for proc in program
        .procs
        .iter()
        .filter(|proc| proc.name.starts_with("b_"))
    {
        let path = format!("/proc/{}", proc.name);
        let index = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .strings
                    .get(proc.strings[0] as usize)
                    .is_some_and(|s| s.data.as_slice() == path.as_bytes())
            })
            .unwrap();
        assert_eq!(
            lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&program)).unwrap(),
            native.proc_code_words(index).unwrap(),
            "{}",
            proc.name
        );
    }
}
#[test]
fn indexed_text_key_matches_native_reference() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/indexed_keys.json"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram);
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, old: u32) -> Option<u32> {
            if matches!(
                self.0.procs.get(old as usize)?.name.as_str(),
                "lowertext" | "uppertext"
            ) {
                None
            } else {
                Some(old)
            }
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            match self.0.procs.get(old as usize)?.name.as_str() {
                "lowertext" => Some(0x75),
                "uppertext" => Some(0x74),
                _ => None,
            }
        }
    }
    for (name, native) in [("indexed_lower", 0x75), ("indexed_upper", 0x74)] {
        let proc = program.procs.iter().find(|proc| proc.name == name).unwrap();
        let words = lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &Ids(&program)).unwrap();
        assert_eq!(
            words,
            [
                0x33, 0xffd9, 2, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, native, 0x7c, 0x33, 0xffd9, 0,
                0x12, 0
            ]
        );
    }
}
#[test]
fn constructor_argument_span_includes_call_result() {
    // The first value in `new T(t.place(), amount)` is a Call result.
    let words = [0x29, 0xffdc, 0xffd9, 0, 0xffdd, 438, 0, 0x33, 0xffd9, 1];
    assert_eq!(constructor_argument_start(&words, 2), Some(0));
}
#[test]
fn constructor_argument_span_includes_computed_named_call() {
    // Paired graph_astar: new graph_astar_node(start, null, 0,
    // call(start, dist)(end), 0). CallName consumes receiver, name,
    // and its single argument, then supplies one constructor argument.
    let words = [
        0x33, 0xffd9, 0, 0x60, 0, 0, 0x50, 0, 0x33, 0xffd9, 0, 0x33, 0xffd9, 3, 0x33, 0xffd9, 1,
        0xb5, 1, 0x50, 0,
    ];
    assert_eq!(constructor_argument_start(&words, 5), Some(0));
    // A one-target CallPath consumes the proc reference and argument.
    let path_words = [
        0x33, 0xffd9, 0, 0x60, 0, 0, 0x50, 0, 0x33, 0xffd9, 3, 0x33, 0xffd9, 1, 0x2b, 1, 0x50, 0,
    ];
    assert_eq!(constructor_argument_start(&path_words, 5), Some(0));
}
#[test]
fn computed_call_with_proc_reference_reorders_receiver_name_and_argument() {
    // Paired graph_astar: call(start, dist)(end). OpenDream PushNRefs
    // groups [end, dist, start], whereas native CallName consumes
    // [start, dist, end].
    let od = [
        0x87, 3, 0, 0, 0, 8, 1, 8, 3, 8, 0, 0x9e, 1, 1, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    assert_eq!(
        words,
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 3, 0x33, 0xffd9, 1, 0xb5, 1, 0x12, 0]
    );
}
#[test]
fn indexed_value_span_includes_min_expression() {
    // Paired _get_flat_icon line 220: add_size[1] = min(flatX1, pixel_x + 1).
    let words = [
        0x33, 0xffda, 15, 0x50, 1, 0x7b, 0x33, 0xffdc, 0xffda, 9, 187, 0x50, 1, 0x3e, 0xa5, 2,
    ];
    assert_eq!(constructor_argument_start(&words, 1), Some(0));
}
#[test]
fn output_format_span_includes_global_arglist_call() {
    // Paired log_research WRITE_FILE: time_stamp(format=...) is a
    // CallGlobalArgList result consumed by OutputFormat.
    let words = [
        0x60, 6, 310, 0x60, 6, 3623, 0xc8, 1, 0xcd, 654, 0x33, 0xffd9, 0, 0x02, 3624, 2,
    ];
    assert_eq!(constructor_argument_start(&words, 1), Some(0));
}
#[test]
fn indexed_assignment_after_new_list_initializer_stores_then_reloads_local() {
    // Paired graph_astar: path = new /list(n); path[path.len] = current.position.
    let od = [
        0x38, 0, 0, 0x80, 0x3f, 0x11, 0x02, 5, 0, 0, 0, 0x2e, 1, 1, 0, 0, 0, 0x09, 9, 2, 0x86, 9,
        2, 1, 0, 0, 0, 0x86, 9, 4, 2, 0, 0, 0, 0x85, 7, 0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 5).then_some(40)
        }
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 5).then_some(0)
        }
        fn string(&self, old: u32) -> Option<u32> {
            Some(if old == 1 { 57 } else { 327 })
        }
    }
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&words)
        .unwrap()
        .into_iter()
        .map(|item| item.name)
        .collect();
    assert!(names
        .windows(5)
        .any(|seq| seq == ["SetVar", "GetVar", "GetVar", "GetVar", "ListSet"]));
}
#[test]
fn indexed_assignment_expression_preserves_new_value_for_following_local() {
    // Paired qdel line 418: new_holder = GLOB.gc_holders[to_delete.type]
    // = new(to_delete.type). Native evaluates New, duplicates its value,
    // writes ListSet, then stores the same value in new_holder.
    let od = [
        0x06, 9, 0, 0x06, 9, 1, 0x11, 0x02, 5, 0, 0, 0, 0x2e, 0, 0, 0, 0, 0, 0x09, 7, 0x09, 9, 2,
        0x10,
    ];
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 5).then_some(9)
        }
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 5).then_some(1)
        }
    }
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&words)
        .unwrap()
        .into_iter()
        .map(|item| item.name)
        .collect();
    assert!(names
        .windows(5)
        .any(|seq| seq == ["New", "PushTop", "GetVar", "GetVar", "ListSet"]));
}
#[test]
fn indexed_assignment_accepts_pure_computed_key() {
    // Paired dq_latent_type_snapshot line 98:
    // snapshot[count + w] = tag_words[w].
    let od = [
        0x87, 3, 0, 0, 0, 9, 3, 9, 1, 9, 6, 0x08, 0x87, 2, 0, 0, 0, 9, 5, 9, 6, 0x69, 0x85, 7, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    let names: Vec<_> = byond_dmb::bytecode::decode(&words)
        .unwrap()
        .iter()
        .map(|item| item.name)
        .collect();
    assert!(names.windows(2).any(|seq| seq == ["Add", "ListSet"]));
}
#[test]
fn method_arglist_uses_native_call_sentinel() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            (old == 0).then_some(438)
        }
    }
    let od = [
        0x06, 8, 0, 0x06, 8, 1, 0x6a, 0, 0, 0, 0, 3, 1, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let calls: Vec<_> = byond_dmb::bytecode::decode(&words)
        .unwrap()
        .into_iter()
        .filter(|item| item.name == "Call")
        .collect();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].operands, [0xffdc, 0xffd9, 0, 0xffdd, 438, 0xffff]);
    for offset in [3, 6] {
        let source = [crate::opendream::OpenDreamSourceInfo {
            offset,
            file: Some(0),
            line: 21,
        }];
        let debug = lower_proc_bytecode_with_debug_info(&od, &Ids, 0, &[], &source).unwrap();
        let items = byond_dmb::bytecode::decode(&debug).unwrap();
        let call = items.iter().find(|item| item.opcode == 0x29).unwrap();
        assert_eq!(call.operands, [0xffdc, 0xffd9, 0, 0xffdd, 438, 0xffff]);
        assert!(items
            .iter()
            .any(|item| item.opcode == 0x85 && item.operands == [21]));
    }
}
#[test]
fn named_method_call_builds_assoc_argument_list() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn string(&self, old: u32) -> Option<u32> {
            match old {
                0 => Some(438),
                298 => Some(248),
                299 => Some(247),
                _ => None,
            }
        }
    }
    let od = [
        0x06, 8, 0, 0x8e, 2, 0, 0, 0, 0x2a, 1, 0, 0, 0, 0, 0, 0x40, 0x2b, 1, 0, 0, 0, 0, 0x80,
        0x3f, 0x6a, 0, 0, 0, 0, 2, 4, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &Ids).unwrap();
    let decoded = byond_dmb::bytecode::decode(&words).unwrap();
    assert_eq!(decoded[4].name, "NewAssocList");
    assert_eq!(decoded[5].name, "Call");
    assert_eq!(decoded[5].operands.last(), Some(&0xffff));
}
#[test]
fn branch_rebases_byte_offsets() {
    let code = [0x11, 0x0c, 8, 0, 0, 0, 0x11, 0x10, 0x10];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [0x60, 0, 0, 0x0d, 0x11, 10, 0x60, 0, 0, 0x12, 0x12, 0]
    );
}
#[test]
fn opendream_smoke_add_matches_dreammaker_code() {
    // add(a,b) from the current OpenDream compiler, compared with the
    // same source compiled by DreamMaker 516.1687.
    let od = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 8, 0x10];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x3e, 0x12, 0]
    );
}
#[test]
fn opendream_smoke_parent_and_global_calls() {
    // Prefix of /world/New: ..(); then call add(2,3).
    struct Ids;
    impl SymbolResolver for Ids {
        fn proc_id(&self, old: u32) -> Option<u32> {
            (old == 2).then_some(1)
        }
    }
    let od = [
        0x0a, 6, 4, 0, 0, 0, 0, 0x51, 0x88, 2, 0, 0, 0, 0, 0, 0, 0x40, 0, 0, 0x40, 0x40, 0x0a, 11,
        2, 0, 0, 0, 1, 2, 0, 0, 0, 0x51,
    ];
    let out = lower_proc_bytecode(&od, &Ids).unwrap();
    assert_eq!(&out[..2], &[0x2c, 0x51]);
    assert!(out.windows(3).any(|w| w == [0x30, 2, 1]));
}
#[test]
fn world_log_output_matches_dreammaker_shape() {
    // OpenDream's world.log << "SMOKE READY" subsequence.
    let od = [0x06, 5, 3, 41, 1, 0, 0, 0x4e, 12, 42, 1, 0, 0];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffdc, 0xffe5, 298, 0x60, 6, 297, 0x03, 0]
    );
}
#[test]
fn repeated_world_log_output_reuses_live_cache() {
    let od = [
        0x06, 5, 3, 41, 1, 0, 0, 0x4e, 12, 42, 1, 0, 0, 0x06, 5, 0x38, 0, 0, 0, 0x40, 0x4e, 12, 42,
        1, 0, 0,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    assert_eq!(
        out.windows(4)
            .filter(|w| *w == [0x33, 0xffdc, 0xffe5, 298])
            .count(),
        1
    );
    assert!(out.windows(2).any(|w| w == [0x33, 298]));
}
#[test]
fn world_fields_reuse_world_owner_cache() {
    // world.log << "[world.maxx][world.maxy]" without formatting.
    let od = [
        0x06, 5, 0x86, 5, 54, 0, 0, 0, 0x86, 5, 55, 0, 0, 0, 0x4e, 12, 78, 0, 0, 0,
    ];
    let out = lower_proc_bytecode(&od, &()).unwrap();
    // Native world.log output prefix establishes World before its RHS;
    // both subsequent direct World fields use the selected cache.
    assert_eq!(out, [0x33, 0xffdc, 0xffe5, 78, 0x33, 54, 0x33, 55, 0x03, 0]);
}
#[test]
fn formatted_world_output_uses_dreammaker_fused_opcode() {
    let od = [
        0x06, 5, // world output target
        0x38, 0, 0, 0x80, 0x3f, // float 1 interpolation
        0x04, 7, 0, 0, 0, 1, 0, 0, 0, // FormatString(7, 1)
        0x4e, 12, 78, 0, 0, 0, // OutputReference(world.log)
    ];
    assert_eq!(
        lower_proc_bytecode(&od, &()).unwrap(),
        [0x33, 0xffdc, 0xffe5, 78, 0x60, 0x2a, 0x3f80, 0, 0x04, 7, 1, 0]
    );
    let source = [crate::opendream::OpenDreamSourceInfo {
        offset: 16,
        file: Some(9),
        line: 44,
    }];
    let debug = lower_proc_bytecode_with_debug_info(&od, &(), 0, &[], &source).unwrap();
    let decoded = byond_dmb::bytecode::decode(&debug).unwrap();
    assert!(decoded
        .iter()
        .any(|item| item.opcode == 0x84 && item.operands == [9]));
    assert!(decoded
        .iter()
        .any(|item| item.opcode == 0x85 && item.operands == [44]));
    assert_eq!(
        byond_dmb::bytecode::encode(
            &decoded
                .into_iter()
                .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                .collect::<Vec<_>>()
        ),
        lower_proc_bytecode(&od, &()).unwrap()
    );
}
#[test]
fn compact_list_constructors_expand_without_losing_value_order() {
    // These are the optimizer's CreateListN* forms. The reference form
    // contains a local reference (kind 9, slot 0).
    let strings = [0x90, 2, 0, 0, 0, 7, 0, 0, 0, 8, 0, 0, 0];
    let refs = [0x91, 1, 0, 0, 0, 9, 0];
    let resources = [0x92, 1, 0, 0, 0, 4, 0, 0, 0];
    struct Ids;
    impl SymbolResolver for Ids {
        fn resource(&self, old: u32) -> Option<u32> {
            Some(old)
        }
    }
    assert_eq!(
        lower_proc_bytecode(&strings, &Ids).unwrap(),
        [0x60, 6, 7, 0x60, 6, 8, 0x1a, 2, 0]
    );
    assert_eq!(
        lower_proc_bytecode(&refs, &Ids).unwrap(),
        [0x33, 0xffda, 0, 0x1a, 1, 0]
    );
    assert_eq!(
        lower_proc_bytecode(&resources, &Ids).unwrap(),
        [0x60, 12, 4, 0x1a, 1, 0]
    );
}
#[test]
fn typed_and_angles_match_paired_compilers() {
    // fixtures/lowering/compact_lists_and_types.dm, OpenDream and
    // DreamMaker 516.1687. The /obj type is type 26 in OpenDream JSON.
    struct Ids;
    impl SymbolResolver for Ids {
        fn type_id(&self, old: u32) -> Option<u32> {
            (old == 26).then_some(4)
        }
        fn type_tag(&self, old: u32) -> Option<u8> {
            (old == 26).then_some(9)
        }
    }
    let typed = [0x06, 8, 0, 0x95, 26, 0, 0, 0, 0x10];
    let angles = [0x06, 8, 0, 0x7b, 0x06, 8, 1, 0x7e, 0x08, 0x10];
    assert_eq!(
        lower_proc_bytecode(&typed, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x60, 9, 4, 0x7d, 0x12, 0]
    );
    assert_eq!(
        lower_proc_bytecode(&angles, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x184, 0x33, 0xffd9, 1, 0x145, 0x3e, 0x12, 0]
    );
    let angle2 = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x7f, 0x10];
    assert_eq!(
        lower_proc_bytecode(&angle2, &Ids).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x146, 0x12, 0]
    );
}
#[test]
fn membership_output_and_getstep_match_paired_compilers() {
    // Paired DreamMaker/OpenDream 516.1687 source in the moreops fixture.
    let member = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x36, 0x10];
    let emit = [0x06, 8, 1, 0x4e, 8, 0];
    let getstep = [0x87, 2, 0, 0, 0, 8, 0, 8, 1, 0x75, 0x10];
    assert_eq!(
        lower_proc_bytecode(&member, &()).unwrap(),
        [0x33, 0xffd9, 1, 0x33, 0xffd9, 0, 0xa9, 5, 0x36, 0x12, 0]
    );
    assert_eq!(
        lower_proc_bytecode(&emit, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x03, 0]
    );
    assert_eq!(
        lower_proc_bytecode(&getstep, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x90, 0x12, 0]
    );
}
#[test]
fn pick_list_matches_dreammaker_and_multiple_candidates_are_preserved() {
    let one = [0x06, 8, 0, 0x54, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&one, &()).unwrap(),
        [0x33, 0xffd9, 0, 0xd2, 0x12, 0]
    );
    let three = [0x87, 3, 0, 0, 0, 8, 0, 8, 1, 8, 2, 0x54, 3, 0, 0, 0, 0x10];
    let out = lower_proc_bytecode(&three, &()).unwrap();
    assert_eq!(
        out,
        [
            0x79, 2, 21845, 7, 43690, 12, 17, 0x33, 0xffd9, 0, 0x0f, 20, 0x33, 0xffd9, 1, 0x0f, 20,
            0x33, 0xffd9, 2, 0x12, 0
        ]
    );
}
#[test]
fn packed_pick_counts_are_bounded_by_the_supplied_operand_stream() {
    for opcode in [0x54, 0x88, 0x87, 0x8c, 0x89] {
        let malformed = [opcode, 0xff, 0xff, 0xff, 0xff, 0x10];
        let error = lower_proc_bytecode(&malformed, &()).unwrap_err();
        assert_eq!(error.offset, 0);
        assert!(error.reason.contains("count"));
    }
}
