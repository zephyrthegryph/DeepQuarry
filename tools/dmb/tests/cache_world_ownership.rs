use byond_dmb::{compare::compare_proc_code, dmb::Dmb, translate::translate_named_debug};
mod common;
#[test]
fn world_method_cache_reuse_preserves_managed_result_lifetime() {
    let common::TranslationFixture {
        dir: fixture,
        input,
        baseline,
        template,
        native,
    } = common::translation_fixture("cache_world_ownership");
    let names = [
        "read_name",
        "read_contents",
        "read_global",
        "write_name",
        "compound_name",
        "other_owner",
        "read_branch",
    ];
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for name in names {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let diff = compare_proc_code(
                &native,
                find(&native),
                &actual.dmb,
                find(&actual.dmb),
                &path,
                100,
                true,
            );
            assert!(diff.is_empty(), "debug={debug} {path}: {diff:#?}");
        }
    }
}
