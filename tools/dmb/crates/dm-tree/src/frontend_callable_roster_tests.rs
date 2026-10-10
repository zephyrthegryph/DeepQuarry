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
