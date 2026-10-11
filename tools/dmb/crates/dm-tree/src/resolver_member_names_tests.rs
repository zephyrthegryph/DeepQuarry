use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, ColdFrontend, FrontendConfig, RetainedSemanticTree,
};
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(state: &mut RetainedSemanticTree, source: &'static str) -> ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("member_names.dme"),
        &Source(source),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(state),
    )
    .unwrap()
}

#[test]
fn retained_member_name_inventory_tracks_add_delete_and_keeps_old_readers() {
    let mut state = RetainedSemanticTree::default();
    let first = build(
        &mut state,
        "/proc/root_only()\n    return 1\n/datum/a/proc/member()\n    return 1\n",
    );
    let original = first.snapshot.tree.member_callable_name_storage();
    assert_eq!(original.len(), 1);
    assert!(original.contains_key(&SymbolId::of("member")));
    assert!(!original.contains_key(&SymbolId::of("root_only")));

    let shifted = build(
        &mut state,
        "// source shift\n/proc/root_only()\n    return 2\n/datum/a/proc/member()\n    return 3\n",
    );
    assert!(Arc::ptr_eq(
        original,
        shifted.snapshot.tree.member_callable_name_storage()
    ));

    let added = build(&mut state,
        "/proc/root_only()\n    return 1\n/datum/a/proc/member()\n    return 1\n/datum/b/proc/new_member()\n    return 2\n");
    let additions = added.snapshot.tree.member_callable_name_storage();
    assert!(!Arc::ptr_eq(original, additions));
    assert!(additions.contains_key(&SymbolId::of("new_member")));
    assert!(!original.contains_key(&SymbolId::of("new_member")));

    let deleted = build(
        &mut state,
        "/proc/root_only()\n    return 1\n/datum/b/proc/new_member()\n    return 2\n",
    );
    let current = deleted.snapshot.tree.member_callable_name_storage();
    assert!(!current.contains_key(&SymbolId::of("member")));
    assert!(current.contains_key(&SymbolId::of("new_member")));
    assert!(original.contains_key(&SymbolId::of("member")));
    assert!(additions.contains_key(&SymbolId::of("member")));
}

#[test]
fn source_verbs_issue_member_name_availability_without_admitting_globals() {
    let mut state = RetainedSemanticTree::default();
    let output = build(
        &mut state,
        "/proc/root_only()\n    return 1\n/datum/a/verb/verb_only()\n    return 1\n",
    );
    let tree = &output.snapshot.tree;
    assert_eq!(
        tree.source_member_callable_name(SymbolId::of("verb_only")),
        Some(true)
    );
    assert_eq!(
        tree.source_member_callable_name(SymbolId::of("root_only")),
        None
    );
    assert_eq!(
        tree.source_member_callable_name(SymbolId::of("absent")),
        None
    );
}

#[test]
fn demanded_member_name_receipt_survives_unrelated_edits_and_tracks_absence() {
    use dm_ir::{ResolveQuery, Resolver};
    let mut state = RetainedSemanticTree::default();
    let build_admitted = |state: &mut RetainedSemanticTree, source| {
        // Exercise production engine attachment before final issuer publication.
        // Post-hoc with_complete_intrinsics would publish two distinct revisions
        // and intentionally prune demands not read in the intermediate revision.
        let mut symbols = dm_ir::SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let datum = symbols.intern("/datum").unwrap();
        let seed = crate::frontend::EngineSeed {
            identity: 19,
            symbols,
            hierarchy: crate::EngineHierarchy {
                schema: 19,
                parents: vec![(root, None), (datum, Some(root))],
            },
            intrinsics: Vec::new().into(),
            fields: Vec::new().into(),
        };
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        build_with_executor_and_semantic_state(
            Path::new("member_names.dme"),
            &Source(source),
            &BTreeMap::new(),
            FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
            None,
            &executor,
            Some(state),
        )
        .unwrap()
    };
    let first = build_admitted(&mut state, "/datum/a/proc/member()\n    return 1\n");
    let first_admitted = &first.snapshot.tree;
    let absent = ResolveQuery::MemberCallableName(SymbolId::of("future"));
    let present = ResolveQuery::MemberCallableName(SymbolId::of("member"));
    let version = first_admitted.domain_version(absent.domain()).unwrap();
    let member_version = first_admitted.domain_version(present.domain()).unwrap();
    assert_eq!(
        build(
            &mut RetainedSemanticTree::default(),
            "/datum/a/proc/member()\n    return 1\n"
        )
        .snapshot
        .tree
        .domain_version(absent.domain()),
        None,
        "incomplete source cannot borrow admitted negative"
    );
    let unrelated = build_admitted(
        &mut state,
        "/datum/a/proc/member()\n    return 1\n/datum/b/proc/other()\n    return 2\n",
    );
    let unrelated = &unrelated.snapshot.tree;
    assert_eq!(unrelated.domain_version(absent.domain()), Some(version));
    assert_eq!(
        unrelated.domain_version(present.domain()),
        Some(member_version)
    );
    let changed = build_admitted(
        &mut state,
        "// shifted\n/datum/a/proc/member()\n    return 3\n/datum/b/verb/future()\n    return 4\n",
    );
    let changed = &changed.snapshot.tree;
    assert_ne!(changed.domain_version(absent.domain()), Some(version));
    assert_eq!(
        Resolver::resolve(changed.as_ref(), absent),
        dm_ir::ResolvedMeaning::Presence(true)
    );
    assert_eq!(
        first_admitted.domain_version(absent.domain()),
        Some(version),
        "old issued snapshot remains immutable"
    );
    let unqueried = ResolveQuery::MemberCallableName(SymbolId::of("never_queried"));
    assert_eq!(
        first_admitted.domain_version(unqueried.domain()),
        None,
        "old unqueried cannot mint current authority"
    );
}
