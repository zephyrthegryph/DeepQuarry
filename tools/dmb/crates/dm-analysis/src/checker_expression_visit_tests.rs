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
                        Event::ResolvedField { .. }
                        | Event::ResolvedImplicitListConstructor { .. } => continue,
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
fn logical_or_passes_the_destination_hint_to_both_original_new_operands() {
    let source = include_str!("../../../fixtures/unified_checks/implicit_new_or_hint/project.dme");
    let rows = observe(source).unwrap();
    let relevant: Vec<_> = rows.iter().map(|(kind, name, line, _)| (kind.as_str(), name.as_str(), *line)).collect();
    assert_eq!(relevant, [
        ("resolved", "New", 5),
        ("missing", "missing_argument", 5),
        ("resolved", "New", 6),
        ("implicit_new", "new", 7),
        ("implicit_new", "new", 8),
    ]);
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
        "    first()\n    return src.unissued_array_receiver.deep_field\n",
        "    first()\n    return src.unissued.deep_field\n",
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
fn formerly_unissued_array_suffixes_preserve_complete_original_call_events() {
    for suffix in [
        "[]",
        "[1]",
        "[missing_dimension()]",
        "[1][][missing_dimension()]",
    ] {
        // Keep every exact former negative source. The original checker skips
        // implicit dimensions when this source has no actual /list/New target.
        let source=format!("/datum/example/proc/probe()\n    missing_earlier()\n    var/datum/value{suffix}\n    missing_later()\n");
        let rows = observe_mode(&source, true).unwrap();
        let missing = rows
            .into_iter()
            .filter(|r| r.0 == "missing")
            .collect::<Vec<_>>();
        assert_eq!(
            missing,
            [
                ("missing".into(), "missing_earlier".into(), 2, 5),
                ("missing".into(), "missing_later".into(), 4, 5),
            ],
            "{suffix}"
        );
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

#[test]
fn supported_primary_input_preserves_the_original_former_negative_and_full_old_errors() {
    let source =
        include_str!("../../../fixtures/unified_checks/input_negative_migration/probe.dme");
    assert_eq!(
        observe(source)
            .unwrap()
            .iter()
            .map(|(kind, name, line, column)| (kind.as_str(), name.as_str(), *line, *column))
            .collect::<Vec<_>>(),
        [("missing", "first", 2, 5), ("missing", "hidden", 3, 18)]
    );
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
    .unwrap();
    let resolver = frontend.snapshot.tree.as_ref();
    let profile = resolver.checker_builtin_profile().unwrap();
    let mut arena = BodyArena::new_typed(&frontend, |_| true);
    let mut actual = String::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend).unwrap() {
        arena
            .with_parsed(occurrence, |body| {
                let diagnostics =
                    crate::checks_undefined_proc::check(&frontend, body, resolver, profile, true)
                        .unwrap();
                for diagnostic in diagnostics {
                    assert_eq!(diagnostic.severity, crate::checks::Severity::Error);
                    let line = frontend.location(diagnostic.span.start).unwrap().line;
                    let column = frontend.expanded.text[..diagnostic.span.start]
                        .rsplit('\n')
                        .next()
                        .unwrap()
                        .len()
                        + 1;
                    actual.push_str(&format!(
                        "@FIXTURE@, line {line}, column {column}:\nerror: {}\n\n",
                        diagnostic.message
                    ));
                }
            })
            .unwrap();
    }
    assert_eq!(
        actual,
        include_str!("../../../fixtures/unified_checks/input_negative_migration/reference.stderr"),
        "actual native diagnostics preserve the complete independent old transcript"
    );
}

#[test]
fn primary_array_constructor_gates_dimensions_and_preserves_exact_old_call_order() {
    assert_eq!(observe("/datum/example/proc/probe()\n    var/datum/typed[side_effect()]\n    return visible()\n").unwrap(),
        [("missing".into(),"visible".into(),3,12)]);
    for (source, expected) in [
        (
            include_str!(
                "../../../fixtures/unified_checks/arrays/constructor_dimensions/probe.dme"
            ),
            vec![("first_dimension", 4, 21), ("second_dimension", 4, 42)],
        ),
        (
            include_str!("../../../fixtures/unified_checks/arrays/explicit_initializer/probe.dme"),
            vec![("actual_initializer", 4, 44)],
        ),
        (
            include_str!("../../../fixtures/unified_checks/arrays/implicit_range/probe.dme"),
            vec![
                ("end_bound", 4, 31),
                ("dimension", 4, 15),
                ("missing_body", 5, 9),
            ],
        ),
    ] {
        let actual = observe_mode(source, true)
            .unwrap()
            .into_iter()
            .filter(|row| row.0 == "missing")
            .map(|row| (row.1, row.2, row.3))
            .collect::<Vec<_>>();
        assert_eq!(
            actual,
            expected
                .into_iter()
                .map(|(name, line, col)| (name.to_owned(), line, col))
                .collect::<Vec<_>>()
        );
    }
}

fn native_array_undefined_stderr(source: &str) -> String {
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
    .unwrap();
    let resolver = frontend.snapshot.tree.as_ref();
    let profile = resolver.checker_builtin_profile().unwrap();
    let mut arena = BodyArena::new_typed(&frontend, |_| true);
    let mut actual = String::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend).unwrap() {
        arena
            .with_parsed(occurrence, |body| {
                let diagnostics = crate::checks_undefined_proc::check_evaluated(
                    &frontend, body, resolver, profile, true,
                )
                .unwrap();
                for diagnostic in diagnostics {
                    assert_eq!(diagnostic.severity, crate::checks::Severity::Error);
                    let line = frontend.location(diagnostic.span.start).unwrap().line;
                    let column = frontend.expanded.text[..diagnostic.span.start]
                        .rsplit('\n')
                        .next()
                        .unwrap()
                        .len()
                        + 1;
                    actual.push_str(&format!(
                        "@FIXTURE@, line {line}, column {column}:\nerror: {}\n\n",
                        diagnostic.message
                    ));
                }
            })
            .unwrap();
    }
    actual
}
#[test]
fn complete_original_array_call_diagnostics_match_independent_old_executable_transcripts() {
    for (source, reference) in [
        (
            include_str!(
                "../../../fixtures/unified_checks/arrays/constructor_dimensions/probe.dme"
            ),
            include_str!(
                "../../../fixtures/unified_checks/arrays/constructor_dimensions/reference.stderr"
            ),
        ),
        (
            include_str!("../../../fixtures/unified_checks/arrays/explicit_initializer/probe.dme"),
            include_str!(
                "../../../fixtures/unified_checks/arrays/explicit_initializer/reference.stderr"
            ),
        ),
        (
            include_str!("../../../fixtures/unified_checks/arrays/implicit_range/probe.dme"),
            include_str!("../../../fixtures/unified_checks/arrays/implicit_range/reference.stderr"),
        ),
    ] {
        assert_eq!(native_array_undefined_stderr(source), reference);
    }
}

#[test]
fn blocking_operator_grammar_requires_real_primary_token_and_exact_native_callable() {
    let source="/datum/counter/proc/operator++()\n    return\n/datum/counter/proc/sleep()\n    return\n/proc/probe(datum/counter/C)\n    C++\n";
    let seed = reference_hierarchy::seed();
    let frontend = build_with_config(
        Path::new("blocking-operator.dme"),
        &Source(source.into()),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let archive = frontend.body_archive().unwrap();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let index = archive
        .occurrences()
        .iter()
        .position(|o| tree.member(o.member).unwrap().name == SymbolId::of("probe"))
        .unwrap();
    let body = archive.parse(index).unwrap();
    let statement = &body.statement_body().parsed().statements[0];
    let expression = match &statement.kind {
        StatementKind::Expression(e) | StatementKind::Call(e) => e,
        other => panic!("{other:?}"),
    };
    let receiver = SymbolId::of("/datum/counter");
    let overload =
        checker_call_facts::callable_any(tree, tree, profile, receiver, SymbolId::of("operator++"))
            .unwrap();
    assert_eq!(
        blocking_call_reason(
            tree,
            profile,
            archive.expanded_source(),
            expression,
            receiver,
            &overload
        )
        .unwrap(),
        None
    );
    let unrelated =
        checker_call_facts::callable_any(tree, tree, profile, receiver, SymbolId::of("sleep"))
            .unwrap();
    assert!(blocking_call_reason(
        tree,
        profile,
        archive.expanded_source(),
        expression,
        receiver,
        &unrelated
    )
    .unwrap_err()
    .contains("original operator grammar"));
    let changed = archive.expanded_source().replace("C++", "C--");
    assert!(
        blocking_call_reason(tree, profile, &changed, expression, receiver, &overload).is_err(),
        "original issued ++ shape cannot license changed operator bytes"
    );
}

#[test]
fn original_local_paths_are_not_normalized_a_second_time() {
    let normal =
        "/datum/T\n    var/member\n/proc/check()\n    var/datum/T/P\n    return P.member\n";
    assert!(observe_mode(normal, true).is_ok());
    let repeated =
        "/datum/T\n    var/member\n/proc/check()\n    var/var/datum/T/P\n    return P.member\n";
    let error = observe_mode(repeated, true).unwrap_err();
    assert!(
        error.contains("undefined-type diagnostic projection"),
        "{error}"
    );
    let embedded =
        "/datum/T\n    var/member\n/proc/check()\n    var/datum/static/T/P\n    return P.member\n";
    let error = observe_mode(embedded, true).unwrap_err();
    assert!(
        error.contains("undefined-type diagnostic projection"),
        "{error}"
    );
}

#[test]
fn original_dimension_division_cannot_change_the_local_binding_name() {
    let source="/datum/T\n    var/member\n/proc/check()\n    var/datum/T/P[6 / 2]\n    return P[1].member\n";
    assert!(observe_mode(source, true).is_ok());
}

#[test]
fn absolute_header_type_is_not_a_checker_argument_or_implicit_local() {
    let rows =
        observe("/proc/probe(datum/M,/datum/marker/A,actual_power=1)\n    return A\n").unwrap();
    assert_eq!(
        rows.iter()
            .map(|row| (row.0.as_str(), row.1.as_str(), row.2))
            .collect::<Vec<_>>(),
        [("missing_var", "A", 2)]
    );
}

#[test]
fn contextual_delete_visits_operand_only_but_expression_del_remains_an_ordinary_call(){
 let rows=observe_mode("/proc/p(D)\n    del(hidden(D))\n    visible_tail()\n    return del(D)\n",true).unwrap();
 assert_eq!(rows.iter().map(|row|row.1.as_str()).collect::<Vec<_>>(),["hidden","visible_tail","del"],"only the expression-context del is an unscoped call");
 let rows=observe_mode("/datum/holder/proc/p()\n    del(src)\n    visible_tail()\n",true).unwrap();assert_eq!(rows.iter().map(|row|row.1.as_str()).collect::<Vec<_>>(),["visible_tail"],"pinned Checker does not terminate traversal on deletion");
}

#[test]
fn authored_operator_checker_walk_preserves_pinned_operand_and_assignment_observations(){
 let rows=observe_mode("/proc/p(flag)\n    flag ||= rhs_or()\n    flag &&= rhs_and()\n    return ~mask() ~= other()\n",true).unwrap();
 assert_eq!(rows.iter().map(|row|row.1.as_str()).collect::<Vec<_>>(),["rhs_or","rhs_and","mask","other"],"pinned Checker visits every assignment RHS, including logical assignments; it does not execute runtime short-circuiting");
}

#[test]
fn dynamic_dispatch_checker_observes_target_arguments_then_invocation_arguments_without_a_call_name_event(){
 let rows=observe_mode("/proc/p()\n    return call(make_target(),make_name())(get_value())\n",true).unwrap();
 assert_eq!(rows.iter().map(|row|row.1.as_str()).collect::<Vec<_>>(),["make_target","make_name","get_value"],"same pinned DynamicCall target-list then argument-list traversal, not an unscoped call named call");
}

#[test]
fn actual_reserved_primitive_trace_uses_its_call_node_and_issued_member_not_cached_body(){
    let source="/proc/first(target)\n    return call(target)\n/proc/second(value)\n    return pick(value)\n";
    let seed=reference_hierarchy::seed();
    let front=build_with_config(Path::new("primitive_trace.dme"),&Source(source.into()),&Default::default(),FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap();
    let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();let arena=BodyArena::new_typed(&front,|_|true);
    let mut seen=0;
    for(_,occurrence)in crate::checker_order::bodies(&front).unwrap(){
        arena.with_parsed(occurrence,|body|{
            let view=BodyView::new(&front,body).unwrap();
            let StatementKind::Return(Some(expression))=&view.syntax().parsed().statements[0].kind else{panic!("actual retained Return call")};
            let ExprKind::Call{callee,..}=&expression.kind else{panic!("actual retained primary Call")};
            let ExprKind::Ident(name)=&callee.kind else{panic!("actual named primitive")};
            let member_name=tree.symbols().text(tree.member(occurrence.member).unwrap().name).unwrap();
            assert!(matches!((member_name,name.as_str()),("first","call")|("second","pick")));
            let mut bytes=Vec::new();write_primitive_context_trace(tree,None,CodeSource::issued(&front.expanded.text),occurrence.member,expression,callee,Some(expression),&mut bytes);
            let trace=String::from_utf8(bytes).unwrap();
            assert!(trace.contains(&format!("callee=Some({name:?})")));assert!(trace.contains(&format!("member_name=Some({member_name:?})")));
            assert!(trace.contains(&format!("current_expression=Ok({:?})",expression.span)));
            assert!(trace.contains("source_point=unavailable"),"no borrowed archive means no invented file/line");
            if name=="call"{assert_eq!(linear(&front,body,tree,profile).unwrap_err(),"call needs a primary syntax-primitive context, not ordinary proc lookup");}
            else{assert!(linear(&front,body,tree,profile).is_ok(),"normal pick remains a primary primitive, not a new failure");}
            seen+=1;
        }).unwrap();
    }
    assert_eq!(seen,2);
}

#[test]
fn original_unlint_missing_proc_skips_arguments_but_keeps_following_evaluation(){
 let rows=observe_mode("/proc/probe()\n    SpacemanDMM_unlint(hidden(src),ignored())\n    visible_tail()\n",true).unwrap();
 assert_eq!(rows.iter().map(|row|row.1.as_str()).collect::<Vec<_>>(),["visible_tail"],"actual pinned missing-proc escape skips every argument, including global src");
}
#[test]
fn original_unlint_declared_proc_keeps_ordinary_resolution_and_argument_visitation(){
 let rows=observe_mode("/proc/SpacemanDMM_unlint(value)\n    return value\n/proc/probe()\n    return SpacemanDMM_unlint(visible_argument())\n",true).unwrap();
 assert!(rows.iter().any(|row|row.0=="resolved"&&row.1=="SpacemanDMM_unlint"));
 assert_eq!(rows.iter().filter(|row|row.0=="missing").map(|row|row.1.as_str()).collect::<Vec<_>>(),["visible_argument"],"a real declared proc wins before the escape branch");
}
#[test]
fn original_unlint_escape_is_not_member_global_or_other_reserved_call_authority(){
 let member=observe_mode("/datum/holder/proc/probe()\n    src.SpacemanDMM_unlint(hidden())\n",true).unwrap();
 assert!(member.iter().any(|row|row.0=="missing"&&row.1=="SpacemanDMM_unlint"));assert!(!member.iter().any(|row|row.1=="hidden"));
 let global=observe_mode("/proc/probe()\n    ::SpacemanDMM_unlint(hidden())\n",true).unwrap();assert!(global.iter().any(|row|row.0=="missing"&&row.1=="SpacemanDMM_unlint"));
 assert_eq!(observe_mode("/proc/probe(target)\n    return call(target)\n",true).unwrap_err(),"call needs a primary syntax-primitive context, not ordinary proc lookup");
}

#[test]
fn actual_unknown_field_trace_borrows_failing_ast_and_keeps_origin_refusal(){
 let source="/proc/first(value)\n    return value.field\n/proc/second(other)\n    return other.second_field\n";let seed=reference_hierarchy::seed();let front=build_with_config(Path::new("unknown_field_trace.dme"),&Source(source.into()),&Default::default(),FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap();let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();let arena=BodyArena::new_typed(&front,|_|true);let mut seen=0;
 for(_,occurrence)in crate::checker_order::bodies(&front).unwrap(){arena.with_parsed(occurrence,|body|{
  let view=BodyView::new(&front,body).unwrap();let StatementKind::Return(Some(expression))=&view.syntax().parsed().statements[0].kind else{panic!("real Return")};let ExprKind::Member{object,selector,..}=&expression.kind else{panic!("real field")};let member_name=tree.symbols().text(tree.member(occurrence.member).unwrap().name).unwrap();
  let mut bytes=Vec::new();write_unknown_field_context_trace(tree,None,CodeSource::issued(&front.expanded.text),occurrence.member,expression,object,selector,TypeFact::Unknown,&mut bytes);let trace=String::from_utf8(bytes).unwrap();assert!(trace.contains("base=Unknown object_kind=Ident"));assert!(trace.contains(&format!("selector={selector:?}")));assert!(trace.contains(&format!("member_name=Some({member_name:?})")));assert!(trace.contains(&format!("current_expression=Ok({:?})",expression.span)));assert!(trace.contains("source_point=unavailable"));
  assert_eq!(linear(&front,body,tree,profile).unwrap_err(),"unknown-receiver field access needs pinned fix-hint/declaration origins");seen+=1;
 }).unwrap();}assert_eq!(seen,2);
}

const ORIGINAL_BINARY_EMPTY_FIXTURE:&str="/datum/attr\n/datum/meter\n    var/datum/attr/attr\n/datum/sched\n    var/datum/meter/meter\n/proc/probe(datum/sched/left,datum/sched/right)\n    return (left?.meter || right.meter).attr\n/proc/hint_probe(datum/meter/left)\n    return left || new\n/proc/list_probe(list/items)\n    return items + items\n";
#[derive(Default)]struct BinaryEmptyEvents{rows:Vec<(&'static str,String,bool)>,fail:Option<usize>}
impl<'a> OriginalEvents<'a,String> for BinaryEmptyEvents{
 fn expression_event(&mut self,event:Event<'a>)->Result<(),String>{match event{
  Event::ResolvedField{name,..}=>self.rows.push(("field",name.into(),true)),
  Event::FieldWithoutStaticType{name,hint,..}=>self.rows.push(("field_static",name.into(),hint.is_none())),
  Event::MissingImplicitNewHint{..}=>self.rows.push(("missing_new","new".into(),true)),
  _=>self.rows.push(("other",String::new(),true)),
 }if self.fail==Some(self.rows.len()){return Err("actual binary operand event failure".into())}Ok(())}
 fn flow_event(&mut self,_:crate::checker_reachable::Event<'a>)->Result<(),String>{Ok(())}
 fn access_row(&mut self,_:crate::checks_proc_visibility::Row<'a>)->Result<(),String>{Ok(())}
 fn immediate_row(&mut self,_:crate::checks::Diagnostic)->Result<(),String>{Ok(())}
}
#[test]
fn actual_original_binary_empty_analysis_has_no_operand_type_or_fix_hint(){
 let seed=reference_hierarchy::seed();let front=build_with_config(Path::new("binary_empty.dme"),&Source(ORIGINAL_BINARY_EMPTY_FIXTURE.into()),&Default::default(),FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap();let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();let arena=BodyArena::new_typed(&front,|_|true);let mut seen=0;
 for(_,occurrence)in crate::checker_order::bodies(&front).unwrap(){if tree.member(occurrence.member).unwrap().name!=SymbolId::of("probe"){continue}arena.with_parsed(occurrence,|body|{
  let view=BodyView::new(&front,body).unwrap();let StatementKind::Return(Some(expression))=&view.syntax().parsed().statements[0].kind else{panic!("actual return")};let ExprKind::Member{object,..}=&expression.kind else{panic!("actual attr follow")};let ExprKind::Group(binary)=&object.kind else{panic!("actual grouped OR")};let mut events=BinaryEmptyEvents::default();{
   let mut walker=Walker::new(tree,None,&view.syntax().parsed().local_variables,&front.expanded.text,occurrence,body.checker_parameters(profile).unwrap(),tree,profile,None).unwrap();walker.original_events=Some(&mut events);walker.original_values=true;
   assert_eq!(walker.expression(binary,None).unwrap(),TypeFact::Unhinted);assert_eq!(walker.last_impurity,None);assert!(walker.original_value.is_none());assert_eq!(walker.expression(expression,None).unwrap(),TypeFact::Unhinted);
  }
  assert_eq!(events.rows.iter().map(|r|(r.0,r.1.as_str(),r.2)).collect::<Vec<_>>(),[("field","meter",true),("field","meter",true),("field","meter",true),("field","meter",true),("field_static","attr",true)],"both known operand fields visited; OR yields empty static analysis and no inherited declaration note");
  assert_eq!(linear(&front,body,tree,profile).unwrap_err(),"unknown-receiver field access needs pinned fix-hint/declaration origins","compatibility Unknown remains closed");seen+=1;
 }).unwrap();}assert_eq!(seen,1);
}
#[test]
fn actual_original_binary_empty_analysis_keeps_destination_hint_list_shape_and_first_error(){
 let seed=reference_hierarchy::seed();let front=build_with_config(Path::new("binary_empty_roles.dme"),&Source(ORIGINAL_BINARY_EMPTY_FIXTURE.into()),&Default::default(),FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap();let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();let arena=BodyArena::new_typed(&front,|_|true);let mut seen=0;
 for(_,occurrence)in crate::checker_order::bodies(&front).unwrap(){let name=tree.member(occurrence.member).unwrap().name;if ![SymbolId::of("probe"),SymbolId::of("hint_probe"),SymbolId::of("list_probe")].contains(&name){continue}arena.with_parsed(occurrence,|body|{
  let view=BodyView::new(&front,body).unwrap();let StatementKind::Return(Some(expression))=&view.syntax().parsed().statements[0].kind else{panic!("actual return")};let mut events=BinaryEmptyEvents{fail:(name==SymbolId::of("probe")).then_some(2),..Default::default()};{
   let mut walker=Walker::new(tree,None,&view.syntax().parsed().local_variables,&front.expanded.text,occurrence,body.checker_parameters(profile).unwrap(),tree,profile,None).unwrap();walker.original_events=Some(&mut events);walker.original_values=true;
   if name==SymbolId::of("probe"){assert_eq!(walker.expression(expression,None).unwrap_err(),"actual binary operand event failure");}
   else if name==SymbolId::of("hint_probe"){assert_eq!(walker.expression(expression,Some(SymbolId::of("/datum/meter"))).unwrap(),TypeFact::Unhinted);assert_eq!(walker.last_impurity,None);assert!(walker.original_value.is_none());}
   else{assert_eq!(walker.expression(expression,None).unwrap(),TypeFact::List(None));assert_eq!(walker.last_impurity,None);assert!(walker.original_value.is_none());}
  }
  if name==SymbolId::of("probe"){assert_eq!(events.rows.iter().map(|r|r.1.as_str()).collect::<Vec<_>>(),["meter","meter"],"failure stops before outerfield and does not revisit operands");}
  if name==SymbolId::of("hint_probe"){assert!(!events.rows.iter().any(|r|r.0=="missing_new"),"OR forwards real destination hint to RHS implicit new");}seen+=1;
 }).unwrap();}assert_eq!(seen,3);
}

#[derive(Default)]struct DiagnosedEmptyEvents{rows:Vec<&'static str>,fail:bool}
impl<'a> OriginalEvents<'a,String> for DiagnosedEmptyEvents{
 fn expression_event(&mut self,event:Event<'a>)->Result<(),String>{self.rows.push(match event{Event::MissingParent{..}=>"parent",Event::MissingImplicitNewHint{..}=>"implicit_new",_=>"other"});if self.fail{return Err("actual diagnosed event failure".into())}Ok(())}
 fn flow_event(&mut self,_:crate::checker_reachable::Event<'a>)->Result<(),String>{Ok(())}
 fn access_row(&mut self,_:crate::checks_proc_visibility::Row<'a>)->Result<(),String>{Ok(())}
 fn immediate_row(&mut self,_:crate::checks::Diagnostic)->Result<(),String>{Ok(())}
}
const DIAGNOSED_EMPTY_TERM_FIXTURE:&str="/proc/parent_probe()\n    return ..(must_not_visit())\n/proc/new_probe()\n    return new(must_not_visit())\n";
#[test]
fn actual_original_diagnosed_parent_and_new_results_clear_origins_without_visiting_args(){
 let seed=reference_hierarchy::seed();let front=build_with_config(Path::new("diagnosed_empty_terms.dme"),&Source(DIAGNOSED_EMPTY_TERM_FIXTURE.into()),&Default::default(),FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap();let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();let arena=BodyArena::new_typed(&front,|_|true);let mut seen=0;
 for(_,occurrence)in crate::checker_order::bodies(&front).unwrap(){arena.with_parsed(occurrence,|body|{
  let view=BodyView::new(&front,body).unwrap();let StatementKind::Return(Some(expression))=&view.syntax().parsed().statements[0].kind else{panic!("real return term")};let name=tree.member(occurrence.member).unwrap().name;let expected=if name==SymbolId::of("parent_probe"){"parent"}else{"implicit_new"};let mut events=DiagnosedEmptyEvents::default();{
   let mut walker=Walker::new(tree,None,&view.syntax().parsed().local_variables,&front.expanded.text,occurrence,body.checker_parameters(profile).unwrap(),tree,profile,None).unwrap();walker.original_events=Some(&mut events);walker.original_values=true;
   assert_eq!(walker.expression(expression,None).unwrap(),TypeFact::Unhinted);assert_eq!(walker.last_impurity,None);assert!(walker.original_value.is_none());
  }assert_eq!(events.rows,[expected],"pinned diagnosed terms skip argument evaluation");
  let mut compatibility=Walker::new(tree,None,&view.syntax().parsed().local_variables,&front.expanded.text,occurrence,body.checker_parameters(profile).unwrap(),tree,profile,None).unwrap();assert_eq!(compatibility.expression(expression,None).unwrap(),TypeFact::Unknown,"compatibility absence remains unproved");seen+=1;
 }).unwrap();}assert_eq!(seen,2);
}
#[test]
fn actual_original_diagnosed_empty_terms_do_not_complete_after_first_observer_failure(){
 let seed=reference_hierarchy::seed();let front=build_with_config(Path::new("diagnosed_empty_first_error.dme"),&Source(DIAGNOSED_EMPTY_TERM_FIXTURE.into()),&Default::default(),FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap();let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();let arena=BodyArena::new_typed(&front,|_|true);let mut seen=0;
 for(_,occurrence)in crate::checker_order::bodies(&front).unwrap(){arena.with_parsed(occurrence,|body|{
  let view=BodyView::new(&front,body).unwrap();let StatementKind::Return(Some(expression))=&view.syntax().parsed().statements[0].kind else{panic!("real return term")};let mut events=DiagnosedEmptyEvents{fail:true,..Default::default()};{
   let mut walker=Walker::new(tree,None,&view.syntax().parsed().local_variables,&front.expanded.text,occurrence,body.checker_parameters(profile).unwrap(),tree,profile,None).unwrap();walker.original_events=Some(&mut events);walker.original_values=true;assert_eq!(walker.expression(expression,None).unwrap_err(),"actual diagnosed event failure");
  }assert_eq!(events.rows.len(),1,"no later argument or follow work after the first real error");seen+=1;
 }).unwrap();}assert_eq!(seen,2);
}
