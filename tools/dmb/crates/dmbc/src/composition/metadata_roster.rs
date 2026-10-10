//! Ordered successful frame preparation on the existing composition plan.
use super::*;
use std::sync::Arc;
struct Row {
    table_index: u32,
    artifact: usize,
    identity: UnitIdentity,
    frame: Arc<crate::symbolic::FrozenFrame>,
    abi: Arc<crate::procedure_policy::PreparedAbi>,
    recipe: Arc<crate::composition::ProcedureMetadataRecipe>,
    prepared: Arc<super::super::frame_contribution::FrameContribution>,
}
pub(super) struct MetadataRoster {
    references: Arc<dm_link::ArgumentSourceReferences>,
    declarations: Option<Arc<std::collections::BTreeMap<Key, bool>>>,
    rows: Vec<Option<Row>>,
}
impl MetadataRoster {
    pub(super) fn capture(
        slots: &[Slot<UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        references: &Arc<dm_link::ArgumentSourceReferences>,
        prepared: &[Result<PreparedMetadata, CompositionError>],
    ) -> Option<Self> {
        if slots.len() != prepared.len() {
            return None;
        }
        let rows = slots
            .iter()
            .zip(prepared)
            .map(|(slot, value)| {
                let PreparedMetadata::Retained(prepared) = value.as_ref().ok()? else {
                    return None;
                };
                let artifact = slot.artifact?;
                let unit = batch.units.get(artifact)?;
                Some(Row {
                    table_index: slot.table_index,
                    artifact,
                    identity: slot.identity,
                    frame: Arc::clone(&unit.lowered.frame),
                    abi: Arc::clone(unit.lowered.abi.as_ref()?),
                    recipe: Arc::clone(&unit.metadata_recipe),
                    prepared: Arc::clone(prepared),
                })
            })
            .collect::<Vec<_>>();
        if !rows.iter().any(Option::is_some) {
            return None;
        }
        Some(Self {
            references: Arc::clone(references),
            declarations: projection.map(|p| Arc::clone(&p.procedure_declarations)),
            rows,
        })
    }
    pub(super) fn admit(
        &self,
        slots: &[Slot<UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &Arc<dm_link::ArgumentSourceReferences>,
    ) -> Option<Vec<Option<Arc<super::super::frame_contribution::FrameContribution>>>> {
        // A references owner is admitted only under the enclosing plan's current
        // binding owner. A numerically equal independently minted owner declines.
        if !Arc::ptr_eq(&self.references, references) {
            return None;
        }
        match (&self.declarations, projection) {
            (None, None) => {}
            (Some(old), Some(current))
                if Arc::ptr_eq(old, &current.procedure_declarations)
                    || old.as_ref() == current.procedure_declarations.as_ref() => {}
            _ => return None,
        }
        // Each current slot retains its own exact proof. Missing, shifted, or
        // changed rows decline independently; the common preparation path handles
        // them in current order. No errors or fresh metadata are retained.
        Some(
            slots
                .iter()
                .enumerate()
                .map(|(index, slot)| {
                    let row = self.rows.get(index)?.as_ref()?;
                    let unit = batch.units.get(slot.artifact?)?;
                    if row.table_index != slot.table_index
                        || Some(row.artifact) != slot.artifact
                        || row.identity != slot.identity
                        || unit.lowered.identity != row.identity
                        || !Arc::ptr_eq(&row.frame, &unit.lowered.frame)
                        || !Arc::ptr_eq(&row.abi, unit.lowered.abi.as_ref()?)
                        || !Arc::ptr_eq(&row.recipe, &unit.metadata_recipe)
                        || symbols.text(row.identity.owner).is_none()
                        || symbols.text(row.identity.name).is_none()
                    {
                        return None;
                    }
                    Some(Arc::clone(&row.prepared))
                })
                .collect(),
        )
    }
    pub(super) fn retain_current_prefix(&mut self, len: usize) {
        // Used only after every current position passed exact admission.
        self.rows.truncate(len);
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        let label = "composition.metadata_roster";
        census.vec_payload(label, &self.rows);
        census.arc_object(label, &self.references);
        census.unknown(
            label,
            "argument-reference and declaration BTreeMap private backing is unavailable",
        );
        if let Some(owner) = &self.declarations {
            census.arc_object(label, owner);
        }
        for row in self.rows.iter().flatten() {
            census.frozen_frame(label, &row.frame);
            census.abi(&row.abi);
            crate::composition::ProcedureMetadataRecipe::census(&row.recipe, census);
            if census.arc_object("procedure_metadata.frame", &row.prepared) {
                row.prepared.census(census);
            }
        }
    }
}
#[cfg(test)]
#[path = "metadata_roster_tests.rs"]
mod tests;
