//! Callable names are admitted on demand by the sole current metadata issuer.
use super::*;
pub(super) type SelectionKey = (SymbolId, SymbolId, bool);

pub(super) fn keys<M: std::ops::Index<usize, Output = MemberNode>>(
    _tree: &SemanticTree,
    _members: &M,
    _order: &[MemberId],
) -> Vec<Arc<[u8]>> {
    // No eager local-name artifacts. Current queried names are retained by the
    // existing demanded_keys roster, including their required ancestor receipts.
    Vec::new()
}
impl RetainedMetadata {
    pub(crate) fn certify_selections(&self, tree: &SemanticTree) -> BTreeMap<SelectionKey, u128> {
        // Old issued tokens remain readable through that snapshot's demand owner;
        // unqueried old snapshots cannot mint authority for a later revision.
        self.begin_selection_revision(tree);
        BTreeMap::new()
    }
}
#[cfg(test)]
#[path = "selection_tests.rs"]
mod tests;
