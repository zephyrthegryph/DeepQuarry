use byond_dmb::{compare::compare_proc_code, dmb::Dmb, translate::translate_named_debug};
mod common;
#[test]
fn external_expression_entries_and_skipped_safe_receivers_match_native() {
    let common::TranslationFixture {
        dir: fixture,
        input,
        baseline,
        template,
        native,
    } = common::translation_fixture("cache_branch_entries");
    let names = [
        "index_sub",
        "index_add",
        "index_sub_expression",
        "safe_and",
        "safe_or",
        "safe_and_argument",
        "safe_nested_logic",
        "safe_ternary",
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
