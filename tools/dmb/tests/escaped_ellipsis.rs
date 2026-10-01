use byond_dmb::{
    compare::{compare_dmbs, compare_proc_code, CompareOptions},
    dmb::Dmb,
    opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn escaped_ellipsis_retains_native_control_bytes_in_values_and_operations() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/escaped_ellipsis");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("probe.native.bin")).unwrap()).unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    assert!(input.strings.iter().any(|s| s == "\u{ff21}"));
    assert!(input.strings.iter().any(|s| s == "..."));
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
        let differences = compare_dmbs(
            &native,
            &output.dmb,
            &CompareOptions {
                authored_prefixes: vec!["/datum/ellipsis_proof".to_owned(), "/proc".to_owned()],
                compare_bytecode: false,
                max_discrepancies: 100,
            },
        );
        assert!(differences.is_empty(), "debug={debug}: {differences:#?}");
        let mut comparisons = 0;
        for name in [
            "escaped_return",
            "plain_return",
            "encoded",
            "compare",
            "count",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
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
                "debug={debug} {path}: {differences:#?}"
            );
            comparisons += 1;
        }
        assert_eq!(comparisons, 5);
        for dmb in [&native, &output.dmb] {
            assert!(dmb
                .strings
                .iter()
                .any(|s| s.data.as_slice() == [0xff, 0x12]));
            assert!(dmb.strings.iter().any(|s| s.data.as_slice() == b"..."));
        }
    }
}
