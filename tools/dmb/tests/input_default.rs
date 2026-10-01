use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn omitted_input_type_retains_native_default_mask() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/input_default");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("input_default.native.bin")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("input_default.json")).unwrap();
    for debug in [false, true] {
        let output = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixtures,
            Some("input_default"),
            debug,
        )
        .unwrap();
        for (name, mask, choices) in [
            ("implicit_prompt", 0, 0),
            ("text_prompt", 4, 0),
            ("implicit_choice", 0, 64),
            ("anything_choice", 4096, 64),
            ("implicit_short", 0, 0),
            ("text_short", 4, 0),
            ("implicit_null_choice", 0, 64),
            ("text_null_choice", 4, 64),
            ("text_choice", 4, 64),
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let config = |dmb: &Dmb| {
                decode(dmb.proc_code_words(find(dmb)).unwrap())
                    .unwrap()
                    .into_iter()
                    .find(|i| i.opcode == 0xc1)
                    .unwrap()
                    .operands
            };
            assert_eq!(config(&native), vec![mask, 0, choices], "native {name}");
            assert_eq!(
                config(&output.dmb),
                vec![mask, 0, choices],
                "debug={debug} {name}"
            );
            let differences = compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                30,
                true,
            );
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
