//! Expressions lowering regression tests.
use super::*;

#[test]
fn shifts_fold_native_unsigned_24_bit_values_and_leave_unsafe_cases_to_runtime() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/integer_shifts.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/integer_shifts.dm"
    ));
    for id in 0..4 {
        let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
        assert_eq!(
            link_proc(&compiled.code, &Ledger::default()).unwrap().words,
            native.proc_code_words(id).unwrap()
        );
    }
    for source in [
        "1 << 32",
        "1 << -1",
        "1 >> 32",
        "1 >> -1",
        "1.#INF << 1",
        "2147483648 >> 1",
        "-2147483904 << 1",
        "5.5 >> 1",
        "1 << 1.5",
    ] {
        assert!(
            fold_number(&parse_expression(source).expr.unwrap()).is_none(),
            "{source}"
        );
    }
}

/// Value tags of builtin-family type paths, measured on the DeepQuarry production build with DreamMaker 516.1687
/// (`dmb-equiv dump-proc ... | grep path`): `/atom` and `/turf/...` are 10, `/atom/movable/...` and `/obj/...` 9,
/// `/area/...` 11, `/datum/...` 32. This compiler used to tag `/atom` itself as 9 (317 sites in the production tree).
#[test]
fn type_path_literals_carry_the_native_family_tag() {
    for (source, tag) in [
        ("/atom", 10u8),
        ("/atom/movable", 9),
        ("/obj", 9),
        ("/obj/item", 9),
        ("/mob", 8),
        ("/turf", 10),
        ("/turf/simulated", 10),
        ("/area", 11),
        ("/datum", 32),
    ] {
        let ast = dm_syntax::parse(&format!("/proc/probe()
    return {source}
"));
        assert!(ast.diagnostics.is_empty(), "{source}: {:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let tags: Vec<_> = compiled
            .code
            .items
            .iter()
            .filter_map(|item| match item {
                crate::Item::Instruction(instruction) => Some(&instruction.operands),
                _ => None,
            })
            .flatten()
            .filter_map(|word| match word {
                crate::Word::Value(crate::ValueWord::ClassPath { tag, .. }) => Some(*tag),
                _ => None,
            })
            .collect();
        assert_eq!(tags, vec![tag], "{source}");
    }
}

#[test]
fn runtime_power_matches_native_fixture() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/runtime_power/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/runtime_power/probe.native.bin"
    ))
    .unwrap();
    let id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/power".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(id).unwrap());
}

#[test]
fn logical_assignments_match_native_short_circuit_bodies() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/logical_assignment/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/logical_assignment/probe.native.bin"
    ))
    .unwrap();
    for (item, path, params) in [
        (
            &ast.items[1],
            "/proc/or_assign",
            vec!["x".into(), "y".into()],
        ),
        (
            &ast.items[2],
            "/proc/and_assign",
            vec!["x".into(), "y".into()],
        ),
        (&ast.items[3], "/proc/member", vec!["x".into()]),
    ] {
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
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
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let expected = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(
            ours.iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            expected
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            "{path}"
        );
    }
}

#[test]
fn grouped_augmented_assignment_target_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/group_target/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["A".into()]).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/group_target/probe.native.bin"
    ))
    .unwrap();
    let mut ledger = Ledger::default();
    for key in &compiled.strings {
        let string_id = native
            .strings
            .iter()
            .position(|entry| entry.data == compiled.string_bytes(key.id).unwrap())
            .unwrap();
        ledger
            .bind(reference(Table::String, key), string_id as u32)
            .unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn shift_assignments_match_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/shift_assign/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/shift_assign/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let compiled = compile_simple_proc_with_params(&item.children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn logical_chains_match_native_without_recursive_chain_lowering() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/logic_chain/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/logic_chain/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let compiled =
            compile_simple_proc_with_params(&item.children, &["a".into(), "b".into(), "c".into()])
                .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
    let clauses = (0..40)
        .map(|_| "(a && b && c)")
        .collect::<Vec<_>>()
        .join(" || ");
    std::thread::Builder::new()
        .stack_size(1024 * 1024)
        .spawn(move || {
            let large = dm_syntax::parse(&format!("/proc/large(a,b,c)\n    return {clauses}\n"));
            assert!(large.diagnostics.is_empty(), "{:?}", large.diagnostics);
            compile_simple_proc_with_params(
                &large.items[0].children,
                &["a".into(), "b".into(), "c".into()],
            )
            .unwrap();
        })
        .unwrap()
        .join()
        .unwrap();
}

#[test]
fn equivalence_operators_match_native_bytecode() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/equivalence/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/equivalence/probe.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let compiled =
            compile_simple_proc_with_params(&item.children, &["a".into(), "b".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(linked.words, native.proc_code_words(index).unwrap());
    }
}

#[test]
fn augmented_assignments_decode_without_stack_pop() {
    let ast = dm_syntax::parse("/proc/test()\n  var/x = 1\n  x += 2\n  x &= 3\n  return x\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::AUG_ADD));
    assert!(decoded
        .iter()
        .any(|instruction| instruction.opcode == opcode::AUG_BAND));
}
