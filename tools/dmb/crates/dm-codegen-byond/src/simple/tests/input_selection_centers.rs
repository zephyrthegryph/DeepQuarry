//! Separate native controls for centered selection and lexical builtin shadows.
use super::*;
#[test]
fn input_center_and_lexical_shadow_forms_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/input_selection_centers/input_selection_centers.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../../fixtures/translation/input_selection_centers/input_selection_centers.native.bin")).unwrap();
    for (index, name, parameters) in [
        (0, "center_radius", vec![]),
        (1, "center_first", vec![]),
        (2, "center_dynamic", vec!["n"]),
        (3, "center_oview", vec![]),
        (4, "shadow_center", vec!["usr"]),
        (5, "shadow_first", vec!["usr"]),
        (6, "shadow_world", vec!["world", "usr"]),
        (7, "shadow_usr", vec!["world", "usr"]),
    ] {
        let parameters = parameters
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>();
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
        let path = format!("/proc/{name}");
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
            "{name}"
        );
        assert_eq!(
            ours[..actual_input]
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            expected[..expected_input]
                .iter()
                .map(|instruction| instruction.opcode)
                .collect::<Vec<_>>(),
            "{name}"
        );
        if index >= 4 {
            assert_eq!(
                ours[actual_input].operands,
                [2, if index < 6 { 5 } else { 0 }, 64],
                "{name}"
            );
            // The shadow must stay an evaluated argument, not builtin world/usr.
            assert!(
                ours[..actual_input]
                    .iter()
                    .any(|instruction| instruction.opcode == 0x33
                        && instruction.operands.first() == Some(&65497)),
                "{name}"
            );
        }
    }
}
