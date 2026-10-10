//! Actual accessible owners of retained assembled initializer code.
use super::*;
use crate::initializer_lowering::InitializerAssemblies;
use dm_session::ObservedArtifactStorageView as View;

pub(crate) fn inspect(store: &InitializerAssemblies) -> HeapCensusReport {
    let mut census = HeapCensus::new("retained_initializer_assemblies");
    inspect_into(&mut census, store);
    census.finish()
}
pub(super) fn inspect_into(mut census: &mut HeapCensus, store: &InitializerAssemblies) {
    store.visit_storage(|view| match view {
        View::Store { buckets, entries } => {
            census.owner("initializer_assemblies.index").observed_items += entries as u64;
            if buckets != 0 {
                census.unknown("initializer_assemblies.index", "private ArtifactStore BTree node backing and Arc control blocks excluded; exposed payload capacities counted separately");
            }
        }
        View::Bucket { address, len, capacity, element_size } => {
            census.buffer("initializer_assemblies.buckets", address, len.saturating_mul(element_size), capacity.saturating_mul(element_size));
        }
        View::Entry { key, reads, versions, value } => {
            census.slice("initializer_assemblies.keys", key, true);
            census.receipt("initializer_assemblies.reads", reads);
            census.slice("initializer_assemblies.versions", versions, true);
            for read in reads.iter() {
                match &read.answer {
                    crate::initializer_lowering::receipts::Answer::Semantic(answer) => super::resident_weight::answer(&mut census, answer),
                    crate::initializer_lowering::receipts::Answer::Input(inputs) => census.initializer_receipt(inputs),
                }
            }
            if census.arc_object("initializer_assemblies.payload", value) {
                let (code, recipes, root_indexes, references) = value.retained_parts();
                census.resolver_code(code);
                census.initializer_fragment_recipes(recipes, references);
                census.vec_payload("initializer_assemblies.root_indexes", root_indexes);
                census.initializer_encoding(value.encoding());
            }
        }
    });
}

impl HeapCensus {
    pub(crate) fn initializer_encoding(
        &mut self,
        encoding: &Arc<crate::symbolic::InitializerEncoding>,
    ) {
        if self.arc_object("initializer_encoding", encoding) {
            self.initializer_type_requests(encoding.retained_types());
            if let Some(ready) = encoding.retained() {
                if self.arc_object("initializer_encoding.payload", ready) {
                    self.latest_image(&ready.image_owner);
                    self.frozen_code(&ready.frozen);
                    self.vec_payload("initializer_encoding.slots", &ready.slots);
                    self.prepared_strings(&ready.strings);
                }
            }
        }
    }
}

impl HeapCensus {
    pub(crate) fn initializer_receipt(
        &mut self,
        inputs: &Arc<crate::initializer_lowering::receipts::Inputs>,
    ) {
        use crate::initializer_lowering::receipts::{Inputs, Shape};
        let owner = "initializer_receipts";
        if !self.arc_object(owner, inputs) {
            return;
        }
        match inputs.as_ref() {
            Inputs::Fragment(input) => {
                match &input.write.value {
                    dm_ir::InitializerValue::Expression(value) => self.expression(owner, value),
                    dm_ir::InitializerValue::ArrayAllocation(value) => self.array(owner, value),
                    dm_ir::InitializerValue::NoAuthoredValue => (),
                }
                if let Some(array) = &input.write.declared_array {
                    self.array(owner, array);
                }
                if let Shape::SizedArray(dimensions) | Shape::SizedArrayExplicit(dimensions, _) =
                    &input.shape
                {
                    self.slice(owner, dimensions, true);
                }
                if let Some(accepted) = &input.accepted {
                    accepted
                        .visit(|value| super::initializer_artifacts::classification(self, value));
                }
            }
            Inputs::Assembly { writes, .. } => {
                if self.vec_payload(owner, writes) {
                    for write in writes {
                        self.initializer_receipt(&write.fragment);
                        match &write.default {
                            crate::initializer_policy::DefaultValue::Transform(_) => (),
                            crate::initializer_policy::DefaultValue::Scalar(value) => {
                                self.semantic_value(owner, value)
                            }
                            crate::initializer_policy::DefaultValue::InitializerExpression {
                                canonical,
                                ..
                            } => {
                                self.slice(owner, canonical, true);
                            }
                        }
                    }
                }
            }
        }
    }
}

impl HeapCensus {
    pub(crate) fn initializer_type_requests(
        &mut self,
        types: &Arc<crate::initializer_code::TypeRequests>,
    ) {
        if self.arc_object("initializer_type_requests", types) {
            self.vec_payload("initializer_type_requests.ordered", types.ordered());
        }
    }
    pub(crate) fn initializer_code(&mut self, code: &crate::InitializerCode) {
        if self.arc_object("current_initializer_code", code.code_owner()) {
            self.resolver_code(code);
        }
        self.initializer_type_requests(code.requests());
    }
}
