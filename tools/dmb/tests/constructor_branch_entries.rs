use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn constructor_branches_enter_before_inserted_type_receiver() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/constructor_branch_entries");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/file_entry",
        "/proc/file_arglist",
        "/proc/sound_entry",
        "/proc/sound_named",
        "/proc/icon_entry",
        "/proc/icon_named",
        "/proc/type_entry",
        "/proc/file_conditional",
        "/proc/file_short",
        "/proc/type_conditional",
        "/proc/sound_conditional",
        "/proc/icon_conditional",
        "/proc/generator_entry",
        "/proc/sound_named_conditional",
        "/proc/icon_named_conditional",
        "/proc/generator_conditional",
        "/proc/type_named_conditional",
        "/proc/dynamic_entry",
        "/proc/dynamic_conditional",
    ];
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        for path in paths {
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
