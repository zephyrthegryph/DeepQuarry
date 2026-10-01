use byond_dmb::{compare::compare_proc_code, dmb::Dmb, translate::translate_named_debug};
mod common;
#[test]
fn usr_cache_reuse_preserves_managed_result_lifetime() {
    let common::TranslationFixture {
        dir: fixture,
        input,
        baseline,
        template,
        native,
    } = common::translation_fixture("cache_usr_ownership");
    let names = [
        "usr_calls",
        "usr_fields",
        "usr_assign",
        "usr_callee_assign",
        "usr_other_owner",
        "usr_global_helper",
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
