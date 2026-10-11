//! Control flow lowering regression tests.
use super::*;

#[test]
fn repeated_local_declarations_are_source_errors_at_current_typed_headers() {
    for source in [
        "/proc/shadow_probe()\n    var/value = 7\n    if(1)\n        var/value = 9\n    return value\n",
        "/proc/shadow_probe()\n    var/value = 7\n    var/value = 9\n    return value\n",
    ] {
        let parsed = dm_syntax::parse(source);
        let body = dm_syntax::parse_body_items(&parsed.items[0].children);
        assert!(body.diagnostics.is_empty());
        let expected = source.rfind("var/value = 9").unwrap();
        let errors = compile_simple_proc(&parsed.items[0].children).unwrap_err();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
        assert_eq!(errors[0].reason, "value: duplicate definition");
        assert_eq!(errors[0].span.unwrap().start, expected);
        assert_eq!(errors[0].related.len(), 1);
        assert_eq!(errors[0].related[0].span.start, source.find("var/value = 7").unwrap());
        assert_eq!(errors[0].related[0].message, "value: previous definition");
    }
}

#[test]
fn independent_sibling_local_declarations_and_outer_assignment_remain_accepted() {
    for source in [
        "/proc/shadow_probe()\n    var/result = 0\n    if(1)\n        var/value = 7\n        result += value\n    if(1)\n        var/value = 9\n        result += value\n    return result\n",
        "/proc/shadow_probe()\n    var/value = 7\n    if(1)\n        value = 9\n    return value\n",
    ] {
        let parsed = dm_syntax::parse(source);
        let compiled = compile_simple_proc(&parsed.items[0].children).unwrap();
        assert!(link_proc(&compiled.code, &Ledger::default()).is_ok());
    }
}

#[test]
fn duplicate_label_is_source_error_at_exact_header_span() {
    let parsed =
        dm_syntax::parse("/proc/p()\n    repeat:\n        return\n    repeat:\n        return\n");
    let error = super::compile_simple_proc(&parsed.items[0].children)
        .unwrap_err()
        .remove(0);
    assert_eq!(error.kind, super::LowerErrorKind::SourceError);
    assert_eq!(
        error.span.unwrap().start,
        parsed.items[0].children[1].header_span.start
    );
}

#[test]
fn spawn_and_do_while_match_native_bodies() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/spawn_do_while/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/spawn_do_while/probe.native.bin"
    ))
    .unwrap();
    for (item, path) in [
        (&ast.items[0], "/proc/test"),
        (&ast.items[1], "/proc/spawn_test"),
    ] {
        let compiled = compile_simple_proc_with_params(&item.children, &["n".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
    }
}

#[test]
fn existing_local_iterator_matches_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/existing_iterator/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/existing_iterator/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn in_list_and_range_match_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/in_range/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/in_range/probe.native.bin"
    ))
    .unwrap();
    for (item, path, params) in [
        (&ast.items[0], "/proc/range_check", vec!["x".into()]),
        (
            &ast.items[1],
            "/proc/list_member",
            vec!["x".into(), "L".into()],
        ),
    ] {
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
    }
}

#[test]
fn weighted_pick_matches_native_switch_layout() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/weighted_pick/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/weighted_pick/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn dynamic_weighted_pick_matches_native_switch_layout() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/dynamic_pick/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["a".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/dynamic_pick/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn implicit_world_iterator_matches_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/implicit_for/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(reference(Table::Class, "/datum/thing"), 0)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/implicit_for/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn typed_list_iterator_supplies_implicit_istype_path() {
    let ast = dm_syntax::parse(
        "/proc/probe(list/L)\n    for(var/datum/thing/M in L)\n        if(istype(M))\n            return M\n",
    );
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    assert!(compiled.class_paths.contains(&SymbolId::of("/datum/thing")));
}

#[test]
fn typed_iterator_masks_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/remaining_forms.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/remaining_forms.native.bin"
    ))
    .unwrap();
    for id in 0..3 {
        let compiled =
            compile_simple_proc_with_params(&ast.items[id].children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "iterator {id}"
        );
    }
}

