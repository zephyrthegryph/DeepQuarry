//! Direct producer comparisons with the committed native deletion capture.
use super::*;

fn executable(words: &[u32]) -> Vec<(u32, Vec<u32>)> {
    let mut result = Vec::new();
    for instruction in byond_dmb::bytecode::decode(words).unwrap() {
        if matches!(instruction.opcode, 0x84 | 0x85) {
            continue;
        }
        result.push((instruction.opcode, instruction.operands));
        // del(src) terminates its procedure; compare all executable instructions,
        // including End, without comparing unreachable compiler terminal padding.
        if instruction.opcode == opcode::END {
            break;
        }
    }
    result
}

#[test]
fn mutable_local_argument_and_temporary_deletion_match_native() {
    let source = include_str!("../../../../../fixtures/translation/delete_lvalue/delete_lvalue.dm");
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/delete_lvalue/delete_lvalue.native.bin"
    ))
    .unwrap();
    let ast = dm_syntax::parse(source);
    for (path, parameters) in [
        ("/proc/delete_local", vec![]),
        ("/proc/delete_argument", vec!["value".into()]),
        ("/proc/delete_text_storage", vec![]),
        ("/proc/delete_temporary", vec![]),
        ("/datum/holder/proc/delete_src", vec![]),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.split('(').next() == Some(path))
            .unwrap();
        let compiled = compile_simple_proc_with_params(&item.children, &parameters).unwrap();
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.bytes.as_ref())
                .unwrap();
            ledger.bind(SymRef::String(string.id), id as u32).unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            executable(&linked.words),
            executable(native.proc_code_words(id).unwrap()),
            "{path}"
        );
    }
}

#[test]
fn lexical_src_parameter_is_cleared_and_does_not_terminate_body() {
    let ast = dm_syntax::parse("/proc/delete_shadow(src)\n    del(src)\n    return src\n");
    let compiled =
        compile_simple_proc_with_params(&ast.items[0].children, &["src".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let instructions = executable(&linked.words);
    let deletion = instructions
        .iter()
        .position(|(opcode, _)| *opcode == 0x0c)
        .unwrap();
    assert_eq!(instructions[deletion - 2], (opcode::PUSH_VAL, vec![0, 0]));
    assert_eq!(
        instructions[deletion - 1],
        (opcode::SET_VAR, vec![0xffd9, 0])
    );
    assert_eq!(
        instructions[deletion + 1],
        (opcode::GET_VAR, vec![0xffd9, 0])
    );
    assert_eq!(instructions[deletion + 2].0, opcode::RET);
}
