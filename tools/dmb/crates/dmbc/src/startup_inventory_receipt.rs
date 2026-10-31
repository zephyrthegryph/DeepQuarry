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
    pub(super) fn capture(rows:Vec<(ProcedureIdentity,Arc<StaticLayout>)>,plans:&[&StaticPlan])->Option<Self>{
        Self::capture_with(rows,plans,|_,plans|StaticInventory::from_plans(plans.iter().map(|p|(p.procedure,*p))).ok())
    }
    pub(super) fn capture_original(rows:Vec<(ProcedureIdentity,Arc<StaticLayout>)>,plans:&[&StaticPlan])->Option<Self>{
        Self::capture_with(rows,plans,|rows,plans|StaticInventory::from_canonical_layouts(rows.iter().zip(plans).map(|((procedure,layout),plan)|(*procedure,*plan,layout))).ok())
    }
    fn capture_with(rows:Vec<(ProcedureIdentity,Arc<StaticLayout>)>,plans:&[&StaticPlan],produce:impl FnOnce(&[(ProcedureIdentity,Arc<StaticLayout>)],&[&StaticPlan])->Option<StaticInventory>)->Option<Self>{
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
        let mut inventory = produce(&rows,plans)?;
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

    /// Exact current producer objects supplement ordinary semantic validation.
    /// An equal detached/older roster cannot claim source-required admission.
    pub(super) fn admit_original(&self,current:&[(ProcedureIdentity,Arc<StaticLayout>)],rosters:&[Option<Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>>])->Option<Arc<StaticInventory>>{
        let inventory=self.admit(current)?;let mut count=0usize;
        for roster in rosters.iter().flatten(){for declaration in roster.iter(){
            count=count.checked_add(1)?;
            if !inventory.declaration(declaration.identity).is_some_and(|old|Arc::ptr_eq(old,declaration)){return None;}
        }}
        (inventory.declarations().count()==count).then_some(inventory)
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
