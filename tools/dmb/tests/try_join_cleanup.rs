use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;

#[test]
fn protected_body_joins_enter_native_cleanup_without_exit_branches() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/try_join_cleanup");
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
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
            "join_if_else",
            "join_nested_if",
            "join_nested_try",
            "join_ternary",
            "join_goto_out",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let exits = |dmb: &Dmb| {
                decode(dmb.proc_code_words(find(dmb)).unwrap())
                    .unwrap()
                    .into_iter()
                    .filter(|i| matches!(i.opcode, 0x12c..=0x12f))
                    .map(|i| i.opcode)
                    .collect::<Vec<_>>()
            };
            assert_eq!(exits(&output.dmb), exits(&native), "debug={debug} {path}");
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
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