#[test]
fn dynamic_range_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/dynamic_range_step/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/dynamic_range_step/probe.native.bin"
    ))
    .unwrap();
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["n".into(), "s".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn view_orange_and_turf_pick_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/view_orange.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/view_orange.native.bin"
    ))
    .unwrap();
    for id in 0..7 {
        let params = if id == 2 || id == 5 {
            vec!["A".into()]
        } else {
            vec![]
        };
        let compiled = compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
        let mut ledger = Ledger::default();
        if id == 6 {
            let class_id = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .find(|instruction| {
                    instruction.opcode == opcode::PUSH_VAL
                        && instruction.operands.first() == Some(&10)
                })
                .unwrap()
                .operands[1];
            ledger
                .bind(reference(Table::Class, "/turf"), class_id)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn labeled_loops_and_comparison_flags_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/labeled_nested_iter/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/labeled_nested_iter/probe.native.bin"
    ))
    .unwrap();
    for (id, item) in ast.items.iter().enumerate() {
        let params = match id {
            0..=2 | 11 | 12 | 14 | 17 | 19 => vec!["L".into()],
            6..=8 => vec!["a".into(), "b".into()],
            10 => vec!["x".into()],
            _ => vec![],
        };
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let mut ledger = Ledger::default();
        if id == 16 {
            ledger.bind(reference(Table::Class, "/datum"), 0).unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        if id == 18 {
            let native_code =
                byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
            assert_eq!(
                ours.iter()
                    .filter(|instruction| instruction.opcode == opcode::JMP_LOOP)
                    .count(),
                native_code
                    .iter()
                    .filter(|instruction| instruction.opcode == opcode::JMP_LOOP)
                    .count()
            );
            continue;
        }
        if id == 10 {
            assert_eq!(
                linked
                    .words
                    .windows(2)
                    .filter(|pair| pair == &[opcode::TEQ, opcode::POP])
                    .count(),
                2
            );
            continue;
        }
        assert_eq!(
            linked.words,
            native.proc_code_words(id).unwrap(),
            "proc {id}"
        );
    }
}

#[test]
fn sibling_labeled_loops_with_same_name_lower() {
    let ast = dm_syntax::parse("/proc/probe(list/L)\n    var/result = 0\n    if(L)\n        outer_loop:\n            for(var/x in L)\n                if(x)\n                    break outer_loop\n                result += x\n    if(L)\n        outer_loop:\n            for(var/y in L)\n                if(y)\n                    continue outer_loop\n                result += y\n    return result\n");
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    link_proc(&compiled.code, &Ledger::default()).unwrap();
}

