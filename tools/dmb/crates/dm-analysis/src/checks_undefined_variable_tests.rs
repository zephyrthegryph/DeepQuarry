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
fn observations(source: &str) -> Result<Vec<(usize, usize, String)>, String> {
    let seed = reference_hierarchy::seed();
    let front = build_with_config(
        Path::new("variables.dme"),
        &Source(source.into()),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .map_err(|e| format!("{e:?}"))?;
    let tree = front.snapshot.tree.as_ref();
    let profile = tree
        .checker_builtin_profile()
        .ok_or("fixed hierarchy unavailable")?;
    let arena = BodyArena::new_typed(&front, |_| true);
    let mut rows = Vec::new();
    for (_, occurrence) in crate::checker_order::bodies(&front)? {
        arena
            .with_parsed(occurrence, |body| -> Result<(), String> {
                for diagnostic in check(&front, body, tree, profile, true)? {
                    let line = front
                        .location(diagnostic.span.start)
                        .ok_or("source origin absent")?
                        .line;
                    let column = front.expanded.text[..diagnostic.span.start]
                        .rsplit('\n')
                        .next()
                        .unwrap()
                        .chars()
                        .count()
                        + 1;
                    rows.push((line, column, diagnostic.message));
                }
                Ok(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(rows)
}
#[test]
fn ordinary_typed_fields_match_independent_pinned_messages_order_and_columns() {
    let rows = observations(include_str!(
        "../../../fixtures/unified_checks/evaluated_variables/probe.dm"
    ))
    .unwrap();
    let expected = [
        (
            8,
            10,
            "undefined field: \"absent_parameter\" on /datum/target",
        ),
        (9, 15, "undefined field: \"absent_nested\" on /datum/target"),
        (
            10,
            18,
            "undefined field: \"absent_list_parameter\" on /datum/target",
        ),
        (12, 10, "undefined field: \"absent_local\" on /datum/target"),
        (
            14,
            13,
            "undefined field: \"absent_list_local\" on /datum/target",
        ),
        (15, 10, "undefined field: \"absent_owned\" on /datum/target"),
        (16, 16, "undefined field: \"absent_root\" on /datum/target"),
        (
            17,
            23,
            "undefined field: \"absent_explicit_root\" on /datum/target",
        ),
        (18, 5, "undefined var: \"missing_unscoped\""),
        (19, 11, "undefined field: \"missing_global\" on (global)"),
    ];
    assert_eq!(rows, expected.map(|(l, c, m)| (l, c, m.into())).to_vec());
}
#[test]
fn unresolved_fix_hints_and_declaration_shapes_discard_all_partial_findings() {
    for body in [
        "    missing_first\n    plain.field\n",
        "    missing_first\n    var/datum/value[side_effect()]\n",
        "    missing_first\n    var/static/datum/value\n",
        "    missing_first\n    var/list/list/datum/values\n",
    ] {
        assert!(
            observations(&format!("/datum/example/proc/probe(plain)\n{body}")).is_err(),
            "{body}"
        );
    }
}
