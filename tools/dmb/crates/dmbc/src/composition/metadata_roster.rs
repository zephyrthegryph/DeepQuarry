//! Ordered successful frame preparation on the existing composition plan.
use super::*;
use std::sync::Arc;
#[derive(Clone)]
struct Row {
    identity: UnitIdentity,
    frame: Arc<crate::symbolic::FrozenFrame>,
    abi: Arc<crate::procedure_policy::PreparedAbi>,
    recipe: Arc<crate::composition::ProcedureMetadataRecipe>,
    prepared: Arc<super::super::frame_contribution::FrameContribution>,
}
#[derive(Clone)]
pub(super) struct MetadataRoster {
    rows: Vec<Option<Row>>,
    identities: Vec<(UnitIdentity, usize)>,
}
impl MetadataRoster {
    pub(super) fn capture(
        slots: &[Slot<UnitIdentity>],
        batch: &FrozenBatch,
        _projection: Option<&crate::class_projection::ClassProjection>,
        _references: &Arc<dm_link::ArgumentSourceReferences>,
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
        let mut identities: Vec<_> = rows
            .iter()
            .enumerate()
            .filter_map(|(index, row)| row.as_ref().map(|row| (row.identity, index)))
            .collect();
        identities.sort_unstable_by_key(|row| row.0);
        if identities.windows(2).any(|pair| pair[0].0 == pair[1].0) {
            return None;
        }
        Some(Self { rows, identities })
    }
    pub(super) fn admit(
        &self,
        slots: &[Slot<UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &Arc<dm_link::ArgumentSourceReferences>,
    ) -> Option<Vec<Option<Arc<super::super::frame_contribution::FrameContribution>>>> {
        // Current identities select old owners independently of physical roster
        // positions. The frame's existing metadata admission checks the exact
        // current declaration and every embedded helper binding. Final emission
        // still checks string/variable frontiers and rebinds procedure/list IDs.
        Some(
            slots
                .iter()
                .map(|slot| {
                    let position = self
                        .identities
                        .binary_search_by_key(&slot.identity, |row| row.0)
                        .ok()?;
                    let row = self.rows.get(self.identities[position].1)?.as_ref()?;
                    let unit = batch.units.get(slot.artifact?)?;
                    if row.identity != slot.identity
                        || unit.lowered.identity != row.identity
                        || !Arc::ptr_eq(&row.frame, &unit.lowered.frame)
                        || !Arc::ptr_eq(&row.abi, unit.lowered.abi.as_ref()?)
                        || !Arc::ptr_eq(&row.recipe, &unit.metadata_recipe)
                        || symbols.text(row.identity.owner).is_none()
                        || symbols.text(row.identity.name).is_none()
                        || !row
                            .prepared
                            .admit_current_metadata(unit, projection, symbols, references)
                    {
                        return None;
                    }
                    Some(Arc::clone(&row.prepared))
                })
                .collect(),
        )
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        let label = "composition.metadata_roster";
        census.vec_payload(label, &self.rows);
        census.vec_payload(label, &self.identities);
        for row in self.rows.iter().flatten() {
            census.frozen_frame(label, &row.frame);
            census.abi(&row.abi);
            crate::composition::ProcedureMetadataRecipe::census(&row.recipe, census);
            if census.arc_object("procedure_metadata.frame", &row.prepared) {
                row.prepared.census(census);
            }
        }
    }
    /// Performance-only index retention after every current row was admitted.
    /// Reordered/deleted rows get a new index; numeric slot IDs need not persist.
    pub(super) fn is_current_roster(
        &self,
        slots: &[Slot<UnitIdentity>],
        prepared: &[Result<PreparedMetadata, CompositionError>],
    ) -> bool {
        self.rows.len() == slots.len()
            && prepared.len() == slots.len()
            && self
                .rows
                .iter()
                .zip(slots)
                .zip(prepared)
                .all(|((row, slot), prepared)| {
                    let (Some(row), Ok(PreparedMetadata::Retained(prepared))) = (row, prepared)
                    else {
                        return false;
                    };
                    row.identity == slot.identity && Arc::ptr_eq(&row.prepared, prepared)
                })
    }
}
#[cfg(test)]
#[path = "metadata_roster_tests.rs"]
mod tests;
