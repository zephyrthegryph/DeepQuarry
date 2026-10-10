use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, BodyArena, FrontendConfig, FrontendRevision,
};
use std::{collections::BTreeMap, path::Path};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn owned_declarations_reuse_with_fresh_current_file_and_source_issuance() {
    let source =
        "/obj/base\n    var/count=1\n/proc/p()\n    set name = \"Display\"\n    return 1\n";
    let mut state = RetainedSemanticTree::new();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let first = build_with_executor_and_semantic_state(
        Path::new("first.dme"),
        &Source(source),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
    )
    .unwrap();
    let second = build_with_executor_and_semantic_state(
        Path::new("second.dme"),
        &Source(source),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
    )
    .unwrap();
    assert!(state.declaration_retention_stats().hits > 0);
    assert!(Arc::ptr_eq(&first.snapshot.tree, &second.snapshot.tree));
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &second.snapshot.occurrences
    ));
    assert_eq!(
        second.bodies[0].source.path.file_name().unwrap(),
        "second.dme"
    );
    assert_eq!(
        first.bodies[0].source.path.file_name().unwrap(),
        "first.dme"
    );
    let arena = BodyArena::new(&second);
    assert!(arena.with_parsed(&first.bodies[0], |_| ()).is_err());
    assert!(arena.with_parsed(&second.bodies[0], |_| ()).is_ok());
}
fn build(state: &mut RetainedSemanticTree, source: &'static str) -> crate::frontend::ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("project.dme"),
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
fn body_edit_shares_semantics_but_issues_new_source_occurrences_and_body() {
    let mut state = RetainedSemanticTree::new();
    let first = FrontendRevision::new(build(
        &mut state,
        "/proc/p()\n    return 1\n/proc/q()\n    return 2\n",
    ));
    let original_issuance = first.issuance();
    let second = FrontendRevision::new(build(
        &mut state,
        "/proc/p()\n    return 12345\n/proc/q()\n    return 2\n",
    ));
    assert!(Arc::ptr_eq(&first.snapshot.tree, &second.snapshot.tree));
    let fresh_query = dm_ir::ResolveQuery::HasMemberVar {
        owner: dm_ir::SymbolId::of("/"),
        name: dm_ir::SymbolId::of("new_unqueried_name"),
    };
    // Exact normalization returns the admitted semantic owner; an unseen query
    // must still issue a live dependency receipt after current body rebinding.
    assert!(
        dm_ir::Resolver::domain_version(second.snapshot.tree.as_ref(), fresh_query.domain())
            .is_some()
    );
    assert!(!Arc::ptr_eq(
        &first.snapshot.occurrences,
        &second.snapshot.occurrences
    ));
    assert!(!original_issuance.matches(&second));
    assert_ne!(
        first.bodies[1].expanded_span.start,
        second.bodies[1].expanded_span.start
    );
    let arena = BodyArena::new(&second);
    assert!(arena.with_parsed(&first.bodies[0], |_| ()).is_err());
    let parsed = arena.take_parsed(&second.bodies[0]).unwrap();
    assert_eq!(parsed.item().children[0].header, "return 12345");
    assert_eq!((state.hits(), state.rebuilds()), (1, 1));
}
#[test]
fn ordered_declarations_and_defaults_invalidate_tree_and_match_fresh_result() {
    let mut state = RetainedSemanticTree::new();
    let first = build(&mut state, "var/a = 1\nvar/b = 2\n");
    let reordered = build(&mut state, "var/b = 2\nvar/a = 1\n");
    assert!(!Arc::ptr_eq(&first.snapshot.tree, &reordered.snapshot.tree));
    let changed = build(&mut state, "var/b = 2\nvar/a = 3\n");
    assert!(!Arc::ptr_eq(
        &reordered.snapshot.tree,
        &changed.snapshot.tree
    ));
    let fresh = build(&mut RetainedSemanticTree::new(), "var/b = 2\nvar/a = 3\n");
    assert_eq!(
        changed.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        changed.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    assert_eq!(
        (state.hits(), state.rebuilds(), state.metadata_updates()),
        (0, 2, 1)
    );
}
#[test]
fn stable_metadata_updates_inherited_arrays_storage_and_selector_negatives_match_full_build() {
    use dm_ir::{ResolveQuery as Q, Resolver, SymbolId};
    let before = "/datum/base\n    var/static/shared = 1\n    var/list/data[2]\n/datum/base/child\n    shared = 2\n    data = list(1)\n/datum/other\n    var/static/unrelated = 3\n";
    let after = "/datum/base\n    var/shared = 4\n    var/list/data[4]\n/datum/base/child\n    shared = 2\n    data = list(1)\n/datum/other\n    var/static/unrelated = 3\n";
    let mut state = RetainedSemanticTree::new();
    let original = build(&mut state, before);
    let updated = build(&mut state, after);
    let full = build(&mut RetainedSemanticTree::new(), after);
    assert_eq!((state.rebuilds(), state.metadata_updates()), (1, 1));
    assert_eq!(
        updated.snapshot.tree.identity(),
        full.snapshot.tree.identity()
    );
    assert_eq!(
        updated.snapshot.tree.declarations(),
        full.snapshot.tree.declarations()
    );
    for (current, expected) in updated
        .snapshot
        .tree
        .members()
        .iter()
        .zip(full.snapshot.tree.members())
    {
        assert_eq!(current.owner, expected.owner);
        assert_eq!(current.previous, expected.previous);
        assert_eq!(current.metadata, expected.metadata);
        assert_eq!(current.content, expected.content);
    }
    for owner in ["/datum/base", "/datum/base/child", "/datum/other"] {
        let owner = SymbolId::of(owner);
        for name in ["shared", "data", "unrelated", "missing"] {
            let name = SymbolId::of(name);
            for query in [
                Q::Var { owner, name },
                Q::VarStorage { owner, name },
                Q::DeclaredVarType { owner, name },
                Q::UniqueStaticVar(name),
            ] {
                assert_eq!(
                    Resolver::resolve(updated.snapshot.tree.as_ref(), query),
                    Resolver::resolve(full.snapshot.tree.as_ref(), query)
                );
            }
        }
    }
    let unrelated = SymbolId::of("unrelated");
    let old = original
        .snapshot
        .tree
        .members()
        .iter()
        .find(|member| member.name == unrelated)
        .unwrap();
    let new = updated
        .snapshot
        .tree
        .members()
        .iter()
        .find(|member| member.name == unrelated)
        .unwrap();
    assert!(Arc::ptr_eq(&old.metadata, &new.metadata));
    assert!(!Arc::ptr_eq(
        &original.snapshot.occurrences,
        &updated.snapshot.occurrences
    ));
}
#[test]
fn invalid_current_declaration_reports_current_origin_without_poisoning_retained_tree() {
    let mut state = RetainedSemanticTree::new();
    let valid = build(&mut state, "var/a = 1\n");
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let result = build_with_executor_and_semantic_state(
        Path::new("project.dme"),
        &Source("\n\nvar/a = 1\nvar/a = 2\n"),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
    );
    let errors = match result {
        Err(errors) => errors,
        Ok(_) => panic!("duplicate declaration accepted"),
    };
    assert!(errors.iter().any(|error| error
        .location
        .as_ref()
        .is_some_and(|location| location.line == 4)));
    let repeated = build(&mut state, "var/a = 1\n");
    assert!(Arc::ptr_eq(&valid.snapshot.tree, &repeated.snapshot.tree));
    assert_eq!((state.hits(), state.rebuilds()), (1, 1));
}
#[test]
fn keyed_retained_owners_share_across_metadata_and_structural_rebuilds() {
    let mut state = RetainedSemanticTree::new();
    build(
        &mut state,
        "/datum/a\n    var/value = 1\n/datum/b\n    var/other = 2\n",
    );
    let b = dm_ir::SymbolId::of("/datum/b");
    let a = dm_ir::SymbolId::of("/datum/a");
    let original_b = state
        .entry
        .as_ref()
        .unwrap()
        .index
        .owner(b)
        .unwrap()
        .clone();
    let original_a = state
        .entry
        .as_ref()
        .unwrap()
        .index
        .owner(a)
        .unwrap()
        .clone();
    build(
        &mut state,
        "/datum/a\n    var/value = 3\n/datum/b\n    var/other = 2\n",
    );
    let entry = state.entry.as_ref().unwrap();
    assert!(Arc::ptr_eq(&original_b, entry.index.owner(b).unwrap()));
    assert!(!Arc::ptr_eq(&original_a, entry.index.owner(a).unwrap()));
    assert_eq!((state.rebuilds(), state.metadata_updates()), (1, 1));
    let source =
        "/datum/a\n    var/value = 3\n    var/new_value = 4\n/datum/b\n    var/other = 2\n";
    let changed = build(&mut state, source);
    assert!(Arc::ptr_eq(
        &original_b,
        state.entry.as_ref().unwrap().index.owner(b).unwrap()
    ));
    let fresh = build(&mut RetainedSemanticTree::new(), source);
    assert_eq!(
        changed.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        changed.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    assert_eq!((state.rebuilds(), state.metadata_updates()), (2, 1));
}

#[test]
fn metadata_update_copies_only_dirty_member_chunks_and_preserves_old_snapshot() {
    fn source(value: usize) -> &'static str {
        let mut text = String::from("/datum/a\n");
        for index in 0..300 {
            let initial = if index == 0 { value } else { index };
            text.push_str(&format!("    var/v{index} = {initial}\n"));
        }
        Box::leak(text.into_boxed_str())
    }
    let mut state = RetainedSemanticTree::new();
    let original = build(&mut state, source(1));
    let changed_source = source(999);
    let changed = build(&mut state, changed_source);
    let fresh = build(&mut RetainedSemanticTree::new(), changed_source);
    assert_eq!(state.metadata_updates(), 1);
    let old = original.snapshot.tree.members();
    let new = changed.snapshot.tree.members();
    assert_eq!(old.len(), new.len());
    assert_eq!(old.chunks().len(), new.chunks().len());
    assert!(!Arc::ptr_eq(&old.chunks()[0], &new.chunks()[0]));
    for (old_chunk, new_chunk) in old.chunks().iter().zip(new.chunks()).skip(1) {
        assert!(Arc::ptr_eq(old_chunk, new_chunk));
    }
    for (actual, expected) in new.iter().zip(fresh.snapshot.tree.members()) {
        assert_eq!(actual.metadata, expected.metadata);
        assert_eq!(actual.content, expected.content);
        assert_eq!(actual.previous, expected.previous);
    }
    assert_ne!(old[0].metadata, new[0].metadata);
    assert_eq!(
        old.iter().next_back().unwrap().name,
        old[old.len() - 1].name
    );
    assert!(old.get(old.len()).is_none());
}

#[test]
fn structural_projection_reuses_unaffected_owner_normalization_and_matches_fresh() {
    let mut state = RetainedSemanticTree::new();
    build(
        &mut state,
        "/datum/a\n    var/x = 1\n/datum/a/child\n    x = 2\n/datum/b\n    var/y = 3\n",
    );
    let source="/datum/a\n    var/x = 1\n    var/added = 4\n/datum/a/child\n    x = 2\n/datum/b\n    var/y = 3\n";
    let actual = build(&mut state, source);
    let fresh = build(&mut RetainedSemanticTree::new(), source);
    assert!(state.normalization_hits() > 0);
    assert_eq!(
        actual.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        actual.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    for (actual, expected) in actual
        .snapshot
        .tree
        .members()
        .iter()
        .zip(fresh.snapshot.tree.members())
    {
        assert_eq!(actual.owner, expected.owner);
        assert_eq!(actual.kind, expected.kind);
        assert_eq!(actual.previous, expected.previous);
        assert_eq!(actual.metadata, expected.metadata);
    }
}

#[test]
fn structural_metadata_reuses_unaffected_owners_and_invalidates_inherited_flags() {
    let mut state = RetainedSemanticTree::new();
    let before =
        "/datum/a\n    var/static/x = 1\n/datum/a/child\n    x = 2\n/datum/b\n    var/y = 3\n";
    build(&mut state, before);
    let with_added = "/datum/a\n    var/static/x = 1\n    var/added = 4\n/datum/a/child\n    x = 2\n/datum/b\n    var/y = 3\n";
    build(&mut state, with_added);
    assert!(state.metadata_owner_hits() > 0);
    let previous_hits = state.metadata_owner_hits();
    // This structural edit also changes x storage, which must invalidate the
    // child's effective metadata despite an unchanged selected predecessor key.
    let changed = "/datum/a\n    var/x = 1\n    var/added = 4\n    var/another = 5\n/datum/a/child\n    x = 2\n/datum/b\n    var/y = 3\n";
    let actual = build(&mut state, changed);
    let fresh = build(&mut RetainedSemanticTree::new(), changed);
    assert_eq!(state.metadata_owner_hits() - previous_hits, 1);
    assert_eq!(
        actual.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    for (actual, expected) in actual
        .snapshot
        .tree
        .members()
        .iter()
        .zip(fresh.snapshot.tree.members())
    {
        assert_eq!(actual.owner, expected.owner);
        assert_eq!(actual.previous, expected.previous);
        assert_eq!(actual.metadata, expected.metadata);
    }
    use dm_ir::{ResolveQuery, Resolver};
    let query = ResolveQuery::VarStorage {
        owner: dm_ir::SymbolId::of("/datum/a/child"),
        name: dm_ir::SymbolId::of("x"),
    };
    assert_eq!(
        Resolver::resolve(actual.snapshot.tree.as_ref(), query),
        Resolver::resolve(fresh.snapshot.tree.as_ref(), query)
    );
}

#[test]
fn structural_edits_reuse_local_shapes_and_preserve_formal_before_implicit_order() {
    let mut state = RetainedSemanticTree::new();
    build(&mut state,"/datum/a\n    var/x = 1\n    callback()\n        return 1\n    proc/callback()\n        return 2\n/datum/b\n    var/y = 3\n");
    let source="/datum/a\n    var/x = 1\n    var/added = 4\n    callback()\n        return 1\n    proc/callback()\n        return 2\n/datum/b\n    var/y = 3\n";
    let actual = build(&mut state, source);
    let fresh = build(&mut RetainedSemanticTree::new(), source);
    assert!(state.local_shape_hits() > 0);
    assert_eq!(
        actual.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        actual.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    for (actual, expected) in actual
        .snapshot
        .tree
        .members()
        .iter()
        .zip(fresh.snapshot.tree.members())
    {
        assert_eq!(actual.kind, expected.kind);
        assert_eq!(actual.previous, expected.previous);
        assert_eq!(actual.metadata, expected.metadata);
    }
}
#[test]
fn changed_inherited_callable_anchor_invalidates_local_shape() {
    let mut state = RetainedSemanticTree::new();
    build(&mut state,"/datum/a\n    proc/callback()\n        return 1\n/datum/a/child\n    callback()\n        return 2\n");
    let source="/datum/a\n    verb/callback()\n        return 1\n/datum/a/child\n    callback()\n        return 2\n";
    let actual = build(&mut state, source);
    let fresh = build(&mut RetainedSemanticTree::new(), source);
    for (actual, expected) in actual
        .snapshot
        .tree
        .members()
        .iter()
        .zip(fresh.snapshot.tree.members())
    {
        assert_eq!(actual.kind, expected.kind);
        assert_eq!(actual.previous, expected.previous);
    }
    let child = dm_ir::SymbolId::of("/datum/a/child");
    let member = actual
        .snapshot
        .tree
        .members()
        .iter()
        .find(|member| actual.snapshot.tree.types()[member.owner.index()].path == child)
        .unwrap();
    assert_eq!(member.kind, crate::MemberKind::Verb);
}
#[test]
fn mutated_overlay_cannot_reuse_or_store_the_old_catalog_receipt() {
    let source = Arc::new(dm_ir::SymbolTable::default());
    let catalog = super::super::symbol_catalog::SymbolCatalog::capture(None, source, None).unwrap();
    let make = || crate::SharedAdaptedDeclarations {
        symbols: dm_ir::SymbolTable::overlay(Arc::clone(&catalog.symbols)),
        symbol_catalog: Some(Arc::clone(&catalog)),
        skeletons: crate::skeleton_roster::SkeletonRoster::default(),
        origins: Vec::new().into(),
    };
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = RetainedSemanticTree::new();
    state
        .resolve(
            make(),
            None,
            |_, _, _| panic!("unexpected resolution error"),
            &executor,
        )
        .unwrap();
    assert!(state.entry.as_ref().unwrap().symbol_catalog.is_some());
    let mut changed = make();
    changed.symbols.intern("new_current_spelling").unwrap();
    state
        .resolve(
            changed,
            None,
            |_, _, _| panic!("unexpected resolution error"),
            &executor,
        )
        .unwrap();
    assert_eq!(state.hits, 0);
    assert!(state.entry.as_ref().unwrap().symbol_catalog.is_none());
    assert!(state
        .entry
        .as_ref()
        .unwrap()
        .symbols
        .iter()
        .any(|(_, text)| text == "new_current_spelling"));
}

/// Retained frontend state only: this does not exercise daemon transport or exits.
#[test]
fn retained_resolution_failure_repeat_shift_and_repair_match_fresh_diagnostics() {
    use crate::frontend::Diagnostic;
    fn attempt(
        state: &mut RetainedSemanticTree,
        source: &'static str,
        path: &str,
        executor: &dm_exec::BuildExecutor,
    ) -> Result<crate::frontend::ColdFrontend, Vec<Diagnostic>> {
        build_with_executor_and_semantic_state(
            Path::new(path),
            &Source(source),
            &BTreeMap::new(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            executor,
            Some(state),
        )
    }
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut retained = RetainedSemanticTree::new();
    let valid = "/datum/a\n/datum/b\n/datum/child\n    parent_type = /datum/a\n";
    let invalid = "/datum/a\n/datum/b\n/datum/child\n    parent_type = /datum/a\n/datum/child\n    parent_type = /datum/b\n";
    let shifted = "// current prefix\n// second prefix\n/datum/a\n/datum/b\n/datum/child\n    parent_type = /datum/a\n/datum/child\n    parent_type = /datum/b\n";
    let initial = attempt(&mut retained, valid, "old.dme", &executor).unwrap();
    let mut first_line = None;
    for (source, path) in [
        (invalid, "old.dme"),
        (invalid, "old.dme"),
        (shifted, "current.dme"),
    ] {
        let current = attempt(&mut retained, source, path, &executor).unwrap_err();
        let fresh = attempt(&mut RetainedSemanticTree::new(), source, path, &executor).unwrap_err();
        assert_eq!(format!("{current:?}"), format!("{fresh:?}"));
        let error = current
            .iter()
            .find(|error| error.message.contains("ConflictingParent"))
            .expect("independent conflicting parent source must fail resolution");
        assert_eq!(error.kind, crate::frontend::DiagnosticKind::SourceError);
        let location = error
            .location
            .as_ref()
            .expect("current authored failure location");
        assert_eq!(location.path.as_path(), Path::new(path));
        if path == "old.dme" {
            if let Some(previous) = first_line {
                assert_eq!(location.line, previous);
            }
            first_line = Some(location.line);
        } else {
            assert_eq!(location.line, first_line.unwrap() + 2);
        }
    }
    let repaired = attempt(&mut retained, valid, "current.dme", &executor).unwrap();
    let fresh = attempt(
        &mut RetainedSemanticTree::new(),
        valid,
        "current.dme",
        &executor,
    )
    .unwrap();
    assert_eq!(
        repaired.snapshot.tree.identity(),
        fresh.snapshot.tree.identity()
    );
    assert_eq!(
        repaired.snapshot.tree.declarations(),
        fresh.snapshot.tree.declarations()
    );
    let current_order = repaired.snapshot.occurrences.source_order();
    let fresh_order = fresh.snapshot.occurrences.source_order();
    assert_eq!(current_order.len(), fresh_order.len());
    for (current, expected) in current_order.iter().zip(fresh_order) {
        assert_eq!(current.target, expected.target);
        assert_eq!(current.provenance, expected.provenance);
    }
    for &target in repaired.snapshot.tree.declarations() {
        assert_eq!(
            repaired.snapshot.occurrences.for_target(target),
            fresh.snapshot.occurrences.for_target(target)
        );
    }
    assert_eq!(
        initial.snapshot.tree.identity(),
        repaired.snapshot.tree.identity()
    );
    assert!(retained.declaration_retention_stats().hits > 0);
}

#[test]
fn admitted_reused_tree_restores_demand_issuer_after_abandoned_candidate() {
    let mut state = RetainedSemanticTree::new();
    let first = build(&mut state, "/proc/p()\n    return 1\n");
    let mut abandoned = first.snapshot.tree.as_ref().clone();
    abandoned.owner_callable_demands = Arc::new(crate::owner_metadata::CallableDemands::default());
    state
        .normalization
        .metadata
        .bind_selection_owner(&abandoned);
    drop(abandoned);
    let reused = build(&mut state, "/proc/p()\n    return 2\n");
    assert!(Arc::ptr_eq(&first.snapshot.tree, &reused.snapshot.tree));
    let query = dm_ir::ResolveQuery::HasMemberProc {
        owner: dm_ir::SymbolId::of("/"),
        name: dm_ir::SymbolId::of("previously_unqueried"),
    };
    assert!(
        dm_ir::Resolver::domain_version(reused.snapshot.tree.as_ref(), query.domain()).is_some()
    );
}
