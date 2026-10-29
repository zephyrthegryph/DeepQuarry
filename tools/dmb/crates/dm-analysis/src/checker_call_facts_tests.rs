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
fn frontend(source: &'static str) -> ColdFrontend {
    let seed = reference_hierarchy::seed();
    build_with_config(
        Path::new("call_facts.dme"),
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
fn fact(frontend: &ColdFrontend, owner: &str, name: &str) -> Result<CallableFact, String> {
    let tree = frontend.snapshot.tree.as_ref();
    let profile = tree.checker_builtin_profile().unwrap();
    callable(
        &frontend.snapshot.tree,
        tree,
        profile,
        SymbolId::of(owner),
        SymbolId::of(name),
        false,
    )
}
#[test]
fn source_and_checker_builtin_calls_use_one_qualified_native_resolver() {
    let frontend = frontend("/datum/base/proc/read(x)\n    return x\n/datum/base/child\n");
    assert!(
        matches!(fact(&frontend,"/datum/base/child","read").unwrap(),CallableFact::Source {identity,..} if identity.owner==SymbolId::of("/datum/base"))
    );
    assert!(
        matches!(fact(&frontend,"/datum/base/child","New").unwrap(),CallableFact::CheckerBuiltin {declaring_owner,..} if declaring_owner==SymbolId::of("/datum"))
    );
    assert_eq!(
        fact(&frontend, "/datum/base/child", "unknown_in_both_namespaces").unwrap(),
        CallableFact::Missing
    );
}
#[test]
fn pinned_root_globals_and_authored_names_follow_checker_ancestry() {
    let frontend = frontend("/datum/base/proc/abs(value)\n    return value\n/datum/other\n");
    assert!(
        matches!(fact(&frontend,"/","abs").unwrap(),CallableFact::CheckerBuiltin {declaring_owner,..} if declaring_owner==SymbolId::of("/"))
    );
    assert!(
        matches!(fact(&frontend,"/datum/other","abs").unwrap(),CallableFact::CheckerBuiltin {declaring_owner,..} if declaring_owner==SymbolId::of("/"))
    );
    assert!(matches!(
        fact(&frontend, "/datum/base", "abs").unwrap(),
        CallableFact::Source { .. }
    ));
}
#[test]
fn foreign_profile_never_certifies_builtin_absence() {
    let frontend = frontend("/datum/base\n");
    let original = frontend.snapshot.tree.as_ref();
    let tree = original;
    let profile = tree.checker_builtin_profile().unwrap();
    for (resolver, profile) in [(tree, PackedU128::new(profile.get() ^ 1))] {
        assert!(callable(
            original,
            resolver,
            profile,
            SymbolId::of("/datum/base"),
            SymbolId::of("absent"),
            false
        )
        .is_err());
    }
}
#[test]
fn source_only_positive_does_not_require_builtin_metadata_or_runtime_aliasing() {
    let frontend = frontend("/datum/base/proc/read()\n    return 1\n");
    let tree = frontend.snapshot.tree.as_ref();
    assert!(matches!(
        callable(
            tree,
            tree,
            PackedU128::new(0),
            SymbolId::of("/datum/base"),
            SymbolId::of("read"),
            false
        )
        .unwrap(),
        CallableFact::Source { .. }
    ));
}

#[test]
fn nearer_builtin_precedes_farther_authored_ancestor() {
    let frontend = frontend("/datum/proc/Login()\n    return 1\n/mob/example\n");
    assert!(
        matches!(fact(&frontend,"/mob/example","Login").unwrap(),CallableFact::CheckerBuiltin {declaring_owner,..} if declaring_owner==SymbolId::of("/mob"))
    );
}
