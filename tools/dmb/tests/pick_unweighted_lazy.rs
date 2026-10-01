use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;

fn proc_id(dmb: &Dmb, name: &str) -> usize {
    let path = format!("/proc/{name}");
    dmb.procs
        .iter()
        .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
        .unwrap()
}

#[test]
fn multiargument_pick_evaluates_only_its_selected_native_candidate() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/pick_unweighted_lazy");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("probe.native.bin")).unwrap()).unwrap();
    for debug in [false, true] {
        let output = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixtures,
            Some("probe"),
            debug,
        )
        .unwrap();
        for name in [
            "pick_two",
            "pick_three",
            "pick_four",
            "pick_six",
            "pick_single",
            "pick_list",
            "pick_conditional",
            "pick_short_circuit",
            "pick_safe",
            "pick_nested",
            "pick_argument",
            "pick_loop",
            "pick_field",
            "pick_field_call",
            "pick_computed_field",
            "pick_many",
            "pick_formatted_ternary",
            "pick_formatted_nested",
        ] {
            let expected_id = proc_id(&native, name);
            let actual_id = proc_id(&output.dmb, name);
            let differences = compare_proc_code(
                &native,
                expected_id,
                &output.dmb,
                actual_id,
                name,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{name}, debug={debug}: {differences:?}"
            );
            let body = decode(output.dmb.proc_code_words(actual_id).unwrap()).unwrap();
            if matches!(name, "pick_single" | "pick_list") {
                assert_eq!(body.iter().filter(|item| item.opcode == 0xd2).count(), 1);
                assert!(body.iter().all(|item| item.opcode != 0x79));
            } else {
                assert!(body.iter().any(|item| item.opcode == 0x79));
                if !matches!(name, "pick_formatted_ternary" | "pick_formatted_nested") {
                    assert!(body.iter().all(|item| item.opcode != 0xd2));
                }
            }
            if name.starts_with("pick_many") {
                let table = body.iter().find(|item| item.opcode == 0x79).unwrap();
                assert_eq!(table.operands[0], 299);
                for index in 1..300 {
                    assert_eq!(table.operands[2 * index - 1], (65535 / 300) * index as u32);
                }
            }
            if name == "pick_four" {
                let table = body.iter().find(|item| item.opcode == 0x79).unwrap();
                assert_eq!(
                    [table.operands[1], table.operands[3], table.operands[5]],
                    [16383, 32766, 49149]
                );
            }
        }
    }
}
