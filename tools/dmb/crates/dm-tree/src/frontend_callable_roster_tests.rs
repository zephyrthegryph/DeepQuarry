use super::*;
use crate::frontend::{
    build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree,
};
use std::{collections::BTreeMap, path::Path};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(state: &mut RetainedSemanticTree, source: &'static str) -> super::super::ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("roster.dme"),
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
fn body_shift_reuses_indexes_with_current_source_and_structural_edits_replace_them() {
    let mut state = RetainedSemanticTree::default();
    let old = build(
        &mut state,
        "/datum/test/proc/p()\n    return 1\n/datum/test/p()\n    return 2\n",
    );
    let current = build(
        &mut state,
        "// shift\n/datum/test/proc/p()\n    return 3\n/datum/test/p()\n    return 2\n",
    );
    let old_roster = old.callable_roster().unwrap();
    let roster = current.callable_roster().unwrap();
    assert!(Arc::ptr_eq(old_roster, roster));
    assert_eq!(roster.members().len(), 2);
    let abi = current.callable_abi_roster().unwrap().unwrap();
    assert!(Arc::ptr_eq(
        old.callable_abi_roster().unwrap().unwrap(),
        abi
    ));
    assert_eq!(abi.entries()[0].predecessor, None);
    assert_eq!(abi.entries()[1].predecessor, Some(abi.entries()[0].member));
    assert_eq!(roster.ready(), &[0]);
    assert_eq!(roster.dependents(0), &[1]);
    assert_eq!(roster.identity(0).unwrap().occurrence, 0);
    assert_eq!(roster.identity(1).unwrap().occurrence, 1);
    assert_eq!(current.bodies[0].source.line, 2);
    assert_eq!(old.bodies[0].source.line, 1);
    let mut tampered = current.clone();
    tampered.bodies = Arc::clone(&old.bodies);
    assert!(tampered.callable_roster().is_err());
    assert!(tampered.callable_abi_roster().is_err());
    let changed = build(
        &mut state,
        "/datum/test/proc/p()\n    return 3\n/datum/test/proc/q()\n    return 2\n",
    );
    assert!(!Arc::ptr_eq(roster, changed.callable_roster().unwrap()));
    // Old request readers remain valid after replacement/clear.
    state.clear();
    assert_eq!(
        old_roster.identity(1).unwrap().name,
        dm_ir::SymbolId::of("p")
    );
}

#[test]
fn abi_roster_equality_covers_settings_signature_and_current_parent_structure() {
    let mut state = RetainedSemanticTree::default();
    let first = build(
        &mut state,
        "/datum/base/proc/p(x=1)\n    set waitfor = 0\n    return x\n/datum/base/child\n",
    );
    let before = first.callable_abi_roster().unwrap().unwrap();
    let shifted = build(&mut state, "// moved\n/datum/base/proc/p(x=1)\n    set waitfor = 0\n    return x+2\n/datum/base/child\n");
    assert!(before == shifted.callable_abi_roster().unwrap().unwrap());
    let signature = build(
        &mut state,
        "/datum/base/proc/p(x=2)\n    set waitfor = 0\n    return x\n/datum/base/child\n",
    );
    assert!(before != signature.callable_abi_roster().unwrap().unwrap());
    let settings = build(
        &mut state,
        "/datum/base/proc/p(x=1)\n    set waitfor = 1\n    return x\n/datum/base/child\n",
    );
    assert!(before != settings.callable_abi_roster().unwrap().unwrap());
    let ancestry = build(&mut state, "/datum/base/proc/p(x=1)\n    set waitfor = 0\n    return x\n/datum/base/child\n    parent_type = /datum\n");
    assert!(before != ancestry.callable_abi_roster().unwrap().unwrap());
}

#[test]
fn lexical_facade_rebind_reuses_graph_but_rejects_foreign_dense_layout() {
    let mut state = RetainedSemanticTree::default();
    let current = build(
        &mut state,
        "/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n",
    );
    let roster = current.callable_roster().unwrap();
    let mut facade = current.snapshot.tree.as_ref().clone();
    let mut symbols = facade.symbols().clone();
    let spelling = symbols.intern("new_body_spelling").unwrap();
    facade.symbols = Arc::new(symbols);
    let facade = Arc::new(facade);
    let rebound = roster.rebind_semantic_owner(&facade).unwrap();
    assert!(rebound.authenticates_tree(&facade));
    assert!(Arc::ptr_eq(&roster.index, &rebound.index));
    assert!(!rebound.authenticates_tree(&current.snapshot.tree));
    assert!(Arc::ptr_eq(roster.abi().unwrap(), rebound.abi().unwrap()));
    assert!(Arc::ptr_eq(
        roster.abi().unwrap().graph(),
        rebound.abi().unwrap().graph()
    ));
    assert_eq!(roster.members(), rebound.members());
    assert!(facade.symbols().text(spelling).is_some());
    assert!(current.snapshot.tree.symbols().text(spelling).is_none());
    let issued = CallableRoster::issue(&facade, &current.bodies).unwrap();
    assert_eq!(issued.abi().unwrap(), rebound.abi().unwrap());
    assert_eq!(issued.index.identities, rebound.index.identities);
    let changed = build(&mut state, "/var/inserted=1\n/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n");
    assert!(roster
        .rebind_semantic_owner(&changed.snapshot.tree)
        .is_none());
    let signature = build(
        &mut state,
        "/datum/a/proc/p(x=3)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n",
    );
    if let Some(rebound) = roster.rebind_semantic_owner(&signature.snapshot.tree) {
        let fresh = CallableRoster::issue(&signature.snapshot.tree, &signature.bodies).unwrap();
        assert!(Arc::ptr_eq(&roster.index, &rebound.index));
        assert_eq!(rebound.abi(), fresh.abi());
        assert_ne!(
            roster.abi().unwrap().graph(),
            rebound.abi().unwrap().graph()
        );
    }
}

#[test]
fn current_chunk_rebind_shares_index_and_refreshes_exact_abi_metadata() {
    let mut state = RetainedSemanticTree::default();
    let current = build(
        &mut state,
        "/var/unrelated=1\n/datum/a/proc/p(x=1)\n    return x\n",
    );
    let roster = current.callable_roster().unwrap();
    let mut facade = current.snapshot.tree.as_ref().clone();
    let member = roster.members()[0];
    // Body content is separately admitted by the current body/source producer.
    facade.members[member.index()].content ^= 1;
    let facade = Arc::new(facade);
    let rebound = roster.rebind_semantic_owner(&facade).unwrap();
    assert!(Arc::ptr_eq(&roster.index, &rebound.index));
    assert!(Arc::ptr_eq(roster.abi().unwrap(), rebound.abi().unwrap()));
    let issued = CallableRoster::issue(&facade, &current.bodies).unwrap();
    assert_eq!(issued.abi(), rebound.abi());

    let replacement = build(
        &mut RetainedSemanticTree::default(),
        "/var/unrelated=1\n/datum/a/proc/p(x=9)\n    return x\n",
    );
    let metadata = replacement
        .callable_abi_roster()
        .unwrap()
        .unwrap()
        .entries()[0]
        .metadata
        .clone();
    let mut facade = facade.as_ref().clone();
    Arc::make_mut(&mut facade.members[member.index()].metadata).procedure = Some(metadata);
    let facade = Arc::new(facade);
    let refreshed = rebound.rebind_semantic_owner(&facade).unwrap();
    assert!(Arc::ptr_eq(&roster.index, &refreshed.index));
    assert!(!Arc::ptr_eq(
        roster.abi().unwrap().graph(),
        refreshed.abi().unwrap().graph()
    ));
    let issued = CallableRoster::issue(&facade, &current.bodies).unwrap();
    assert_eq!(issued.abi(), refreshed.abi());
    assert!(refreshed.authenticates_tree(&facade));
    assert_eq!(
        roster.abi().unwrap().entries()[0].metadata,
        current.callable_abi_roster().unwrap().unwrap().entries()[0].metadata
    );

    let mut changed = facade.as_ref().clone();
    changed.members[member.index()].previous = Some(member);
    assert!(refreshed
        .rebind_semantic_owner(&Arc::new(changed))
        .is_none());
    let mut changed = facade.as_ref().clone();
    changed.members[member.index()].definition = crate::DefinitionMode::Override;
    assert!(refreshed
        .rebind_semantic_owner(&Arc::new(changed))
        .is_none());
}

#[test]
fn callable_source_recipe_reuses_exact_bindings_and_order_across_body_shifts() {
    let mut state = RetainedSemanticTree::default();
    let before = build(&mut state, "/datum/a/proc/p()\n    return 1\n/datum/a/p()\n    return 2\n/datum/a/verb/v()\n    return 3\n");
    let after = build(&mut state, "\n/datum/a/proc/p()\n    return 4\n/datum/a/p()\n    return 2\n/datum/a/verb/v()\n    return 3\n");
    let old = before.callable_roster().unwrap();
    let current = after.callable_roster().unwrap();
    assert!(Arc::ptr_eq(&old.index, &current.index));
    assert!(std::ptr::eq(
        old.source_bindings(),
        current.source_bindings()
    ));
    assert!(std::ptr::eq(old.source_order(), current.source_order()));
    let fresh = CallableRoster::issue(&after.snapshot.tree, &after.bodies).unwrap();
    assert_eq!(fresh.source_bindings(), current.source_bindings());
    assert_eq!(fresh.source_order(), current.source_order());
    for ordinal in 0..after.bodies.len() {
        assert_eq!(fresh.effective(ordinal), current.effective(ordinal));
    }
    let added = build(&mut state, "/datum/a/proc/p()\n    return 4\n/datum/a/p()\n    return 2\n/datum/a/verb/v()\n    return 3\n/proc/added()\n    return 5\n");
    let replacement = added.callable_roster().unwrap();
    assert!(!Arc::ptr_eq(&current.index, &replacement.index));
    assert_ne!(current.source_bindings(), replacement.source_bindings());
}
