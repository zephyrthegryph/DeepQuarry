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

#[derive(Default)]
struct MockResolver {
    strings: HashMap<u32, u32>,
    builtins: HashMap<u32, u32>,
    types: HashMap<u32, (u8, u32)>,
    modified_instances: HashMap<(u32, u32), u32>,
    reject_procs: bool,
}

impl MockResolver {
    fn with_string(mut self, source: u32, native: u32) -> Self {
        self.strings.insert(source, native);
        self
    }

    fn with_builtin(mut self, source: u32, native: u32) -> Self {
        self.builtins.insert(source, native);
        self
    }

    fn without_procs(mut self) -> Self {
        self.reject_procs = true;
        self
    }

    fn with_type(mut self, source: u32, tag: u8, native: u32) -> Self {
        self.types.insert(source, (tag, native));
        self
    }

    fn with_modified_instance(mut self, ty: u32, string: u32, instance: u32) -> Self {
        self.modified_instances.insert((ty, string), instance);
        self
    }
}

impl SymbolResolver for MockResolver {
    fn string(&self, old: u32) -> Option<u32> {
        self.strings.get(&old).copied()
    }

    fn proc_id(&self, old: u32) -> Option<u32> {
        (!self.reject_procs).then_some(old)
    }

    fn builtin_proc(&self, old: u32) -> Option<u32> {
        self.builtins.get(&old).copied()
    }

    fn type_id(&self, old: u32) -> Option<u32> {
        self.types
            .get(&old)
            .map(|(_, native)| *native)
            .or(Some(old))
    }

    fn type_tag(&self, old: u32) -> Option<u8> {
        self.types.get(&old).map(|(tag, _)| *tag).or(Some(32))
    }

