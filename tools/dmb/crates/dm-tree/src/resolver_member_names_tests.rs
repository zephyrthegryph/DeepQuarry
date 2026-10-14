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

#[test]
fn demanded_verb_namespace_receipts_track_proc_priority_and_old_readers() {
    use dm_ir::{ResolveQuery, Resolver};
    fn current(state: &mut RetainedSemanticTree, source: &'static str) -> ColdFrontend {
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
            Path::new("selector.dme"),
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
    }
    let mut state = RetainedSemanticTree::default();
    let query = ResolveQuery::MemberCallableVerbName(SymbolId::of("choice"));
    let first = current(&mut state, "/datum/a/verb/choice()\n    return 1\n");
    let token = first.snapshot.tree.domain_version(query.domain()).unwrap();
    assert_eq!(
        Resolver::resolve(first.snapshot.tree.as_ref(), query),
        dm_ir::ResolvedMeaning::Presence(true)
    );
    let unrelated = current(
        &mut state,
        "// shift\n/datum/a/verb/choice()\n    return 2\n/datum/b/proc/other()\n    return 3\n",
    );
    assert_eq!(
        unrelated.snapshot.tree.domain_version(query.domain()),
        Some(token)
    );
    let mixed = current(
        &mut state,
        "/datum/a/verb/choice()\n    return 2\n/datum/b/proc/choice()\n    return 3\n",
    );
    let mixed_token = mixed.snapshot.tree.domain_version(query.domain()).unwrap();
    assert_ne!(mixed_token, token);
    assert_eq!(
        Resolver::resolve(mixed.snapshot.tree.as_ref(), query),
        dm_ir::ResolvedMeaning::Presence(false)
    );
    assert_eq!(
        first.snapshot.tree.domain_version(query.domain()),
        Some(token)
    );
    let old_unqueried = ResolveQuery::MemberCallableVerbName(SymbolId::of("other"));
    assert_eq!(
        first.snapshot.tree.domain_version(old_unqueried.domain()),
        None
    );
    let removed = current(&mut state, "/datum/a/verb/choice()\n    return 2\n");
    assert_ne!(
        removed.snapshot.tree.domain_version(query.domain()),
        Some(mixed_token)
    );
    assert_eq!(
        Resolver::resolve(removed.snapshot.tree.as_ref(), query),
        dm_ir::ResolvedMeaning::Presence(true)
    );
    let incomplete = build(
        &mut RetainedSemanticTree::default(),
        "/datum/a/verb/choice()\n    return 2\n",
    );
    assert_eq!(
        incomplete.snapshot.tree.domain_version(query.domain()),
        None
    );
}

#[test]
fn global_member_absence_tracks_other_owner_addition_without_changing_local_selection() {
    use dm_ir::{ResolveQuery, Resolver};
    fn current(state: &mut RetainedSemanticTree, source: &'static str) -> ColdFrontend {
        let mut symbols = dm_ir::SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let datum = symbols.intern("/datum").unwrap();
        let list = symbols.intern("/list").unwrap();
        let seed = crate::frontend::EngineSeed {
            identity: 19,
            symbols,
            hierarchy: crate::EngineHierarchy {
                schema: 19,
                parents: vec![(root, None), (datum, Some(root)), (list, Some(datum))],
            },
            intrinsics: Vec::new().into(),
            fields: Vec::new().into(),
        };
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        build_with_executor_and_semantic_state(
            Path::new("absence.dme"),
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
    }
    let mut state = RetainedSemanticTree::default();
    let name = SymbolId::of("formerly_missing");
    let global = ResolveQuery::MemberCallableName(name);
    let local = ResolveQuery::Proc {
        owner: SymbolId::of("/list"),
        name,
        verb: false,
    };
    let first = current(&mut state, "/datum/anchor/proc/keep()\n    return 1\n");
    let first_tree = first.snapshot.tree.as_ref();
    assert_eq!(first_tree.source_member_callable_name(name), Some(false));
    let absent_token = first_tree.domain_version(global.domain()).unwrap();
    let local_token = first_tree.domain_version(local.domain()).unwrap();
    assert_eq!(
        Resolver::resolve(first_tree, local),
        dm_ir::ResolvedMeaning::Unsupported(local)
    );
    let added = current(&mut state,"/datum/anchor/proc/keep()\n    return 1\n/datum/unrelated/proc/formerly_missing()\n    return 2\n");
    let added_tree = added.snapshot.tree.as_ref();
    assert_eq!(added_tree.source_member_callable_name(name), Some(true));
    let present_token = added_tree.domain_version(global.domain()).unwrap();
    assert_ne!(present_token, absent_token);
    assert_eq!(added_tree.domain_version(local.domain()), Some(local_token));
    assert_eq!(
        Resolver::resolve(added_tree, local),
        dm_ir::ResolvedMeaning::Unsupported(local)
    );
    let removed = current(&mut state, "/datum/anchor/proc/keep()\n    return 1\n");
    let removed_tree = removed.snapshot.tree.as_ref();
    assert_eq!(removed_tree.source_member_callable_name(name), Some(false));
    assert_ne!(
        removed_tree.domain_version(global.domain()),
        Some(present_token)
    );
    assert_eq!(
        removed_tree.domain_version(local.domain()),
        Some(local_token)
    );
    // Old readers retain exact issued meanings, never the current namespace.
    assert_eq!(
        first_tree.domain_version(global.domain()),
        Some(absent_token)
    );
    assert_eq!(first_tree.source_member_callable_name(name), Some(false));
    assert_eq!(
        added_tree.domain_version(global.domain()),
        Some(present_token)
    );
    assert_eq!(added_tree.source_member_callable_name(name), Some(true));
}

#[test]
fn stable_roster_metadata_edits_preserve_authenticated_member_name_owner() {
    let mut state = RetainedSemanticTree::default();
    let first = build(
        &mut state,
        "/datum/a\n    var/value = 1\n    proc/member(arg = 2)\n        return arg\n",
    );
    let changed = build(
        &mut state,
        "/datum/a\n    var/value = 3\n    proc/member(arg = 4)\n        return arg\n",
    );
    let fresh = build(
        &mut RetainedSemanticTree::default(),
        "/datum/a\n    var/value = 3\n    proc/member(arg = 4)\n        return arg\n",
    );
    assert!(!Arc::ptr_eq(&first.snapshot.tree, &changed.snapshot.tree));
    assert!(Arc::ptr_eq(
        first.snapshot.tree.member_callable_name_storage(),
        changed.snapshot.tree.member_callable_name_storage()
    ));
    assert_eq!(
        changed.snapshot.tree.member_callable_name_storage(),
        fresh.snapshot.tree.member_callable_name_storage()
    );
    assert_eq!(
        changed
            .snapshot
            .tree
            .member_callable_name_storage()
            .get(&SymbolId::of("member")),
        Some(&1)
    );
    // The semantic update is real, even though declaration-name authority stays
    // unchanged. Exact query replay must observe the new default.
    let query = dm_ir::ResolveQuery::Var {
        owner: SymbolId::of("/datum/a"),
        name: SymbolId::of("value"),
    };
    assert_ne!(
        dm_ir::Resolver::resolve(first.snapshot.tree.as_ref(), query),
        dm_ir::Resolver::resolve(changed.snapshot.tree.as_ref(), query)
    );
}
