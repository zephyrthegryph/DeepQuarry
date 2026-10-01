use byond_dmb::{
    bytecode::decode, dmb::Dmb, opendream::OpenDreamProgram, translate::translate_named_debug,
};
use std::path::Path;

fn budget_branches(dmb: &Dmb, name: &str) -> Vec<(u32, bool, u32)> {
    let path = format!("/proc/{name}");
    let id = dmb
        .procs
        .iter()
        .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
        .unwrap();
    let instructions = decode(dmb.proc_code_words(id).unwrap()).unwrap();
    instructions
        .iter()
        .filter(|item| matches!(item.opcode, 0xf8 | 0x12f))
        .map(|item| {
            let target = item.operands[0] as usize;
            let next = instructions
                .iter()
                .find(|next| next.offset >= target && !matches!(next.opcode, 0x84 | 0x85))
                .unwrap();
            (item.opcode, target <= item.offset, next.opcode)
        })
        .collect()
}

#[test]
fn synthetic_loop_joins_do_not_gain_authored_continue_budget_checks() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/continue_budget");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("probe.native.bin")).unwrap()).unwrap();
    for (name, count, opcode) in [
        ("while_join", 1, 0xf8),
        ("while_tail_join", 1, 0xf8),
        ("for_continue", 2, 0xf8),
        ("while_continue", 2, 0xf8),
    ] {
        let expected = budget_branches(&native, name);
        assert_eq!(expected.len(), count, "native {name}");
        assert!(
            expected.iter().all(|branch| branch.0 == opcode),
            "native {name}"
        );
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
            assert_eq!(
                budget_branches(&output.dmb, name),
                expected,
                "{name}, debug={debug}"
            );
        }
    }
}
