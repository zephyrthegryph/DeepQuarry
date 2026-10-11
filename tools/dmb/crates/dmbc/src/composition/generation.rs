//! One canonical generation retained at the existing validated model boundary.
//! Exact model equality is authoritative; no hash admits a generation.
use super::*;
#[cfg(test)]
use std::sync::Arc;
use std::sync::Mutex;

/// Request-local model after source/stage, instruction and reference admission.
/// Construction is private to the composition implementation so a caller cannot
/// replace those checks with an output fingerprint.
pub(super) struct CertifiedGenerationInputs {
    model: Dmb,
    string_seed: Option<strings::StringSeed>,
}
impl CertifiedGenerationInputs {
    pub(super) fn with_string_seed(mut self, seed: Option<strings::StringSeed>) -> Self {
        self.string_seed = seed;
        self
    }
    pub(super) fn after_validation(model: Dmb) -> Self {
        Self {
            model,
            string_seed: None,
        }
    }
}

/// A single latest successful generation; no history or source authority retained.
#[derive(Default)]
pub struct RetainedGeneration {
    current: Mutex<Option<Generation>>,
    plan: Mutex<Option<procedure_plan::CachedPlan>>,
    /// Symbolic header decisions share the session generation's policy and lifetime.
    /// Values and dense table IDs are always bound from the current model.
    pub(super) header_recipes: crate::class_projection::HeaderRecipes,
}
struct Generation {
    inputs: CertifiedGenerationInputs,
    encoded: byond_dmb::dmb::EncodedDmb,
}
impl RetainedGeneration {
    pub(super) fn string_index(
        &self,
        model: &Dmb,
    ) -> Result<(StringIndex, strings::StringSeed), CompositionError> {
        let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        let mut index = current
            .as_ref()
            .and_then(|old| {
                old.inputs
                    .string_seed
                    .as_ref()
                    .and_then(|seed| seed.admit(model, &old.inputs.model))
            })
            .map(Ok)
            .unwrap_or_else(|| StringIndex::build(model))?;
        let seed = index.seed(model.strings.len());
        Ok((index, seed))
    }
    pub(crate) fn census_string_index(&self, census: &mut crate::heap_census::HeapCensus) {
        if let Some(seed) = self
            .current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|generation| generation.inputs.string_seed.as_ref())
        {
            seed.census(census);
        }
    }

    pub(crate) fn census_headers(&self, census: &mut crate::heap_census::HeapCensus) {
        census.header_recipes(&self.header_recipes);
    }

    /// All current composition checks must finish before this entry is called.
    /// Equality includes every ordered output table, raw string byte and header.
    /// A mismatch follows the ordinary canonical encoder and independent decoder.
    pub(super) fn encode(
        &self,
        inputs: CertifiedGenerationInputs,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
        let mut current = self
            .current
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(hit) = current
            .as_ref()
            .filter(|hit| hit.inputs.model == inputs.model)
        {
            return Ok(hit.encoded.clone());
        }
        // Equality is complete. Reuse only the previous successful generation
        // during canonical row encoding; errors leave an empty performance memo.
        let encoded_result = {
            let _profile = dm_profile::stage("composition.encode");
            inputs
                .model
                .encode_reusing_list_rows(
                    current
                        .as_ref()
                        .map(|previous| &previous.inputs.model.lists),
                    executor,
                )
                .map_err(CompositionError::Decode)
        };
        // The previous generation is only a source of immutable row encodings.
        // Release it before decoder validation and publication of its replacement.
        *current = None;
        let (encoded, certificate) = encoded_result?;
        validate_encoded(&encoded)?;
        if !inputs.model.lists.retain_encoded_rows(certificate) {
            return Err(unsupported(
                "canonical row certificate differs from current words",
            ));
        }
        *current = Some(Generation {
            inputs,
            encoded: encoded.clone(),
        });
        Ok(encoded)
    }
    pub(super) fn bind_plan(
        &self,
        mut raw: procedure_plan::CompositionPlan,
        batch: &FrozenBatch,
    ) -> procedure_plan::BoundCompositionPlan {
        let mut cached = self.plan.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(hit) = cached
            .as_ref()
            .and_then(|previous| previous.admit(&raw, batch))
        {
            return hit;
        }
        let captured = raw.clone();
        raw.canonicalize();
        let bound = raw.bind(batch);
        let mut replacement = procedure_plan::CachedPlan::capture(captured, batch, &bound);
        if let (Some(next), Some(previous)) = (replacement.as_mut(), cached.as_mut()) {
            next.inherit_metadata(previous);
        }
        *cached = replacement;
        bound
    }
    pub(super) fn argument_sources(
        &self,
        tables: &dm_link::LinkTables,
        start: usize,
        order: &[Key],
    ) -> Result<std::sync::Arc<dm_link::ArgumentSourceReferences>, dm_link::LinkError> {
        let mut plan = self.plan.lock().unwrap_or_else(|error| error.into_inner());
        match plan.as_mut() {
            Some(plan) => plan.argument_sources(tables, start, order),
            None => dm_link::ArgumentSourceReferences::assign(tables, start, order)
                .map(std::sync::Arc::new),
        }
    }
    pub(super) fn prepare_metadata(
        &self,
        slots: &[procedure_plan::Slot<crate::lowering::UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &std::sync::Arc<dm_link::ArgumentSourceReferences>,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Vec<Result<procedure_plan::PreparedMetadata, CompositionError>> {
        let mut plan = self.plan.lock().unwrap_or_else(|e| e.into_inner());
        match plan.as_mut() {
            Some(plan) => {
                plan.prepare_metadata(slots, batch, projection, symbols, references, executor)
            }
            None => procedure_plan::prepare_metadata(
                slots, batch, projection, symbols, references, executor, true,
            ),
        }
    }
    pub(crate) fn census_plan(&self, census: &mut crate::heap_census::HeapCensus) {
        if let Some(plan) = self
            .plan
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
        {
            plan.census(census);
        }
    }
    pub fn clear(&self) {
        self.header_recipes.clear();
        self.release_wire_images();
    }
    /// Release physical generation buffers without discarding symbolic header recipes.
    pub(crate) fn release_wire_images(&self) {
        *self.plan.lock().unwrap_or_else(|error| error.into_inner()) = None;
        *self
            .current
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = None;
    }
    /// Borrow retained physical owners for opt-in census without cloning buffers.
    pub(crate) fn visit_retained(
        &self,
        mut visitor: impl FnMut(&Dmb, &byond_dmb::dmb::EncodedDmb),
    ) {
        let current = self
            .current
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(generation) = current.as_ref() {
            visitor(&generation.inputs.model, &generation.encoded);
        }
    }
}
pub(super) fn encode_model(
    model: &Dmb,
    executor: Option<&dm_exec::BuildExecutor>,
) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
    let encoded = {
        let _profile = dm_profile::stage("composition.encode");
        match executor {
            Some(executor) => model.encode_on_executor(executor),
            None => model.encode(),
        }
        .map_err(CompositionError::Decode)?
    };
    Ok(encoded)
}
pub(super) fn validate_encoded(
    encoded: &byond_dmb::dmb::EncodedDmb,
) -> Result<(), CompositionError> {
    let _profile = dm_profile::stage("composition.independent_roundtrip");
    Dmb::from_bytes(encoded.bytes())
        .and_then(|decoded| decoded.validate_references())
        .map_err(CompositionError::Decode)?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    fn model() -> Dmb {
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap()
    }
    #[test]
    fn successful_generation_reuses_initial_string_seed_with_fresh_output_parity() {
        let owner = RetainedGeneration::default();
        let initial = model();
        let (mut index, seed) = owner.string_index(&initial).unwrap();
        let mut first_model = initial.clone();
        index
            .intern(&mut first_model, b"late generation metadata")
            .unwrap();
        owner
            .encode(
                CertifiedGenerationInputs::after_validation(first_model)
                    .with_string_seed(Some(seed)),
                None,
            )
            .unwrap();
        let (mut retained, next_seed) = owner.string_index(&initial).unwrap();
        let mut next = initial.clone();
        let mut fresh = initial.clone();
        let mut fresh_index = StringIndex::build(&fresh).unwrap();
        for bytes in [
            b"replacement metadata".as_slice(),
            b"late generation metadata",
        ] {
            assert_eq!(
                retained.intern(&mut next, bytes).unwrap(),
                fresh_index.intern(&mut fresh, bytes).unwrap()
            );
        }
        let result = owner
            .encode(
                CertifiedGenerationInputs::after_validation(next).with_string_seed(Some(next_seed)),
                None,
            )
            .unwrap();
        assert_eq!(result.bytes(), fresh.encode().unwrap().bytes());
        owner.clear();
        let (_, seed_after_clear) = owner.string_index(&initial).unwrap();
        assert!(seed_after_clear.admit(&initial, &initial).is_some());
    }
    #[test]
    fn complete_model_equality_reuses_and_ordered_payload_change_invalidates() {
        let owner = RetainedGeneration::default();
        let original = model();
        let first = owner
            .encode(
                CertifiedGenerationInputs::after_validation(original.clone()),
                None,
            )
            .unwrap();
        let second = owner
            .encode(
                CertifiedGenerationInputs::after_validation(original.clone()),
                None,
            )
            .unwrap();
        assert!(Arc::ptr_eq(first.shared_bytes(), second.shared_bytes()));
        let mut changed = original.clone();
        changed.lists.push(vec![7, 9]);
        let third = owner
            .encode(
                CertifiedGenerationInputs::after_validation(changed.clone()),
                None,
            )
            .unwrap();
        assert!(!Arc::ptr_eq(first.shared_bytes(), third.shared_bytes()));
        assert_eq!(third.bytes(), changed.encode().unwrap().bytes());
        let last = changed.lists.len() - 1;
        changed.lists[last].reverse();
        let fourth = owner
            .encode(CertifiedGenerationInputs::after_validation(changed), None)
            .unwrap();
        assert!(!Arc::ptr_eq(third.shared_bytes(), fourth.shared_bytes()));
        owner.clear();
        let fifth = owner
            .encode(CertifiedGenerationInputs::after_validation(original), None)
            .unwrap();
        assert!(!Arc::ptr_eq(first.shared_bytes(), fifth.shared_bytes()));
    }
}
