use byond_dmb::{compare::compare_proc_code, dmb::Dmb, translate::translate_named_debug};
mod common;
#[test]
fn pick_entries_match_native_frontend_context_across_probability_effects() {
    let common::TranslationFixture {
        dir: fixture,
        input,
        baseline,
        template,
        native,
    } = common::translation_fixture("cache_pick_freeze");
    let names = [
        "pick_frozen",
        "weighted_pick_frozen",
        "pick_initial_frozen",
        "pick_mixed_owners",
        "pick_branch_join",
        "pick_dynamic_weight",
        "pick_weight_helper",
        "pick_weight_field",
        "pick_weight_method",
        "pick_weight_binding",
        "pick_weight_nested",
        "pick_weight_second",
        "pick_weight_mixed_candidates",
        "pick_weight_field_candidates",
        "pick_weight_initial_candidates",
        "pick_weight_two_effects",
        "pick_weight_conditional",
        "pick_weight_nested_dispatch",
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
