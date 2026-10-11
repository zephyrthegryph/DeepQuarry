use super::*;

#[test]
fn debug_file_string_ids_are_resolved() {
    let mut dmb = template();
    let first = dmb.strings.len() as u32;
    dmb.strings.push(crate::dmb::DmString {
        data: b"fixture.dm".to_vec(),
        long_chunks: 0,
    });
    let second = dmb.strings.len() as u32;
    dmb.strings.push(dmb.strings[first as usize].clone());
    let make = |id| bytecode::Instruction {
        offset: 0,
        opcode: 0x84,
        name: "DbgFile",
        operands: vec![id],
    };
    assert_eq!(
        instruction(&memo::NormalizationContext::new(&dmb), &make(first)).unwrap(),
        instruction(&memo::NormalizationContext::new(&dmb), &make(second)).unwrap()
    );
}

#[test]
fn class_initializer_is_compared_by_class_path() {
    let mut expected = template();
    let class_id = expected
        .classes
        .iter()
        .position(|class| expected.string(class.path_string_id()) == Some(b"/datum" as &[u8]))
        .unwrap();
    expected.classes[class_id].lists_and_procs[2] = 0;
    let mut actual = expected.clone();
    actual.procs[0].flags ^= 1;
    let options = CompareOptions {
        authored_prefixes: vec!["/datum".into()],
        compare_bytecode: false,
        ..Default::default()
    };
    let differences = compare_dmbs(&expected, &actual, &options);
    assert!(differences
        .iter()
        .any(|item| item.path == "/datum::<init>" && item.field == "proc.flags"));
    let table_differences = compare_proc_tables(&expected, &actual, 100);
    assert!(table_differences
        .iter()
        .any(|item| item.path == "/datum::<init>" && item.field == "proc.flags"));
}

#[test]
fn branch_targets_normalize_across_instruction_widths() {
    let mut expected = template();
    let mut actual = expected.clone();
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected.lists.push(vec![0x50, 2, 0xf, 4, 0x12]);
    actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
    actual.lists.push(vec![0x60, 42, 0x4000, 0, 0xf, 6, 0x12]);
    let mut collector = Collector {
        output: Vec::new(),
        limit: 10,
        report: None,
    };
    compare_code(
        &memo::NormalizationContext::new(&expected),
        0,
        &memo::NormalizationContext::new(&actual),
        0,
        "/test",
        &mut collector,
    );
    assert!(collector.output.is_empty(), "{:?}", collector.output);
}

#[test]
fn spawn_targets_normalize_without_masking_different_destinations() {
    let mut expected = template();
    let mut actual = expected.clone();
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected.lists.push(vec![0x50, 2, 0x25, 4, 0x12, 0]);
    actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
    actual
        .lists
        .push(vec![0x60, 42, 0x4000, 0, 0x25, 6, 0x12, 0]);
    assert!(compare_proc_code(&expected, 0, &actual, 0, "/test", 10, false).is_empty());
    let code_id = actual.procs[0].code_locals_args[0] as usize;
    actual.lists[code_id][5] = 7;
    assert!(!compare_proc_code(&expected, 0, &actual, 0, "/test", 10, false).is_empty());
}

#[test]
fn debug_markers_can_be_ignored_without_losing_jump_targets() {
    let mut expected = template();
    let mut actual = expected.clone();
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected
        .lists
        .push(vec![0x85, 7, 0x50, 2, 0xf, 6, 0x85, 8, 0x12]);
    actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
    actual.lists.push(vec![0x60, 42, 0x4000, 0, 0xf, 6, 0x12]);
    assert!(compare_proc_code(&expected, 0, &actual, 0, "/test", 10, true).is_empty());
    assert!(!compare_proc_code(&expected, 0, &actual, 0, "/test", 10, false).is_empty());
}

