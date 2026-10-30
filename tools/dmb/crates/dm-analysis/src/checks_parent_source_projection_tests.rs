//! Exact original checker SOURCE predecessor, distinct from runtime namespaces.
use super::*;
use dm_ir::SymbolId;
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
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
fn try_build(source: &str) -> Result<ColdFrontend, Vec<dm_tree::frontend::Diagnostic>> {
    let seed = reference_hierarchy::seed();
    dm_tree::frontend::build_with_config(
        Path::new("source-parent.dme"),
        &Source(AcquiredSource::from_original_bytes(
            source.as_bytes().to_vec(),
            (),
        )),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
}
fn build(source: &str) -> ColdFrontend {
    try_build(source).unwrap()
}
fn member(front: &ColdFrontend, owner: &str, name: &str, verb: bool) -> MemberId {
    front
        .snapshot
        .tree
        .declarations()
        .iter()
        .find_map(|target| {
            let dm_tree::Target::Member(id) = target else {
                return None;
            };
            let m = front.snapshot.tree.member(*id)?;
            let o = front.snapshot.tree.type_node(m.owner)?;
            (o.path == SymbolId::of(owner)
                && m.name == SymbolId::of(name)
                && m.kind
                    == if verb {
                        MemberKind::Verb
                    } else {
                        MemberKind::Proc
                    })
            .then_some(*id)
        })
        .unwrap()
}
#[test]
fn existing_presence_and_call_facts_and_exact_projection_share_original_global_fallback() {
    let front = build(include_str!(
        "../../../fixtures/unified_checks/purity/global-source/probe.dme"
    ));
    let tree = front.snapshot.tree.as_ref();
    let profile = tree.checker_builtin_profile().unwrap();
    let m = member(&front, "/datum/box", "write", false);
    let parent = parent_fact_in_profile(tree, m, tree, Some(profile)).unwrap();
    assert!(
        parent.has_parent,
        "existing presence helper already includes pinned global source parent"
    );
    let SourcePredecessorProjection::Source(id) =
        source_predecessor_in_profile(tree, m, tree, profile).unwrap()
    else {
        panic!("exact global source predecessor must be projected")
    };
    assert_eq!(id.owner, SymbolId::of("/"));
    assert_eq!(id.name, SymbolId::of("write"));
    assert!(!id.verb);
    let original = crate::checker_call_facts::callable_any(
        tree,
        tree,
        profile,
        SymbolId::of("/datum"),
        SymbolId::of("write"),
    )
    .unwrap();
    assert!(
        matches!(original,crate::checker_call_facts::CallableFact::Source{identity,..}if identity==id)
    );
    assert_eq!(
        source_predecessor_in_profile(tree, member(&front, "/", "check", false), tree, profile)
            .unwrap(),
        SourcePredecessorProjection::NoParent
    );
}
#[test]
fn builtin_presence_never_turns_into_an_absent_parent_without_an_issued_target() {
    let front = build(include_str!(
        "../../../fixtures/unified_checks/purity/builtin-root/probe.dme"
    ));
    let tree = front.snapshot.tree.as_ref();
    let profile = tree.checker_builtin_profile().unwrap();
    let m = member(&front, "/datum/box", "sleep", false);
    assert!(
        parent_fact_in_profile(tree, m, tree, Some(profile))
            .unwrap()
            .has_parent
    );
    assert_eq!(
        source_predecessor_in_profile(tree, m, tree, profile).unwrap(),
        SourcePredecessorProjection::BuiltinBoundary
    );
    assert!(source_predecessor_in_profile(tree, m, tree, 0.into()).is_err());
}
#[test]
fn exact_projection_refuses_unissued_unified_namespace_order_instead_of_selecting_a_parent() {
    let source =
        "/datum/base/proc/probe()\n    return\n/datum/base/child/verb/probe()\n    return\n";
    let front = match try_build(source) {
        Ok(front) => front,
        Err(errors) => {
            // The original native builder currently cannot issue this valid old
            // unified-namespace source. Keep that real refusal at entry rather
            // than fabricating an ambiguous tree to reach the projection helper.
            assert_eq!(errors.len(), 1, "{errors:?}");
            let error = &errors[0];
            assert_eq!(error.kind, dm_tree::frontend::DiagnosticKind::SourceError);
            assert_eq!(error.stage, dm_tree::frontend::DiagnosticStage::Resolution);
            assert_eq!(error.message, "probe: duplicate definition");
            let location = error
                .location
                .as_ref()
                .expect("actual duplicate source origin");
            assert_eq!(location.path.as_path(), Path::new("source-parent.dme"));
            assert_eq!(location.line, 3);
            assert_eq!((location.span.start, location.span.end), (36, 67));
            return;
        }
    };
    let tree = front.snapshot.tree.as_ref();
    let profile = tree.checker_builtin_profile().unwrap();
    let m = member(&front, "/datum/base/child", "probe", true);
    assert!(
        parent_fact_in_profile(tree, m, tree, Some(profile))
            .unwrap()
            .has_parent
    );
    assert!(source_predecessor_in_profile(tree, m, tree, profile)
        .unwrap_err()
        .contains("unified"));
}
#[test]
fn nearer_original_builtin_precedes_both_global_and_farther_source_ancestors() {
    for source in [
        "/proc/Move()\n    return\n/mob/child/Move()\n    return\n",
        "/atom/proc/Move()\n    return\n/mob/child/Move()\n    return\n",
    ] {
        let front = build(source);
        let tree = front.snapshot.tree.as_ref();
        let profile = tree.checker_builtin_profile().unwrap();
        let m = member(&front, "/mob/child", "Move", false);
        assert_eq!(
            source_predecessor_in_profile(tree, m, tree, profile).unwrap(),
            SourcePredecessorProjection::BuiltinBoundary,
            "native source.previous cannot skip nearer original builtin /atom/movable/Move"
        );
    }
}
#[test]
fn same_owner_builtin_source_collision_cannot_escape_through_no_parent() {
    let front = build("/proc/sleep()\n    return\n");
    let tree = front.snapshot.tree.as_ref();
    let profile = tree.checker_builtin_profile().unwrap();
    let m = member(&front, "/", "sleep", false);
    assert!(source_predecessor_in_profile(tree, m, tree, profile)
        .unwrap_err()
        .contains("same-owner"));
}
