use super::*;

#[test]
fn lowering_errors_have_machine_readable_kinds() {
    let mut reader = Reader {
        code: &[],
        at: 0,
        local_slots: Vec::new(),
        remap_locals: false,
        referenced_args: Vec::new(),
        native_arg_slots: Vec::new(),
    };
    assert_eq!(
        reader.word().unwrap_err().kind,
        LowerErrorKind::TruncatedOperand
    );
    assert_eq!(
        mapped(None, 0, "type").unwrap_err().kind,
        LowerErrorKind::UnresolvedSymbol
    );
}

#[test]
fn store_reload_provenance_preserves_statement_lifetime_and_validates_boundaries() {
    struct Mark(&'static [u32]);
    impl SymbolResolver for Mark {
        fn native_store_reload(&self, offset: usize) -> bool {
            self.0.contains(&(offset as u32))
        }
        fn native_store_reload_offsets(&self) -> &[u32] {
            self.0
        }
    }
    for kind in [8, 9] {
        let code = [0x38, 0, 0, 0x80, 0x3f, 0x09, kind, 0, 0x10];
        let words = lower_proc_bytecode(&code, &Mark(&[5])).unwrap();
        let ops: Vec<_> = crate::bytecode::decode(&words)
            .unwrap()
            .into_iter()
            .map(|ins| ins.opcode)
            .collect();
        assert_eq!(ops, [0x60, 0x34, 0x33, 0x12, 0]);
        let words = lower_proc_bytecode(&code, &Mark(&[])).unwrap();
        assert!(crate::bytecode::decode(&words)
            .unwrap()
            .iter()
            .any(|ins| ins.opcode == 0x35));
    }
    let invalid_ref = [0x38, 0, 0, 0x80, 0x3f, 0x09, 5, 0x10];
    assert!(lower_proc_bytecode(&invalid_ref, &Mark(&[5]))
        .unwrap_err()
        .reason
        .contains("local or argument"));
    let operand_marker = [0x38, 0x09, 0, 0, 0x3f, 0x10];
    for offsets in [&[1][..], &[0][..], &[99][..]] {
        let error = lower_proc_bytecode(&operand_marker, &Mark(offsets)).unwrap_err();
        assert!(error.reason.contains("instruction boundary"));
    }
}

#[test]
fn do_while_provenance_rejects_unpaired_or_forward_backedges() {
    struct Ids;
    impl SymbolResolver for Ids {
        fn native_do_while_condition(&self, offset: usize) -> bool {
            offset == 3
        }
    }
    for code in [
        vec![0x06, 8, 0, 0x0c, 9, 0, 0, 0, 0x10],
        vec![0x06, 8, 0, 0x0c, 13, 0, 0, 0, 0x0e, 13, 0, 0, 0, 0x10],
    ] {
        let error = lower_proc_bytecode(&code, &Ids).unwrap_err();
        assert_eq!(error.offset, 3);
        assert!(error.reason.contains("do/while"));
    }
}
#[test]
fn exporter_cache_reference_consumes_no_operand_index() {
    struct Ids;
    impl SymbolResolver for Ids {}
    let mut reader = Reader {
        code: &[17, 0x50],
        at: 0,
        local_slots: Vec::new(),
        remap_locals: false,
        referenced_args: Vec::new(),
        native_arg_slots: Vec::new(),
    };
    assert_eq!(reference(&mut reader, &Ids).unwrap(), Variable::Cache);
    assert_eq!(reader.at, 1);
    assert_eq!(reader.byte().unwrap(), 0x50);
}

#[test]
fn frozen_root_pass_distinguishes_binding_writes_and_receiver_changes() {
    fn emit(out: &mut Vec<u32>, opcode: u32, variable: Variable, count: Option<u32>) {
        out.push(opcode);
        out.extend(variable.encode());
        if let Some(count) = count {
            out.push(count);
        }
    }
    let global = Variable::Global(10);
    let field = || Variable::SetCache(Box::new(global.clone()), Box::new(Variable::Field(20)));
    let method = || {
        Variable::SetCache(
            Box::new(global.clone()),
            Box::new(Variable::DynamicProc(30)),
        )
    };
    let mut out = Vec::new();
    emit(&mut out, 0x33, field(), None);
    emit(&mut out, 0x29, method(), Some(0));
    emit(&mut out, 0x34, field(), None);
    emit(&mut out, 0x33, field(), None);
    emit(&mut out, 0x34, global.clone(), None);
    emit(&mut out, 0x33, field(), None);
    emit(
        &mut out,
        0x29,
        Variable::SetCache(
            Box::new(Variable::Arg(1)),
            Box::new(Variable::DynamicProc(30)),
        ),
        Some(0),
    );
    emit(&mut out, 0x33, field(), None);
    emit(&mut out, 0x34, Variable::Cache, None);
    emit(&mut out, 0x33, field(), None);
    retain_frozen_root_cache(
        &mut out,
        &mut HashMap::new(),
        &mut [],
        &Default::default(),
        &[],
    );
    let instructions = crate::bytecode::decode(&out).unwrap();
    assert_eq!(
        instructions[1].typed_operands().unwrap()[0],
        crate::bytecode::Operand::Variable(Variable::DynamicProc(30))
    );
    assert_eq!(
        instructions[2].typed_operands().unwrap()[0],
        crate::bytecode::Operand::Variable(Variable::Field(20))
    );
    assert_eq!(
        instructions[3].typed_operands().unwrap()[0],
        crate::bytecode::Operand::Variable(Variable::Field(20))
    );
    for index in [5, 7, 9] {
        assert_eq!(
            instructions[index].typed_operands().unwrap()[0],
            crate::bytecode::Operand::Variable(field())
        );
    }
}

#[test]
fn frozen_root_pass_keeps_branch_entries_and_derived_owners_explicit() {
    let root = Variable::Global(10);
    let field = || Variable::SetCache(Box::new(root.clone()), Box::new(Variable::Field(20)));
    let mut out = vec![0x33];
    out.extend(field().encode());
    out.extend([0x11, 0]);
    let target = out.len();
    out.push(0x33);
    out.extend(field().encode());
    let derived = Variable::SetCache(Box::new(Variable::Field(21)), Box::new(Variable::Field(22)));
    out.push(0x33);
    out.extend(derived.encode());
    out.push(0x33);
    out.extend(field().encode());
    let mut offsets = HashMap::from([(777, target as u32)]);
    let mut fixups = vec![Fixup {
        at: target - 1,
        target: 777,
        source: 0,
    }];
    retain_frozen_root_cache(
        &mut out,
        &mut offsets,
        &mut fixups,
        &Default::default(),
        &[],
    );
    let instructions = crate::bytecode::decode(&out).unwrap();
    assert_eq!(
        instructions[2].typed_operands().unwrap()[0],
        crate::bytecode::Operand::Variable(field())
    );
    assert_eq!(
        instructions[3].typed_operands().unwrap()[0],
        crate::bytecode::Operand::Variable(derived)
    );
    assert_eq!(
        instructions[4].typed_operands().unwrap()[0],
        crate::bytecode::Operand::Variable(field())
    );
    assert_eq!(offsets[&777] as usize, instructions[2].offset);
    assert_eq!(fixups[0].at, instructions[1].offset + 1);
}

#[test]
fn statement_call_skip_marker_precedes_pop_source_events() {
    let code = [0x0a, 14, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0x51, 0x06, 0, 0x10];
    let events = [crate::opendream::OpenDreamSourceInfo {
        offset: 11,
        file: Some(2),
        line: 77,
    }];
    let words = lower_proc_bytecode_with_debug_info(&code, &(), 0, &[], &events).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    assert_eq!(items[0].opcode, 0x2a);
    assert_eq!(items[1].opcode, 0x51);
    assert_eq!(items[2].opcode, 0x84);
    assert_eq!(items[3].opcode, 0x85);
    assert_eq!(items[3].operands, [77]);
}

#[test]
fn later_backedge_keeps_void_builtin_pop_executable() {
    struct Seed;
    impl SymbolResolver for Seed {
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn builtin_proc(&self, _: u32) -> Option<u32> {
            Some(0xda)
        }
    }
    // Push null then rand_seed(null), Pop at13. The later edge supplies
    // its own null before entering Pop; the builtin arm needs null too.
    let code = [
        0x06, 0, 0x0a, 11, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0x51, 0x06, 0, 0x0e, 13, 0, 0, 0,
    ];
    let words = lower_proc_bytecode(&code, &Seed).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    let seed = items.iter().position(|item| item.opcode == 0xda).unwrap();
    assert_eq!(items[seed + 1].opcode, 0x60);
    assert_eq!(items[seed + 1].operands, [0, 0]);
    assert_eq!(items[seed + 2].opcode, 0x51);
    let jump = items.iter().find(|item| item.opcode == 0xf8).unwrap();
    assert_eq!(jump.operands, [items[seed + 2].offset as u32]);
    let words = lower_proc_bytecode(&code[..14], &Seed).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    assert!(items.iter().all(|item| item.opcode != 0x51));
}

#[test]
fn later_backedge_keeps_call_pop_executable() {
    struct Names;
    impl SymbolResolver for Names {
        fn self_call_name(&self, _: u32) -> Option<u32> {
            Some(438)
        }
    }
    // Call self.result() at0; Pop at11. The later branch pushes null
    // before entering that same Pop, so it must execute on that edge.
    let code = [
        0x0a, 14, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0x51, 0x06, 0, 0x0e, 11, 0, 0, 0,
    ];
    let words = lower_proc_bytecode(&code, &Names).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    assert_eq!(items[0].opcode, 0x29);
    assert_eq!(items[1].opcode, 0x51);
    let jump = items.iter().find(|item| item.opcode == 0xf8).unwrap();
    assert_eq!(jump.operands, [items[1].offset as u32]);
    // Without an incoming branch, this is the native statement marker.
    let words = lower_proc_bytecode(&code[..12], &Names).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    assert_eq!(items[0].opcode, 0x2a);
    assert_eq!(items[1].opcode, 0x51);
}

#[test]
fn frame_reference_kinds_match_native_reserved_operands() {
    for (kind, word) in [(15, 0xfff1), (16, 0xfff0)] {
        assert_eq!(
            lower_proc_bytecode(&[0x06, kind, 0x10], &()).unwrap(),
            [0x33, word, 0x12, 0]
        );
        let code = [0x06, kind, 0x68, 7, 0, 0, 0, 0x10];
        let native = lower_proc_bytecode(&code, &()).unwrap();
        assert_eq!(native, [0x33, 0xffdc, word, 7, 0x12, 0]);
    }
}
#[test]
fn iterator_masks_and_nested_cleanup_match_native_compiler() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/iterator_parity.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/iterator_parity.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram);
    impl SymbolResolver for Ids<'_> {
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
    for name in [
        "iterator_untyped",
        "iterator_anything",
        "iterator_union",
        "iterator_numbers",
        "iterator_nested",
        "iterator_labelled",
        "iterator_range_nested",
        "iterator_clients",
        "iterator_typed",
        "iterator_world_type",
    ] {
        let proc = input.procs.iter().find(|proc| proc.name == name).unwrap();
        let words = lower_proc_bytecode_with_local_events_and_order(
            proc.bytecode.as_deref().unwrap(),
            &Ids(&input),
            proc.max_variable_id,
            &proc.locals,
            &proc.lexical_local_add_indices,
        )
        .unwrap();
        let actual = crate::bytecode::decode(&words).unwrap();
        let path = format!("/proc/{name}");
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = crate::bytecode::decode(native.proc_code_words(native_id).unwrap()).unwrap();
        let masks = |items: &[crate::bytecode::Instruction]| {
            items
                .iter()
                .filter(|item| item.opcode == 0x52)
                .map(|item| item.operands.clone())
                .collect::<Vec<_>>()
        };
        assert_eq!(masks(&actual), masks(&expected), "{name}: filter masks");
        for opcode in [0x54, 0x55, 0xfb] {
            assert_eq!(
                actual.iter().filter(|item| item.opcode == opcode).count(),
                expected.iter().filter(|item| item.opcode == opcode).count(),
                "{name}: cleanup opcode {opcode:x}"
            );
        }
        // Every edge leaving the inner list/range loop must reach the
        // outer iteration only after both required cleanups.
        if name == "iterator_range_nested" {
            assert!(actual.windows(3).any(|items| items[0].opcode == 0x55
                && items[1].opcode == 0xfb
                && items[1].operands == [2]
                && items[2].opcode == 0x0f));
        }
    }
}
#[test]
fn argument_reference_scanner_ignores_constant_operand_bytes() {
    assert_eq!(
        referenced_argument_indices(&[0x06, 8, 0, 0x10]).unwrap(),
        [0]
    );
    assert!(referenced_argument_indices(&[0x38, 0x06, 8, 0, 0, 0x10])
        .unwrap()
        .is_empty());
}
#[test]
fn flag_result_argument_span_includes_its_producer() {
    assert_eq!(
        constructor_argument_start(&[0x33, 0xffda, 0, 0x8a, 0x36], 1),
        Some(0)
    );
    assert_eq!(
        constructor_argument_start(&[0x33, 0xffda, 0, 0x33, 0xffda, 1, 0xa9, 5, 0x36], 1),
        Some(0)
    );
}
#[test]
fn lexical_local_add_order_remaps_bytecode_slots() {
    let events = [
        crate::opendream::OpenDreamLocal {
            offset: 0,
            remove: None,
            add: Some("later".into()),
        },
        crate::opendream::OpenDreamLocal {
            offset: 0,
            remove: None,
            add: Some("earlier".into()),
        },
    ];
    let od = [0x06, 9, 0, 0x06, 9, 1, 0x08, 0x10];
    let native =
        lower_proc_bytecode_with_local_events_and_order(&od, &(), 2, &events, &[1, 0]).unwrap();
    let decoded = crate::bytecode::decode(&native).unwrap();
    assert_eq!(decoded[0].operands, [0xffda, 1]);
    assert_eq!(decoded[1].operands, [0xffda, 0]);
    assert!(
        lower_proc_bytecode_with_local_events_and_order(&od, &(), 2, &events, &[1, 1]).is_err()
    );
}
#[test]
fn omitted_native_argument_shifts_following_slots() {
    let native = lower_proc_bytecode_with_native_layout(
        &[0x06, 8, 2, 0x10],
        &(),
        0,
        &[],
        &[],
        &[false, true, false],
        None,
    )
    .unwrap();
    assert_eq!(
        crate::bytecode::decode(&native).unwrap()[0].operands,
        [0xffd9, 1]
    );
    assert!(lower_proc_bytecode_with_native_layout(
        &[0x06, 8, 1, 0x10],
        &(),
        0,
        &[],
        &[],
        &[false, true, false],
        None,
    )
    .is_err());
}
#[test]
fn method_call_with_conditional_format_uses_direct_local_owner() {
    let od = [
        0x06, 9, 0, 0x06, 8, 0, 0x0c, 21, 0, 0, 0, 0x38, 0, 0, 0x80, 0x3f, 0x0e, 26, 0, 0, 0, 0x38,
        0, 0, 0, 0, 0x04, 1, 0, 0, 0, 1, 0, 0, 0, 0x6a, 2, 0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    let items = crate::bytecode::decode(&words).unwrap();
    assert_eq!(items[0].operands, [0xffd9, 0]);
    let call = items.iter().find(|item| item.opcode == 0x29).unwrap();
    assert_eq!(call.operands, [0xffdc, 0xffda, 0, 0xffdd, 2, 1]);
    for offset in [6, 35] {
        let source = [crate::opendream::OpenDreamSourceInfo {
            offset,
            file: Some(9),
            line: 12,
        }];
        let debug = lower_proc_bytecode_with_debug_info(&od, &(), 0, &[], &source).unwrap();
        let items = crate::bytecode::decode(&debug).unwrap();
        let call = items.iter().find(|item| item.opcode == 0x29).unwrap();
        assert_eq!(call.operands, [0xffdc, 0xffda, 0, 0xffdd, 2, 1]);
        assert!(items
            .iter()
            .any(|item| item.opcode == 0x85 && item.operands == [12]));
        assert_eq!(
            items
                .iter()
                .filter(|item| item.opcode == 0x33 && item.operands == [0xffda, 0])
                .count(),
            0
        );
    }
}
#[test]
fn native_field_operations_match_all_paired_operators_and_receiver_mutations() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/field_compound.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/field_compound.native.bin"
    ))
    .unwrap();
    struct Ids<'a> {
        program: &'a crate::opendream::OpenDreamProgram,
        native: &'a crate::dmb::Dmb,
    }
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            {
                let value = self.program.strings.get(old as usize)?;
                self.native
                    .strings
                    .iter()
                    .position(|s| s.data == value.as_bytes())
                    .map(|i| i as u32)
            }
        }
        fn proc_id(&self, old: u32) -> Option<u32> {
            let name = &self.program.procs.get(old as usize)?.name;
            self.native
                .procs
                .iter()
                .position(|p| {
                    self.native.string(p.strings[0]) == Some(format!("/proc/{name}").as_bytes())
                })
                .map(|i| i as u32)
        }
    }
    let ids = Ids {
        program: &program,
        native: &native,
    };
    for proc_ in program.procs.iter().filter(|p| p.name.starts_with("fa_")) {
        let native_id = native
            .procs
            .iter()
            .position(|p| {
                native.string(p.strings[0]) == Some(format!("/proc/{}", proc_.name).as_bytes())
            })
            .unwrap();
        let words = lower_proc_bytecode(proc_.bytecode.as_deref().unwrap(), &ids).unwrap();
        assert_eq!(
            words,
            native.proc_code_words(native_id).unwrap(),
            "{}",
            proc_.name
        );
    }
}
#[test]
fn final_builtin_overloads_match_paired_native_procedures() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/builtin_final.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/translation/builtin_final.native.bin"
    ))
    .unwrap();
    struct Ids<'a> {
        program: &'a crate::opendream::OpenDreamProgram,
        generator: u32,
    }
    impl SymbolResolver for Ids<'_> {
        fn proc_id(&self, _: u32) -> Option<u32> {
            None
        }
        fn generator_type_string(&self) -> Option<u32> {
            Some(self.generator)
        }
        fn builtin_proc(&self, old: u32) -> Option<u32> {
            Some(match self.program.procs.get(old as usize)?.name.as_str() {
                "sha1" => 0x14b,
                "winclone" => 0x10e,
                "generator" => 0x10001,
                "max" => 0xa6,
                "min" => 0xa5,
                "splicetext_char" => 0x160,
                "url_decode" => 0x108,
                "walk_rand" => 0x127,
                _ => return None,
            })
        }
    }
    let generator = native
        .strings
        .iter()
        .position(|string| string.data == b"/generator")
        .unwrap() as u32;
    for proc_ in program
        .procs
        .iter()
        .filter(|proc_| proc_.name.starts_with("bf_"))
    {
        let native_id = native
            .procs
            .iter()
            .position(|native_proc| {
                native.string(native_proc.strings[0])
                    == Some(format!("/proc/{}", proc_.name).as_bytes())
            })
            .unwrap();
        let actual = lower_proc_bytecode(
            proc_.bytecode.as_deref().unwrap(),
            &Ids {
                program: &program,
                generator,
            },
        )
        .unwrap();
        assert_eq!(
            actual,
            native.proc_code_words(native_id).unwrap(),
            "{}",
            proc_.name
        );
    }
}
#[test]
fn sha1_and_winclone_match_paired_native_shapes() {
    let ids = MockResolver::default()
        .without_procs()
        .with_builtin(0, 0x14b)
        .with_builtin(1, 0x10e);
    let sha = [6, 8, 0, 0x0a, 11, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&sha, &ids).unwrap(),
        [0x33, 0xffd9, 0, 0x14b, 0x12, 0]
    );
    let clone = [
        0x87, 3, 0, 0, 0, 8, 0, 8, 1, 8, 2, 0x0a, 11, 1, 0, 0, 0, 1, 3, 0, 0, 0, 0x51,
    ];
    assert_eq!(
        lower_proc_bytecode(&clone, &ids).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x10e, 0]
    );
}
#[test]
fn indexed_append_short_circuit_keeps_native_rhs_first_join() {
    let code = [
        0x87, 2, 0, 0, 0, 8, 0, 8, 1, 6, 8, 2, 0x2f, 20, 0, 0, 0, 6, 8, 3, 0x84, 7,
    ];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [
            0x33, 0xffd9, 2, 0xb2, 8, 0x33, 0xffd9, 3, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x34,
            0xffe3, 0x34, 0xffd8, 0x45, 0xffe4, 0
        ]
    );
}
#[test]
fn indexed_safe_rhs_preserves_native_null_and_or_joins() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/lowering/indexed_safe_rhs.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../../fixtures/lowering/indexed_safe_rhs.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
    impl SymbolResolver for Ids<'_> {
        fn string(&self, old: u32) -> Option<u32> {
            let text = self.0.strings.get(old as usize)?.as_bytes();
            self.1
                .strings
                .iter()
                .position(|value| value.data == text)
                .map(|id| id as u32)
        }
    }
    let normalized = |words: &[u32]| {
        let items = crate::bytecode::decode(words).unwrap();
        items
            .iter()
            .map(|item| {
                let mut opcode = item.opcode;
                let mut operands = item.operands.clone();
                if opcode == 0x50 {
                    operands = vec![(operands[0] as i32 as f32).to_bits()];
                } else if opcode == 0x60 && operands[0] == 42 {
                    opcode = 0x50;
                    operands = vec![(operands[1] << 16) | operands[2]];
                } else if matches!(opcode, 0x13d | 0xb2) {
                    operands[0] = items
                        .iter()
                        .position(|target| target.offset == operands[0] as usize)
                        .unwrap() as u32;
                }
                (opcode, operands)
            })
            .collect::<Vec<_>>()
    };
    for name in ["indexed_safe_append", "indexed_safe_remove"] {
        let proc = input.procs.iter().find(|proc| proc.name == name).unwrap();
        let actual =
            lower_proc_bytecode(proc.bytecode.as_deref().unwrap(), &Ids(&input, &native)).unwrap();
        let path = format!("/proc/{name}");
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            normalized(&actual),
            normalized(native.proc_code_words(id).unwrap()),
            "{name}"
        );
    }
}
#[test]
fn computed_field_increment_span_includes_its_cached_owner() {
    let words = [0x30, 0, 7, 0x34, 0xffd8, 0x62, 9];
    assert_eq!(constructor_argument_start(&words, 1), Some(0));
}
#[test]
fn indexed_assignment_value_span_keeps_the_store_and_duplicate() {
    let words = [
        0x33, 0xffd9, 0, 0x13c, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0x7c,
    ];
    assert_eq!(constructor_argument_start(&words, 1), Some(0));
}

