//! Typed structural change between two admitted declaration rosters.
//!
//! Design: `tools/dmb/doc/structural_change_set.md`. The set is computed from
//! the retained and the current `KeyedDeclarations` plus both trees' type
//! rosters, and it is conservative: an owner/name pair it does not report is
//! one whose local declarations, inherited chain and hierarchy are unchanged.
//! Consumers fall back to their full path whenever `unclassified` is set.
use crate::declaration_contributions::{DeclarationFamily, KeyedDeclarations};
use crate::SemanticTree;
use dm_ir::SymbolId;
use std::collections::HashSet;
use std::sync::Mutex;

#[derive(Debug, Default)]
pub struct StructuralChangeSet {
    /// Types added, removed, or whose parent path changed (explicitly or implicitly).
    pub hierarchy: HashSet<SymbolId>,
    /// Owners with an added, removed or changed member row.
    pub member_owners: HashSet<SymbolId>,
    /// Member names with an added, removed or changed row on any owner.
    pub names: HashSet<SymbolId>,
    pub rows_changed: usize,
    pub order_changed: bool,
    /// Set when a consumer must not trust the set (reason for the log).
    pub unclassified: Option<&'static str>,
}

/// A classified change between two trees, kept on the newer one for consumers that retained
/// answers against the older one (the query database's answer inputs).
#[derive(Debug)]
pub struct ChangeSince {
    pub from_identity: u128,
    pub set: StructuralChangeSet,
}
impl ChangeSince {
    /// Whether an answer about `name` read through `owner` (its ancestors) may differ.
    pub fn owner_name_dirty(&self, tree: &SemanticTree, owner: SymbolId, name: SymbolId) -> bool {
        StructuralChangeSet::under(tree, owner, &self.set.hierarchy)
            || (self.set.names.contains(&name)
                && StructuralChangeSet::under(tree, owner, &self.set.member_owners))
    }
    /// Whether a name-global answer (any owner) may differ.
    pub fn name_dirty(&self, name: SymbolId) -> bool {
        self.set.names.contains(&name) || !self.set.hierarchy.is_empty()
    }
}
impl StructuralChangeSet {
    pub fn between(
        previous_tree: &SemanticTree,
        previous: &KeyedDeclarations,
        current_tree: &SemanticTree,
        current: &KeyedDeclarations,
    ) -> Self {
        let delta = current.delta_since(previous);
        let mut set = Self {
            rows_changed: delta.changes.len(),
            order_changed: delta.order_changed,
            ..Self::default()
        };
        for change in &delta.changes {
            match change.key.family {
                DeclarationFamily::Type => {
                    set.hierarchy.insert(change.key.owner);
                }
                DeclarationFamily::Member { name, .. } => {
                    set.member_owners.insert(change.key.owner);
                    set.names.insert(name);
                }
            }
        }
        // Implicit types have no Type row: compare the type rosters directly.
        for node in current_tree.types.iter() {
            let parent = node.parent.map(|id| current_tree.types[id.index()].path);
            let before = previous_tree.lookup_type(node.path).map(|id| {
                previous_tree.types[id.index()]
                    .parent
                    .map(|parent| previous_tree.types[parent.index()].path)
            });
            if before != Some(parent) {
                set.hierarchy.insert(node.path);
            }
        }
        for node in previous_tree.types.iter() {
            if current_tree.lookup_type(node.path).is_none() {
                set.hierarchy.insert(node.path);
            }
        }
        if previous_tree.inventory.complete != current_tree.inventory.complete
            || previous_tree.inventory.hierarchy_certified
                != current_tree.inventory.hierarchy_certified
        {
            set.unclassified = Some("intrinsic inventory state changed");
        } else if previous_tree.inventory.intrinsic != current_tree.inventory.intrinsic {
            set.unclassified = Some("intrinsic inventory changed");
        }
        set
    }
    pub fn is_empty(&self) -> bool {
        self.rows_changed == 0 && self.hierarchy.is_empty()
    }
    /// True when `owner` or one of its current ancestors is in `roots`.
    pub(crate) fn under(tree: &SemanticTree, owner: SymbolId, roots: &HashSet<SymbolId>) -> bool {
        if roots.is_empty() {
            return false;
        }
        let Some(mut id) = tree.lookup_type(owner) else {
            return true;
        };
        for _ in 0..=tree.types.len() {
            let node = &tree.types[id.index()];
            if roots.contains(&node.path) {
                return true;
            }
            match node.parent {
                Some(parent) => id = parent,
                None => return false,
            }
        }
        true
    }
    /// Whether a per-owner, per-name demand certificate may differ between the
    /// two trees. Namespaces 4 and 5 are root member-name selectors (global per
    /// name); the rest walk the owner's ancestor chain.
    pub fn summary(&self) -> String {
        format!(
            "rows={} hierarchy={} member_owners={} names={} order_changed={}",
            self.rows_changed,
            self.hierarchy.len(),
            self.member_owners.len(),
            self.names.len(),
            self.order_changed
        )
    }
}

static LAST_OUTCOMES: Mutex<Vec<String>> = Mutex::new(Vec::new());
/// Record one consumer outcome ("<stage> reused ..." or "<stage> full (<reason>)").
pub fn record_outcome(line: String) {
    LAST_OUTCOMES
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .push(line);
}
/// Drain the outcomes recorded since the last call (one request at a time).
pub fn take_outcomes() -> Vec<String> {
    std::mem::take(&mut *LAST_OUTCOMES.lock().unwrap_or_else(|error| error.into_inner()))
}

