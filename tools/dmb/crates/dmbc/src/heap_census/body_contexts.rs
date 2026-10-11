//! Shared current source envelope census, counting immutable owners once.
use super::*;
impl HeapCensus {
    pub(crate) fn body_occurrences(
        &mut self,
        owner: &str,
        bodies: &Arc<[dm_tree::frontend::BodyOccurrence]>,
    ) {
        self.slice(owner, bodies, true);
        for body in bodies.iter() {
            self.slice(owner, &body.ast_path, true);
            self.slice(owner, &body.setting_context_origins, true);
            self.source_location(owner, &body.source);
            for location in body.setting_context_origins.iter() {
                self.source_location(owner, location);
            }
        }
    }
    pub(crate) fn source_export_mapping(
        &mut self,
        mapping: &Arc<dm_tree::frontend::SourceExportMapping>,
    ) {
        let owner = "query_snapshot.source_mapping";
        if !self.arc_object(owner, mapping) {
            return;
        }
        let (region_count, include_count, location_count) = mapping.coordinate_counts();
        self.owner(owner).observed_items += (region_count + include_count + location_count) as u64;
        let (regions, region_bytes, includes, include_bytes) = mapping.coordinate_storage();
        self.buffer(owner, regions, region_bytes, region_bytes);
        self.buffer(owner, includes, include_bytes, include_bytes);
        mapping.origin_storage(|address, _, bytes| {
            self.buffer(owner, address, bytes, bytes);
        });
        if let Some(locations) = mapping.locations_if_issued() {
            self.slice(owner, locations, true);
            for location in locations.iter().flatten() {
                self.source_location(owner, location);
            }
        }
        self.unknown(owner,"Arc control blocks, shared path/trace nested buffers and private shared source-path HashMap backing are not exposed");
    }
}
