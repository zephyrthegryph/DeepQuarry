use super::*;
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
use dm_tree::frontend::{build_with_config, BodyArena, FrontendConfig};
use std::path::Path;
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(AcquiredSource);
impl SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("original acquisition required".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(&self, _: &Path, text: &SourceText) -> Option<AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn observe(source: &str, severity: Severity) -> Result<Vec<(usize, usize)>, String> {
    let seed = reference_hierarchy::seed();
    let files = Source(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let frontend = build_with_config(
        Path::new("implicit-new.dme"),
        &files,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .map_err(|e| format!("{e:?}"))?;
    let tree = frontend.snapshot.tree.as_ref();
    let context = crate::checker_context::CheckerContext::live(
        &frontend,
        tree,
        tree.checker_builtin_profile().unwrap(),
    )?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut rows = Vec::new();
    for (_, occurrence) in crate::checker_order::bodies(&frontend)? {
        arena
            .with_parsed(occurrence, |body| -> Result<(), String> {
                for row in context.implicit_new_live(&frontend, body, severity)? {
                    assert_eq!(row.family, FAMILY);
                    assert_eq!(row.severity, severity);
                    assert_eq!(row.message, "no type hint available on implicit new()");
                    assert!(row.notes.is_empty());
                    let original = frontend
                        .source_export_mapping()
                        .ok_or("original mapping absent")?
                        .original_note_origin(row.span.start)?;
                    rows.push((original.line, original.byte_column));
                }
                Ok(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(rows)
}
#[test]
fn seeded_implicit_new_matches_independent_pinned_bytes_order_and_suppression() {
    let source = include_str!("../../../fixtures/unified_checks/implicit_new/probe.dm");
    assert_eq!(
        observe(source, Severity::Error).unwrap(),
        [
            (7, 2),
            (8, 9),
            (10, 16),
            (12, 7),
            (12, 15),
            (17, 2),
            (19, 4)
        ]
    );
    assert_eq!(observe(source, Severity::Warning).unwrap().len(), 7);
    assert!(observe(source, Severity::Disabled).unwrap().is_empty());
}
#[test]
fn unsupported_later_shape_discards_earlier_family_findings() {
    let source = "/proc/p()\n    new()\n    var/static/datum/kept\n";
    assert!(observe(source, Severity::Error).is_err());
    assert!(observe(source, Severity::Disabled).unwrap().is_empty());
}
#[test]
fn hinted_assignments_and_explicit_constructors_do_not_warn() {
    let source="/datum/target\n/datum/target/New(x)\n    return\n/proc/p()\n    var/datum/target/t = new(1)\n    t = new(2)\n    new /datum/target(3)\n";
    assert!(observe(source, Severity::Error).unwrap().is_empty());
}
#[test]
fn a_terminating_return_skips_later_implicit_new_and_its_arguments() {
    assert!(observe(
        "/proc/p()\n    return 1\n    new(never_called())\n",
        Severity::Error
    )
    .unwrap()
    .is_empty());
}
