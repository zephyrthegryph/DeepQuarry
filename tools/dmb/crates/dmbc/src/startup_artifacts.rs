//! Position-independent stored-declaration syntax. Every use is bound to an
//! authenticated current body before this immutable payload may be borrowed.
use dm_ir::{ProcedureIdentity, ProcedureStaticDeclaration};
use dm_session::observations::ObservationHost;
use dm_tree::frontend::{IssuedStaticPlan, RelativeStaticPlan};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

#[path = "startup_callable_index.rs"]
mod callable_index;
#[path = "startup_inventory_receipt.rs"]
mod inventory_receipt;
const INVENTORY_KEY: &[u8] = b"dmbc-startup-inventory-v1\0";

pub struct StartupArtifacts {
    callables: callable_index::CallableIndex,
    values: dm_session::ObservedArtifactStore<
        Artifact,
        ProcedureIdentity,
        Arc<[Arc<ProcedureStaticDeclaration>]>,
        (),
    >,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
    pub inventory_hits: AtomicU64,
    pub inventory_recomputed: AtomicU64,
}
impl Default for StartupArtifacts {
    fn default() -> Self {
        Self {
            callables: Default::default(),
            values: dm_session::ObservedArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
            inventory_hits: AtomicU64::new(0),
            inventory_recomputed: AtomicU64::new(0),
        }
    }
}
pub(crate) enum Artifact {
    Syntax(Arc<RelativeStaticPlan>),
    Layout(Arc<dm_tree::procedure_statics::StaticLayout>),
    Inventory(inventory_receipt::InventoryReceipt),
}
struct StaticInputs(Arc<[Arc<ProcedureStaticDeclaration>]>);
impl ObservationHost<ProcedureIdentity, Arc<[Arc<ProcedureStaticDeclaration>]>, ()>
    for StaticInputs
{
    fn answer(&self, _: &ProcedureIdentity) -> Arc<[Arc<ProcedureStaticDeclaration>]> {
        Arc::clone(&self.0)
    }
}
fn layout_key(procedure: ProcedureIdentity) -> Arc<[u8]> {
    let mut key = b"dmbc-procedure-static-layout-v1\0".to_vec();
    key.extend_from_slice(&procedure.owner.bits().to_le_bytes());
    key.extend_from_slice(&procedure.name.bits().to_le_bytes());
    key.push(u8::from(procedure.verb));
    key.extend_from_slice(&procedure.occurrence.to_le_bytes());
    key.into()
}
pub(super) fn key(identity: ProcedureIdentity, source: &str) -> Vec<u8> {
    let mut key = b"dmbc-startup-static-syntax-v1\0".to_vec();
    key.extend_from_slice(&identity.owner.bits().to_le_bytes());
    key.extend_from_slice(&identity.name.bits().to_le_bytes());
    key.push(u8::from(identity.verb));
    key.extend_from_slice(&identity.occurrence.to_le_bytes());
    key.extend_from_slice(&(source.len() as u64).to_le_bytes());
    key.extend_from_slice(source.as_bytes());
    key
}
impl StartupArtifacts {
    /// Drop only the source-neutral callable index's strong semantic root.
    /// Stored static syntax/layout payloads do not own the semantic tree.
    pub(crate) fn clear_callable_index(&self) {
        self.callables.clear();
    }

    pub(crate) fn retain_callable_tree(&self, tree: Option<&Arc<dm_tree::SemanticTree>>) {
        self.callables.retain_tree(tree);
    }
    pub(super) fn unit_members(
        &self,
        frontend: &dm_tree::frontend::ColdFrontend,
    ) -> Result<
        Arc<std::collections::BTreeMap<crate::lowering::UnitIdentity, dm_tree::MemberId>>,
        String,
    > {
        self.callables.get(frontend)
    }
    pub(crate) fn visit_callable_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                Arc<std::collections::BTreeMap<crate::lowering::UnitIdentity, dm_tree::MemberId>>,
                (),
                Arc<dm_tree::frontend::CallableRoster>,
                (),
            >,
        ),
    ) {
        self.callables.visit_storage(visitor);
    }

    pub(super) fn retain_keys<'a>(
        &self,
        keys: impl IntoIterator<Item = &'a [u8]>,
        procedures: impl IntoIterator<Item = ProcedureIdentity>,
    ) {
        let mut roster: Vec<Arc<[u8]>> = keys.into_iter().map(Arc::from).collect();
        roster.extend(procedures.into_iter().map(layout_key));
        roster.push(Arc::from(INVENTORY_KEY));
        self.values
            .retain_current_keys(roster.iter().map(AsRef::as_ref));
    }
    pub(super) fn lookup(&self, key: &[u8]) -> Option<Arc<RelativeStaticPlan>> {
        let value = self.values.lookup(key, &StaticInputs(Arc::from([])))?;
        let Artifact::Syntax(payload) = value.as_ref() else {
            return None;
        };
        self.hits.fetch_add(1, Ordering::Relaxed);
        Some(Arc::clone(payload))
    }
    pub(super) fn remember(&self, key: Vec<u8>, receipt: &Arc<IssuedStaticPlan>) {
        let Ok(payload) = receipt.relative_payload() else {
            self.declined.fetch_add(1, Ordering::Relaxed);
            self.recomputed.fetch_add(1, Ordering::Relaxed);
            return;
        };
        // Current-roster retention has no byte admission budget. The issued
        // relative payload remains mandatory; this is only an inline charge.
        self.values.insert_with(
            key.into(),
            Vec::new(),
            Vec::new(),
            std::mem::size_of::<Artifact>(),
            || Artifact::Syntax(payload),
        );
        self.recomputed.fetch_add(1, Ordering::Relaxed);
    }
}

