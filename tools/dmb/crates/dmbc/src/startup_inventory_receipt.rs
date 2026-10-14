//! Source-neutral inventory receipt owned by the existing startup artifact store.
use dm_ir::ProcedureIdentity;
use dm_tree::procedure_statics::{StaticInventory, StaticLayout, StaticPlan};
use std::sync::Arc;

pub(crate) struct InventoryReceipt {
    rows: Vec<(ProcedureIdentity, Arc<StaticLayout>)>,
    inventory: Arc<StaticInventory>,
}
impl InventoryReceipt {
    /// Only publish after ordinary capture succeeds. Validate complete coverage,
    /// including procedures with no static declarations, without trusting tokens.
    pub(super) fn capture(
        rows: Vec<(ProcedureIdentity, Arc<StaticLayout>)>,
        plans: &[&StaticPlan],
    ) -> Option<Self> {
        if plans.len() != rows.len() {
            return None;
        }
        let mut procedures = std::collections::BTreeSet::new();
        for ((procedure, layout), plan) in rows.iter().zip(plans) {
            if !procedures.insert(*procedure) || *procedure != plan.procedure {
                return None;
            }
            let mut declarations: Vec<_> = plan.declarations.iter().collect();
            declarations.sort_by_key(|declaration| declaration.identity);
            if !layout
                .declarations()
                .iter()
                .map(AsRef::as_ref)
                .eq(declarations)
            {
                return None;
            }
        }
        let mut inventory =
            StaticInventory::from_plans(plans.iter().map(|p| (p.procedure, *p))).ok()?;
        let layouts: std::collections::BTreeMap<_, _> =
            rows.iter().map(|(id, layout)| (*id, layout)).collect();
        inventory.certify(|id, _| layouts.get(&id).map(|layout| Arc::clone(layout)));
        let inventory = Arc::new(inventory);
        Some(Self { rows, inventory })
    }

    /// Current rows must come from admitted per-body layouts after current source
    /// rebind. Full declaration value equality includes initializers and modifiers.
    pub(super) fn admit(
        &self,
        current: &[(ProcedureIdentity, Arc<StaticLayout>)],
    ) -> Option<Arc<StaticInventory>> {
        if self.rows.len() != current.len()
            || !self
                .rows
                .iter()
                .zip(current)
                .all(|((old_id, old), (id, now))| {
                    old_id == id
                        && (Arc::ptr_eq(old, now) || old.declarations() == now.declarations())
                })
        {
            return None;
        }
        Some(Arc::clone(&self.inventory))
    }

    /// Borrow descriptor backing for the existing pointer-deduplicating census.
    pub(crate) fn storage(
        &self,
    ) -> (
        &Vec<(ProcedureIdentity, Arc<StaticLayout>)>,
        &Arc<StaticInventory>,
    ) {
        (&self.rows, &self.inventory)
    }
}

#[cfg(test)]
#[path = "startup_inventory_receipt_tests.rs"]
mod tests;
