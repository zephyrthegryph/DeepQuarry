use super::*;
use dm_tree::frontend::{build, ColdFrontend};
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str) -> ColdFrontend {
    build(
        Path::new("code/declarations.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
}
fn list_type(tree: &SemanticTree, owner: &str, name: &str) -> Result<Option<String>, Unsupported> {
    tracked_list_declared_type(tree, SymbolId::of(owner), SymbolId::of(name))
        .map(|value| value.map(|value| tree.symbols().text(value).unwrap().to_string()))
}

#[test]
fn tracked_list_selection_matches_legacy_declared_type_policy() {
    // These expected classifications are Sem::var_decl(...).is_list(), not a
    // runtime-value approximation. No body is parsed to answer this selection.
    let f = frontend("/datum/base\n    var/list/items\n    var/list/datum/typed_items\n    var/untyped = list()\n    var/num/number\n    var/listish/lookalike\n/datum/base/child\n    items = list(1)\n");
    let tree = f.snapshot.tree.as_ref();
    assert_eq!(
        list_type(tree, "/datum/base", "items").unwrap().as_deref(),
        Some("/list")
    );
    // Native declarations keep the element annotation separately: classification
    // still matches legacy is_list(), while the returned canonical type is /list.
    assert_eq!(
        list_type(tree, "/datum/base", "typed_items")
            .unwrap()
            .as_deref(),
        Some("/list")
    );
    assert_eq!(
        list_type(tree, "/datum/base/child", "items")
            .unwrap()
            .as_deref(),
        Some("/list")
    );
    for name in ["untyped", "number", "lookalike"] {
        assert_eq!(
            list_type(tree, "/datum/base", name).unwrap(),
            None,
            "{name}"
        );
    }
}

#[test]
fn tracked_lists_follow_parent_type_not_lexical_path_nesting() {
    let f = frontend("/datum/base\n    var/list/items\n/datum/other\n    parent_type = /datum/base\n/datum/base/detached\n    parent_type = /datum\n    var/items\n");
    assert_eq!(
        list_type(&f.snapshot.tree, "/datum/other", "items")
            .unwrap()
            .as_deref(),
        Some("/list")
    );
    assert_eq!(
        list_type(&f.snapshot.tree, "/datum/base/detached", "items").unwrap(),
        None
    );
}

#[test]
fn tracked_marker_selection_borrows_original_markers_and_preserves_order() {
    let f = frontend("/datum/base\n    var/list/items\n    var/scalar\n");
    let markers = [
        ("/datum/base", "items", 10),
        ("/datum/base", "scalar", 20),
        ("/datum/base", "items", 30),
    ];
    let selected = select_tracked_list_markers(&f.snapshot.tree, &markers, |m| (m.0, m.1)).unwrap();
    assert_eq!(selected.iter().map(|m| m.2).collect::<Vec<_>>(), [10, 30]);
    assert!(std::ptr::eq(selected[0], &markers[0]));
    assert!(std::ptr::eq(selected[1], &markers[2]));
}

#[test]
fn unknown_intrinsic_field_is_not_silently_treated_as_a_non_list() {
    let f = frontend("/datum/base\n");
    assert!(!f.snapshot.tree.intrinsic_inventory_complete());
    assert!(list_type(&f.snapshot.tree, "/datum/base", "unknown").is_err());
}

#[test]
fn complete_fixture_inventory_can_prove_missing_fields() {
    let f = frontend("/datum/base\n");
    // This fixture intentionally has no runtime members; completeness here is
    // a fixture-issued contract, not a claim about production's builtin table.
    let hierarchy = dm_tree::EngineHierarchy {
        schema: 1,
        parents: f
            .snapshot
            .tree
            .types()
            .iter()
            .map(|t| {
                (
                    t.path,
                    t.parent.map(|p| f.snapshot.tree.type_node(p).unwrap().path),
                )
            })
            .collect(),
    };
    let tree = f
        .snapshot
        .tree
        .as_ref()
        .clone()
        .with_complete_intrinsics(hierarchy, vec![])
        .unwrap();
    assert_eq!(list_type(&tree, "/datum/base", "unknown").unwrap(), None);
}

#[test]
fn archive_declaration_queries_survive_frontend_release() {
    let archive = frontend("/datum/base\n    var/list/items\n")
        .body_archive()
        .unwrap();
    assert_eq!(
        list_type(archive.tree(), "/datum/base", "items")
            .unwrap()
            .as_deref(),
        Some("/list")
    );
}
