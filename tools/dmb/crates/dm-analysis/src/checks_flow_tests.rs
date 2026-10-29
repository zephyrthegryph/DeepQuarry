use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn observe(
    source: &str,
    family: Family,
    severity: Severity,
) -> Result<Vec<(usize, String)>, String> {
    let frontend = build(
        Path::new("flow.dme"),
        &Source(source.into()),
        &Default::default(),
        1,
    )
    .map_err(|e| format!("{e:?}"))?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut rows = Vec::new();
    for occurrence in frontend.bodies.iter() {
        arena
            .with_parsed(occurrence, |body| {
                let view = BodyView::new(&frontend, body)?;
                for diagnostic in check(&view, family, severity)? {
                    assert_eq!(diagnostic.family, family.name());
                    assert!(diagnostic.notes.is_empty());
                    assert_eq!(diagnostic.severity, severity);
                    rows.push((
                        view.location(&diagnostic).ok_or("missing source")?.line,
                        diagnostic.message,
                    ));
                }
                Ok::<_, String>(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(rows)
}
#[test]
fn only_first_unreachable_sibling_is_reported_and_not_visited() {
    let rows = observe(
        "/proc/p(a)\n    return\n    if(1)\n        return\n    a=1\n",
        Family::Unreachable,
        Severity::Error,
    )
    .unwrap();
    assert_eq!(rows, [(3, "possible unreachable code here".into())]);
    assert!(observe(
        "/proc/p(a)\n    return\n    if(1)\n        return\n",
        Family::IfDeterminate,
        Severity::Error
    )
    .unwrap()
    .is_empty());
}
#[test]
fn branch_visits_are_not_pruned_and_if_diagnostics_follow_own_body() {
    let source="/proc/p(a)\n    if(0)\n        if(1)\n            a=1\n    else if(1)\n        a=2\n    else if(0)\n        a=3\n    else\n        a=4\n";
    let rows = observe(source, Family::IfDeterminate, Severity::Warning).unwrap();
    assert_eq!(
        rows,
        [
            (3, "if condition is always true".into()),
            (2, "if condition is always false".into()),
            (5, "if condition is always true".into()),
            (7, "if condition is always false".into())
        ]
    );
    let rows = observe(source, Family::Unreachable, Severity::Error).unwrap();
    assert_eq!(
        rows,
        [
            (
                7,
                "unreachable if block, preceeding if/elseif condition(s) are always true".into()
            ),
            (
                10,
                "unreachable else block, preceeding if/elseif condition(s) are always true".into()
            )
        ]
    );
}
#[test]
fn only_c_style_for_tests_have_loop_determinate_diagnostics() {
    let source="/proc/p(a)\n    for(var/i=0;1;i++)\n        a=1\n    for(var/j=0;0;j++)\n        a=2\n    while(1)\n        a=3\n    do\n        a=4\n    while(0)\n";
    assert_eq!(
        observe(source, Family::LoopDeterminate, Severity::Error).unwrap(),
        [
            (2, "loop condition is always true".into()),
            (4, "loop condition is always false".into())
        ]
    );
}
#[test]
fn do_return_propagates_without_visiting_condition_or_siblings() {
    let source = "/proc/p(a)\n    do\n        return\n    while(1)\n    if(1)\n        a=1\n";
    assert!(observe(source, Family::IfDeterminate, Severity::Error)
        .unwrap()
        .is_empty());
    assert!(observe(source, Family::LoopDeterminate, Severity::Error)
        .unwrap()
        .is_empty());
    assert_eq!(
        observe(source, Family::Unreachable, Severity::Error).unwrap(),
        [(5, "possible unreachable code here".into())]
    );
}
#[test]
fn semantic_constants_and_short_circuit_guesses_do_not_become_determinate() {
    for expression in ["a", "1 || a", "0 && a", "1 == 1", "-1"] {
        let source=format!("/proc/p(a)\n    if({expression})\n        a=1\n    for(var/i=0;{expression};i++)\n        a=2\n");
        assert!(observe(&source, Family::IfDeterminate, Severity::Error)
            .unwrap()
            .is_empty());
        assert!(observe(&source, Family::LoopDeterminate, Severity::Error)
            .unwrap()
            .is_empty());
    }
}
#[test]
fn unsupported_range_step_discards_earlier_findings_and_disabled_is_empty() {
    let source =
        "/proc/p(a)\n    if(1)\n        a=1\n    for(var/i=1 to 1 step a::b)\n        a=2\n";
    assert!(observe(source, Family::IfDeterminate, Severity::Error).is_err());
    assert!(observe(source, Family::IfDeterminate, Severity::Disabled)
        .unwrap()
        .is_empty());
}

#[test]
fn constructor_follow_truthiness_preserves_new_primary_boundaries() {
    let source =
        "/proc/p(a)\n    if(new /datum().foo())\n        a=1\n    if(new a.b())\n        a=2\n";
    assert_eq!(
        observe(source, Family::IfDeterminate, Severity::Error).unwrap(),
        [(4, "if condition is always true".into())]
    );
}