#[test]
fn try_catch_targets_normalize_across_instruction_widths() {
    let mut expected = template();
    let mut actual = expected.clone();
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected
        .lists
        .push(vec![0x50, 2, 0x12c, 4, 0x12e, 8, 0x12f, 8, 0x12]);
    actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
    actual.lists.push(vec![
        0x60, 42, 0x4000, 0, 0x12c, 6, 0x12e, 10, 0x12f, 10, 0x12,
    ]);
    let mut collector = Collector {
        output: Vec::new(),
        limit: 10,
        report: None,
    };
    compare_code(
        &memo::NormalizationContext::new(&expected),
        0,
        &memo::NormalizationContext::new(&actual),
        0,
        "/test",
        &mut collector,
    );
    assert!(collector.output.is_empty(), "{:?}", collector.output);
}

#[test]
fn safe_reference_jump_targets_normalize_across_instruction_widths() {
    let mut expected = template();
    let mut actual = expected.clone();
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected.lists.push(vec![0x50, 2, 0x13e, 4, 0x12]);
    actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
    actual.lists.push(vec![0x60, 42, 0x4000, 0, 0x13e, 6, 0x12]);
    let mut collector = Collector {
        output: Vec::new(),
        limit: 10,
        report: None,
    };
    compare_code(
        &memo::NormalizationContext::new(&expected),
        0,
        &memo::NormalizationContext::new(&actual),
        0,
        "/test",
        &mut collector,
    );
    assert!(collector.output.is_empty(), "{:?}", collector.output);
}

#[test]
fn weighted_pick_targets_normalize_across_instruction_widths() {
    let mut expected = template();
    let mut actual = expected.clone();
    expected.procs[0].code_locals_args[0] = expected.lists.len() as u32;
    expected.lists.push(vec![0x50, 10, 0xb1, 2, 6, 7, 0x12, 0]);
    actual.procs[0].code_locals_args[0] = actual.lists.len() as u32;
    actual
        .lists
        .push(vec![0x60, 42, 0x4120, 0, 0xb1, 2, 8, 9, 0x12, 0]);
    let mut collector = Collector {
        output: Vec::new(),
        limit: 10,
        report: None,
    };
    compare_code(
        &memo::NormalizationContext::new(&expected),
        0,
        &memo::NormalizationContext::new(&actual),
        0,
        "/test",
        &mut collector,
    );
    assert!(collector.output.is_empty(), "{:?}", collector.output);
}

#[test]
fn selected_path_count_detects_empty_filter() {
    let dmb = template();
    let missing = CompareOptions {
        authored_prefixes: vec!["does_not_exist".into()],
        ..Default::default()
    };
    assert_eq!(selected_path_count(&dmb, &missing), 0);
    let present = CompareOptions {
        authored_prefixes: vec!["/datum".into()],
        ..Default::default()
    };
    assert!(selected_path_count(&dmb, &present) > 0);
}

#[test]
fn world_settings_are_compared_without_raw_string_ids() {
    let expected = template();
    let mut actual = expected.clone();
    let old_name = actual.world.name_string_id();
    actual
        .strings
        .push(actual.strings[old_name as usize].clone());
    actual.world.ids[6] = (actual.strings.len() - 1) as u32;
    let options = CompareOptions {
        compare_bytecode: false,
        ..Default::default()
    };
    assert!(compare_dmbs(&expected, &actual, &options).is_empty());

    actual.world.tick_lag += 1;
    let differences = compare_dmbs(&expected, &actual, &options);
    assert!(differences
        .iter()
        .any(|item| item.path == "/world" && item.field == "numeric_settings"));
}

#[test]
fn global_declaration_flags_are_compared() {
    let expected = template();
    let mut actual = expected.clone();
    let footer = actual.variable_footer as usize;
    assert!(actual.lists[footer].len() >= 2);
    actual.lists[footer][1] ^= 2;
    let differences = compare_dmbs(
        &expected,
        &actual,
        &CompareOptions {
            compare_bytecode: false,
            ..Default::default()
        },
    );
    assert!(differences
        .iter()
        .any(|item| item.path.starts_with("/globals/") && item.field == "declaration"));
    let class_differences = compare_class_tables(&expected, &actual, 100);
    assert!(class_differences
        .iter()
        .any(|item| item.path.starts_with("/globals/") && item.field == "declaration"));
}

