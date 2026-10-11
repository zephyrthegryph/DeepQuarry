//! Control flow lowering regression tests.
use super::*;

#[test]
fn typed_obj_iterator_filters_subtypes_after_domain_mask() {
    let ast =
        dm_syntax::parse("/proc/test()\n    for(var/obj/firedoor/F in src)\n        return F\n");
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(reference(Table::Class, "/obj/firedoor"), 1)
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
        .bind(reference(Table::Class, "/datum/coil"), 0)
        .unwrap();
    let words = link_proc(&compiled.code, &ledger).unwrap().words;
    assert_eq!(words, [0x60, 32, 0, 0x33, 0xffd9, 0, 0x97, 0x12, 0]);
}

#[test]
fn strict_root_obj_iterator_matches_authenticated_native_and_ignores_field_spelling() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native/iterator_root_filter/probe.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native/iterator_root_filter/probe.native.bin"
    ))
    .unwrap();
    let class = native
        .classes
        .iter()
        .position(|class| native.string(class.path_string_id()) == Some(b"/obj".as_slice()))
        .unwrap();
    let proc_id = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/root_obj".as_slice()))
        .unwrap();
    for shadow in [false, true] {
        let mut bindings = LowerBindings {
            parameters: vec!["L".into()],
            ..Default::default()
        };
        if shadow {
            bindings.fields.insert("obj".into());
            bindings
                .field_types
                .insert("obj".into(), "/datum/shadow".into());
        }
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        assert_eq!(compiled.class_paths, [SymbolId::of("/obj")]);
        let mut ledger = Ledger::default();
        ledger
            .bind(reference(Table::Class, "/obj"), class as u32)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded.iter().any(|instruction| instruction.opcode == 0x7d));
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::ITER_LOAD
                && instruction.operands == [5, 2]));
    }
}
