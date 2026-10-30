//! Borrowed ORIGINAL hierarchy authority, separate from member completeness.
//! No copied index/model, source re-read, secondary parser or negative guesses.
use super::*;
use dm_ir::{HierarchyQuestion, ResolvedMeaning as M};
pub struct HierarchyView<'a> {
    tree: &'a SemanticTree,
}
impl SemanticTree {
    pub fn certified_hierarchy(&self) -> Option<HierarchyView<'_>> {
        self.inventory
            .hierarchy_certified
            .then_some(HierarchyView { tree: self })
    }
}
impl HierarchyView<'_> {
    pub fn require_tree(&self, tree: &SemanticTree) -> bool {
        std::ptr::eq(self.tree, tree)
    }
    /// Query only the same already-built native lookup/parent/ancestry owners.
    /// A qualified Missing proves hierarchy absence, never member absence.
    pub fn answer(&self, kind: HierarchyQuestion, path: SymbolId) -> M {
        match kind {
            HierarchyQuestion::Type => self
                .tree
                .lookup_type(path)
                .map(|_| M::Symbol(path))
                .unwrap_or(M::Missing),
            HierarchyQuestion::Parent => self
                .tree
                .lookup_type(path)
                .and_then(|id| self.tree.parent(id))
                .map(|id| M::Symbol(self.tree.types[id.index()].path))
                .unwrap_or(M::Missing),
            HierarchyQuestion::Ancestry => {
                if let Some(paths) = self.tree.owner_ancestry.get(&path) {
                    return M::Symbols(Arc::clone(paths));
                }
                let Some(mut id) = self.tree.lookup_type(path) else {
                    return M::Missing;
                };
                let mut paths = Vec::new();
                loop {
                    paths.push(self.tree.types[id.index()].path);
                    match self.tree.parent(id) {
                        Some(parent) => id = parent,
                        None => break,
                    }
                }
                M::Symbols(paths.into())
            }
        }
    }
}
#[cfg(test)]
#[path = "certified_hierarchy_tests.rs"]
mod tests;
