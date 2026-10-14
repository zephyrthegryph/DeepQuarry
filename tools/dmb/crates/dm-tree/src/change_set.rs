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
    fn under(tree: &SemanticTree, owner: SymbolId, roots: &HashSet<SymbolId>) -> bool {
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
    pub(crate) fn demand_dirty(
        &self,
        tree: &SemanticTree,
        (owner, name, namespace): (SymbolId, SymbolId, u8),
    ) -> bool {
        if matches!(namespace, 4 | 5) {
            return self.names.contains(&name) || !self.hierarchy.is_empty();
        }
        Self::under(tree, owner, &self.hierarchy)
            || (self.names.contains(&name) && Self::under(tree, owner, &self.member_owners))
    }
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

impl SemanticTree {
    /// Seed this tree's demand certificates with the previous tree's tokens for
    /// every selection the change set leaves clean. Both trees must share the
    /// same certificate issuer (the token store) and intrinsic inventory.
    pub(crate) fn inherit_demand_tokens(
        &mut self,
        previous: &SemanticTree,
        change: &StructuralChangeSet,
    ) -> Result<(usize, usize), &'static str> {
        if let Some(reason) = change.unclassified {
            return Err(reason);
        }
        match (&self.owner_certificate_issuer, &previous.owner_certificate_issuer) {
            (Some(current), Some(old)) if std::sync::Arc::ptr_eq(current, old) => {}
            _ => return Err("different certificate issuer"),
        }
        if std::sync::Arc::ptr_eq(&self.owner_callable_demands, &previous.owner_callable_demands) {
            return Err("demand owner shared with previous tree");
        }
        let old = previous.owner_callable_demands.snapshot();
        let mut kept = Vec::with_capacity(old.len());
        let mut dropped = 0;
        for (selection, token) in old {
            if self.lookup_type(selection.0).is_some() && !change.demand_dirty(self, selection) {
                kept.push((selection, token));
            } else {
                dropped += 1;
            }
        }
        let carried = kept.len();
        self.owner_callable_demands.seed(kept);
        self.selection_prune_skippable = change.hierarchy.is_empty();
        Ok((carried, dropped))
    }
}
