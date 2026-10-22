//! Instruction shapes that DreamMaker 516.1687 (`dm.exe`) compiles and native must match, one test per rule. Each source was
//! compiled with `dm.exe` and the procedure read back with `dmb-equiv dump-proc`; `tools/ci/dm_equiv.sh` compares the whole
//! tree the same way.
use super::*;

/// The mnemonics of a procedure body compiled from `source` with arguments `a`, `b` and `c`.
fn shape(source: &str) -> Vec<String> {
    let ast = dm_syntax::parse(source);
    let params: Vec<String> = ["a", "b", "c"].iter().map(|p| p.to_string()).collect();
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &params).unwrap();
    let mut ledger = Ledger::default();
    for (index, text) in string_texts(&compiled).iter().enumerate() {
        ledger.bind(reference(Table::String, text.as_str()), 100 + index as u32).unwrap();
    }
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    byond_dmb::bytecode::decode(&linked.words)
        .unwrap()
        .iter()
        // `PushInt n` is `PushVal n` for a small whole number (FORMAT.md).
        .map(|instruction| if instruction.name == "PushInt" { "PushVal" } else { instruction.name }.to_string())
        .collect()
}

fn proc_returning(expression: &str) -> String {
    format!("/proc/test(a, b, c)\n  return {expression}\n")
}

fn assigning(expression: &str) -> String {
    format!("/proc/test(a, b, c)\n  a = {expression}\n  return a\n")
}

#[test]
fn square_replaces_a_product_of_the_same_plain_value() {
    assert_eq!(shape(&proc_returning("a*a")), ["GetVar", "Square", "Ret", "End"]);
    assert_eq!(shape(&proc_returning("a**2")), ["GetVar", "Square", "Ret", "End"]);
    // The left operand of another product stays a plain product; an index or a call is not a plain value.
    assert_eq!(shape(&proc_returning("a*a*b")), ["GetVar", "GetVar", "Mul", "GetVar", "Mul", "Ret", "End"]);
    assert_eq!(shape(&proc_returning("a[1]*a[1]")).iter().filter(|op| *op == "Square").count(), 0);
}

#[test]
fn text_chains_with_a_parenthesised_sum_move_right_except_at_the_root_of_an_assignment() {
    // `"P" + (a + b) + "."`: after `return` the tail moves into the right operand, `P (a b Add) "." Add Add`.
    assert_eq!(
        shape(&proc_returning("\"P\" + (a + b) + \".\"")),
        ["PushVal", "GetVar", "GetVar", "Add", "PushVal", "Add", "Add", "Ret", "End"]
    );
    // As the whole value of an assignment the chain is left as written: `P (a b Add) Add "." Add`.
    assert_eq!(
        shape(&assigning("\"P\" + (a + b) + \".\"")),
        ["PushVal", "GetVar", "GetVar", "Add", "Add", "PushVal", "Add", "SetVar", "GetVar", "Ret", "End"]
    );
    // A subtraction in the middle is not an `+` chain.
    assert_eq!(
        shape(&proc_returning("a - (b - c) - 1")),
        ["GetVar", "GetVar", "GetVar", "Sub", "Sub", "PushVal", "Sub", "Ret", "End"]
    );
}

#[test]
fn constants_decide_short_circuit_chains() {
    // `a && 1 && b` is `a && b`; `a && 0 && b` ends at the 0; `a || null || b` is `a || b`.
    assert_eq!(shape(&proc_returning("a && 1 && b")), ["GetVar", "JmpAnd", "GetVar", "Ret", "End"]);
    assert_eq!(shape(&proc_returning("a && 0 && b")), ["GetVar", "JmpAnd", "PushVal", "Ret", "End"]);
    assert_eq!(shape(&proc_returning("a || null || b")), ["GetVar", "JmpOr", "GetVar", "Ret", "End"]);
    // A constant text decides a ternary and `!`.
    assert_eq!(shape(&proc_returning("\"x\" ? a : b")), ["GetVar", "Ret", "End"]);
    assert_eq!(shape(&proc_returning("!\"x\"")), ["PushVal", "Ret", "End"]);
}

