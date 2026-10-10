#[test]
fn duplicate_proc_pairing_uses_bindings_and_detects_body_swaps() {
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/procedure_membership_order.native.bin"
    ))
    .unwrap();
    let index = proc_index(
        &memo::NormalizationContext::new(&native),
        &CompareOptions::default(),
    );
    let (path, group) = index
        .iter()
        .find(|(_, ids)| {
            ids.len() > 1 && ids.iter().all(|&id| native.procs[id].strings[0] != 0xffff)
        })
        .expect("paired duplicate path");
    let mut reversed = group.clone();
    reversed.reverse();
    order_proc_group_by_binding(&native, &mut reversed);
    assert_eq!(&reversed, group);
    let mut corrupted = native.clone();
    let first = group[0];
    let second = group[1];
    let left = corrupted.procs[first].code_locals_args;
    corrupted.procs[first].code_locals_args = corrupted.procs[second].code_locals_args;
    corrupted.procs[second].code_locals_args = left;
    let discrepancies = compare_dmbs(&native, &corrupted, &CompareOptions::default());
    assert!(
        discrepancies
            .iter()
            .any(|difference| difference.path.as_bytes() == path.as_slice()
                && (difference.field.contains("arguments")
                    || difference.field.contains("locals")
                    || difference.field.contains("bytecode"))),
        "{discrepancies:#?}"
    );
}
#[test]
fn shared_marker_tokens_do_not_hide_constructor_aliasing() {
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/marker_tokens.native.bin"
    ))
    .unwrap();
    let field = |name: &[u8]| {
        native
            .variables
            .iter()
            .position(|variable| native.string(variable.name) == Some(name))
            .unwrap()
    };
    let a = field(b"a");
    let b = field(b"b");
    let x = field(b"x");
    let d = field(b"d");
    let e = field(b"e");
    assert_eq!(native.variables[a].value, native.variables[x].value);
    assert_ne!(native.variables[a].value, native.variables[b].value);
    assert_eq!(native.variables[d].value, native.variables[e].value);
    let id = native.world.ids[4] as usize;
    let code_id = native.procs[id].code_locals_args[0] as usize;
    let code = native.proc_code_words(id).unwrap();
    let instructions = crate::bytecode::decode(code).unwrap();
    let constructors: Vec<_> = instructions
        .iter()
        .filter(|instruction| instruction.opcode == 1)
        .collect();
    assert!(constructors.len() >= 2);
    let mut aliased = native.clone();
    let offset = constructors[1].offset;
    aliased.lists[code_id].splice(offset..offset + 2, [0x33, 0xffdb, a as u32]);
    assert_eq!(marker_integrity(&native), marker_integrity(&aliased));
    assert!(
        !compare_proc_code(&native, id, &aliased, id, "global initializer", 100, true).is_empty()
    );
}
#[test]
fn authored_proc_marker_is_canonicalized_for_identity() {
    assert_eq!(
        super::canonical_proc_path(b"/area/proc/Adjacent".to_vec()),
        b"/area/Adjacent"
    );
    assert_eq!(
        super::canonical_proc_path(b"/proc/global_proc".to_vec()),
        b"/proc/global_proc"
    );
    assert_eq!(
        super::canonical_proc_path(b"/mob/verb/whisper".to_vec()),
        b"/mob/whisper"
    );
}
use super::*;

fn template() -> Dmb {
    Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap()
}

#[test]
fn procedure_and_verb_selectors_are_not_field_reads() {
    let dmb = template();
    let selectors = [
        Variable::Field(0),
        Variable::DynamicProc(0),
        Variable::DynamicVerb(0),
        Variable::StaticProc(0),
        Variable::StaticVerb(0),
    ];
    for (index, left) in selectors.iter().enumerate() {
        for right in &selectors[index + 1..] {
            if matches!(
                (left, right),
                (Variable::DynamicProc(_), Variable::StaticProc(_))
                    | (Variable::DynamicVerb(_), Variable::StaticVerb(_))
            ) {
                continue;
            }
            assert_ne!(
                variable(&memo::NormalizationContext::new(&dmb), left),
                variable(&memo::NormalizationContext::new(&dmb), right)
            );
        }
    }
}

