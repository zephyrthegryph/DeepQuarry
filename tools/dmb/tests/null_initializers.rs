use byond_dmb::bytecode::decode;
use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn synthetic_null_initializers_preserve_retained_call_values() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/null_initializers");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/loop_default",
        "/proc/typed_loop_default",
        "/proc/local_default",
        "/proc/local_authored",
        "/proc/for_default",
        "/proc/for_authored",
    ];
    for path in [
        "/proc/loop_default",
        "/proc/typed_loop_default",
        "/proc/for_default",
    ] {
        let id = native
            .procs
            .iter()
            .position(|p| native.string(p.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let body = decode(native.proc_code_words(id).unwrap()).unwrap();
        assert!(
            body.iter()
                .any(|i| i.opcode == 0x60 && i.operands == [0, 0]),
            "synthetic null witness missing: {path}"
        );
        assert!(
            !body
                .iter()
                .any(|i| i.opcode == 0x33 && i.operands == [0xffe6]),
            "synthetic initializer must not release retained eval: {path}"
        );
    }
    let authored = native
        .procs
        .iter()
        .position(|p| native.string(p.strings[0]) == Some(b"/proc/local_authored".as_slice()))
        .unwrap();
    assert!(
        decode(native.proc_code_words(authored).unwrap())
            .unwrap()
            .iter()
            .any(|i| i.opcode == 0x33 && i.operands == [0xffe6]),
        "authored null witness missing"
    );
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        for path in [
            "/proc/for_default",
            "/proc/for_authored",
            "/proc/local_default",
        ] {
            let id = output
                .dmb
                .procs
                .iter()
                .position(|p| output.dmb.string(p.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let body = decode(output.dmb.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                .collect::<Vec<_>>();
            if path == "/proc/for_authored" {
                assert!(body
                    .iter()
                    .any(|i| i.opcode == 0x33 && i.operands == [0xffe6]));
                assert_eq!(body[2].opcode, 0x60);
                assert_eq!(body[2].operands, [0, 0]);
            } else {
                assert_eq!(body[2].opcode, 0x60);
                assert_eq!(body[2].operands, [0, 0]);
            }
        }
        for path in paths.into_iter().filter(|path| {
            !matches!(
                *path,
                "/proc/local_default" | "/proc/for_default" | "/proc/for_authored"
            )
        }) {
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
                path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{path}, debug={debug}: {differences:#?}"
            );
        }
    }
}
