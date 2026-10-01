use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn runtime_trigonometric_handlers_match_native_516() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/runtime_trig");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("runtime_trig.native.bin")).unwrap()).unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("runtime_trig.json")).unwrap();
    for debug in [false, true] {
        let output = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixtures,
            Some("runtime_trig"),
            debug,
        )
        .unwrap();
        for (name, opcode) in [
            ("sin", 0x182),
            ("cos", 0x183),
            ("tan", 0x184),
            ("arcsin", 0xc4),
            ("arccos", 0xc5),
            ("arctan", 0x145),
            ("arctan2", 0x146),
            ("trig_arguments", 0x182),
        ] {
            let path = format!("/proc/runtime_{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            for dmb in [&native, &output.dmb] {
                let body = decode(dmb.proc_code_words(find(dmb)).unwrap()).unwrap();
                assert!(
                    body.iter().any(|i| i.opcode == opcode),
                    "debug={debug} {path}"
                );
                assert!(
                    !body.iter().any(|i| matches!(i.opcode, 0xc2 | 0xc3)),
                    "obsolete trig {path}"
                );
            }
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
