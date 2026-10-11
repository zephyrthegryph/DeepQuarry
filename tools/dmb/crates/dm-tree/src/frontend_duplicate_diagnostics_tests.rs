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
