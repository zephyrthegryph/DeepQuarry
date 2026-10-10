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
        census.latest_image(&artifact.image_owner);
        crate::composition::ProcedureMetadataRecipe::census(&artifact.metadata_recipe, census);
        census.retained_symbolic_procedure(&artifact.frozen, &artifact.frame, &artifact.abi);
        census.prepared_strings(&artifact.strings.0);
        census.vec_payload("session_symbolic.slots", &artifact.slots.0);
        census.prepared_entry_bytes(&artifact.content);
        if census.vec_payload("session_symbolic.helpers", &artifact.helpers) {
            for helper in &artifact.helpers {
                census.latest_image(&helper.image_owner);
                census.retained_symbolic_helper(&helper.frozen, &helper.local_names);
                census.prepared_strings(&helper.strings.0);
                census.vec_payload("session_symbolic.slots", &helper.slots.0);
                census.prepared_entry_bytes(&helper.content);
            }
        }
    }
}
