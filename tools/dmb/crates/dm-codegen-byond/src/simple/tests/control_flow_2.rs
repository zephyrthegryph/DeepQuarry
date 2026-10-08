//! Control flow lowering regression tests.
use super::*;

#[test]
fn typed_obj_iterator_filters_subtypes_after_domain_mask() {
    let ast =
        dm_syntax::parse("/proc/test()\n    for(var/obj/firedoor/F in src)\n        return F\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Class, "/obj/firedoor"), 1)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let instructions = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(instructions
        .iter()
        .any(|instruction| instruction.opcode == 0x7d));
    assert!(instructions.iter().any(
        |instruction| instruction.opcode == opcode::ITER_LOAD && instruction.operands == [5, 2]
    ));
}
#[test]
fn locate_in_returns_object_instead_of_membership_boolean() {
    let ast = dm_syntax::parse("/proc/test(L)\n    return locate(/datum/coil) in L\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Class, "/datum/coil"), 0)
        .unwrap();
    let words = link_proc(&compiled.code, &ledger).unwrap().words;
    assert_eq!(words, [0x60, 32, 0, 0x33, 0xffd9, 0, 0x97, 0x12, 0]);
}
