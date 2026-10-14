use super::*;
struct Source(String);
impl SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn check(
    source: &str,
    state: Option<&mut RetainedSemanticTree>,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("variables.dme"),
        &Source(source.into()),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        state,
    )
}
fn messages(errors: &[Diagnostic]) -> Vec<(usize, &str)> {
    errors
        .iter()
        .map(|error| {
            assert_eq!(error.kind, DiagnosticKind::SourceError);
            (
                error.location.as_ref().unwrap().line,
                error.message.as_str(),
            )
        })
        .collect()
}
#[test]
fn authored_inherited_declarations_reject_but_assignments_remain_legal() {
    for modifier in ["", "static/"] {
        let legal = format!("/datum/base\n    var/{modifier}value = 1\n/datum/child\n    parent_type = /datum/base\n    value = 2\n");
        let rejected = format!("/datum/base\n    var/{modifier}value = 1\n/datum/child\n    parent_type = /datum/base\n    var/{modifier}value = 2\n");
        assert!(check(&legal, None).is_ok());
        let fresh = check(&rejected, None).unwrap_err();
        assert_eq!(
            messages(&fresh),
            vec![
                (5, "value: duplicate definition"),
                (2, "value: previous definition")
            ]
        );
        let mut state = RetainedSemanticTree::new();
        check(&legal, Some(&mut state)).unwrap();
        let retained = check(&rejected, Some(&mut state)).unwrap_err();
        assert_eq!(messages(&retained), messages(&fresh));
        check(&legal, Some(&mut state)).unwrap();
        let shifted = check(
            &format!("// shifted current source\n{rejected}"),
            Some(&mut state),
        )
        .unwrap_err();
        assert_eq!(
            messages(&shifted),
            vec![
                (6, "value: duplicate definition"),
                (3, "value: previous definition")
            ]
        );
    }
}
#[test]
fn duplicate_type_static_uses_pinned_definition_order_and_source_names() {
    let errors = check(
        "/datum/example\n    var/static/value = 1\n    var/static/value = 2\n",
        None,
    )
    .unwrap_err();
    assert_eq!(
        messages(&errors),
        vec![
            (2, "value: duplicate definition"),
            (3, "value: previous definition")
        ]
    );
}
#[test]
fn formal_callable_overrides_and_different_variable_names_remain_legal() {
    check("/datum/base\n    var/value = 1\n    proc/p()\n        return 1\n/datum/child\n    parent_type = /datum/base\n    var/other = 2\n    proc/p()\n        return 2\n", None).unwrap();
}

#[test]
fn inherited_assignment_between_declarations_keeps_actual_definition_location() {
    let source = "/datum/base\n    var/value = 1\n/datum/middle\n    parent_type = /datum/base\n    value = 3\n/datum/child\n    parent_type = /datum/middle\n    var/value = 2\n";
    let fresh = check(source, None).unwrap_err();
    assert_eq!(
        messages(&fresh),
        vec![
            (8, "value: duplicate definition"),
            (2, "value: previous definition")
        ]
    );
}

#[test]
fn cached_absent_parent_field_does_not_hide_new_redeclaration_or_publish_failure() {
    let legal = "/datum/base\n/datum/child\n    parent_type = /datum/base\n    var/value = 2\n";
    let invalid = "/datum/base\n    var/value = 1\n/datum/child\n    parent_type = /datum/base\n    var/value = 2\n";
    let mut state = RetainedSemanticTree::new();
    let original = check(legal, Some(&mut state)).unwrap();
    let published = original.snapshot.tree.clone();
    let fresh = check(invalid, None).unwrap_err();
    let retained = check(invalid, Some(&mut state)).unwrap_err();
    assert_eq!(messages(&retained), messages(&fresh));
    assert!(
        Arc::ptr_eq(state.snapshot_tree().unwrap(), &published),
        "failed declaration candidate must not replace successful semantic authority"
    );
    let moved = check(&format!("// current attempt\n{invalid}"), Some(&mut state)).unwrap_err();
    assert_eq!(
        messages(&moved),
        vec![
            (6, "value: duplicate definition"),
            (3, "value: previous definition")
        ]
    );
    assert!(Arc::ptr_eq(state.snapshot_tree().unwrap(), &published));
    let recovered = check(legal, Some(&mut state)).unwrap();
    assert!(Arc::ptr_eq(&recovered.snapshot.tree, &published));
}
#[test]
fn cached_parent_chain_change_rejects_current_declaration() {
    let initial = "/datum/a\n    var/value = 1\n/datum/b\n/datum/child\n    parent_type = /datum/b\n    var/value = 2\n";
    let changed = initial.replace("parent_type = /datum/b", "parent_type = /datum/a");
    let mut state = RetainedSemanticTree::new();
    check(initial, Some(&mut state)).unwrap();
    let retained = check(&changed, Some(&mut state)).unwrap_err();
    let fresh = check(&changed, None).unwrap_err();
    assert_eq!(messages(&retained), messages(&fresh));
    assert_eq!(
        messages(&retained),
        vec![
            (6, "value: duplicate definition"),
            (2, "value: previous definition")
        ]
    );
}

#[test]
fn active_include_duplicate_locations_keep_distinct_current_encounters() {
    struct Included;
    impl SourceProvider for Included {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name| name.to_str()) {
                Some("variables.dme") => {
                    Ok("#include \"first.dm\"\n#include \"second.dm\"\n".into())
                }
                Some("first.dm" | "second.dm") => {
                    Ok("/datum/example\n    var/static/value = 1\n".into())
                }
                _ => Err("unknown fixture input".into()),
            }
        }
    }
    let errors = build(Path::new("variables.dme"), &Included, &BTreeMap::new(), 1).unwrap_err();
    assert_eq!(
        messages(&errors),
        vec![
            (2, "value: duplicate definition"),
            (2, "value: previous definition")
        ]
    );
    let first = errors[0].location.as_ref().unwrap();
    let second = errors[1].location.as_ref().unwrap();
    assert_ne!(first.include_occurrence, second.include_occurrence);
    assert_ne!(first.encounter_ordinal, second.encounter_ordinal);
    assert_ne!(first.include_chain, second.include_chain);
}

#[test]
fn repeated_include_suppression_does_not_invent_duplicate_declarations() {
    struct Included;
    impl SourceProvider for Included {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name| name.to_str()) {
                Some("variables.dme") => Ok("#include \"same.dm\"\n#include \"same.dm\"\n".into()),
                Some("same.dm") => Ok("/datum/example\n    var/static/value = 1\n".into()),
                _ => Err("unknown fixture input".into()),
            }
        }
    }
    build(Path::new("variables.dme"), &Included, &BTreeMap::new(), 1).unwrap();
}