impl StartupArtifacts {
    pub(super) fn admit_layout(
        &self,
        procedure: ProcedureIdentity,
        declarations: Arc<[Arc<ProcedureStaticDeclaration>]>,
    ) -> Option<Arc<dm_tree::procedure_statics::StaticLayout>> {
        let key = layout_key(procedure);
        let host = StaticInputs(Arc::clone(&declarations));
        if let Some(owner) = self.values.lookup(&key, &host) {
            if let Artifact::Layout(layout) = owner.as_ref() {
                return Some(Arc::clone(layout));
            }
        }
        let ledger = dm_session::observations::ObservationLedger::default();
        ledger.record(procedure, Arc::clone(&declarations), (), None);
        // Current-roster store has no byte admission budget. Exact owner
        // accounting belongs to explicit census, not a hot-path heap walk.
        let layout = dm_tree::procedure_statics::StaticLayout::capture(procedure, declarations)?;
        let owner = self.values.insert_with_owned(
            key,
            ledger.reads(),
            ledger.domain_receipts(),
            0,
            || Artifact::Layout(Arc::new(layout)),
        )?;
        match owner.as_ref() {
            Artifact::Layout(layout) => Some(Arc::clone(layout)),
            Artifact::Syntax(_) | Artifact::Inventory(_) => None,
        }
    }
    /// Called only after current source capture and initializer assembly succeed.
    #[cfg(test)]
    pub(super) fn inventory(
        &self,
        plans: &[&dm_tree::procedure_statics::StaticPlan],
    ) -> Result<Arc<dm_tree::procedure_statics::StaticInventory>, String> {
        self.inventory_with_rosters(plans, &[])
    }
    pub(super) fn inventory_with_rosters(
        &self,
        plans: &[&dm_tree::procedure_statics::StaticPlan],
        rosters: &[Option<Arc<[Arc<ProcedureStaticDeclaration>]>>],
    ) -> Result<Arc<dm_tree::procedure_statics::StaticInventory>, String> {
        let mut rows = Vec::with_capacity(plans.len());
        for (index, plan) in plans.iter().enumerate() {
            let declarations = match rosters.get(index).and_then(Option::as_ref) {
                Some(owner) => {
                    let mut current: Vec<_> = plan.declarations.iter().collect();
                    current.sort_by_key(|declaration| declaration.identity);
                    if !owner.iter().map(AsRef::as_ref).eq(current) {
                        return self.fresh_inventory(plans);
                    }
                    Arc::clone(owner)
                }
                None => {
                    let mut declarations: Vec<_> =
                        plan.declarations.iter().cloned().map(Arc::new).collect();
                    declarations.sort_by_key(|declaration| declaration.identity);
                    declarations.into()
                }
            };
            let Some(layout) = self.admit_layout(plan.procedure, declarations) else {
                return self.fresh_inventory(plans);
            };
            rows.push((plan.procedure, layout));
        }
        let mut admitted = None;
        self.values
            .visit_explained(INVENTORY_KEY, &StaticInputs(Arc::from([])), &mut |owner| {
                if let Artifact::Inventory(receipt) = owner.as_ref() {
                    admitted = receipt.admit(&rows);
                }
                admitted.is_some()
            });
        if let Some(inventory) = admitted {
            self.inventory_hits.fetch_add(1, Ordering::Relaxed);
            return Ok(inventory);
        }
        let Some(receipt) = inventory_receipt::InventoryReceipt::capture(rows, plans) else {
            return self.fresh_inventory(plans);
        };
        let inventory = Arc::clone(receipt.storage().1);
        self.values
            .insert_with_owned(Arc::from(INVENTORY_KEY), Vec::new(), Vec::new(), 0, || {
                Artifact::Inventory(receipt)
            });
        self.inventory_recomputed.fetch_add(1, Ordering::Relaxed);
        Ok(inventory)
    }
    fn fresh_inventory(
        &self,
        plans: &[&dm_tree::procedure_statics::StaticPlan],
    ) -> Result<Arc<dm_tree::procedure_statics::StaticInventory>, String> {
        let mut inventory = dm_tree::procedure_statics::StaticInventory::from_plans(
            plans.iter().map(|plan| (plan.procedure, *plan)),
        )?;
        inventory.certify(|procedure, declarations| self.admit_layout(procedure, declarations));
        self.inventory_recomputed.fetch_add(1, Ordering::Relaxed);
        Ok(Arc::new(inventory))
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                Artifact,
                ProcedureIdentity,
                Arc<[Arc<ProcedureStaticDeclaration>]>,
                (),
            >,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
    pub fn retention_census(&self) -> crate::heap_census::HeapCensusReport {
        let mut census = crate::heap_census::HeapCensus::new("startup_artifacts");
        crate::heap_census::startup_artifacts::inspect(&mut census, self);
        census.finish()
    }
}
