//! Shared current source envelope census, counting immutable owners once.
use super::*;
impl HeapCensus {
    pub(crate) fn body_archive(&mut self, archive: &Arc<dm_tree::frontend::BodyArchive>) {
        if self.arc_object("query_snapshot.body_archive", archive) {
            let (callables, indices) = archive.binding_storage();
            self.callable_roster(callables);
            if self.arc_object("query_snapshot.body_archive.indices", indices) {
                self.collection_entries::<(dm_tree::OccurrenceId, usize)>(
                    "query_snapshot.body_archive.indices",
                    Arc::as_ptr(indices) as usize,
                    indices.len(),
                );
                self.unknown(
                    "query_snapshot.body_archive.indices",
                    "private HashMap backing and Arc control block",
                );
            }
            archive.visit_storage(|source, syntax, bodies| {
                self.source_text("query_snapshot.body_archive.text", source);
                self.declaration_syntax("query_snapshot.body_archive.syntax", syntax);
                self.body_occurrences("query_snapshot.body_archive.bodies", bodies);
            });
        }
    }
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
    pub(crate) fn resolved_query_host(
        &mut self,
        resolver: &Arc<
            dm_resources::native_resolver::NativeResourceResolver<
                crate::engine_host::EngineResolverHost<
                    dm_tree::constant_resolution::ScalarSnapshot,
                >,
            >,
        >,
    ) {
        let owner = "query_snapshot.current_resolver";
        if !self.arc_object(owner, resolver) {
            return;
        }
        resolver.visit_metadata_storage(|symbols, aliases, ordered, contexts, lookups| {
            self.symbols(symbols);
            self.vec_payload(owner, aliases);
            for (alias, path) in aliases {
                self.string(owner, alias);
                self.path(owner, path);
            }
            self.vec_payload(owner, ordered);
            self.collection_entries::<(u128, Arc<[u8]>)>(
                owner,
                contexts as *const _ as usize,
                contexts.len(),
            );
            for bytes in contexts.values() {
                self.slice(owner, bytes, true);
            }
            self.collection_entries::<(
                (dm_ir::SymbolId, u128),
                dm_resources::native_resolver::CapturedResourceOutcome,
            )>(owner, lookups as *const _ as usize, lookups.len());
        });
        self.query_scalar_snapshot(resolver.tree().shared_source());
        self.unknown(owner, "private resource HashMap backing and Arc control blocks; metadata-only host has no ResourceSet or encoded RSC");
    }
    pub(crate) fn resolved_analysis_host(
        &mut self,
        resolver: &Arc<
            crate::engine_host::EngineResolverHost<dm_tree::constant_resolution::ScalarSnapshot>,
        >,
    ) {
        if self.arc_object("query_snapshot.analysis_resolver", resolver) {
            self.query_scalar_snapshot(resolver.shared_source());
        }
    }
    fn query_scalar_snapshot(
        &mut self,
        scalar: &Arc<dm_tree::constant_resolution::ScalarSnapshot>,
    ) {
        let owner = "query_snapshot.scalar";
        if self.arc_object("query_snapshot.scalar", scalar) {
            self.snapshot(&scalar.source);
            self.slice(owner, &scalar.requested, true);
            if self.arc_object(owner, &scalar.outcomes) {
                self.collection_entries::<(
                    dm_tree::constant_resolution::ScalarQuery,
                    dm_tree::constant_resolution::ScalarOutcome,
                )>(
                    owner,
                    Arc::as_ptr(&scalar.outcomes) as usize,
                    scalar.outcomes.len(),
                );
                for value in scalar.outcomes.values() {
                    match value {
                        dm_tree::constant_resolution::ScalarOutcome::Value(value) => {
                            self.semantic_value(owner, value)
                        }
                        dm_tree::constant_resolution::ScalarOutcome::Cycle(cycle) => {
                            self.slice(owner, cycle, true);
                        }
                        _ => {}
                    }
                }
            }
            if self.arc_object(owner, &scalar.dependencies) {
                self.collection_entries::<(
                    dm_tree::constant_resolution::ScalarQuery,
                    Arc<[dm_tree::constant_resolution::ScalarQuery]>,
                )>(
                    owner,
                    Arc::as_ptr(&scalar.dependencies) as usize,
                    scalar.dependencies.len(),
                );
                for dependencies in scalar.dependencies.values() {
                    self.slice(owner, dependencies, true);
                }
            }
            if self.arc_object(owner, scalar.certificates()) {
                self.collection_entries::<(dm_tree::constant_resolution::ScalarQuery, u64)>(
                    owner,
                    Arc::as_ptr(scalar.certificates()) as usize,
                    scalar.certificates().len(),
                );
            }
            if self.arc_object(owner, &scalar.predefined_reads) {
                self.collection_entries::<(
                    dm_ir::SymbolId,
                    dm_tree::constant_resolution::PredefinedOutcome,
                )>(
                    owner,
                    Arc::as_ptr(&scalar.predefined_reads) as usize,
                    scalar.predefined_reads.len(),
                );
                for answer in scalar.predefined_reads.values() {
                    if let dm_tree::constant_resolution::PredefinedOutcome::Value(value) = answer {
                        self.semantic_value(owner, value);
                    }
                }
            }
        }
        self.unknown(
            owner,
            "private engine catalogs, scalar BTree backing and Arc control blocks are not exposed",
        );
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
