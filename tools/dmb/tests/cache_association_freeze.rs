use byond_dmb::{compare::compare_proc_code, dmb::Dmb, translate::translate_named_debug};
mod common;
#[test]
fn field_chain_association_preserves_native_frozen_receivers() {
    let common::TranslationFixture {
        dir: fixture,
        input,
        baseline,
        template,
        native,
    } = common::translation_fixture("cache_association_freeze");
    let names = [
        "src_condition",
        "src_condition_arg",
        "src_sequential",
        "src_explicit_write",
        "src_condition_write",
        "src_deep",
        "src_other_select",
        "src_join",
        "src_assignment_expression",
        "src_compound_return",
        "src_direct_write",
        "src_compound_expression",
        "src_increment_expression",
    ];
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for name in names {
            let path = format!("/datum/cache_outer/proc/{name}");
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
