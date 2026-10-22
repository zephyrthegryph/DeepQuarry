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
    // Pinned DreamMaker 516.1687 results (fixtures/diagnostics, `dmb-equiv dump-proc`): counts are taken modulo 32 and a negative
    // count is 0, fractions truncate, values saturate at 32 bits, and results are 24 bits wide.
    for (source, expected) in [
        ("1 << 32", 1.0),
        ("1 << -1", 1.0),
        ("1 >> 32", 1.0),
        ("1 >> -1", 1.0),
        ("1.#INF << 1", 16777214.0),
        ("2147483648 >> 1", 0.0),
        ("-2147483904 << 1", 0.0),
        ("5.5 >> 1", 2.0),
        ("1 << 1.5", 2.0),
    ] {
        assert_eq!(
            fold_number(&parse_expression(source).expr.unwrap()),
            Some(expected),
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

/// A `var/x` with no initializer stores null when it runs again: through a loop, and through a backward `goto` to a
/// label (DreamMaker emits the store for every declaration; native only where a second pass can happen).
#[test]
fn bare_declaration_resets_on_a_goto_loop() {
    let null_stores = |source: &str| {
        let ast = dm_syntax::parse(source);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        // `PushVal null; SetVar local`: a null value is tag 0.
        decoded
            .windows(2)
            .filter(|pair| {
                pair[0].opcode == opcode::PUSH_VAL
                    && pair[0].operands.first().is_some_and(|tag| tag & 0xff == 0)
                    && pair[1].opcode == opcode::SET_VAR
            })
            .count()
    };
    let straight = "/proc/test()
  var/x
  x = 1
  return x
";
    let goto_loop = "/proc/test()
  var/n = 0
  again:
  var/x
  x += 1
  n += 1
  if(n < 3)
    goto again
  return x
";
    assert_eq!(null_stores(straight), 0, "no second pass, no store");
    assert_eq!(null_stores(goto_loop), 1, "the bare declaration stores null again on the goto");
}

/// Constants measured on DreamMaker 516.1687 (a grid of 196 operand pairs per operator, compiled with `dm.exe` and read back
/// with `dmb-equiv dump-proc`; the unit-test world repeats the whole grid at runtime: `dq_compiler_behaviour`).
#[test]
fn constant_folds_match_dreammaker() {
    for (source, expected) in [
        ("1 | 2 | 4", Some(7.0)),
        ("1 | 2 | 8", Some(11.0)),
        ("7 & 3", Some(3.0)),
        ("5 ^ 1", Some(4.0)),
        ("16777215 & 255", Some(255.0)),
        ("255 | 16777216", Some(255.0)),
        ("-1 | 1", Some(16777215.0)),
        ("-2.5 & 255", Some(254.0)),
        ("-2.5 ^ -1", Some(1.0)),
        ("3.14159 ^ 255", Some(252.0)),
        ("~0", Some(16777215.0)),
        ("~255", Some(16776960.0)),
        ("~-1", Some(16777215.0)),
        ("~16777215", Some(0.0)),
        ("!0", Some(1.0)),
        ("!3", Some(0.0)),
        ("2 ** 3", Some(8.0)),
        ("2 ** 0.5", Some(1.4142135)),
        ("255 ** -2.5", Some(9.630515e-7)),
        ("2 ** 256", Some(f32::INFINITY)),
        ("0 && 5", Some(0.0)),
        ("5 && 6", Some(6.0)),
        ("0 || 7", Some(7.0)),
        ("-1 || 0", Some(-1.0)),
        ("1 ? 2 : 3", Some(2.0)),
        ("0 ? 2 : 3", Some(3.0)),
        ("0 && x", Some(0.0)),
        ("1 || x", Some(1.0)),
        ("1 ? 2 : x", Some(2.0)),
        ("(3 | 4) ? 16 : 32", Some(16.0)),
        // DreamMaker rejects these, or leaves them to the runtime.
        ("-1 ** 0.5", None),
        ("0 ** -1", None),
        ("3 == 3", None),
        ("3 < 4", None),
        ("1 && x", None),
        ("x ? 1 : 2", None),
    ] {
        assert_eq!(
            fold_number(&parse_expression(source).expr.unwrap()),
            expected,
            "{source}"
        );
    }
}

/// Builtin math on literal arguments, measured the same way (`f1_*`, `f2_*`, `f3_*` in the grid): `round(x)` floors, angles are
/// degrees, `min` and `max` are left to the runtime, a reversed `clamp` range is swapped, and a domain error is not a number.
#[test]
fn builtin_math_folds_match_dreammaker() {
    for (source, expected) in [
        ("round(303.975)", Some(303.0)),
        ("round(-2.5)", Some(-3.0)),
        ("floor(-2.5)", Some(-3.0)),
        ("ceil(-2.5)", Some(-2.0)),
        ("abs(-2.5)", Some(2.5)),
        ("sqrt(3)", Some(1.7320508)),
        ("sqrt(3) + 1", Some(2.7320508)),
        ("sin(1)", Some(0.017452406)),
        ("cos(0)", Some(1.0)),
        ("arcsin(1)", Some(90.0)),
        ("arccos(-1)", Some(180.0)),
        ("arctan(1)", Some(45.0)),
        ("arctan(-1, 1)", Some(135.0)),
        ("log(2)", Some(0.6931472)),
        ("log(2, 256)", Some(8.0)),
        ("round(3.14159, 2)", Some(4.0)),
        ("round(-2.5, 3)", Some(-3.0)),
        ("round(16777215, 1)", Some(16777216.0)),
        ("clamp(0, 2, -2.5)", Some(0.0)),
        ("clamp(5, 0, 3)", Some(3.0)),
        ("clamp(-5, 0, 3)", Some(0.0)),
        ("min(1, 2)", None),
        ("max(1, 2)", None),
        ("sqrt(-1)", None),
        ("arcsin(2)", None),
        ("log(0)", None),
        ("log(1, 5)", None),
        ("round(x)", None),
    ] {
        assert_eq!(
            fold_number(&parse_expression(source).expr.unwrap()),
            expected,
            "{source}"
        );
    }
}

#[test]
fn diagnostic_numbers_print_like_printf_g() {
    use crate::simple::calls_intrinsics::format_g;
    for (value, expected) in [
        (0.0, "0"),
        (2.0, "2"),
        (-2.5, "-2.5"),
        (0.5, "0.5"),
        (65535.0, "65535"),
        (16777216.0, "1.67772e+07"),
        (-2147483648.0, "-2.14748e+09"),
        (3.14159, "3.14159"),
        (0.0001, "0.0001"),
        (0.00001, "1e-05"),
    ] {
        assert_eq!(format_g(value), expected, "{value}");
    }
}

/// An authored `null` is read through the Null variable reader (`GetVar 65510`, two words) and an omitted argument pushes a null value
/// (`PushVal null`, three words). The words are DreamMaker 516.1687's for the same source. The two-word form is what lets a large static
/// table of nested lists fit the 65,535-word limit of the global initializer exactly as it does under DreamMaker.
#[test]
fn authored_null_is_a_variable_read_and_an_omitted_argument_is_a_pushed_null() {
    let ast = dm_syntax::parse(
        "/proc/hole(a, b, c)\n\treturn b\n/proc/null_literals()\n\treturn list(list(1), null, 2, null)\n/proc/null_hole()\n\treturn hole(1,,null)\n",
    );
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let mut bindings = LowerBindings::default();
    bindings
        .global_procs
        .insert("hole".into(), reference(Table::Proc, "/proc/hole"));
    let mut ledger = Ledger::default();
    ledger.bind(reference(Table::Proc, "/proc/hole"), 0).unwrap();
    for (item, expected) in [
        (
            1,
            vec![80, 1, 26, 1, 51, 65510, 80, 2, 51, 65510, 26, 4, 18, 0],
        ),
        (2, vec![80, 1, 96, 0, 0, 51, 65510, 48, 3, 0, 18, 0]),
    ] {
        let compiled =
            compile_fixture_proc_with_bindings(&ast.items[item].children, &bindings).unwrap();
        assert_eq!(
            link_proc(&compiled.code, &ledger).unwrap().words,
            expected.as_slice(),
            "item {}",
            item
        );
    }
}

#[test]
fn string_literals_drop_carriage_returns_like_dreammaker() {
    // dm.exe 516.1681: a multi-line `{"..."}` in a CRLF file holds `\n`, and a lone CR is dropped.
    for (raw, expected) in [
        ("{\"AAA\r\nBBB\r\nCCC\"}", "AAA\nBBB\nCCC"),
        ("{\"XQ\rYQ\rZQ\"}", "XQYQZQ"),
        ("\"LQ\rMQ\"", "LQMQ"),
        ("@{\"XQ\r\nYQ\rZQ\"}", "XQ\nYQZQ"),
        ("@\"LQ\rMQ\"", "LQMQ"),
    ] {
        assert_eq!(
            decode_constant_string_literal(raw).unwrap().unwrap(),
            expected.as_bytes(),
            "{raw:?}"
        );
    }
}