#[test]
fn static_proc_normalization_requires_its_actual_display_name() {
    let mut dmb = template();
    let display = dmb.strings.len() as u32;
    dmb.strings.push(crate::dmb::DmString {
        data: b"Actual Display".to_vec(),
        long_chunks: 0,
    });
    let wrong = dmb.strings.len() as u32;
    dmb.strings.push(crate::dmb::DmString {
        data: b"identifier_only".to_vec(),
        long_chunks: 0,
    });
    dmb.procs[0].strings[1] = display;
    assert_eq!(
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticProc(0)
        ),
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::DynamicProc(display)
        )
    );
    assert_ne!(
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticProc(0)
        ),
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::DynamicProc(wrong)
        )
    );
    assert_ne!(
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticProc(0)
        ),
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticVerb(0)
        )
    );
    dmb.procs[0].strings[1] = 0xffff;
    assert_ne!(
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticProc(0)
        ),
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::DynamicProc(0xffff)
        )
    );
}

#[test]
fn static_verb_normalization_preserves_namespace_and_actual_display_name() {
    let mut dmb = template();
    let display = dmb.strings.len() as u32;
    dmb.strings.push(crate::dmb::DmString {
        data: b"Shared Alias".to_vec(),
        long_chunks: 0,
    });
    let wrong = dmb.strings.len() as u32;
    dmb.strings.push(crate::dmb::DmString {
        data: b"identifier_only".to_vec(),
        long_chunks: 0,
    });
    dmb.procs[0].strings[1] = display;
    assert_eq!(
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticVerb(0)
        ),
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::DynamicVerb(display)
        )
    );
    for other in [
        Variable::DynamicVerb(wrong),
        Variable::DynamicProc(display),
        Variable::StaticProc(0),
    ] {
        assert_ne!(
            variable(
                &memo::NormalizationContext::new(&dmb),
                &Variable::StaticVerb(0)
            ),
            variable(&memo::NormalizationContext::new(&dmb), &other)
        );
    }
    dmb.procs[0].strings[1] = 0xffff;
    assert_ne!(
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticVerb(0)
        ),
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::DynamicVerb(0xffff)
        )
    );
    assert_ne!(
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::StaticVerb(u32::MAX)
        ),
        variable(
            &memo::NormalizationContext::new(&dmb),
            &Variable::DynamicVerb(0xffff)
        )
    );
}

#[test]
#[cfg(feature = "opendream-translation")]
fn colliding_display_aliases_follow_native_dynamic_call_encoding() {
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/selector_alias_collision.bin"
    ))
    .unwrap();
    let input = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/selector_alias_collision.json"
    ))
    .unwrap();
    let baseline = crate::opendream::OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let emitted = crate::translate::translate_named_debug(
        &input,
        &baseline,
        &template(),
        std::path::Path::new("fixtures/lowering"),
        Some("selector_alias_collision"),
        false,
    )
    .unwrap();
    for name in ["/proc/selector_call_first", "/proc/selector_call_second"] {
        let find = |dmb: &Dmb| {
            dmb.procs
                .iter()
                .position(|proc| dmb.string(proc.strings[0]) == Some(name.as_bytes()))
                .unwrap()
        };
        // Receiver cache materialization can introduce extra instructions.
        // This regression checks selector identity and argument count,
        // while the separate receiver tests verify cache timing.
        let call = |dmb: &Dmb, id| {
            let instruction = bytecode::decode(dmb.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .find(|i| matches!(i.opcode, 0x29 | 0x2a))
                .unwrap();
            let operands = instruction.typed_operands().unwrap();
            let Operand::Variable(mut selector) = operands[0].clone() else {
                panic!("call selector missing")
            };
            while let Variable::SetCache(_, right) = selector {
                selector = *right;
            }
            (
                instruction.opcode,
                variable(&memo::NormalizationContext::new(dmb), &selector),
                operands[1].clone(),
            )
        };
        assert_eq!(
            call(&native, find(&native)),
            call(&emitted.dmb, find(&emitted.dmb)),
            "{name}"
        );
    }
    let find = |name: &[u8]| {
        native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(name))
            .unwrap()
    };
    assert_eq!(
        native.proc_code_words(find(b"/proc/selector_call_first")),
        native.proc_code_words(find(b"/proc/selector_call_second"))
    );
    assert_eq!(
        native.proc_code_words(find(b"/proc/selector_cached_first")),
        native.proc_code_words(find(b"/proc/selector_cached_second"))
    );
}

