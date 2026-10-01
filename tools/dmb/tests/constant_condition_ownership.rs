use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn constant_conditions_preserve_retained_eval() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/constant_condition_ownership");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/constant_condition_ownership/probe.native.bin"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        for dmb in [&native, &output.dmb] {
            assert_eq!(
                dmb.lists[dmb.variable_footer as usize]
                    .chunks_exact(2)
                    .filter(|pair| pair[1] == 3
                        && dmb.string(dmb.variables[pair[0] as usize].name)
                            == Some(b"DEAD".as_slice()))
                    .count(),
                1
            );
        }
        for name in [
            "if_null",
            "if_true",
            "if_false",
            "while_null",
            "while_true",
            "while_false",
            "runtime_condition",
            "nested_constant_scope",
            "constant_else_if",
            "constant_text",
            "constant_empty_text",
            "constant_type",
            "dead_const",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let differences = compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{path} debug={debug}: {differences:#?}"
            );
        }
    }
}
