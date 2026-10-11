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
    // Plan forks share this immutable recipe; current admission never mutates it.
    rows: Arc<Vec<Option<Row>>>,
    identities: Arc<Vec<(UnitIdentity, usize)>>,
}
/// Facts produced by the same mandatory row admission. `current_order` only
/// permits retaining the old performance index; it grants no semantic admission.
pub(super) struct Admission {
    pub(super) rows: Vec<Option<Arc<super::super::frame_contribution::FrameContribution>>>,
    pub(super) complete: bool,
    pub(super) current_order: bool,
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
        Some(Self {
            rows: Arc::new(rows),
            identities: Arc::new(identities),
        })
    }
    pub(super) fn admit_current(
        &self,
        slots: &[Slot<UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &Arc<dm_link::ArgumentSourceReferences>,
    ) -> Option<Admission> {
        // Current identities select old owners independently of physical roster
        // positions. The frame's existing metadata admission checks the exact
        // current declaration and every embedded helper binding. Final emission
        // still checks string/variable frontiers and rebinds procedure/list IDs.
        let mut complete = true;
        let mut current_order = self.rows.len() == slots.len();
        let rows = slots
            .iter()
            .enumerate()
            .map(|(index, slot)| {
                let admitted = (|| {
                    let position = self
                        .identities
                        .binary_search_by_key(&slot.identity, |row| row.0)
                        .ok()?;
                    let old_index = self.identities[position].1;
                    current_order &= old_index == index;
                    let row = self.rows.get(old_index)?.as_ref()?;
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
                })();
                complete &= admitted.is_some();
                current_order &= admitted.is_some();
                admitted
            })
            .collect();
        Some(Admission {
            rows,
            complete,
            current_order,
        })
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        let label = "composition.metadata_roster";
        if census.arc_object(label, &self.rows) {
            census.vec_payload(label, &self.rows);
        }
        if census.arc_object(label, &self.identities) {
            census.vec_payload(label, &self.identities);
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
    #[cfg(test)]
    fn admit(
        &self,
        slots: &[Slot<UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &Arc<dm_link::ArgumentSourceReferences>,
    ) -> Option<Vec<Option<Arc<super::super::frame_contribution::FrameContribution>>>> {
        self.admit_current(slots, batch, projection, symbols, references)
            .map(|admission| admission.rows)
    }
}
#[cfg(test)]
#[path = "metadata_roster_tests.rs"]
mod tests;
