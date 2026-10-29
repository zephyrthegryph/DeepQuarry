use super::*;
use dm_tree::frontend::{build_with_config, BodyArena, FrontendConfig};
use std::path::Path;
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn observe(source: &str) -> Result<Vec<(String, String, usize, usize)>, String> {
    observe_mode(source, false)
}
fn observe_mode(
    source: &str,
    control: bool,
) -> Result<Vec<(String, String, usize, usize)>, String> {
    let seed = reference_hierarchy::seed();
    let frontend = build_with_config(
        Path::new("evaluated_calls.dme"),
        &Source(source.into()),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .map_err(|e| format!("{e:?}"))?;
    let resolver = frontend.snapshot.tree.as_ref();
    let profile = resolver.checker_builtin_profile().unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut out = Vec::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend)? {
        arena
            .with_parsed(occurrence, |body| {
                let walk = if control {
                    evaluated(&frontend, body, resolver, profile)?
                } else {
                    linear(&frontend, body, resolver, profile)?
                };
                for event in walk.events {
                    let (kind, name, at) = match event {
                        Event::MissingVariable { name, at, .. } => ("missing_var", name, at),
                        Event::MissingField { name, at, .. } => ("missing_field", name, at),
                        Event::MissingCall { name, at, .. } => ("missing", name, at),
                        Event::ResolvedCall { name, at, .. } => ("resolved", name, at),
                        Event::MissingParent { at, .. } => ("parent", "..", at),
                        Event::UnknownReceiverCall { name, at, .. } => {
                            ("unknown_receiver", name, at)
                        }
                        Event::DynamicMemberCall { name, at, .. } => ("dynamic", name, at),
                        Event::MissingImplicitNewHint { expression } => {
                            ("implicit_new", "new", expression.span)
                        }
                    };
                    let line = frontend
                        .location(at.start)
                        .ok_or("event origin missing")?
                        .line;
                    let column = frontend.expanded.text[..at.start]
                        .rsplit('\n')
                        .next()
                        .unwrap()
                        .chars()
                        .count()
                        + 1;
                    out.push((kind.into(), name.into(), line, column));
                }
                Ok::<_, String>(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(out)
}
#[test]
fn seeded_resolution_suppresses_only_the_arguments_the_old_checker_skips() {
    let rows = observe(include_str!(
        "../../../fixtures/unified_checks/evaluated_calls/probe.dm"
    ))
    .unwrap();
    let missing = rows
        .iter()
        .filter(|r| r.0 == "missing")
        .map(|r| r.1.as_str())
        .collect::<Vec<_>>();
    assert_eq!(
        missing,
        [
            "missing_outer",
            "missing_visible",
            "not_declared",
            "missing_visible_dynamic",
            "missing_initializer",
            "missing_named",
            "missing_list_named",
            "missing_in_string",
            "missing_global",
            "missing_left",
            "missing_left",
            "missing_right"
        ]
    );
    assert!(rows
        .iter()
        .any(|r| r.0 == "unknown_receiver" && r.1 == "not_known"));
    assert!(rows.iter().any(|r| r.0 == "parent"));
    assert!(!rows.iter().any(|r| r.1.starts_with("missing_hidden")));
}
#[test]
fn member_origins_are_verified_from_issued_span_gaps_not_offset_guesses() {
    let rows = observe("/datum/example/proc/probe(datum/typed)\n    typed  .  absent(hidden())\n")
        .unwrap();
    assert_eq!(rows, [("missing".into(), "absent".into(), 2, 12)]);
}
#[test]
fn new_miniexpr_and_missing_implicit_hint_do_not_visit_constructor_arguments() {
    let rows=observe("/datum/example/proc/probe(a)\n    new a(hidden_dynamic())\n    new(hidden_implicit())\n    return visible()\n").unwrap();
    assert_eq!(
        rows.iter()
            .filter(|r| r.0 == "missing")
            .map(|r| r.1.as_str())
            .collect::<Vec<_>>(),
        ["visible"]
    );
    assert!(rows.iter().any(|r| r.0 == "implicit_new"));
}
#[test]
fn return_termination_and_root_lshift_duplicate_visits_match_pinned_policy() {
    let rows = observe(
        "/datum/example/proc/probe()\n    lhs() << rhs()\n    return final()\n    hidden()\n",
    )
    .unwrap();
    assert_eq!(
        rows.iter().map(|r| r.1.as_str()).collect::<Vec<_>>(),
        ["lhs", "lhs", "rhs", "final"]
    );
}
#[test]
fn unsupported_origins_types_and_control_discard_the_entire_contribution() {
    for body in [
        "    first()\n    if(1)\n        second()\n",
        "    first()\n    return !second()\n",
        "    var/datum/typed[side_effect()]\n    return visible()\n",
        "    first()\n    return input(hidden())\n",
        "    first()\n    return src.field.deep_field\n",
    ] {
        assert!(
            observe(&format!("/datum/example/proc/probe()\n{body}")).is_err(),
            "{body}"
        );
    }
}

#[test]
fn shared_control_roots_preserve_pinned_error_order_and_source_positions() {
    // Captured independently using dreamchecker.exe (reference commit recorded
    // by checker_expression_visit), not coordinates generated from native AST.
    let rows = observe_mode(
        include_str!("../../../fixtures/unified_checks/evaluated_controls/probe.dm"),
        true,
    )
    .unwrap();
    let missing = rows
        .iter()
        .filter(|row| row.0 == "missing")
        .map(|row| (row.1.as_str(), row.2, row.3))
        .collect::<Vec<_>>();
    assert_eq!(
        missing,
        [
            ("missing_if", 4, 8),
            ("missing_then", 5, 9),
            ("missing_else_if", 6, 13),
            ("missing_else_then", 7, 9),
            ("missing_else", 9, 9),
            ("missing_while", 10, 11),
            ("missing_while_body", 11, 9),
            ("missing_do_body", 13, 9),
            ("missing_do_condition", 14, 11),
            ("missing_init", 15, 17),
            ("missing_test", 15, 33),
            ("missing_step", 15, 49),
            ("missing_for_body", 16, 9),
            ("missing_end", 17, 36),
            ("missing_stride", 17, 55),
            ("missing_start", 17, 17),
            ("missing_range_body", 18, 9),
            ("missing_iter", 19, 23),
            ("missing_each_body", 20, 9),
            ("missing_delay", 21, 11),
            ("missing_spawn_body", 22, 9),
            ("missing_selector", 23, 12),
            ("missing_case", 24, 12),
            ("missing_case_body", 25, 13),
            ("missing_default_body", 27, 13),
            ("missing_try", 29, 9),
            ("missing_catch", 31, 9),
            ("missing_final", 32, 11),
        ]
    );
}
#[test]
fn shared_control_walk_skips_semantically_dead_siblings_and_do_condition() {
    let rows = observe_mode("/datum/example/proc/probe()\n    do\n        return missing_return()\n    while(missing_skipped_condition())\n    missing_skipped_sibling()\n", true).unwrap();
    let missing = rows
        .iter()
        .filter(|row| row.0 == "missing")
        .map(|row| row.1.as_str())
        .collect::<Vec<_>>();
    assert_eq!(missing, ["missing_return"]);
}
#[test]
fn unsupported_array_binding_discards_all_earlier_control_events() {
    let error = observe_mode("/datum/example/proc/probe(a)\n    missing_earlier()\n    for(var/datum/item[1] in list())\n        missing_later()\n", true).unwrap_err();
    assert!(error.contains("array"));
}
