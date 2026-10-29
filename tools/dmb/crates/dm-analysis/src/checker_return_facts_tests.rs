use super::*;
use dm_tree::frontend::{build_with_config,ColdFrontend,FrontendConfig};
use std::path::Path;
#[path="../examples/support/reference_hierarchy.rs"] mod reference_hierarchy;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {fn read(&self,_:&Path)->Result<String,String>{Ok(self.0.into())}}
fn build(source:&'static str)->ColdFrontend {
    let seed=reference_hierarchy::seed();
    build_with_config(Path::new("return-facts.dme"),&Source(source),&Default::default(),FrontendConfig{workers:1,engine:Some(&seed),observer:None}).unwrap()
}
#[test]
fn root_builtin_returns_require_exact_catalog_identity_and_preserve_dead_argslist_typo() {
    let front=build("");let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();
    for (name,base,element) in [
        ("get_step",Some("/turf"),None),
        ("block",Some("/list"),Some("/turf")),
        ("range",Some("/list"),Some("/atom")),
        ("viewers",Some("/list"),Some("/mob")),
        ("arglist",None,None),("abs",None,None),
    ] {
        let fact=return_hint(tree,tree,profile,SymbolId::of("/"),SymbolId::of(name)).unwrap();
        assert_eq!(fact,ReturnHint{declared_type:base.map(SymbolId::of),list_element_type:element.map(SymbolId::of)},"{name}");
    }
    assert!(return_hint(tree,tree,profile,SymbolId::of("/"),SymbolId::of("argslist")).is_err());
}
#[test]
fn source_override_borrows_its_formal_header_return_without_evaluating_defaults() {
    let front=build("/datum/target\n/datum/base/proc/make(datum/arg=missing_default()) as /datum/target\n    return null\n/datum/base/child/make(datum/arg)\n    return null\n");
    let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();
    assert_eq!(return_hint(tree,tree,profile,SymbolId::of("/datum/base/child"),SymbolId::of("make")).unwrap(),ReturnHint::direct("/datum/target"));
}
#[test]
fn settings_and_foreign_profile_or_owner_cannot_be_used_as_static_return_proof() {
    let front=build("/datum/target\n/proc/make()\n    set SpacemanDMM_return_type=/datum/target\n    return null\n");
    let tree=front.snapshot.tree.as_ref();let profile=tree.checker_builtin_profile().unwrap();
    assert!(return_hint(tree,tree,profile,SymbolId::of("/"),SymbolId::of("make")).unwrap_err().contains("contiguous-prefix"));
    let foreign=build("/datum/target\n/proc/make()\n    set SpacemanDMM_return_type=/datum/target\n    return null\n");
    assert!(return_hint(tree,foreign.snapshot.tree.as_ref(),profile,SymbolId::of("/"),SymbolId::of("get_step")).is_err());
    assert!(return_hint(tree,tree,PackedU128::new(profile.get()^1),SymbolId::of("/"),SymbolId::of("get_step")).is_err());
}
