//! Actual immutable map-output owners; opaque modifier payloads decline admission.
use super::*;
use crate::{
    initialization_artifact::{InitializationArtifact, InitializationCoverage},
    lowering_memo::ResolverRead,
    map_output::DescriptorPlan,
    map_projection::Projection,
};
use dm_ir::ReadDomain;
use dm_tree::maps::MapPlan;

#[expect(
    clippy::too_many_arguments,
    reason = "Borrow each independently owned artifact field and ledger without allocating a diagnostic envelope."
)]
pub(crate) fn weight(
    plans: &Arc<[MapPlan]>,
    projection: &Projection,
    paths: &Arc<[Arc<str>]>,
    descriptors: &DescriptorPlan,
    artifacts: &Arc<[InitializationArtifact]>,
    key: &Arc<[u8]>,
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    let mut census = HeapCensus::new("resident_map_outputs");
    census.slice("retained_maps.key", key, true);
    census.slice("retained_maps.plans", plans, true);
    let mut private = 0usize;
    for plan in plans.iter() {
        private = private.saturating_add(census.retained_map_plan(plan));
    }
    census.retained_map_projection(projection);
    if census.slice("retained_maps.semantic_paths", paths, true) {
        for path in paths.iter() {
            census.arc_text("retained_maps.semantic_paths", path);
        }
    }
    let DescriptorPlan {
        keys,
        initializers,
        entries,
    } = descriptors;
    census.slice("retained_maps.descriptor_keys", keys, true);
    census.slice("retained_maps.descriptor_initializers", initializers, true);
    if census.slice("retained_maps.descriptors", entries, true) {
        for entry in entries.iter() {
            census.entry_content("retained_maps.descriptor_content", &entry.content);
        }
    }
    if census.slice("retained_maps.artifacts", artifacts, true) {
        for artifact in artifacts.iter() {
            let InitializationArtifact {
                identity: _,
                code,
                debug_origins,
                coverage,
                encoding,
            } = artifact;
            if let Some(encoding) = encoding {
                census.initializer_encoding(encoding);
            }
            if census.arc_object("retained_maps.code", code) {
                // Reuse the complete resolver owner walker and its conservative
                // private-index bounds. Separate traversal may overcharge aliases
                // across procedures, but never labels them exact census bytes.
                private = private.saturating_add(super::resident_initializer_fragment::weight(
                    code,
                    &[],
                    &Vec::new(),
                    &Vec::new(),
                    &Vec::new(),
                    &Vec::new(),
                )?);
            }
            if census.arc_object("retained_maps.debug", debug_origins) {
                census.debug("retained_maps.debug", debug_origins);
            }
            match coverage {
                InitializationCoverage::ModifiedAssignments {
                    count: _,
                    canonical_body,
                }
                | InitializationCoverage::MapAssignments {
                    count: _,
                    canonical_body,
                } => {
                    census.slice("retained_maps.coverage", canonical_body, true);
                }
                InitializationCoverage::DeclarationPresence(_) => {}
                InitializationCoverage::DeclarationWrites(writes) => {
                    census.vec_payload("retained_maps.coverage", writes);
                }
            }
        }
    }
    census.vec_payload("retained_maps.reads", reads);
    census.vec_payload("retained_maps.versions", versions);
    for read in reads {
        super::resident_weight::answer(&mut census, &read.answer);
    }
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    Some(
        usize::try_from(report.unique_known_capacity_bytes)
            .ok()?
            .saturating_add(private)
            .saturating_add(encounters.saturating_mul(64))
            .saturating_add(4096)
            .saturating_add(
                size_of::<DescriptorPlan>() + size_of::<Projection>() + 3 * size_of::<Arc<[u8]>>(),
            ),
    )
}
