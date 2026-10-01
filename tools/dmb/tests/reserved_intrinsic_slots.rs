use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn ordinary_fields_and_world_output_match_native_intrinsic_boundaries() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("fixtures/translation/reserved_intrinsic_slots");
    let input = OpenDreamProgram::from_path(fixture.join("probe.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixture.join("probe.native.bin")).unwrap()).unwrap();
    let find = |dmb: &Dmb, path: &str| {
        dmb.procs
            .iter()
            .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
            .unwrap()
    };
    let output = decode(
        native
            .proc_code_words(find(&native, "/proc/world_output_fields"))
            .unwrap(),
    )
    .unwrap();
    assert_eq!(output[0].operands, [0xffdc, 0xffe5, 78]);
    assert_eq!(output[1].operands, [54]);
    assert_eq!(output[2].operands, [55]);
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for path in [
            "/datum/holder/proc/build_software_lists",
            "/proc/world_output_fields",
        ] {
            let diff = compare_proc_code(
                &native,
                find(&native, path),
                &actual.dmb,
                find(&actual.dmb, path),
                path,
                100,
                true,
            );
            assert!(diff.is_empty(), "debug={debug} {path}: {diff:#?}");
        }
    }
}
