//! The change-set splice must produce exactly the fresh constructor's tree for
//! added, removed and changed member rows, including inherited chains, typed
//! arrays, parent_type parents and chained edits; other edits must decline.
use crate::frontend::{build_with_executor_and_semantic_state, FrontendConfig, RetainedSemanticTree};
use std::{collections::BTreeMap, path::Path};

struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn frontend(state: &mut RetainedSemanticTree, source: &str) -> crate::frontend::ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("splice.dme"),
        &Source(source.to_string()),
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
fn same_as_fresh(spliced: &crate::SemanticTree, source: &str) {
    let fresh = frontend(&mut RetainedSemanticTree::new(), source);
    let fresh = &fresh.snapshot.tree;
    assert_eq!(spliced.identity(), fresh.identity(), "identity for {source}");
    assert_eq!(spliced.declarations(), fresh.declarations());
    assert!(spliced.members().iter().eq(fresh.members().iter()), "members for {source}");
    assert_eq!(spliced.types().len(), fresh.types().len());
    for (a, b) in spliced.types().iter().zip(fresh.types().iter()) {
        assert_eq!((a.path, a.parent, a.members.as_ref()), (b.path, b.parent, b.members.as_ref()));
    }
    assert_eq!(
        crate::metadata_update::splice::first_difference(spliced, fresh),
        None
    );
}

const BASE: &str = "/datum/item_a\n/datum/item_b\n/datum/base\n    var/value = 7\n    var/datum/item_a/typed = null\n    var/list/datum/item_a/values[2]\n    proc/result()\n        return value\n    proc/helper()\n        return 1\n/datum/base/child\n    var/own = 2\n    value = 3\n    result()\n        return own\n/datum/other\n    parent_type = /datum/base\n    values = list(1)\n/proc/probe()\n    return 1\n";

#[test]
fn splice_matches_fresh_for_each_member_edit_and_revert() {
    let edits: Vec<(&str, String)> = vec![
        ("new var", BASE.replace("    var/own = 2\n", "    var/extra = 5\n    var/own = 2\n")),
        ("new inherited proc", format!("{BASE}/datum/base/proc/added()\n    return 3\n")),
        ("new override", format!("{BASE}/datum/base/child/helper()\n    return own\n")),
        ("override in parent_type child", format!("{BASE}/datum/other/result()\n    return 9\n")),
        ("removed proc", BASE.replace("    proc/helper()\n        return 1\n", "")),
        ("removed var", BASE.replace("    var/own = 2\n", "").replace("        return own\n", "        return 2\n")),
        ("removed override", BASE.replace("    result()\n        return own\n", "")),
        ("typed array change", BASE.replace("var/list/datum/item_a/values[2]", "var/list/datum/item_b/values[4]")),
        ("default", BASE.replace("var/value = 7", "var/value = 8")),
    ];
    for (label, edited) in edits {
        let mut state = RetainedSemanticTree::new();
        frontend(&mut state, BASE);
        let changed = frontend(&mut state, &edited);
        same_as_fresh(&changed.snapshot.tree, &edited);
        let reverted = frontend(&mut state, BASE);
        same_as_fresh(&reverted.snapshot.tree, BASE);
        if !matches!(label, "default" | "typed array change") {
            assert!(state.splices() >= 1, "{label} must take the splice");
        }
    }
}

#[test]
fn chained_splices_match_fresh() {
    let mut state = RetainedSemanticTree::new();
    frontend(&mut state, BASE);
    let mut source = BASE.to_string();
    for (before, after) in [
        ("    var/own = 2\n", "    var/extra = 5\n    var/own = 2\n"),
        ("/proc/probe()", "/datum/base/child/helper()\n    return extra\n/proc/probe()"),
        ("    proc/helper()\n        return 1\n", "    proc/helper()\n        return 1\n    proc/more()\n        return 4\n"),
        ("/datum/base/child/helper()\n    return extra\n", ""),
    ] {
        source = source.replacen(before, after, 1);
        let changed = frontend(&mut state, &source);
        same_as_fresh(&changed.snapshot.tree, &source);
    }
    assert!(state.splices() >= 3);
}

#[test]
fn type_and_redeclaration_edits_decline_to_the_full_constructor() {
    for edited in [
        format!("{BASE}/datum/fresh_type\n    var/x = 1\n"),
        BASE.replace("/datum/other\n    parent_type = /datum/base", "/datum/other\n    parent_type = /datum/base/child"),
    ] {
        let mut state = RetainedSemanticTree::new();
        frontend(&mut state, BASE);
        let before = state.splices();
        let changed = frontend(&mut state, &edited);
        same_as_fresh(&changed.snapshot.tree, &edited);
        assert_eq!(state.splices(), before);
    }
}
