use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn derived_receivers_freeze_values_and_preserve_computed_field_timing() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("fixtures/translation/cache_derived_freeze");
    let input = OpenDreamProgram::from_path(fixture.join("probe.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixture.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/derived_field_binding",
        "/proc/derived_argument_binding",
        "/proc/derived_binding_statements",
        "/proc/derived_read",
        "/proc/derived_write",
        "/proc/derived_compound",
        "/proc/derived_index",
        "/proc/derived_root_replaced",
        "/proc/explicit_child_write",
        "/proc/explicit_root_write",
        "/proc/explicit_argument_write",
        "/proc/deep_child",
        "/proc/derived_nested_argument",
        "/proc/derived_other_argument",
        "/proc/derived_branch",
        "/proc/derived_join",
        "/proc/derived_computed",
        "/proc/derived_computed_twice",
        "/proc/rebind_child",
        "/proc/computed_argument_mutates_child",
        "/proc/get_parent",
        "/proc/computed_safe_child",
        "/proc/computed_safe_parent",
        "/proc/computed_factory",
        "/proc/computed_safe_parent_nested",
        "/proc/computed_safe_parent_index",
        "/proc/computed_safe_parent_index_arg",
        "/proc/computed_safe_parent_index_nested",
        "/datum/holder/proc/replace_child",
        "/datum/holder/proc/replace_root",
        "/datum/holder/proc/read",
        "/datum/holder/New",
    ];
    assert_eq!(paths.len(), 32);
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for path in paths {
            let id = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap_or_else(|| panic!("missing {path}"))
            };
            let differences = compare_proc_code(
                &native,
                id(&native),
                &actual.dmb,
                id(&actual.dmb),
                path,
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
