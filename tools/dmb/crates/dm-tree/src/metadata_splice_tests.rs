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
    // Declaration order, members, owner rosters, selectors and targets, by declaration position (slots may differ).
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
fn new_and_removed_types_splice_and_match_fresh() {
    let edits = [
        format!("{BASE}/datum/fresh_type
    var/x = 1
"),
        BASE.replace("/datum/other
", "/datum/inserted
    var/y = 2
/datum/other
"),
        format!("{BASE}/datum/base/child/grand/proc/deep()
    return 1
"),
        format!("{BASE}/datum/explicit
    parent_type = /datum/base/child
    own = 9
"),
        BASE.replace("/datum/item_b
", ""),
    ];
    for edited in edits {
        let mut state = RetainedSemanticTree::new();
        frontend(&mut state, BASE);
        let before = state.splices();
        let changed = frontend(&mut state, &edited);
        same_as_fresh(&changed.snapshot.tree, &edited);
        assert!(state.splices() > before, "type edit must splice: {edited}");
        let reverted = frontend(&mut state, BASE);
        same_as_fresh(&reverted.snapshot.tree, BASE);
    }
}

#[test]
fn reparenting_an_existing_type_declines_to_the_full_constructor() {
    let edited = BASE.replace(
        "/datum/other
    parent_type = /datum/base",
        "/datum/other
    parent_type = /datum/base/child",
    );
    let mut state = RetainedSemanticTree::new();
    frontend(&mut state, BASE);
    let before = state.splices();
    let changed = frontend(&mut state, &edited);
    same_as_fresh(&changed.snapshot.tree, &edited);
    assert_eq!(state.splices(), before);
}

#[test]
fn numeric_default_edit_is_reported_relative_to_the_previous_tree() {
    let mut state = RetainedSemanticTree::new();
    let first = frontend(&mut state, BASE);
    let edited = BASE.replace("var/value = 7", "var/value = 9");
    let changed = frontend(&mut state, &edited);
    let edits = changed.snapshot.tree.default_edits().expect("pure numeric default edit");
    assert_eq!(edits.from_identity, first.snapshot.tree.identity());
    assert_eq!(edits.edits.len(), 1);
    assert_eq!(edits.edits[0].value_bits, 9f32.to_bits());
    assert_eq!(edits.edits[0].old_bits, 7f32.to_bits());
    let typed = frontend(&mut state, &edited.replace("var/value = 9", "var/value = \"x\""));
    assert!(typed.snapshot.tree.default_edits().is_none());
}

/// Added members keep every retained slot: the new ones take slots past the
/// end of the arena while the order array places them where they are declared.
#[test]
fn added_members_take_new_slots_and_keep_retained_ones() {
    let mut state = RetainedSemanticTree::new();
    let base = frontend(&mut state, BASE);
    let base_tree = &base.snapshot.tree;
    let mut source = BASE.to_string();
    for (before, after) in [
        ("    var/own = 2\n", "    var/extra = 5\n    var/own = 2\n"),
        ("    proc/helper()\n        return 1\n", "    proc/helper()\n        return 1\n    proc/more()\n        return 4\n"),
        ("/proc/probe()", "/datum/base/child/helper()\n    return extra\n/proc/probe()"),
    ] {
        source = source.replacen(before, after, 1);
        let changed = frontend(&mut state, &source);
        let tree = &changed.snapshot.tree;
        same_as_fresh(tree, &source);
        // Every retained slot still holds the member it held in the base tree.
        for (slot, node) in base_tree.members().iter().enumerate() {
            let now = tree.member(crate::MemberId(slot as u32)).unwrap();
            assert_eq!((now.owner, now.name, now.kind), (node.owner, node.name, node.kind));
        }
        assert!(tree.member_order().iter().enumerate().any(|(position, id)| position != id.index()));
    }
    assert_eq!(state.splices(), 3);
}

/// Removed members take the stable-slot path (a removed slot takes the arena's last member) and the tree equals a fresh
/// build at each step (members, chains, selectors, targets by declaration position).
#[test]
fn removed_members_keep_slots_and_match_fresh() {
    let mut state = RetainedSemanticTree::new();
    let base = frontend(&mut state, BASE);
    let base_tree = std::sync::Arc::clone(&base.snapshot.tree);
    let mut source = BASE.to_string();
    let mut stable = 0;
    for (before, after) in [
        // An earlier member (not the last slot): the last member moves into its slot.
        ("    proc/helper()\n        return 1\n", ""),
        // A var of the child and the override that read it.
        ("    var/own = 2\n", ""),
        ("        return own\n", "        return 2\n"),
        // An override whose chain heads a descendant type's.
        ("    result()\n        return 2\n", ""),
    ] {
        source = source.replacen(before, after, 1);
        let _ = crate::change_set::take_outcomes();
        let changed = frontend(&mut state, &source);
        let outcomes = crate::change_set::take_outcomes();
        stable += outcomes.iter().filter(|line| line.contains("stable slots") && !line.contains(" 0 removed")).count();
        let tree = &changed.snapshot.tree;
        same_as_fresh(tree, &source);
        assert!(tree.members().len() < base_tree.members().len());
    }
    assert!(stable >= 3, "removals took the stable-slot path ({stable})");
    // Reverting to the base adds them back on top.
    let reverted = frontend(&mut state, BASE);
    same_as_fresh(&reverted.snapshot.tree, BASE);
}