#[test]
fn global_call_proc_allocations_resolve_without_erasing_argument_counts() {
    let expected = template();
    let mut actual = expected.clone();
    let relocated = actual.procs.len() as u32;
    actual.procs.push(actual.procs[0].clone());
    for (opcode, native, moved) in [
        (0x30, vec![2, 0], vec![2, relocated]),
        (0xcd, vec![0], vec![relocated]),
    ] {
        let ins = |operands| bytecode::Instruction {
            offset: 0,
            opcode,
            name: "call",
            operands,
        };
        assert_eq!(
            instruction(&memo::NormalizationContext::new(&expected), &ins(native)).unwrap(),
            instruction(&memo::NormalizationContext::new(&actual), &ins(moved)).unwrap()
        );
    }
    let ins = |count| bytecode::Instruction {
        offset: 0,
        opcode: 0x30,
        name: "call",
        operands: vec![count, 0],
    };
    assert_ne!(
        instruction(&memo::NormalizationContext::new(&expected), &ins(2)).unwrap(),
        instruction(&memo::NormalizationContext::new(&expected), &ins(3)).unwrap()
    );
}

#[test]
fn switch_case_string_allocations_do_not_change_semantics() {
    let expected = template();
    let mut actual = expected.clone();
    let relocated = actual.strings.len() as u32;
    actual.strings.push(actual.strings[0].clone());
    let case = |id| Value {
        tag_word: 6,
        data_word: id,
        extra_word: None,
    };
    assert_eq!(
        operand(
            &memo::NormalizationContext::new(&expected),
            Operand::Switch {
                cases: vec![(case(0), 9)],
                default: 11
            }
        ),
        operand(
            &memo::NormalizationContext::new(&actual),
            Operand::Switch {
                cases: vec![(case(relocated), 9)],
                default: 11
            }
        ),
    );
    assert_eq!(
        operand(
            &memo::NormalizationContext::new(&expected),
            Operand::RangeSwitch {
                ranges: vec![],
                exact: vec![(case(0), 9)],
                default: 11
            }
        ),
        operand(
            &memo::NormalizationContext::new(&actual),
            Operand::RangeSwitch {
                ranges: vec![],
                exact: vec![(case(relocated), 9)],
                default: 11
            }
        ),
    );
}

#[test]
fn builtin_type_singletons_do_not_resolve_class_zero() {
    let dmb = template();
    for (tag, name) in [
        (40, b"/list".as_slice()),
        (39, b"/file".as_slice()),
        (36, b"/savefile".as_slice()),
    ] {
        assert_eq!(
            value(
                &memo::NormalizationContext::new(&dmb),
                Value {
                    tag_word: tag,
                    data_word: 0,
                    extra_word: None
                }
            ),
            NormalValue::Type(tag as u8, Some(name.to_vec())),
        );
    }
}

#[test]
fn modified_type_constants_include_override_values() {
    let mut expected = template();
    let code = expected.lists.len() as u32;
    expected
        .lists
        .push(vec![0x50, 1, 0x34, 0xffdc, 0xffce, 0, 0]);
    expected.procs[0].code_locals_args[0] = code;
    let instance = expected.instances.len() as u32;
    expected.instances.push(crate::dmb::Instance {
        kind: 32,
        class: 0,
        initializer: 0,
    });
    let raw = Value {
        tag_word: 41,
        data_word: instance,
        extra_word: None,
    };
    let mut actual = expected.clone();
    assert_eq!(
        value(&memo::NormalizationContext::new(&expected), raw),
        value(&memo::NormalizationContext::new(&actual), raw)
    );
    actual.lists[code as usize][1] = 2;
    assert_ne!(
        value(&memo::NormalizationContext::new(&expected), raw),
        value(&memo::NormalizationContext::new(&actual), raw)
    );
    actual.instances[instance as usize].initializer = 0xffff;
    assert_ne!(
        value(&memo::NormalizationContext::new(&expected), raw),
        value(&memo::NormalizationContext::new(&actual), raw)
    );
}

#[test]
fn unknown_modified_type_initializers_retain_identity_and_avoid_cycles() {
    let mut dmb = template();
    let instance = dmb.instances.len() as u32;
    let code = dmb.lists.len() as u32;
    dmb.lists
        .push(vec![0x60, 41, instance, 0x34, 0xffdc, 0xffce, 0, 0]);
    dmb.procs[0].code_locals_args[0] = code;
    dmb.instances.push(crate::dmb::Instance {
        kind: 32,
        class: 0,
        initializer: 0,
    });
    let raw = Value {
        tag_word: 41,
        data_word: instance,
        extra_word: None,
    };
    let before = value(&memo::NormalizationContext::new(&dmb), raw);
    assert!(matches!(
        before,
        NormalValue::InstanceType(_, _, InstanceInitializer::Opaque(_, _))
    ));
    let second = dmb.procs.len() as u32;
    dmb.procs.push(dmb.procs[0].clone());
    dmb.instances[instance as usize].initializer = second;
    assert_ne!(before, value(&memo::NormalizationContext::new(&dmb), raw));
}

