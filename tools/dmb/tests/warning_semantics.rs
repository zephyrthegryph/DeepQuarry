use byond_dmb::{
    compare::{compare_dmbs, compare_proc_code, CompareOptions},
    dmb::Dmb,
    opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;

fn check_warning_fixture(name: &str, owner: &str, expected_count: usize) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap())
            .unwrap();
    let cases = native
        .procs
        .iter()
        .enumerate()
        .filter_map(|(id, proc)| {
            let path = String::from_utf8(native.string(proc.strings[0])?.to_vec()).ok()?;
            path.rsplit('/')
                .next()?
                .starts_with("wc_")
                .then_some((id, path))
        })
        .collect::<Vec<_>>();
    assert_eq!(cases.len(), expected_count, "all authored warning cases");
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &fixtures, Some(name), debug)
                .unwrap();
        let metadata = compare_dmbs(
            &native,
            &output.dmb,
            &CompareOptions {
                authored_prefixes: vec![owner.to_owned()],
                compare_bytecode: false,
                max_discrepancies: 100,
            },
        );
        assert!(
            metadata.is_empty(),
            "{name} debug={debug} metadata: {metadata:#?}"
        );
        for (native_id, path) in &cases {
            let actual_id = output
                .dmb
                .procs
                .iter()
                .position(|proc| output.dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap_or_else(|| panic!("missing authored procedure {path}"));
            let differences =
                compare_proc_code(&native, *native_id, &output.dmb, actual_id, path, 100, true);
            assert!(
                differences.is_empty(),
                "{name} debug={debug} {path}: {differences:#?}"
            );
        }
    }
}

#[test]
fn warned_effectful_membership_precedence_and_usr_shadow_match_native() {
    check_warning_fixture("warning_context", "/proc", 6);
}

#[test]
fn warned_view_usr_loc_and_instant_verb_metadata_match_native() {
    check_warning_fixture("warning_verbs", "/mob", 3);
}