#[test]
fn paired_numeric_text_conversions_keep_both_argument_spans() {
    // DeepQuarry paint.mix_data uses CopyText; Text2NumRadix; Mul.
    assert_eq!(
        constructor_argument_start(&[0x50, 1, 0x50, 16, 0x158], 1),
        Some(0)
    );
    // communications.tgui_data uses unary Num2Text within Format.
    assert_eq!(constructor_argument_start(&[0x50, 2, 0x77], 1), Some(0));
}

#[test]
fn conditional_indexed_key_joins_before_native_cache_store() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../../fixtures/translation/indexed_conditional_key.json"
    ))
    .unwrap();
    let proc = program
        .procs
        .iter()
        .find(|proc| proc.name == "indexed_conditional_key")
        .unwrap();
    let lowered = lower_proc_bytecode(proc.bytecode.as_deref().unwrap(), &()).unwrap();
    // Paired native proc#0: the key's taken branch must skip to CacheKey,
    // rather than back to the RHS that moved ahead of the destination.
    assert_eq!(
        lowered,
        [
            0x33, 0xffd9, 4, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x0d, 0x11, 17, 0x33, 0xffd9, 2,
            0x0f, 20, 0x33, 0xffd9, 3, 0x34, 0xffe3, 0x34, 0xffd8, 0x45, 0xffe4, 0
        ]
    );
}
#[test]
fn augmented_rhs_span_keeps_the_eval_producer() {
    let words = [0x33, 0xffd9, 1, 0x45, 0xffd9, 0, 0x13f];
    assert_eq!(constructor_argument_start(&words, 1), Some(0));
}
#[test]
fn packed_short_references_do_not_misread_format_string_id_as_membership() {
    let code = [
        0x87, 2, 0, 0, 0, 8, 0, 1, 0x04, 0x36, 0xad, 0, 0, 2, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffce, 0x02, 0xad36, 2, 0x12, 0]
    );
}
#[test]
fn nested_property_method_receiver_is_read_after_argument_mutation() {
    let code = [
        0x86, 8, 0, 0x29, 1, 0, 0, 0xa3, 0x87, 2, 0, 0, 0, 8, 0, 8, 1, 9, 12, 0x29, 1, 0, 0, 0x6a,
        1, 0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [
            0x33, 0xffd9, 1, 0x35, 0xffdc, 0xffd9, 0, 0x129, 0x29, 0xffdc, 0xffd9, 0, 0xffdc,
            0x129, 0xffdd, 1, 1, 0x12, 0
        ]
    );
}
#[test]
fn direct_method_receiver_is_read_after_argument_mutation() {
    let code = [
        6, 8, 0, 0xa3, 6, 8, 1, 9, 8, 0, 0x6a, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [0x33, 0xffd9, 1, 0x35, 0xffd9, 0, 0x29, 0xffdc, 0xffd9, 0, 0xffdd, 1, 1, 0x12, 0]
    );
}
#[test]
fn native_receiver_boundaries_preserve_nested_calls() {
    let code = [
        0x06, 8, 0, 0xa3, 0x06, 8, 1, 0xa3, 0x06, 8, 2, 0x6a, 3, 0, 0, 0, 1, 1, 0, 0, 0, 0x6a, 2,
        0, 0, 0, 1, 1, 0, 0, 0, 0x10,
    ];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [
            0x33, 0xffd9, 2, 0x29, 0xffdc, 0xffd9, 1, 0xffdd, 3, 1, 0x29, 0xffdc, 0xffd9, 0,
            0xffdd, 2, 1, 0x12, 0
        ]
    );
    assert!(lower_proc_bytecode(&[0x06, 8, 0, 0xa3], &()).is_err());
}
#[test]
fn native_ordered_membership_extension_preserves_list_then_item() {
    let code = [0x06, 8, 0, 0x06, 8, 1, 0xa4, 0x10];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xa9, 5, 0x36, 0x12, 0]
    );
}
#[test]
fn native_keyed_assoc_extension_preserves_explicit_null_key() {
    let code = [0x11, 0x06, 8, 0, 0xa2, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [0x60, 0, 0, 0x33, 0xffd9, 0, 0xc8, 1, 0x12, 0]
    );
}
#[test]
fn native_ordered_constructor_extension_keeps_type_before_arguments() {
    let positional = [0x02, 3, 0, 0, 0, 0x06, 8, 0, 0xa1, 1, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&positional, &()).unwrap(),
        [0x60, 32, 3, 0x33, 0xffd9, 0, 0x01, 1, 0x12, 0]
    );
    let arglist = [0x02, 3, 0, 0, 0, 0x06, 8, 0, 0xa1, 3, 1, 0, 0, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&arglist, &()).unwrap(),
        [0x60, 32, 3, 0x33, 0xffd9, 0, 0xcf, 0x12, 0]
    );
}
#[test]
fn native_ordered_call_extension_preserves_target_evaluation_order() {
    let od = [
        0x06, 8, 0, 0x06, 8, 1, 0x06, 8, 2, 0xa0, 0, 2, 1, 1, 0, 0, 0, 0x10,
    ];
    let native = lower_proc_bytecode(&od, &()).unwrap();
    assert_eq!(
        native,
        [0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0x33, 0xffd9, 2, 0xb5, 1, 0x12, 0]
    );
    assert_eq!(
        constructor_argument_start(&native[..native.len() - 2], 1),
        Some(0)
    );
}
#[test]
fn short_circuit_indexed_assignment_evaluates_value_first() {
    // OD retains list/key while computing (list[key] || 0). Native DMB
    // evaluates that value first, then fetches list/key for ListSet.
    let od = [
        0x06, 9, 0, 0x06, 9, 1, 0x06, 9, 0, 0x06, 9, 1, 0x69, 0x2f, 23, 0, 0, 0, 0x38, 0, 0, 0, 0,
        0x85, 7, 0x10,
    ];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    let instructions = crate::bytecode::decode(&words).unwrap();
    let names: Vec<_> = instructions.iter().map(|item| item.name).collect();
    assert_eq!(
        names,
        [
            "GetVar", "GetVar", "ListGet", "JmpOr", "PushVal", "GetVar", "GetVar", "ListSet",
            "Ret", "End"
        ]
    );
}
#[test]
fn arithmetic_and_return() {
    // OpenDream: push 2.0, push 3.0, add, return.
    let mut code = vec![0x38];
    code.extend(2f32.to_le_bytes());
    code.push(0x38);
    code.extend(3f32.to_le_bytes());
    code.extend([0x08, 0x10]);
    let out = lower_proc_bytecode(&code, &()).unwrap();
    assert_eq!(
        out,
        [0x60, 0x2a, 0x4000, 0, 0x60, 0x2a, 0x4040, 0, 0x3e, 0x12, 0]
    );
}
#[test]
fn unoptimized_numeric_switch_cases_keep_all_targets() {
    // switch_constant.no_opts.json, paired with DreamMaker 516.
    // OpenDream places the default body first; both case targets must
    // still reach their matching return values after lowering.
    let od = [
        0x06, 8, 0, 0x38, 0, 0, 0x80, 0x3f, 0x32, 35, 0, 0, 0, 0x38, 0, 0, 0, 0x40, 0x32, 46, 0, 0,
        0, 0x51, 0x38, 0, 0, 0xf0, 0x41, 0x10, 0x0e, 57, 0, 0, 0, 0x38, 0, 0, 0x20, 0x41, 0x10,
        0x0e, 57, 0, 0, 0, 0x38, 0, 0, 0xa0, 0x41, 0x10, 0x0e, 57, 0, 0, 0,
    ];
    let words = lower_proc_bytecode(&od, &()).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    assert_eq!(decoded[1].name, "Switch");
    assert_eq!(decoded[2].name, "PushVal");
    assert_eq!(decoded[5].name, "PushVal");
    assert_eq!(decoded[8].name, "PushVal");
}
#[test]
fn unoptimized_string_switch_cases_keep_distinct_ids() {
    let ids = MockResolver::default()
        .with_string(296, 247)
        .with_string(297, 248);
    let od = [
        0x06, 8, 0, 0x03, 0x28, 1, 0, 0, 0x32, 35, 0, 0, 0, 0x03, 0x29, 1, 0, 0, 0x32, 46, 0, 0, 0,
        0x51, 0x38, 0, 0, 0xf0, 0x41, 0x10, 0x0e, 57, 0, 0, 0, 0x38, 0, 0, 0x20, 0x41, 0x10, 0x0e,
        57, 0, 0, 0, 0x38, 0, 0, 0xa0, 0x41, 0x10, 0x0e, 57, 0, 0, 0,
    ];
    let words = lower_proc_bytecode(&od, &ids).unwrap();
    assert_eq!(&words[3..11], &[0x78, 2, 6, 247, 19, 6, 248, 26]);
}