#[test]
fn switch_targets_and_case_values_normalize_across_word_widths() {
    for opcode in [0x78, 0x79, 0x7a] {
        let mut expected = template();
        let mut actual = expected.clone();
        let mut left = vec![0x50, 2, opcode];
        let mut right = vec![0x60, 42, 0x4000, 0, opcode];
        let table = match opcode {
            0x78 => vec![1, 42, 0x4000, 0, 0, 0],
            0x79 => vec![1, 32767, 0, 0],
            0x7a => vec![1, 42, 0, 0, 42, 0x4000, 0, 0, 1, 0, 0, 0, 0],
            _ => unreachable!(),
        };
        left.extend(&table);
        right.extend(table);
        let left_end = left.len() as u32;
        let right_end = right.len() as u32;
        let target_positions: &[usize] = match opcode {
            0x78 => &[4, 5],
            0x79 => &[2, 3],
            0x7a => &[7, 11, 12],
            _ => unreachable!(),
        };
        for &position in target_positions {
            left[3 + position] = left_end;
            right[5 + position] = right_end;
        }
        left.push(0x12);
        right.push(0x12);
        expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
        expected.lists.push(left);
        actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
        actual.lists.push(right);
        assert!(compare_proc_code(&expected, 0, &actual, 0, "/switch", 10, true).is_empty());
        // A changed destination must remain a discrepancy after normalization.
        let code_id = actual.procs[0].code_locals_args[0] as usize;
        actual.lists[code_id][5 + target_positions[0]] = 0;
        assert!(!compare_proc_code(&expected, 0, &actual, 0, "/switch", 10, true).is_empty());
    }
}

#[test]
fn identical_dmb_has_no_discrepancies() {
    let dmb = template();
    assert!(compare_dmbs(&dmb, &dmb, &CompareOptions::default()).is_empty());
}
#[test]
fn dedicated_icon_state_is_checked_by_both_metadata_comparers() {
    let expected = template();
    let mut actual = expected.clone();
    let id = expected
        .classes
        .iter()
        .position(|class| expected.string(class.path_string_id()) == Some(b"/obj" as &[u8]))
        .unwrap();
    let mut state = actual.strings[0].clone();
    state.data = b"changed inherited state".to_vec();
    actual.classes[id].initial_ids[5] = actual.strings.len() as u32;
    actual.strings.push(state);
    let full = compare_dmbs(
        &expected,
        &actual,
        &CompareOptions {
            compare_bytecode: false,
            ..Default::default()
        },
    );
    let tables = compare_class_tables(&expected, &actual, 100);
    for differences in [full, tables] {
        assert!(
            differences.iter().any(|difference| {
                difference.path == "/obj" && difference.field == "class.header.icon_state"
            }),
            "dedicated appearance slots must not disappear behind matching variable lists"
        );
    }
}
#[test]
fn dedicated_header_ids_are_normalized_but_payload_changes_remain_visible() {
    let mut expected = template();
    let id = expected
        .classes
        .iter()
        .position(|class| expected.string(class.path_string_id()) == Some(b"/obj" as &[u8]))
        .unwrap();
    expected.resources.push(crate::dmb::ResourceRef {
        kind: 6,
        id: 0x1234,
    });
    expected.classes[id].initial_ids[4] = 0;
    let mut actual = expected.clone();
    let old_name = actual.classes[id].name_string_id();
    actual.classes[id].initial_ids[2] = actual.strings.len() as u32;
    actual
        .strings
        .push(actual.strings[old_name as usize].clone());
    actual.resources.push(actual.resources[0].clone());
    actual.classes[id].initial_ids[4] = 1;
    assert!(compare_class_tables(&expected, &actual, 100).is_empty());
    assert!(compare_dmbs(
        &expected,
        &actual,
        &CompareOptions {
            compare_bytecode: false,
            ..Default::default()
        }
    )
    .is_empty());
    actual.resources[1].id ^= 1;
    assert!(compare_class_tables(&expected, &actual, 100)
        .iter()
        .any(|d| d.field == "class.header.icon"));
    actual.resources[1].id ^= 1;
    actual.classes[id].direction ^= 1;
    assert!(compare_class_tables(&expected, &actual, 100)
        .iter()
        .any(|d| d.field == "class.header.direction"));
}
#[test]
fn client_path_is_a_singleton_not_class_zero() {
    let dmb = template();
    let singleton = Value {
        tag_word: 59,
        data_word: 0,
        extra_word: None,
    };
    assert_eq!(
        value(&memo::NormalizationContext::new(&dmb), singleton),
        NormalValue::Type(59, Some(b"/client".to_vec()))
    );
    let invalid = Value {
        data_word: 9,
        ..singleton
    };
    assert_eq!(
        value(&memo::NormalizationContext::new(&dmb), invalid),
        NormalValue::Raw(invalid)
    );
}

