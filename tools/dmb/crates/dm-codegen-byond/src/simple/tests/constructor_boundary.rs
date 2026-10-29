//! Primary AST boundaries must reach generic member/index lowering unchanged.
use super::*;

fn lower_expression(expression: &str) -> SimpleProc {
    let source = format!("/proc/probe()\n    return {expression}\n");
    let syntax = dm_syntax::parse(&source);
    assert!(syntax.diagnostics.is_empty());
    compile_simple_proc(&syntax.items[0].children).unwrap()
}

#[test]
fn explicit_and_grouped_constructed_receiver_have_same_member_call_code() {
    let plain = lower_expression("new /datum/base(7).read(3)");
    let grouped = lower_expression("(new /datum/base(7)).read(3)");
    assert_eq!(plain.code, grouped.code);
    let instructions: Vec<_> = plain
        .code
        .items
        .iter()
        .filter_map(|item| match item {
            crate::Item::Instruction(instruction) => Some(instruction),
            _ => None,
        })
        .collect();
    let allocation = instructions
        .iter()
        .position(|i| i.opcode == opcode::NEW)
        .unwrap();
    let method = instructions
        .iter()
        .position(|i| i.opcode == opcode::CALL)
        .unwrap();
    assert!(allocation < method);
    assert_eq!(
        instructions
            .iter()
            .filter(|i| i.opcode == opcode::NEW)
            .count(),
        1
    );
}

#[test]
fn constructed_list_is_indexed_after_allocation() {
    let plain = lower_expression("new /list(2)[1]");
    let grouped = lower_expression("(new /list(2))[1]");
    assert_eq!(plain.code, grouped.code);
    assert_eq!(
        plain
            .code
            .items
            .iter()
            .filter(|item| matches!(item,crate::Item::Instruction(i) if i.opcode==opcode::NEW))
            .count(),
        1
    );
}
