//! One pointer ledger for accessible owners live before procedure lowering.
use super::*;
use crate::{class_projection::ClassProjection, initializer_policy::DefaultValue};

impl HeapCensus {
    pub(crate) fn boundary_opaque_abi_policy(&mut self) {
        self.unknown("cold_boundary.abi_policy", "standalone custom AbiPolicy does not expose its retained backing; production prepared ABI counted separately");
    }
    pub(crate) fn cold_retained_owners(&mut self, memo: &crate::lowering_memo::ProcedureMemo) {
        if let Some(store) = &memo.startup {
            if self.arc_object("cold_boundary.startup_owner", store) {
                super::startup_artifacts::inspect(self, store);
            }
        }
        if let Some(store) = &memo.initializer_assemblies {
            if self.arc_object("cold_boundary.assemblies_owner", store) {
                super::initializer_assemblies::inspect_into(self, store);
            }
        }
        if let Some(store) = &memo.class_projections {
            if self.arc_object("cold_boundary.projections_owner", store) {
                super::resident_owner_projection::inspect_into(self, store);
            }
        }
        if let Some(store) = &memo.symbolic {
            if self.arc_object("cold_boundary.symbolic_store", store) {
                store.retained_census(self);
            }
        }
        if let Some(store) = &memo.abi {
            if self.arc_object("cold_boundary.abi_store", store) {
                self.abi_artifacts(store);
            }
        }
        if let Some(store) = &memo.initializer_fragments {
            if self.arc_object("cold_boundary.fragment_store", store) {
                store.visit_storage(|view| match view {
                    dm_session::ObservedArtifactStorageView::Store { buckets, entries } => {
                        self.observe_items("cold_boundary.fragment_index", entries);
                        if buckets != 0 { self.unknown("cold_boundary.fragment_index", "private observed-store BTree nodes/control blocks excluded; exposed fragment owners counted separately"); }
                    }
                    dm_session::ObservedArtifactStorageView::Bucket { address, len, capacity, element_size } => {
                        self.buffer("cold_boundary.fragment_buckets", address, len.saturating_mul(element_size), capacity.saturating_mul(element_size));
                    }
                    dm_session::ObservedArtifactStorageView::Entry { key, reads, versions, value } => {
                        self.slice("cold_boundary.fragment_keys", key, true);
                        self.receipt("cold_boundary.fragment_reads", reads);
                        self.slice("cold_boundary.fragment_versions", versions, true);
                        for read in reads.iter() {
                            match &read.answer {
                                crate::initializer_lowering::receipts::Answer::Semantic(answer) => super::resident_weight::answer(self, answer),
                                crate::initializer_lowering::receipts::Answer::Input(inputs) => self.initializer_receipt(inputs),
                            }
                        }
                        if self.arc_object("cold_boundary.fragment_payload", value) {
                            let (code, recipes, references) = value.retained_parts();
                            self.resolver_code(code);
                            self.initializer_fragment_recipes(recipes, references);
                        }
                    }
                });
            }
        }
        if let Some(store) = &memo.required_types {
            if self.arc_object("cold_boundary.required_types_store", store) {
                self.required_type_artifacts(store);
            }
        }
        if let Some(store) = &memo.link_bindings {
            if self.arc_object("cold_boundary.link_bindings_store", store) {
                store.visit_current(|tables| {
                    if let Some(tables) = tables {
                        let (address, bytes, assignments, slots) = tables.storage();
                        if self.buffer("cold_boundary.link_bindings_payload", address, bytes, bytes) {
                            self.observe_items("cold_boundary.link_assignments", assignments);
                            self.observe_items("cold_boundary.link_slots", slots);
                            if assignments != 0 || slots != 0 {
                                self.unknown("cold_boundary.link_bindings_indexes", "BTree assignment/slot node allocation backing and Arc control blocks private; logical entry counts are not capacity measurements");
                            }
                        }
                    }
                });
            }
        }
        if self.arc_object("cold_boundary.rich_store", &memo.values) {
            memo.values.visit_storage(|view| match view {
                dm_session::ArtifactStorageView::Store { buckets, entries } => {
                    self.observe_items("cold_boundary.rich_index", entries);
                    if buckets != 0 { self.unknown("cold_boundary.rich_index", "private ArtifactStore BTree node allocation backing/control blocks excluded"); }
                }
                dm_session::ArtifactStorageView::Bucket { address, len, capacity, element_size } => {
                    self.buffer("cold_boundary.rich_buckets", address, len.saturating_mul(element_size), capacity.saturating_mul(element_size));
                }
                dm_session::ArtifactStorageView::Entry { key, reads, versions, value } => {
                    self.slice("cold_boundary.rich_keys", key, true);
                    self.retained_symbolic_ledger(reads, versions);
                    if self.arc_object("cold_boundary.rich_values", value) {
                        self.lowered_unit(&value.unit);
                        self.vec_payload("cold_boundary.rich_debug_offsets", &value.relative_debug);
                    }
                }
            });
        }
    }
    pub(crate) fn shared_procedure_inputs(
        &mut self,
        inputs: &Arc<dm_codegen_byond::lower_resolver::ProcedureInputs>,
    ) {
        if self.arc_object("resident_abi.input_owner", inputs) {
            self.procedure_inputs(inputs);
        }
    }
    pub(crate) fn procedure_inputs(
        &mut self,
        inputs: &dm_codegen_byond::lower_resolver::ProcedureInputs,
    ) {
        let dm_codegen_byond::lower_resolver::ProcedureInputs {
            procedure_identity: _,
            current_proc_path,
            current_type_path,
            parameters,
            parameter_type_flags,
            parameter_value_sources,
            parameter_defaults,
            parameter_types,
            readonly_parameters: _,
            resource_search_context: _,
        } = inputs;
        let owner = "resident_abi.inputs";
        for path in [current_proc_path, current_type_path].into_iter().flatten() {
            self.string(owner, path);
        }
        self.strings(owner, parameters);
        self.vec_payload(owner, parameter_type_flags);
        self.vec_payload(owner, parameter_value_sources);
        self.vec_payload(owner, parameter_defaults);
        for default in parameter_defaults.iter().flatten() {
            self.string(owner, default);
        }
        for (name, path) in parameter_types {
            self.string(owner, name);
            self.string(owner, path);
        }
    }
    pub(crate) fn prepared_source_abi(
        &mut self,
        prepared: &crate::driver_facts::PreparedSourceAbi,
    ) {
        self.vec_payload("prepared_source_abi.units", &prepared.units);
        self.vec_payload("prepared_source_abi.diagnostics", &prepared.diagnostics);
        for (_, unit) in &prepared.units {
            self.shared_procedure_inputs(&unit.inputs);
            self.items("prepared_source_abi.executable_body", &unit.executable_body);
            if let Some(abi) = &unit.abi {
                self.abi(abi);
            }
            if let Some(certificate) = &unit.canonical {
                self.prepared_canonical(certificate);
            }
            if !unit.inputs.parameter_types.is_empty()
                || !unit.inputs.readonly_parameters.is_empty()
            {
                self.unknown("prepared_source_abi.input_indexes", "HashMap parameter type buckets and BTree readonly parameter nodes have private allocation backing; nested strings counted");
            }
        }
        if !prepared.diagnostics.is_empty() {
            self.unknown(
                "prepared_source_abi.diagnostics",
                "nested ABI error payloads not exposed by this boundary adapter",
            );
        }
    }
    fn projection_default(&mut self, value: &DefaultValue) {
        match value {
            DefaultValue::Transform(_) => (),
            DefaultValue::Scalar(value) => {
                self.semantic_value("current_projection.defaults", value)
            }
            DefaultValue::InitializerExpression { canonical, .. } => {
                self.slice("current_projection.defaults", canonical, true);
            }
        }
    }
    pub(crate) fn current_projection(&mut self, projection: &ClassProjection) {
        self.slice("current_projection.types", &projection.types, true);
        if self.slice("current_projection.fields", &projection.fields, true) {
            for field in projection.fields.iter() {
                super::resident_owner_projection::inspect_field(self, field);
            }
        }
        if self.slice("current_projection.chains", &projection.chains, true) {
            for chain in projection.chains.iter() {
                self.slice("current_projection.chain_entries", &chain.entries, true);
            }
        }
        if self.slice(
            "current_projection.statics",
            &projection.procedure_statics,
            true,
        ) {
            for value in projection.procedure_statics.iter() {
                self.projection_default(&value.value);
            }
        }
        self.slice(
            "current_projection.shared_slots",
            &projection.shared_slot_order,
            true,
        );
        self.slice(
            "current_projection.runtime_writes",
            &projection.runtime_writes,
            true,
        );
        self.slice(
            "current_projection.membership",
            &projection.procedure_membership,
            true,
        );
        if self.arc_object(
            "current_projection.declarations",
            &projection.procedure_declarations,
        ) && !projection.procedure_declarations.is_empty()
        {
            self.unknown("current_projection.declarations", "BTree procedure declaration nodes have private allocation backing; scalar entries do not own nested payloads");
        }
        projection.field_placements.visit_storage(|candidates, locations| {
            self.vec_payload("current_projection.placements", candidates);
            for location in locations.values() { self.source_location("current_projection.placements", location); }
            if !locations.is_empty() { self.unknown("current_projection.placements", "BTree location node allocation backing private; nested current locations counted"); }
        });
    }
    pub(crate) fn current_initializer_units(
        &mut self,
        units: &Vec<crate::initializer_lowering::LoweredInitializerUnit>,
    ) {
        if self.vec_payload("current_initializer_units", units) {
            for unit in units {
                self.vec_payload(
                    "current_initializer_units.write_ordinals",
                    &unit.write_ordinals,
                );
                self.initializer_code(&unit.code);
                self.debug("current_initializer_units.debug", &unit.debug_origins);
                if let Some(encoding) = &unit.encoding {
                    self.initializer_encoding(encoding);
                }
            }
        }
    }
    pub(crate) fn current_map_initializers(
        &mut self,
        units: &Vec<crate::initialization_artifact::InitializationArtifact>,
    ) {
        use crate::initialization_artifact::InitializationCoverage;
        if self.vec_payload("current_map_initializers", units) {
            for unit in units {
                self.initializer_code(&unit.code);
                if self.arc_object("current_map_initializers.debug", &unit.debug_origins) {
                    self.debug("current_map_initializers.debug", &unit.debug_origins);
                }
                if let Some(encoding) = &unit.encoding {
                    self.initializer_encoding(encoding);
                }
                match &unit.coverage {
                    InitializationCoverage::DeclarationWrites(writes) => {
                        self.vec_payload("current_map_initializers.coverage", writes);
                    }
                    InitializationCoverage::ModifiedAssignments { canonical_body, .. }
                    | InitializationCoverage::MapAssignments { canonical_body, .. } => {
                        self.slice("current_map_initializers.coverage", canonical_body, true);
                    }
                    InitializationCoverage::DeclarationPresence(_) => (),
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn combined_current_projection_deduplicates_shared_field_payloads() {
        use crate::class_projection::{FieldPlacements, FieldProjection, FieldRole};
        let field = Arc::new(FieldProjection {
            owner: dm_ir::SymbolId::of("/datum/probe"),
            declaring_owner: dm_ir::SymbolId::of("/datum/probe"),
            name: dm_ir::SymbolId::of("name"),
            role: FieldRole::Declaration,
            wire_flags: Some(0),
            intrinsic: false,
            shared: false,
            value: DefaultValue::Scalar(dm_ir::SemanticValue::Text(Arc::from(
                b"actual owned text".as_slice(),
            ))),
        });
        let projection = ClassProjection {
            field_placements: FieldPlacements::default(),
            procedure_declarations: Arc::new(Default::default()),
            shared_slot_order: Arc::from([]),
            procedure_statics: Arc::from([]),
            runtime_writes: Arc::from([]),
            tree_identity: 1,
            occurrence_count: 0,
            types: Arc::from([]),
            fields: Arc::from([Arc::clone(&field), Arc::clone(&field)]),
            chains: Arc::from([]),
            procedure_membership: Arc::from([]),
        };
        let mut one = HeapCensus::new("one");
        one.current_projection(&projection);
        let expected = one.finish().unique_known_capacity_bytes;
        let mut combined = HeapCensus::new("combined");
        // Model the same field held by retained contribution and current output.
        super::super::resident_owner_projection::inspect_field(&mut combined, &field);
        combined.current_projection(&projection);
        combined.current_projection(&projection);
        let report = combined.finish();
        assert_eq!(report.unique_known_capacity_bytes, expected);
        assert!(report
            .owners
            .iter()
            .any(|owner| owner.shared_encounters > 0));
        assert!(report
            .owners
            .iter()
            .any(|owner| owner.owner == "owner_projection.defaults"
                && owner.unique_known_capacity_bytes
                    >= std::mem::size_of::<FieldProjection>() as u64));
    }
}
