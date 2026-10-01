use byond_dmb::{
    compare::{compare_dmbs, compare_proc_code, CompareOptions},
    dmb::Dmb,
    opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn literal_unicode_does_not_collide_with_internal_format_controls() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/literal_format_unicode");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("probe.native.bin")).unwrap()).unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    assert!(input.strings.iter().any(|s| s == "\u{ff5e}\u{ff21}"));

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
                authored_prefixes: vec![
                    "/datum/literal_format_unicode".to_owned(),
                    "/proc".to_owned(),
                ],
                compare_bytecode: false,
                max_discrepancies: 100,
            },
        );
        assert!(differences.is_empty(), "debug={debug}: {differences:#?}");
        let mut comparisons = 0;
        for name in [
            "literal_return",
            "literal_raw",
            "literal_unicode",
            "literal_length",
            "literal_copytext",
            "literal_md5",
            "literal_json",
            "literal_interpolation",
            "literal_equal",
            "literal_initial_hash",
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
        assert_eq!(comparisons, 10);
        if debug {
            assert!(
                output
                    .dmb
                    .strings
                    .iter()
                    .any(|s| s.data.ends_with("probeＡ２.dm".as_bytes())),
                "debug source filename must stay literal UTF-8"
            );
        }
        for dmb in [&native, &output.dmb] {
            assert!(dmb
                .strings
                .iter()
                .any(|s| s.data.as_slice() == [0xff, 0x12]));
            assert!(dmb
                .strings
                .iter()
                .any(|s| s.data.as_slice() == "Ａ２～".as_bytes()));
        }
    }
}
