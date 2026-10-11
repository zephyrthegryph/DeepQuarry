//! Ownership accounting only; never materializes canonical procedure bytes.
use super::*;
impl ReusableProcedureArtifact {
    pub(crate) fn retained_census(
        artifact: &Arc<Self>,
        census: &mut crate::heap_census::HeapCensus,
    ) {
        if !census.arc_object("session_symbolic.artifact", artifact) {
            return;
        }
        census.slice("session_symbolic.warnings", &artifact.warnings, true);
        census.latest_image(&artifact.image_owner);
        crate::composition::ProcedureMetadataRecipe::census(&artifact.metadata_recipe, census);
        census.retained_symbolic_procedure(&artifact.frozen, &artifact.frame, &None);
        if let Some(abi) = &artifact.abi {
            RetainedAbi::census(abi, census);
        }
        census.prepared_inventory_contribution(&artifact.inventory);
        census.vec_payload("session_symbolic.instances", &artifact.instances);
        if census.vec_payload("session_symbolic.helpers", &artifact.helpers) {
            for helper in &artifact.helpers {
                census.slice("session_symbolic.warnings", &helper.warnings, true);
                census.latest_image(&helper.image_owner);
                census.retained_symbolic_helper(&helper.frozen, &helper.local_names);
                census.prepared_inventory_contribution(&helper.inventory);
                census.vec_payload("session_symbolic.instances", &helper.instances);
            }
        }
    }
}