#[test]
fn implicit_return_preserves_dot_and_ends_like_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/implicit_return/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/implicit_return/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc_with_params(&item.children, &["a".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn bare_returns_end_native_frames_and_preserve_return_variable() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/bare_return.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/bare_return.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let params = if index == 2 {
            vec!["value".into()]
        } else {
            vec![]
        };
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        assert_eq!(
            link_proc(&compiled.code, &Ledger::default()).unwrap().words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn literal_arithmetic_return_decodes_as_native_instructions() {
    let ast = dm_syntax::parse("/proc/test()\n  return 2 + 3 * 4\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(
        decoded.iter().map(|i| i.opcode).collect::<Vec<_>>(),
        [0x50, 0x12, 0]
    );
}

#[test]
fn branches_and_loops_have_valid_native_targets() {
    let ast = dm_syntax::parse("/proc/test(x)\n  var/y = 1\n  while(x)\n    x = x - 1\n  if(y)\n    return x\n  else\n    return 0\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let starts: BTreeSet<_> = decoded.iter().map(|i| i.offset as u32).collect();
    for instruction in decoded {
        for target in instruction.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn nested_break_and_continue_target_the_nearest_loop() {
    let ast = dm_syntax::parse("/proc/test(x)\n  while(x)\n    while(x)\n      continue\n      break\n    break\n  return x\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let starts: BTreeSet<_> = decoded
        .iter()
        .map(|instruction| instruction.offset as u32)
        .collect();
    for instruction in decoded {
        for target in instruction.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
    let invalid = dm_syntax::parse("/proc/test()\n  break\n");
    assert!(compile_simple_proc(&invalid.items[0].children).is_err());
}

#[test]
fn lists_sleep_and_boolean_branches_decode() {
    let ast = dm_syntax::parse(
        "/proc/test(x)\n  var/items = list(1, 2)\n  if(x && 1)\n    sleep(1)\n  return items\n",
    );
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let instructions = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(instructions
        .iter()
        .any(|instruction| instruction.opcode == opcode::NEW_LIST));
    assert!(instructions
        .iter()
        .any(|instruction| instruction.opcode == opcode::SLEEP));
    assert!(instructions
        .iter()
        .any(|instruction| instruction.opcode == opcode::JMP_AND));
    let associative = dm_syntax::parse("/proc/test()\n  return list(\"key\" = 1)\n");
    let compiled = compile_simple_proc(&associative.items[0].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .assign(
            Table::String,
            compiled
                .strings
                .iter()
                .map(|payload| SymRef::String(payload.id)),
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert!(byond_dmb::bytecode::decode(&linked.words)
        .unwrap()
        .iter()
        .any(|ins| ins.opcode == 0xc8));
}

#[test]
fn c_style_for_with_continue_and_break_has_valid_branches() {
    let ast = dm_syntax::parse("/proc/test(n)\n  var/result = 0\n  for(var/i = 0; i < n; i = i + 1)\n    if(i == 2)\n      continue\n    if(i == 5)\n      break\n    result += i\n  return result\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["n".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let starts: BTreeSet<_> = decoded
        .iter()
        .map(|instruction| instruction.offset as u32)
        .collect();
    for instruction in decoded {
        for target in instruction.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn switch_cases_compare_a_single_evaluated_selector() {
    let ast = dm_syntax::parse("/proc/test(x)\n  switch(x)\n    if(1)\n      return 10\n    if(2)\n      return 20\n    else\n      return 30\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    assert_eq!(compiled.local_count, 1);
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(
        decoded
            .iter()
            .filter(|instruction| instruction.opcode == opcode::TEQ)
            .count(),
        2
    );
    let starts: BTreeSet<_> = decoded
        .iter()
        .map(|instruction| instruction.offset as u32)
        .collect();
    for instruction in decoded {
        for target in instruction.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn range_for_supports_ascending_and_descending_steps() {
    for control in [
        "var/i = 1 to n step 2",
        "var/i = 5 to n step -1",
        "var/i in 1 to n",
    ] {
        let source = format!(
            "/proc/test(n)\n  var/result = 0\n  for({control})\n    result += i\n  return result\n"
        );
        let ast = dm_syntax::parse(&source);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["n".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode
                == if control.contains("step") { 0xff } else { 0xfd }));
        assert_eq!(compiled.local_count, 2);
    }
}

#[test]
fn switch_alternatives_and_inclusive_range_decode() {
    let ast = dm_syntax::parse("/proc/test(x)\n  switch(x)\n    if(1, 2)\n      return 10\n    if(3 to 5)\n      return 20\n    else\n      return 0\n");
    let typed = dm_syntax::parse_body_items(&ast.items[0].children);
    assert!(typed.diagnostics.is_empty());
    assert!(matches!(
        typed.statements[0].kind,
        StatementKind::Switch { .. }
    ));
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(compiled.local_count, 0);
    let table = decoded
        .iter()
        .find(|instruction| instruction.opcode == 0x7a)
        .unwrap();
    assert_eq!(table.branch_targets().unwrap().len(), 4);
    assert!(!decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::TEQ));
}

#[test]
fn switch_break_targets_switch_and_continue_targets_outer_loop() {
    let ast = dm_syntax::parse("/proc/test(x)\n  while(x)\n    switch(x)\n      if(1)\n        break\n      else\n        continue\n    return x\n  return 0\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let starts: BTreeSet<_> = decoded
        .iter()
        .map(|instruction| instruction.offset as u32)
        .collect();
    for instruction in decoded {
        for target in instruction.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn native_iterator_setup_matches_paired_fixture() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/iterator_parity.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/iterator_parity.dm"
    ));
    for name in ["iterator_untyped", "iterator_anything"] {
        let proc = ast
            .items
            .iter()
            .find(|item| item.header.contains(name))
            .unwrap();
        let compiled = compile_simple_proc_with_params(&proc.children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(name.as_bytes()))
            })
            .unwrap();
        let native_words = native.proc_code_words(id).unwrap();
        assert_eq!(
            &linked.words[..18],
            &native_words[..18],
            "{name} iterator setup"
        );
    }
    let proc = ast
        .items
        .iter()
        .find(|item| item.header.contains("iterator_typed"))
        .unwrap();
    let compiled = compile_simple_proc_with_params(&proc.children, &["L".into()]).unwrap();
    let class_id = native
        .classes
        .iter()
        .position(|class| {
            native.string(class.path_string_id()) == Some(b"/datum/iterator_probe".as_slice())
        })
        .unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(
            reference(Table::Class, "/datum/iterator_probe"),
            class_id as u32,
        )
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| {
            native
                .string(proc.strings[0])
                .is_some_and(|path| path.ends_with(b"iterator_typed"))
        })
        .unwrap();
    assert_eq!(
        &linked.words[..28],
        &native.proc_code_words(id).unwrap()[..28]
    );
}

#[test]
fn nested_ternary_branches_leave_a_value() {
    let ast = dm_syntax::parse("/proc/choose(x,y)\n  return x ? 1 : y ? 2 : 3\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["x".into(), "y".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(
        decoded
            .iter()
            .filter(|instruction| instruction.opcode == opcode::JZ)
            .count(),
        2
    );
    let starts: BTreeSet<_> = decoded
        .iter()
        .map(|instruction| instruction.offset as u32)
        .collect();
    for instruction in &decoded {
        for target in instruction.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn try_catch_matches_native_fixture_shape() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/try_join_cleanup/probe.native.bin"
    ))
    .unwrap();
    let source = include_str!("../../../../../fixtures/translation/try_join_cleanup/probe.dm");
    let ast = dm_syntax::parse(source);
    let item = ast
        .items
        .iter()
        .find(|item| item.header.starts_with("/proc/join_if_else("))
        .unwrap();
    let bindings = LowerBindings {
        parameters: vec!["x".into()],
        global_procs: HashMap::from([(
            "join_helper".into(),
            reference(Table::Proc, "/proc/join_helper"),
        )]),
        ..LowerBindings::default()
    };
    let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
    assert_eq!(compiled.local_names, ["e"]);
    let mut ledger = Ledger::default();
    for string in &compiled.strings {
        let id = native
            .strings
            .iter()
            .position(|entry| entry.data == string.bytes.as_ref())
            .unwrap();
        ledger
            .bind(reference(Table::String, string), id as u32)
            .unwrap();
    }
    let helper = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/join_helper".as_slice()))
        .unwrap();
    ledger
        .bind(reference(Table::Proc, "/proc/join_helper"), helper as u32)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/join_if_else".as_slice()))
        .unwrap();
    let actual = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let expected = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
    assert_eq!(
        actual
            .iter()
            .take(expected.len() - 1)
            .map(|ins| ins.opcode)
            .collect::<Vec<_>>(),
        expected
            .iter()
            .take(expected.len() - 1)
            .map(|ins| ins.opcode)
            .collect::<Vec<_>>()
    );
}

#[test]
fn nested_try_throw_has_valid_targets_and_catch_slots() {
    let ast = dm_syntax::parse("/proc/guard(x)\n  try\n    try\n      if(x)\n        throw \"inner\"\n    catch(var/exception/inner)\n      throw inner\n  catch(var/outer)\n    return outer\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    assert_eq!(compiled.local_names, ["inner", "outer"]);
    let ledger = Ledger::default();
    let mut ledger = ledger;
    ledger.bind(reference(Table::String, "inner"), 1).unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(decoded.iter().filter(|ins| ins.opcode == 0x12c).count(), 2);
    assert_eq!(decoded.iter().filter(|ins| ins.opcode == 0x12e).count(), 2);
    assert_eq!(decoded.iter().filter(|ins| ins.opcode == 0x12d).count(), 2);
    let starts: BTreeSet<_> = decoded.iter().map(|ins| ins.offset as u32).collect();
    for ins in decoded {
        for target in ins.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn continue_exiting_inner_try_uses_tryjmp() {
    let ast = dm_syntax::parse("/proc/loop(x)\n  while(x)\n    try\n      x = x - 1\n      continue\n    catch(var/e)\n      return e\n  return x\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded.iter().any(|ins| ins.opcode == 0x12f));
    let starts: BTreeSet<_> = decoded.iter().map(|ins| ins.offset as u32).collect();
    for ins in decoded {
        for target in ins.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn goto_exiting_try_uses_native_tryjmp() {
    let source = include_str!("../../../../../fixtures/translation/try_join_cleanup/probe.dm");
    let ast = dm_syntax::parse(source);
    let item = ast
        .items
        .iter()
        .find(|item| item.header.starts_with("/proc/join_goto_out("))
        .unwrap();
    let bindings = LowerBindings {
        parameters: vec!["x".into()],
        global_procs: HashMap::from([(
            "join_helper".into(),
            reference(Table::Proc, "/proc/join_helper"),
        )]),
        ..LowerBindings::default()
    };
    let compiled = compile_fixture_proc_with_bindings(&item.children, &bindings).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/try_join_cleanup/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    for string in &compiled.strings {
        let id = native
            .strings
            .iter()
            .position(|entry| entry.data == string.bytes.as_ref())
            .unwrap();
        ledger
            .bind(reference(Table::String, string), id as u32)
            .unwrap();
    }
    let helper = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/join_helper".as_slice()))
        .unwrap();
    ledger
        .bind(reference(Table::Proc, "/proc/join_helper"), helper as u32)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let native_id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/join_goto_out".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(native_id).unwrap());
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded.iter().any(|ins| ins.opcode == 0x12f));
    let starts: BTreeSet<_> = decoded.iter().map(|ins| ins.offset as u32).collect();
    for ins in decoded {
        for target in ins.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn nested_list_iterators_save_and_restore_outer_state() {
    let ast = dm_syntax::parse("/proc/test(L)\n  for(var/outer in L)\n    for(var/inner in L)\n      if(inner)\n        break\n  return null\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert_eq!(
        decoded
            .iter()
            .filter(|instruction| instruction.opcode == opcode::ITER_PUSH)
            .count(),
        1
    );
    assert_eq!(
        decoded
            .iter()
            .filter(|instruction| instruction.opcode == opcode::ITER_POP)
            .count(),
        1
    );
}
#[test]
fn initializerless_local_inside_loop_resets_each_iteration() {
    let ast = dm_syntax::parse(
        "/proc/test()\n    while(1)\n        var/datum/best\n        best = src\n        break\n",
    );
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let words = link_proc(&compiled.code, &Ledger::default()).unwrap().words;
    assert!(words
        .windows(6)
        .any(|window| window == [0x60, 0, 0, 0x34, 0xffda, 0]));
}
#[test]
fn break_inside_switch_exits_enclosing_loop() {
    let ast = dm_syntax::parse("/proc/test()\n    while(1)\n        switch(1)\n            if(1)\n                break\n    return 7\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let loop_exit = decoded
        .iter()
        .find(|instruction| instruction.opcode == opcode::JZ)
        .unwrap()
        .operands[0];
    assert!(decoded
        .iter()
        .filter(|instruction| instruction.opcode == opcode::JMP)
        .any(|instruction| instruction.operands[0] == loop_exit));
}

#[test]
fn protected_entry_gotos_are_exact_native_bad_link_source_errors() {
    for source in [
        include_str!("../../../../../fixtures/native/protected_entry_diagnostics/goto_into_try.dm"),
        include_str!(
            "../../../../../fixtures/native/protected_entry_diagnostics/goto_into_iterator.dm"
        ),
    ] {
        let parsed = dm_syntax::parse(source);
        assert!(parsed.diagnostics.is_empty());
        let errors = compile_simple_proc(&parsed.items[0].children).unwrap_err();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
        assert_eq!(errors[0].reason, "goto inside: bad link");
        assert_eq!(
            errors[0].span.unwrap().start,
            source.find("goto inside").unwrap()
        );
    }
}

#[test]
fn authenticated_local_var_block_uses_full_declaration_lowering() {
    let source = include_str!(
        "../../../../../fixtures/native/local_declaration_group_diagnostics/group_block_control.dm"
    );
    let parsed = dm_syntax::parse(source);
    let body = dm_syntax::parse_body_items(&parsed.items[0].children);
    assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
    let block = compile_simple_proc(&parsed.items[0].children).unwrap();
    let control = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native/local_declaration_group_diagnostics/separate_control.dm"
    ));
    let separate = compile_simple_proc(&control.items[0].children).unwrap();
    assert_eq!(
        link_proc(&block.code, &Ledger::default()).unwrap().words,
        link_proc(&separate.code, &Ledger::default()).unwrap().words
    );
}