#[test]
fn class_parent_change_uses_logical_path() {
    let expected = template();
    let mut actual = expected.clone();
    let class_id = actual
        .classes
        .iter()
        .position(|c| actual.string(c.path_string_id()) == Some(b"/datum" as &[u8]))
        .unwrap();
    actual.classes[class_id].initial_ids[1] = class_id as u32;
    let diff = compare_dmbs(
        &expected,
        &actual,
        &CompareOptions {
            authored_prefixes: vec!["/datum".into()],
            ..Default::default()
        },
    );
    assert!(diff
        .iter()
        .any(|d| d.path == "/datum" && d.field == "class.parent"));
}

#[test]
fn string_id_allocation_does_not_change_semantic_value() {
    let mut dmb = template();
    let original = dmb.classes[0].path_string_id();
    let copy = dmb.strings[original as usize].clone();
    dmb.strings.push(copy);
    let new_id = (dmb.strings.len() - 1) as u32;
    dmb.classes[0].initial_ids[0] = new_id;
    let reference = template();
    let options = CompareOptions {
        compare_bytecode: false,
        ..Default::default()
    };
    assert!(compare_dmbs(&reference, &dmb, &options).is_empty());
}

#[test]
fn equivalent_integer_pushes_normalize_to_same_float() {
    let dmb = template();
    let compact = bytecode::Instruction {
        offset: 0,
        opcode: 0x50,
        name: "PushInt",
        operands: vec![2],
    };
    let float = bytecode::Instruction {
        offset: 0,
        opcode: 0x60,
        name: "PushVal",
        operands: vec![42, 0x4000, 0],
    };
    assert_eq!(
        instruction(&memo::NormalizationContext::new(&dmb), &compact).unwrap(),
        instruction(&memo::NormalizationContext::new(&dmb), &float).unwrap()
    );
}

#[test]
fn compact_integer_normalization_uses_native_unsigned_word() {
    let dmb = template();
    for raw in [65535, 65536, (-26i32) as u32] {
        let compact = bytecode::Instruction {
            offset: 0,
            opcode: 0x50,
            name: "PushInt",
            operands: vec![raw],
        };
        assert_eq!(
            instruction(&memo::NormalizationContext::new(&dmb), &compact).unwrap(),
            NormalInstruction {
                opcode: 0x60,
                operands: vec![NormalOperand::Value(NormalValue::Number(
                    (raw as u16 as f32).to_bits()
                ))],
            }
        );
    }
}

#[test]
fn format_string_ids_are_resolved() {
    let mut dmb = template();
    let first = dmb.strings.len() as u32;
    dmb.strings.push(crate::dmb::DmString {
        data: b"result [x]".to_vec(),
        long_chunks: 0,
    });
    let second = dmb.strings.len() as u32;
    dmb.strings.push(dmb.strings[first as usize].clone());
    let left = bytecode::Instruction {
        offset: 0,
        opcode: 0x4,
        name: "OutputFormat",
        operands: vec![first, 1],
    };
    let right = bytecode::Instruction {
        offset: 0,
        opcode: 0x4,
        name: "OutputFormat",
        operands: vec![second, 1],
    };
    assert_eq!(
        instruction(&memo::NormalizationContext::new(&dmb), &left).unwrap(),
        instruction(&memo::NormalizationContext::new(&dmb), &right).unwrap()
    );
}

#[path = "compare_code_map_tests.rs"]
mod code_maps;

#[test]
fn explicit_procedure_rank_matches_structural_duplicate_roster() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/procedure_membership_order.native.bin"
    ))
    .unwrap();
    let index = proc_index(
        &memo::NormalizationContext::new(&dmb),
        &CompareOptions::default(),
    );
    let (path, group) = index.iter().find(|(_, ids)| ids.len() > 1).unwrap();
    for (rank, &id) in group.iter().enumerate() {
        assert_eq!(ranked_proc_by_path(&dmb, path, rank), Some(id));
    }
    assert_eq!(ranked_proc_by_path(&dmb, path, group.len()), None);
    assert_eq!(
        ranked_proc_by_path(&dmb, b"/definitely_missing/proc/check", 0),
        None
    );
}
