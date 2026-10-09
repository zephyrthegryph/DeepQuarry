//! Consuming boundary between source-authenticated preparation and wire writing.
use super::*;
use std::sync::Arc;

/// Request-local owned inputs. They are not authenticated until `prepare` has
/// checked them against the still-live frontend and consumed this envelope.
pub struct OwnedCompositionInputs {
    pub engine: Arc<[u8]>,
    pub batch: FrozenBatch,
    pub symbols: Arc<SymbolTable>,
    pub projection: crate::class_projection::ClassProjection,
    pub values: Arc<dyn crate::class_projection::TypeValuePolicy>,
    pub stage: Option<Box<dyn NonTextOutputStage>>,
}

/// A non-Clone, source-authenticated request, with no frontend references.
/// Private ownership prevents swapping a projection, stage or procedure batch
/// after source coverage has been checked. Final wire checks still run normally.
pub struct ValidatedComposition {
    inputs: OwnedCompositionInputs,
}

impl ValidatedComposition {
    pub fn prepare(
        frontend: &dm_tree::frontend::ColdFrontend,
        inputs: OwnedCompositionInputs,
    ) -> Result<Self, CompositionError> {
        owned::validate_projected(
            &inputs.batch,
            frontend,
            &inputs.projection,
            inputs.stage.as_deref(),
        )?;
        Ok(Self { inputs })
    }

    /// Consume the validated inputs through the common composer. This still
    /// validates runtime-initializer coverage, stage key attachment, all actual
    /// instructions/references and the independent encoded round trip.
    pub fn compose(
        self,
        executor: &dm_exec::BuildExecutor,
    ) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
        let OwnedCompositionInputs {
            engine,
            batch,
            symbols,
            projection,
            values,
            stage,
        } = self.inputs;
        compose_records_access(
            &engine,
            owned::BatchAccess::Owned(batch),
            &symbols,
            Some((&projection, values.as_ref())),
            stage.as_deref(),
            Some(executor),
        )
    }
}
