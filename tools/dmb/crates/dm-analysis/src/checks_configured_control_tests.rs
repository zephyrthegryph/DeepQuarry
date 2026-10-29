use super::*;
use std::{cell::Cell, path::Path};
fn names() -> Vec<String> {
    vec![
        "if_condition_determinate".into(),
        "control_condition_static".into(),
    ]
}
fn policy() -> CheckerPolicy {
    CheckerPolicy::from_sections(None,Some(&serde_json::json!({"control_condition_static":"hint","if_condition_determinate":"warning"}))).unwrap()
}
#[test]
fn one_union_walk_and_disabled_selection_are_explicit() {
    let plan = Plan::new(&names(), &policy()).unwrap();
    let calls = Cell::new(0);
    plan.run(|selected| {
        calls.set(calls.get() + 1);
        assert_eq!(selected.len(), 2);
        Ok(Vec::new())
    })
    .unwrap();
    assert_eq!(calls.get(), 1);
    let disabled = CheckerPolicy::from_sections(
        None,
        Some(
            &serde_json::json!({"control_condition_static":"off","if_condition_determinate":"off"}),
        ),
    )
    .unwrap();
    Plan::new(&names(), &disabled)
        .unwrap()
        .run(|_| panic!("disabled union must not compute a flow walk"))
        .unwrap();
}
#[test]
fn duplicates_and_noncontrol_families_refuse_before_walking() {
    for bad in [
        vec![],
        vec!["unknown".into()],
        vec!["ambiguous_not_bitwise".into()],
        vec![
            "control_condition_static".into(),
            "control_condition_static".into(),
        ],
    ] {
        assert!(Plan::new(&bad, &CheckerPolicy::default()).is_err());
    }
}
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn configured_union_preserves_common_event_order_and_query_owned_syntax_authority() {
    let frontend = dm_tree::frontend::build(
        Path::new("control.dme"),
        &Source("/proc/a()\n    if(1)\n        return\n    return\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = dm_tree::frontend::BodyArena::new_typed(&frontend, |_| true);
    let plan = Plan::new(&names(), &policy()).unwrap();
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body).unwrap();
            let rows = plan.check(&view).unwrap();
            assert_eq!(
                rows.iter().map(|r| r.diagnostic.family).collect::<Vec<_>>(),
                ["control_condition_static", "if_condition_determinate"]
            );
            assert_eq!(rows[0].severity, DiagnosticSeverity::Hint);
            assert_eq!(rows[1].severity, DiagnosticSeverity::Warning);
            assert_eq!(rows[0].diagnostic.span, rows[1].diagnostic.span);
        })
        .unwrap();
    let archive = frontend.body_archive().unwrap();
    drop(arena);
    drop(frontend);
    let rows = plan.archived(&archive.parse(0).unwrap()).unwrap();
    assert_eq!(rows.len(), 2);
}
#[test]
fn changing_configuration_rejudges_the_same_body_without_retaining_events() {
    let frontend = dm_tree::frontend::build(
        Path::new("control.dme"),
        &Source("/proc/a()\n    if(1)\n        return\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let archive = frontend.body_archive().unwrap();
    let body = archive.parse(0).unwrap();
    let first = Plan::new(&names(), &policy())
        .unwrap()
        .archived(&body)
        .unwrap();
    let overrides=CheckerPolicy::from_sections(None,Some(&serde_json::json!({"control_condition_static":"off","if_condition_determinate":"hint"}))).unwrap();
    let second = Plan::new(&names(), &overrides)
        .unwrap()
        .archived(&body)
        .unwrap();
    assert_eq!(first.len(), 2);
    assert_eq!(second.len(), 1);
    assert_eq!(second[0].severity, DiagnosticSeverity::Hint);
    assert_eq!(second[0].diagnostic.span, first[1].diagnostic.span);
}
