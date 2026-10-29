use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Source<'a>(&'a str);
impl dm_preprocess::SourceProvider for Source<'_> {
    fn read(&self, _: &Path) -> Result<String, String> { Ok(self.0.into()) }
}
fn observe(source: &str, severity: Severity) -> Vec<(usize, usize, String, Severity)> {
    let frontend = build(Path::new("settings.dme"), &Source(source), &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut rows = Vec::new();
    for occurrence in frontend.bodies.iter() {
        arena.with_parsed(occurrence, |body| {
            let view = BodyView::new(&frontend, body).unwrap();
            for diagnostic in check(&view, severity).unwrap() {
                assert_eq!(diagnostic.family, "set_has_no_effect");
                assert!(diagnostic.notes.is_empty());
                let line = view.location(&diagnostic).unwrap().line;
                let column = frontend.expanded.text[..diagnostic.span.start].rsplit('\n').next().unwrap().chars().count()+1;
                rows.push((line, column, diagnostic.message, diagnostic.severity));
            }
        }).unwrap();
    }
    rows
}
#[test]
fn checker_annotations_keep_prefix_and_report_late_nested_settings() {
    let rows = observe(include_str!("../../../fixtures/set_no_effect/settings.dm"), Severity::Error);
    assert_eq!(rows, [7,12].into_iter().map(|line| (line, if line==12 {9} else {5},
        "set statement not at the top of the proc".into(), Severity::Error)).collect::<Vec<_>>());
}
#[test]
fn disabled_family_and_ordinary_runtime_settings_are_clean() {
    let source = "/proc/p(a)\n    a=1\n    set background=1\n    set SpacemanDMM_should_be_pure=1\n";
    assert!(observe(source, Severity::Disabled).is_empty());
    assert_eq!(observe(source, Severity::Warning).len(), 1);
}
#[test]
fn settings_after_a_terminator_are_not_visited_by_reference_policy() {
    assert!(observe("/proc/p()\n    return\n    set SpacemanDMM_should_be_pure=1\n", Severity::Error).is_empty());
}

#[test]
fn archive_preserves_directive_policy_after_frontend_release() {
    let source = include_str!("../../../fixtures/set_no_effect/settings.dm");
    let frontend = build(Path::new("settings.dme"), &Source(source), &Default::default(), 1).unwrap();
    let archive = frontend.body_archive().unwrap();
    drop(frontend);
    let mut rows = Vec::new();
    for ordinal in 0..archive.occurrences().len() {
        let body = archive.parse(ordinal).unwrap();
        for diagnostic in archived(&body, Severity::Error).unwrap() {
            rows.push((body.location(diagnostic.span.start).unwrap().line,
                "set statement not at the top of the proc".to_owned()));
        }
    }
    assert_eq!(rows, [(7,"set statement not at the top of the proc".into()),
        (12,"set statement not at the top of the proc".into())]);
}
