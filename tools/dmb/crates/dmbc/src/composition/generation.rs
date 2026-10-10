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
}
impl CertifiedGenerationInputs {
    pub(super) fn after_validation(model: Dmb) -> Self {
        Self { model }
    }
}

/// A single latest successful generation; no history or source authority retained.
#[derive(Default)]
pub struct RetainedGeneration {
    current: Mutex<Option<Generation>>,
    plan: Mutex<Option<procedure_plan::CachedPlan>>,
}
struct Generation {
    inputs: CertifiedGenerationInputs,
    encoded: byond_dmb::dmb::EncodedDmb,
}
impl RetainedGeneration {
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
        // Equality is complete. Release the previous model/encoded owner before
        // encoding its replacement; errors leave an empty performance memo.
        *current = None;
        let encoded = encode_model(&inputs.model, executor)?;
        validate_encoded(&encoded)?;
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
        *cached = procedure_plan::CachedPlan::capture(captured, batch, &bound);
        bound
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