    fn modified_instance(&self, old_type: u32, old_string: u32) -> Option<u32> {
        self.modified_instances
            .get(&(old_type, old_string))
            .copied()
    }
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
        "../fixtures/translation/iterator_parity.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/iterator_parity.native.bin"
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
        "../fixtures/translation/field_compound.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/field_compound.native.bin"
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
        "../fixtures/translation/builtin_final.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/builtin_final.native.bin"
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
        "../fixtures/lowering/indexed_safe_rhs.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/indexed_safe_rhs.bin"))
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
        "../fixtures/translation/indexed_conditional_key.json"
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
        "../fixtures/lowering/indexed_logical.json"
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
        "../fixtures/translation/client_iterator.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/client_iterator.native.bin"
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
        "../fixtures/lowering/prompt_file_color.json"
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
        "../fixtures/lowering/prompt_file_color.json"
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
        "../fixtures/lowering/prompt_file_color.json"
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
        "../fixtures/lowering/output_constructors.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/output_constructors.bin"
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
        "../fixtures/lowering/indexed_increment_complex.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/indexed_increment_complex.bin"
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
        "../fixtures/lowering/switch_range_null.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/switch_range_null.bin"))
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
        "../fixtures/translation/computed_method.json"
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
        "../fixtures/translation/safe_indexed_value.json"
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
        "../fixtures/translation/safe_rhs_extended.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/safe_rhs_extended.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        "../fixtures/translation/try_empty.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/try_empty.native.bin"
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
        "../fixtures/translation/client_iterator.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/client_iterator.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        "../fixtures/translation/logical_fields.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/logical_fields.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        "../fixtures/translation/logical_fields_nativeordered.json"
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
        "../fixtures/translation/safe_field_list.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/safe_field_list.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        "../fixtures/translation/safe_method_index.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/safe_method_index.native.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        "../fixtures/translation/assoc_after_filter.json"
    ))
    .unwrap();
    let proc = input
        .procs
        .iter()
        .find(|proc| proc.name == "assoc_after_filter")
        .unwrap();
    let words = lower_proc_bytecode(proc.bytecode.as_ref().unwrap(), &()).unwrap();
    let decoded = crate::bytecode::decode(&words).unwrap();
    assert!(decoded
        .iter()
        .any(|item| item.opcode == 0x52 && item.operands.first() == Some(&20)));
    assert!(decoded.iter().any(|item| item.opcode == 0x17e));
}
#[test]
fn indexed_effectful_operands_follow_native_evaluation_order() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/indexed_order.json"
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
        "../fixtures/translation/builtin_last.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/builtin_last.native.bin"
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
        "../fixtures/translation/indexed_keys.json"
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
    let names: Vec<_> = crate::bytecode::decode(&words)
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
    let names: Vec<_> = crate::bytecode::decode(&words)
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
    let names: Vec<_> = crate::bytecode::decode(&words)
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
    let calls: Vec<_> = crate::bytecode::decode(&words)
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
        let items = crate::bytecode::decode(&debug).unwrap();
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
    let decoded = crate::bytecode::decode(&words).unwrap();
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
    let decoded = crate::bytecode::decode(&debug).unwrap();
    assert!(decoded
        .iter()
        .any(|item| item.opcode == 0x84 && item.operands == [9]));
    assert!(decoded
        .iter()
        .any(|item| item.opcode == 0x85 && item.operands == [44]));
    assert_eq!(
        crate::bytecode::encode(
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let calls: Vec<_> = crate::bytecode::decode(&out)
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
        "../fixtures/translation/indexed_aug.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/indexed_aug.native.bin"
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
        let instructions = crate::bytecode::decode(words).unwrap();
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
        "../fixtures/translation/indexed_conditional_legacy.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/indexed_conditional.native.bin"
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
        let instructions = crate::bytecode::decode(words).unwrap();
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
    let instructions = crate::bytecode::decode(&debug).unwrap();
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
    let instructions = crate::bytecode::decode(&lowered).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
        "../fixtures/lowering/flow_legal_loops.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/flow_legal_loops.bin"))
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
        "../fixtures/lowering/flow_filter_masks.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/flow_filter_masks.bin"))
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
        "../fixtures/lowering/flow_void_join.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/flow_void_join.bin"))
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
        "../fixtures/lowering/flow_void_join.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/flow_void_join.bin"))
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
        "../fixtures/lowering/flow_indexed_join.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/flow_indexed_join.bin"))
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
        "../fixtures/lowering/flow_try_exits.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/flow_try_exits.bin"))
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
#[test]
fn heterogeneous_literal_switch_tables_match_native_cases_and_destinations() {
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/flow_switch_mixed.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/flow_switch_mixed.bin"))
            .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        let items = crate::bytecode::decode(words).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&words).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let names: Vec<_> = crate::bytecode::decode(&lowered)
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
        "../fixtures/lowering/guarded_append_debug.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/guarded_append_debug.bin"
    ))
    .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        let instructions = crate::bytecode::decode(words).unwrap();
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
    assert!(crate::bytecode::decode(&actual)
        .unwrap()
        .iter()
        .any(|item| item.opcode == 0x84));
}
#[test]
fn indexed_append_debug_markers_preserve_native_expression_semantics() {
    let program = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/indexed_append_debug.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/indexed_append_debug.bin"
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
    let instructions = crate::bytecode::decode(&actual).unwrap();
    assert!(instructions
        .iter()
        .any(|item| item.opcode == 0x84 && item.operands == [440]));
    assert!(instructions
        .iter()
        .any(|item| item.opcode == 0x85 && item.operands == [2]));
    fn normalized(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
        crate::bytecode::decode(words)
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
    let debug = crate::bytecode::decode(&debug).unwrap();
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
    let instructions = crate::bytecode::decode(&debug).unwrap();
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
        "../fixtures/lowering/self_call_names.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/self_call_names.bin"))
            .unwrap();
    struct Ids<'a> {
        program: &'a crate::opendream::OpenDreamProgram,
        native: &'a crate::dmb::Dmb,
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
        "../fixtures/lowering/call_selectors.json"
    ))
    .unwrap();
    let native =
        crate::dmb::Dmb::from_bytes(include_bytes!("../fixtures/lowering/call_selectors.bin"))
            .unwrap();
    struct Ids<'a>(&'a crate::opendream::OpenDreamProgram, &'a crate::dmb::Dmb);
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
        "../fixtures/lowering/comparison_results.json"
    ))
    .unwrap();
    let native = crate::dmb::Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/comparison_results.bin"
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let instructions = crate::bytecode::decode(&out).unwrap();
    assert_eq!(instructions[0].name, "PushVal");
    assert_eq!(instructions[0].operands, [40, 0]);
    assert_eq!(instructions[3].name, "New");
    assert_eq!(instructions[3].operands, [2]);
}
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let debug = crate::bytecode::decode(&debug).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let instructions = crate::bytecode::decode(&out).unwrap();
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
    let names: Vec<_> = crate::bytecode::decode(&out)
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
            let decoded = crate::bytecode::decode(&[target]).unwrap();
            assert_eq!(decoded.len(), 1);
            assert!(decoded[0].operands.is_empty());
        }
    }
}
