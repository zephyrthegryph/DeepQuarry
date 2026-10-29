use super::*;
use dm_tree::frontend::{build_with_config, ColdFrontend, FrontendConfig};
use std::path::Path;
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(source: &'static str) -> ColdFrontend {
    let seed = reference_hierarchy::seed();
    build_with_config(
        Path::new("variable-facts.dme"),
        &Source(source),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
}
#[test]
fn authored_formal_globals_and_fixed_sdk_fields_share_original_native_owner() {
    let front=build("var/datum/item/global_item\n/datum/item\n/datum/holder\n    var/datum/item/current\n/datum/holder/child\n    current = null\n");
    let tree = front.snapshot.tree.as_ref();
    let profile = tree.checker_builtin_profile().unwrap();
    let current = variable(
        tree,
        tree,
        profile,
        SymbolId::of("/datum/holder/child"),
        SymbolId::of("current"),
    )
    .unwrap()
    .unwrap();
    assert_eq!(current.owner, SymbolId::of("/datum/holder"));
    assert_eq!(
        current.metadata.declared_type,
        Some(SymbolId::of("/datum/item"))
    );
    assert_eq!(
        variable(
            tree,
            tree,
            profile,
            SymbolId::of("/datum/holder"),
            SymbolId::of("global_item")
        )
        .unwrap()
        .unwrap()
        .owner,
        SymbolId::of("/")
    );
    let field = variable(
        tree,
        tree,
        profile,
        SymbolId::of("/obj"),
        SymbolId::of("name"),
    )
    .unwrap()
    .unwrap();
    assert_eq!(field.owner, SymbolId::of("/atom"));
    assert!(variable(
        tree,
        tree,
        profile,
        SymbolId::of("/obj"),
        SymbolId::of("absent_in_both")
    )
    .unwrap()
    .is_none());
}
#[test]
fn equal_source_foreign_owner_or_profile_never_proves_variable_absence() {
    let a = build("/datum/holder\n");
    let b = build("/datum/holder\n");
    let tree = a.snapshot.tree.as_ref();
    let profile = tree.checker_builtin_profile().unwrap();
    assert_eq!(tree.identity(), b.snapshot.tree.identity());
    assert!(variable(
        tree,
        b.snapshot.tree.as_ref(),
        profile,
        SymbolId::of("/datum/holder"),
        SymbolId::of("absent")
    )
    .is_err());
    assert!(variable(
        tree,
        tree,
        PackedU128::new(profile.get() ^ 1),
        SymbolId::of("/datum/holder"),
        SymbolId::of("absent")
    )
    .is_err());
}
