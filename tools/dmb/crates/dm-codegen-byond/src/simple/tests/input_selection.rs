//! Golden Input selection forms from the pinned compile-only native fixture.
use super::*;
#[test]
fn input_selection_forms_match_native_operands_and_stack_shape() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/input_selection/input_selection.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/input_selection/input_selection.native.bin"
    ))
    .unwrap();
    for (index, path) in [
        (1, "/proc/world_prompt"),
        (2, "/proc/usr_prompt"),
        (3, "/proc/view_prompt"),
        (4, "/proc/oview_prompt"),
        (5, "/proc/view_zero"),
        (6, "/proc/view_default"),
        (7, "/proc/view_dynamic"),
        (8, "/proc/contents_prompt"),
    ] {
        let parameters = if index == 7 {
            vec!["n".to_owned()]
        } else {
            vec![]
        };
        let compiled =
            compile_simple_proc_with_params(&ast.items[index].children, &parameters).unwrap();
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
        let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        let actual_input = ours
            .iter()
            .position(|instruction| instruction.opcode == 0xc1)
            .unwrap();
        let expected_input = expected
            .iter()
            .position(|instruction| instruction.opcode == 0xc1)
            .unwrap();
        assert_eq!(
            ours[actual_input].operands, expected[expected_input].operands,
            "{path}"
        );
        // A specialized choice must not leave an evaluated list on the argument stack.
        assert_eq!(
            ours[..actual_input]
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            expected[..expected_input]
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            "{path}"
        );
    }
}
