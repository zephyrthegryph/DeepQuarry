use byond_dmb::{
    bytecode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;

#[test]
fn only_proven_root_iterator_masks_replace_budgeted_subtype_tests() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("fixtures/translation/iterator_root_budget");
    let input = OpenDreamProgram::from_path(fixture.join("probe.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixture.join("probe.native.bin")).unwrap()).unwrap();
    let cases = [
        ("root_area", false),
        ("root_mob", false),
        ("root_turf", false),
        ("root_obj", true),
        ("root_movable", true),
        ("root_atom", true),
        ("subtype_area", true),
        ("subtype_obj", true),
        ("subtype_mob", true),
        ("subtype_datum", true),
        ("anything_area", false),
        ("orange_mob", false),
        ("orange_turf", false),
        ("orange_area", false),
        ("orange_untyped", false),
        ("orange_anything", false),
        ("orange_subtype", true),
        ("orange_choice", false),
        ("orange_one", false),
        ("orange_default", false),
        ("orange_list", false),
    ];
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for (name, requires_test) in cases {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc_| dmb.string(proc_.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let native_id = find(&native);
            let actual_id = find(&actual.dmb);
            for (dmb, id) in [(&native, native_id), (&actual.dmb, actual_id)] {
                let code = bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
                assert_eq!(
                    code.iter().any(|i| i.opcode == 0xfa),
                    requires_test,
                    "{path}"
                );
            }
            let differences =
                compare_proc_code(&native, native_id, &actual.dmb, actual_id, &path, 100, true);
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
        }
    }
}
