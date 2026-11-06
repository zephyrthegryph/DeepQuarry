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
fn unresolved_parameter_fix_hint_discards_all_partial_findings() {
    let error = observations(concat!(
        "/datum/example/proc/probe(plain)\n",
        "    missing_first\n",
        "    plain.field\n",
    )).unwrap_err();
    assert!(error.contains("unknown-receiver field access needs pinned fix-hint/declaration origins"), "{error}");
}

#[test]
fn local_array_static_and_recursive_list_keep_exact_variable_findings() {
    let source = include_str!("../../../fixtures/unified_checks/variable_declaration_shapes/probe.dm");
    let rows = observations(source).unwrap();
    let expected = [
        ("missing_first", "undefined var: \"missing_first\""),
        (".absent_array_field", "undefined field: \"absent_array_field\" on /datum"),
        (".absent_static_field", "undefined field: \"absent_static_field\" on /datum"),
        (".absent_nested_field", "undefined field: \"absent_nested_field\" on /datum"),
    ];
    let expected: Vec<_> = expected.iter().map(|(needle, message)| {
        let (line, column) = source.lines().enumerate()
            .find_map(|(line, text)| text.find(needle).map(|column| (line+1, column+1)))
            .unwrap();
        (line, column, (*message).to_owned())
    }).collect();
    assert_eq!(rows, expected);
}

#[test]
fn return_header_builtin_and_inherited_receiver_types_match_pinned_observations() {
    let rows=observations(include_str!("../../../fixtures/unified_checks/return_header_fields/probe.dm")).unwrap();
    let expected=[
        (11,11,"absent_header","/datum/target"),
        (12,18,"absent_inherited_header","/datum/target"),
        (13,22,"absent_default_header","/datum/target"),
        (14,22,"absent_builtin","/turf"),
        (15,25,"absent_block_element","/turf"),
    ];
    assert_eq!(rows,expected.map(|(line,column,name,owner)|(line,column,format!("undefined field: {name:?} on {owner}"))).to_vec());
}

#[test]
fn explicit_global_terms_use_root_lookup_and_preserve_pinned_error_order() {
    let source = include_str!("../../../fixtures/unified_checks/explicit_global_variable/probe.dm");
    let rows = observations(source).unwrap();
    let expected = [
        ("::only_local", "undefined global var: \"only_local\""),
        ("missing_unscoped", "undefined var: \"missing_unscoped\""),
        ("::only_field", "undefined global var: \"only_field\""),
        (".absent_field", "undefined field: \"absent_field\" on /datum/global_probe_value"),
    ];
    let expected: Vec<_> = expected.iter().map(|(needle, message)| {
        let (line, column) = source.lines().enumerate()
            .find_map(|(line, text)| text.find(needle).map(|column| (line+1, column+1)))
            .unwrap();
        (line, column, (*message).to_owned())
    }).collect();
    assert_eq!(rows, expected);
}

#[test]
fn explicit_untyped_global_still_refuses_an_unissued_declaration_fix_hint() {
    assert!(observations(concat!(
        "var/untyped_global\n",
        "/proc/probe()\n",
        "    var/first = ::missing_global\n",
        "    var/second = ::untyped_global.member\n",
    )).is_err());
}
