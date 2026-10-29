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
fn rows(source: &str, enabled: bool) -> Result<Vec<(usize, usize, String)>, String> {
    let seed = reference_hierarchy::seed();
    let frontend = build_with_config(
        Path::new("probe.dme"),
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
                for row in check(&frontend, body, resolver, profile, enabled)? {
                    assert_eq!(row.family, "undefined_proc");
                    assert_eq!(row.severity, Severity::Error);
                    assert!(row.notes.is_empty());
                    out.push((
                        frontend.location(row.span.start).unwrap().line,
                        frontend.expanded.text[..row.span.start]
                            .rsplit('\n')
                            .next()
                            .unwrap()
                            .chars()
                            .count()
                            + 1,
                        row.message,
                    ));
                }
                Ok::<_, String>(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(out)
}
#[test]
fn independent_seed_has_exact_pinned_messages_positions_order_and_multiplicity() {
    let rows = rows(
        include_str!("../../../fixtures/unified_checks/evaluated_calls/probe.dm"),
        true,
    )
    .unwrap();
    let expected = [
        (4, 5, "missing_outer", "/datum/example"),
        (5, 11, "missing_visible", "/datum/example"),
        (7, 10, "not_declared", "/datum"),
        (8, 15, "missing_visible_dynamic", "/datum/example"),
        (9, 17, "missing_initializer", "/datum/example"),
        (10, 19, "missing_named", "/datum/example"),
        (11, 17, "missing_list_named", "/datum/example"),
        (12, 28, "missing_in_string", "/datum/example"),
        (13, 11, "missing_global", "(global)"),
        (14, 5, "missing_left", "/datum/example"),
        (14, 5, "missing_left", "/datum/example"),
        (14, 23, "missing_right", "/datum/example"),
    ];
    assert_eq!(
        rows,
        expected
            .map(|(line, column, name, owner)| (
                line,
                column,
                format!("undefined proc: {name:?} on {owner}")
            ))
            .to_vec()
    );
}
#[test]
fn selector_disabled_is_not_a_fabricated_named_legacy_configuration_override() {
    assert!(
        rows("/proc/probe()\n    if(1)\n        unsupported()\n", false)
            .unwrap()
            .is_empty()
    );
}
#[test]
fn unsupported_later_context_does_not_certify_an_earlier_partial_result() {
    assert!(rows(
        "/proc/probe()\n    first()\n    if(1)\n        later()\n",
        true
    )
    .is_err());
}

#[test]
fn explicit_global_missing_proc_preserves_reference_wording_and_skips_arguments() {
    let actual = rows("/proc/probe()\n    ::missing(hidden_argument())\n", true).unwrap();
    assert_eq!(
        actual.len(),
        1,
        "a refused global callee must suppress its arguments"
    );
    assert_eq!(actual[0].0, 2);
    assert_eq!(actual[0].2, "undefined global proc: \"missing\"");
    let bare = rows("/proc/probe()\n    missing()\n", true).unwrap();
    assert_eq!(bare.len(), 1);
    assert_eq!(bare[0].2, "undefined proc: \"missing\" on (global)");
}
