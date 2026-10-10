//! Immutable linker assignment owner, distinct from current symbolic contents.
//! Equality admission occurs only after the ordinary builder validates every
//! current collision, allocation order, fixed index and reservation policy.
use super::*;

#[derive(Clone, Debug)]
pub struct BindingTables {
    inner: Arc<BindingData>,
}
#[derive(Debug, PartialEq, Eq)]
struct BindingData {
    indexes: BTreeMap<Key, u32>,
    slots: BTreeMap<SymbolId, (SymbolId, SymbolId)>,
}
impl BindingTables {
    pub(super) fn validated(
        indexes: BTreeMap<Key, u32>,
        slots: BTreeMap<SymbolId, (SymbolId, SymbolId)>,
        previous: Option<&Self>,
    ) -> Self {
        if let Some(previous) = previous
            .filter(|previous| previous.inner.indexes == indexes && previous.inner.slots == slots)
        {
            return previous.clone();
        }
        Self {
            inner: Arc::new(BindingData { indexes, slots }),
        }
    }
    pub fn assignments(&self) -> &BTreeMap<Key, u32> {
        &self.inner.indexes
    }
    pub fn same_owner(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
    /// Actual immutable owner descriptor and logical index counts for opt-in census.
    /// Private BTree nodes and Arc control blocks are deliberately not estimated.
    pub fn storage(&self) -> (usize, usize, usize, usize) {
        (
            Arc::as_ptr(&self.inner) as usize,
            std::mem::size_of::<BindingData>(),
            self.inner.indexes.len(),
            self.inner.slots.len(),
        )
    }
    pub(super) fn slots(&self) -> &BTreeMap<SymbolId, (SymbolId, SymbolId)> {
        &self.inner.slots
    }
}

/// Latest successful validated binding owner for a live compiler session. This
/// retains no contents, diagnostic locations, or historical variants.
#[derive(Default)]
pub struct RetainedBindings {
    current: std::sync::Mutex<Option<BindingTables>>,
}
impl RetainedBindings {
    pub fn build(&self, inventory: LinkInventory) -> Result<LinkTables, LinkError> {
        let previous = self
            .current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let tables = LinkTables::build_with_bindings(inventory, previous.as_ref())?;
        *self.current.lock().unwrap_or_else(|e| e.into_inner()) = Some(tables.binding_tables());
        Ok(tables)
    }
}
#[cfg(test)]
#[path = "bindings_tests.rs"]
mod tests;