#[test]
fn mob_visibility_records_are_compared() {
    let expected = template();
    let mut actual = expected.clone();
    assert!(!actual.mobs.is_empty());
    actual.mobs[0].sight ^= 1;
    let differences = compare_dmbs(
        &expected,
        &actual,
        &CompareOptions {
            compare_bytecode: false,
            ..Default::default()
        },
    );
    assert!(differences.iter().any(|item| item.field == "mob.record"));
}

#[test]
fn anonymous_argument_source_expression_code_is_compared() {
    let mut expected = template();
    let empty_args = expected.lists.len() as u32;
    expected.lists.push(Vec::new());
    let argument_list = expected.lists.len() as u32;
    expected.lists.push(vec![0, 0x40, 0, 0]);
    expected.procs[0].code_locals_args[2] = argument_list;
    let expression_code = expected.lists.len() as u32;
    expected.lists.push(vec![0x50, 1, 0x12]);
    let mut expression = expected.procs[0].clone();
    expression.strings = [0xffff; 4];
    expression.code_locals_args[0] = expression_code;
    expression.code_locals_args[2] = empty_args;
    let expression_id = expected.procs.len() as u32;
    expected.procs.push(expression);
    expected.proc_references.push(expression_id);
    let mut actual = expected.clone();
    actual.lists[expression_code as usize][1] = 2;

    let differences = compare_dmbs(&expected, &actual, &CompareOptions::default());
    assert!(differences.iter().any(|item| {
        item.path.contains("::<argument 0 source>") && item.field.starts_with("bytecode[")
    }));
}

#[test]
fn decoded_map_cell_instance_changes_are_detected() {
    let mut expected = template();
    expected.dimensions = [1, 1, 1];
    expected.instances.push(crate::dmb::Instance {
        kind: 1,
        class: 0,
        initializer: 0xffff,
    });
    expected.grid.push(crate::dmb::GridRun {
        turf: (expected.instances.len() - 1) as u32,
        area: 0xffff,
        contents: 0xffff,
        copies: 1,
    });
    assert!(compare_maps(&expected, &expected, 10).is_empty());
    let mut actual = expected.clone();
    actual.grid[0].turf = 0xffff;
    let differences = compare_maps(&expected, &actual, 10);
    assert!(differences
        .iter()
        .any(|item| item.path.ends_with("/turf") && item.field == "instance"));
}

#[test]
fn semantic_map_comparison_ignores_object_order_within_a_cell() {
    let mut expected = template();
    expected.dimensions = [1, 1, 1];
    expected.instances.push(crate::dmb::Instance {
        kind: 1,
        class: 0,
        initializer: 0xffff,
    });
    expected.instances.push(crate::dmb::Instance {
        kind: 2,
        class: 0,
        initializer: 0xffff,
    });
    let a = (expected.instances.len() - 2) as u32;
    let b = a + 1;
    expected.map_objects.push(crate::dmb::MapObject {
        offset: 0,
        instance: a,
    });
    expected.map_objects.push(crate::dmb::MapObject {
        offset: 0,
        instance: b,
    });
    let mut actual = expected.clone();
    actual.map_objects[0].instance = b;
    actual.map_objects[1].instance = a;
    assert!(!compare_maps(&expected, &actual, 10).is_empty());
    assert!(compare_maps_semantic(&expected, &actual, 10).is_empty());
}

#[test]
fn mob_map_instance_uses_mob_table_before_class_table() {
    let mut dmb = template();
    assert!(dmb.classes.len() > 1);
    dmb.mobs.push(crate::dmb::MobType {
        class: 1,
        key: 0,
        sight: 0,
        extended_sight: None,
    });
    let mob_id = (dmb.mobs.len() - 1) as u32;
    dmb.instances.push(crate::dmb::Instance {
        kind: 8,
        class: mob_id,
        initializer: 0xffff,
    });
    let instance_id = (dmb.instances.len() - 1) as u32;
    assert_eq!(
        map_instance(&memo::NormalizationContext::new(&dmb), instance_id)
            .unwrap()
            .1,
        path(&dmb, 1)
    );
    assert_eq!(
        value(
            &memo::NormalizationContext::new(&dmb),
            Value {
                tag_word: 8,
                data_word: mob_id,
                extra_word: None,
            },
        ),
        NormalValue::Type(8, path(&dmb, 1)),
    );
    assert_eq!(
        value(
            &memo::NormalizationContext::new(&dmb),
            Value {
                tag_word: 41,
                data_word: instance_id,
                extra_word: None,
            },
        ),
        NormalValue::InstanceType(8, path(&dmb, 1), InstanceInitializer::Absent),
    );
}

