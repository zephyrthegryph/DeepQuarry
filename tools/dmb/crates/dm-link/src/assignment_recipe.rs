//! Exact successful allocation inputs on the existing retained binding owner.
use super::*;
#[derive(Debug, PartialEq, Eq)]
pub(super) struct AssignmentRecipe {
    fixed: Vec<(Key, u32)>,
    orders: BTreeMap<Table, Vec<Key>>,
    append_orders: BTreeMap<Table, Vec<Key>>,
    prefixes: BTreeMap<Table, u32>,
}
impl AssignmentRecipe {
    /// Bucket selector for the shared pool; equality decides sharing.
    pub(super) fn fingerprint(&self) -> u64 {
        use std::hash::{Hash, Hasher};
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        self.fixed.len().hash(&mut hasher);
        for (table, order) in &self.orders {
            (*table as u8, order.len()).hash(&mut hasher);
        }
        hasher.finish()
    }
    pub(super) fn capture(inventory: &LinkInventory) -> Self {
        Self {
            fixed: inventory.fixed.clone(),
            orders: inventory.orders.clone(),
            append_orders: inventory.append_orders.clone(),
            prefixes: inventory.reserved_prefixes.clone(),
        }
    }
    pub(super) fn admits(
        &self,
        inventory: &LinkInventory,
        content: &BTreeMap<Key, EntryContent>,
        slots: &BTreeMap<SymbolId, (SymbolId, SymbolId)>,
        bindings: &BindingTables,
    ) -> bool {
        self.fixed == inventory.fixed
            && self.orders == inventory.orders
            && self.append_orders == inventory.append_orders
            && self.prefixes == inventory.reserved_prefixes
            && content.keys().eq(bindings.assignments().keys())
            && slots == bindings.slots()
    }
    pub(super) fn visit_storage(
        &self,
        mut buffer: impl FnMut(usize, usize, usize),
        mut maps: impl FnMut(usize),
    ) {
        buffer(
            self.fixed.as_ptr() as usize,
            self.fixed.len() * std::mem::size_of::<(Key, u32)>(),
            self.fixed.capacity() * std::mem::size_of::<(Key, u32)>(),
        );
        for map in [&self.orders, &self.append_orders] {
            maps(map.len());
            for values in map.values() {
                buffer(
                    values.as_ptr() as usize,
                    values.len() * std::mem::size_of::<Key>(),
                    values.capacity() * std::mem::size_of::<Key>(),
                );
            }
        }
        maps(self.prefixes.len());
    }
}