#[test]
fn rgb_of_constants_is_text() {
    assert_eq!(shape(&proc_returning("rgb(80,80,80,230)")), ["PushVal", "Ret", "End"]);
    assert_eq!(shape(&proc_returning("rgb(a,80,80,230)")).last().map(String::as_str), Some("End"));
    assert!(shape(&proc_returning("rgb(a,80,80,230)")).contains(&"Rgba".to_string()));
    // rgb2num of constant color text is the list of components.
    assert_eq!(
        shape(&proc_returning("rgb2num(\"#30e028\")")),
        ["PushVal", "PushVal", "PushVal", "NewList", "Ret", "End"]
    );
}

#[test]
fn two_argument_image_has_its_own_opcode() {
    assert_eq!(shape(&proc_returning("image(a, b)")), ["GetVar", "GetVar", "NewImage", "Ret", "End"]);
    assert_eq!(shape(&proc_returning("image(a)")), ["GetVar", "NewImageArgs", "Ret", "End"]);
}

#[test]
fn pick_thresholds_add_the_whole_number_share_of_each_choice() {
    let ast = dm_syntax::parse("/proc/test()\n  return pick(1, 2, 3, 4)\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &[]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let pick = decoded.iter().find(|ins| ins.opcode == 0x79).expect("PickSwitch");
    let thresholds: Vec<u32> = match pick.typed_operands().unwrap().first() {
        Some(byond_dmb::bytecode::Operand::PickSwitch { cases, .. }) => cases.iter().map(|(w, _)| *w).collect(),
        other => panic!("{other:?}"),
    };
    assert_eq!(thresholds, [16383, 32766, 49149]);
}

#[test]
fn switch_tables_list_a_cases_alternatives_last_to_first_and_ranges_before_values() {
    let ast = dm_syntax::parse(
        "/proc/test(a)\n  switch(a)\n    if(1, 2, 3)\n      return 1\n    if(10 to 20, 30 to 40)\n      return 2\n    if(7)\n      return 3\n",
    );
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["a".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let switch = decoded.iter().find(|ins| ins.opcode == 0x7a).expect("SwitchRange");
    match switch.typed_operands().unwrap().first() {
        Some(byond_dmb::bytecode::Operand::RangeSwitch { ranges, exact, .. }) => {
            let number = |v: &byond_dmb::operands::Value| f32::from_bits(v.number_bits().unwrap());
            assert_eq!(ranges.iter().map(|(low, _, _)| number(low)).collect::<Vec<_>>(), [30.0, 10.0]);
            assert_eq!(exact.iter().map(|(v, _)| number(v)).collect::<Vec<_>>(), [3.0, 2.0, 1.0, 7.0]);
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn self_call_without_arguments_has_its_own_opcode() {
    assert_eq!(shape("/proc/test(a)\n  return .()\n"), ["CallSelf", "Ret", "End"]);
}

#[test]
fn range_loops_fuse_the_producer_into_the_iterator() {
    let ops = shape("/proc/test(a)\n  for(var/x in range(a, a))\n    a++\n  return a\n");
    assert!(ops.contains(&"IterLoad".to_string()) && !ops.contains(&"Range".to_string()), "{ops:?}");
}

#[test]
fn a_name_statement_emits_nothing() {
    assert_eq!(shape("/proc/test(a)\n  a\n  return 1\n"), ["PushVal", "Ret", "End"]);
}

#[test]
fn bit_operators_bind_looser_than_comparison_and_in_binds_loosest() {
    let parse = |source: &str| dm_syntax::parse_expression(source).expr.unwrap();
    // `a == b | c` is `(a == b) | c`; `a << b < c` is `a << (b < c)`.
    assert!(matches!(&parse("a == b | c").kind, dm_syntax::ExprKind::Binary { op, .. } if op == "|"));
    assert!(matches!(&parse("a << b < c").kind, dm_syntax::ExprKind::Binary { op, .. } if op == "<<"));
    // `a in b ? c : d` is `a in (b ? c : d)` and `a || b in c` is `(a || b) in c`.
    assert!(matches!(&parse("a in b ? c : d").kind, dm_syntax::ExprKind::Binary { op, rhs, .. }
        if op == "in" && matches!(rhs.kind, dm_syntax::ExprKind::Conditional { .. })));
    assert!(matches!(&parse("a || b in c").kind, dm_syntax::ExprKind::Binary { op, .. } if op == "in"));
    // `<>` is `!=`.
    assert!(matches!(&parse("a <> b").kind, dm_syntax::ExprKind::Binary { op, .. } if op == "!="));
}