#[test]
fn anonymous_proc_sentinel_is_not_string_id_65535() {
    let mut dmb = template();
    dmb.strings.resize(
        65_536,
        crate::dmb::DmString {
            data: b"real string".to_vec(),
            long_chunks: 0,
        },
    );
    dmb.procs[0].strings = [0xffff; 4];
    assert_eq!(dmb.string(0xffff), Some(b"real string" as &[u8]));
    assert_eq!(proc_path(&dmb, 0), None);
    assert!(!proc_index(
        &memo::NormalizationContext::new(&dmb),
        &CompareOptions::default()
    )
    .values()
    .any(|ids| ids.contains(&0)));
}

#[test]
fn independent_constant_map_writes_ignore_order_but_detect_values() {
    let mut expected = template();
    let x = expected.strings.len() as u32;
    expected.strings.push(crate::dmb::DmString {
        data: b"x".to_vec(),
        long_chunks: 0,
    });
    let y = expected.strings.len() as u32;
    expected.strings.push(crate::dmb::DmString {
        data: b"y".to_vec(),
        long_chunks: 0,
    });
    let code = expected.lists.len() as u32;
    expected.lists.push(vec![
        0x50, 1, 0x34, 0xffdc, 0xffce, x, 0x50, 2, 0x34, 0xffdc, 0xffce, y, 0,
    ]);
    let mut initializer = expected.procs[0].clone();
    initializer.strings = [0xffff; 4];
    initializer.code_locals_args[0] = code;
    let initializer_id = expected.procs.len() as u32;
    expected.procs.push(initializer);
    let instance_id = expected.instances.len() as u32;
    expected.instances.push(crate::dmb::Instance {
        kind: 1,
        class: 0,
        initializer: initializer_id,
    });
    expected.dimensions = [1, 1, 1];
    expected.grid.push(crate::dmb::GridRun {
        turf: instance_id,
        area: 0xffff,
        contents: 0xffff,
        copies: 1,
    });
    let mut actual = expected.clone();
    actual.lists[code as usize] = vec![
        0x50, 2, 0x34, 0xffdc, 0xffce, y, 0x50, 1, 0x34, 0xffdc, 0xffce, x, 0,
    ];
    assert!(!compare_maps(&expected, &actual, 10).is_empty());
    assert!(compare_maps_semantic(&expected, &actual, 10).is_empty());
    actual.lists[code as usize] = vec![
        0x50, 2, 0x34, 0xffdc, 0xffce, 0xffdc, 0xffce, y, 0x50, 1, 0x34, 0xffdc, 0xffce, 0xffdc,
        0xffce, x, 0,
    ];
    assert!(compare_maps_semantic(&expected, &actual, 10).is_empty());
    actual.lists[code as usize][6] = 0xffe5;
    assert!(constant_initializer_signature(&actual, initializer_id).is_none());
    assert!(!compare_maps_semantic(&expected, &actual, 10).is_empty());
    actual.lists[code as usize][6] = 0xffce;
    actual.lists[code as usize][1] = 3;
    assert!(!compare_maps_semantic(&expected, &actual, 10).is_empty());
}

#[test]
fn unresolved_fixed_string_ids_remain_exact_numeric_differences() {
    let dmb = template();
    let context = memo::NormalizationContext::new(&dmb);
    for opcode in [0x02, 0x04, 0x84] {
        let make = |id| bytecode::Instruction {
            offset: 0,
            opcode,
            name: "fixed string reference",
            operands: if opcode == 0x84 {
                vec![id]
            } else {
                vec![id, 0]
            },
        };
        let left = instruction(&context, &make(u32::MAX)).unwrap();
        let right = instruction(&context, &make(u32::MAX - 1)).unwrap();
        assert_eq!(left.operands[0], NormalOperand::Word(u32::MAX));
        assert_ne!(left, right);
        assert_eq!(left, instruction(&context, &make(u32::MAX)).unwrap());
    }
}
