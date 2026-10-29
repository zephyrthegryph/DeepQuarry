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
                        // Resolved fields are an observation for visibility;
                        // this fixture asserts the existing call-event stream.
                        Event::ResolvedField { .. } => continue,
                        Event::FieldWithoutStaticType { name, at, .. } => {
                            ("field_static", name, at)
                        }
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

#[test]
fn constructors_and_locate_preserve_exact_visited_argument_roots() {
    let rows = observe_mode(
        include_str!("../../../fixtures/unified_checks/constructor_call_roots/probe.dm"),
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
            ("missing_ctor_arg", 3, 23),
            ("missing_inferred_arg", 4, 36),
            ("missing_locate_arg", 7, 12),
            ("missing_locate_plain", 8, 12),
            ("missing_clause", 9, 12),
            ("missing_container", 9, 38),
        ]
    );
}
#[test]
fn unresolved_live_settings_and_parameter_local_origins_remain_atomic_unsupported() {
    for source in [
        "/datum/target\n/proc/make()\n    set SpacemanDMM_return_type=/datum/target\n    return null\n/proc/probe()\n    make().field\n",
        "/proc/probe(x)\n    x.field\n",
        "/proc/probe()\n    var/x\n    x.field\n",
    ] { assert!(observe_mode(source,true).is_err(),"{source}"); }
}

#[test]
fn issued_array_type_container_does_not_certify_dimension_evaluation_or_for_shape() {
    for suffix in [
        "[]",
        "[1]",
        "[missing_dimension()]",
        "[1][][missing_dimension()]",
    ] {
        let source=format!("/datum/example/proc/probe()\n    missing_earlier()\n    var/datum/value{suffix}\n    missing_later()\n");
        let error = observe_mode(&source, true).unwrap_err();
        assert!(error.contains("array"), "{suffix}: {error}");
    }
}

#[test]
fn common_local_increments_visit_control_without_losing_final_calls() {
    let source="/proc/probe()\n    var/i=0\n    i++\n    ++i\n    i--\n    --i\n    for(var/j=0; j<2; j++)\n        visible_body()\n    visible_tail()\n";
    let rows = observe_mode(source, true).unwrap();
    assert_eq!(
        rows.iter().map(|r| r.1.as_str()).collect::<Vec<_>>(),
        ["visible_body", "visible_tail"]
    );
}
#[test]
fn local_increment_clears_receiver_static_fix_hint_for_followed_access() {
    let rows =
        observe("/proc/probe()\n    var/i=0\n    (i++).field\n    (++i).method()\n").unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| (r.0.as_str(), r.1.as_str(), r.2, r.3))
            .collect::<Vec<_>>(),
        [
            ("field_static", "field", 3, 10),
            ("unknown_receiver", "method", 4, 10),
        ]
    );
}
#[test]
fn typed_and_nonlocal_increments_remain_explicitly_unsupported() {
    for source in [
        "/proc/probe(datum/D)\n    D++\n",
        "/proc/probe(list/L)\n    --L\n",
        "/datum/probe\n    var/x\n/datum/probe/proc/test()\n    x++\n",
        "/proc/probe(datum/D)\n    ++D.value\n",
    ] {
        assert!(
            observe(source).unwrap_err().contains("increment"),
            "{source}"
        );
    }
}
#[test]
fn increment_origin_requires_real_primary_operator_and_operand_boundaries() {
    let parsed = dm_syntax::parse_expression("count++");
    let expression = parsed.expr.as_ref().unwrap();
    let ExprKind::Unary { op, value } = &expression.kind else {
        panic!("primary unary missing")
    };
    let source = "count++".to_owned();
    assert_eq!(
        increment_origin(&source, expression, value, op).unwrap(),
        Span::new(5, 7)
    );
    assert!(increment_origin(&source.replace("++", "--"), expression, value, op).is_err());
    let mut foreign = expression.clone();
    foreign.span.start += 1;
    assert!(increment_origin(&source, &foreign, value, op).is_err());
}

#[test]
fn increment_purity_never_treats_parameters_or_local_aliases_as_fresh_literals() {
    for source in [
        "/proc/p(i)\n    i++\n",
        "/datum/example\n    var/value\n/datum/example/proc/p()\n    var/i=value\n    i++\n",
        "/proc/p(parameter)\n    var/i=parameter\n    i++\n",
        "/proc/p()\n    var/i=0\n    var/alias=i\n    alias++\n",
    ] {
        assert!(
            observe_mode(source, true).unwrap_err().contains("purity"),
            "{source}"
        );
    }
}
#[test]
fn reassignment_branch_and_argument_escape_invalidate_local_mutation_proof() {
    for source in [
        "/proc/p(parameter)\n    var/i=0\n    i=parameter\n    i++\n",
        "/proc/p(parameter)\n    var/i=0\n    if(parameter)\n        i=parameter\n    i++\n",
        "/proc/consume(x)\n    return\n/proc/p()\n    var/i=0\n    consume(i)\n    i++\n",
        "/proc/p(parameter)\n    var/i=0\n    if(parameter)\n        i=parameter\n        var/i=0\n    i++\n",
    ] {assert!(observe_mode(source,true).unwrap_err().contains("purity"),"{source}");}
}
#[test]
fn inner_shadow_does_not_replace_the_exact_outer_literal_proof() {
    let rows=observe_mode("/proc/p(condition)\n    var/i=0\n    if(condition)\n        var/i=condition\n    i++\n    visible_tail()\n",true).unwrap();
    assert_eq!(
        rows.iter().map(|r| r.1.as_str()).collect::<Vec<_>>(),
        ["visible_tail"]
    );
}
