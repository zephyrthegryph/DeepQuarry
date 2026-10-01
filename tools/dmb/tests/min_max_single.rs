use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn single_min_max_preserve_native_list_reduction() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/min_max_single");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("min_max_single.native.bin")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("min_max_single.json")).unwrap();
    for debug in [false, true] {
        let output = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixtures,
            Some("min_max_single"),
            debug,
        )
        .unwrap();
        for operation in ["min", "max"] {
            for shape in [
                "single",
                "list",
                "scalar",
                "null",
                "text",
                "empty",
                "effectful",
                "pair",
            ] {
                let path = format!("/proc/{operation}_{shape}");
                let find = |dmb: &Dmb| {
                    dmb.procs
                        .iter()
                        .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                        .unwrap()
                };
                let opcode = match (operation, shape) {
                    ("min", "pair") => 0xa5,
                    ("max", "pair") => 0xa6,
                    ("min", _) => 0xd0,
                    _ => 0xd1,
                };
                for dmb in [&native, &output.dmb] {
                    let body = decode(dmb.proc_code_words(find(dmb)).unwrap()).unwrap();
                    let instruction = body
                        .iter()
                        .find(|i| i.opcode == opcode)
                        .unwrap_or_else(|| panic!("debug={debug} {path} missing{opcode:x}"));
                    assert_eq!(
                        instruction.operands,
                        if shape == "pair" { vec![2] } else { vec![] },
                        "{path}"
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
}
