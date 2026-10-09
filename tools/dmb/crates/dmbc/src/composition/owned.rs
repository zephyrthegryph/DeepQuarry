//! Single composition implementation with borrowed or consuming image access.
use super::*;
use crate::symbolic::{BytecodeFeatures, IntegrationError};
use std::ops::Deref;

pub(super) enum BatchAccess<'a> {
    Borrowed(&'a FrozenBatch),
    Owned(FrozenBatch),
}
impl Deref for BatchAccess<'_> {
    type Target = FrozenBatch;
    fn deref(&self) -> &Self::Target {
        match self {
            Self::Borrowed(batch) => batch,
            Self::Owned(batch) => batch,
        }
    }
}
impl BatchAccess<'_> {
    pub(super) fn unit_words(
        &mut self,
        index: usize,
        mobs: &dm_link::MobBindings,
    ) -> Result<Vec<u32>, IntegrationError> {
        let image = match self {
            Self::Borrowed(batch) => Ok::<dm_link::ProcedureImage, IntegrationError>(
                batch.link_unit(index, &Default::default())?,
            ),
            Self::Owned(batch) => Ok::<dm_link::ProcedureImage, IntegrationError>(
                batch.take_unit_image(index, &Default::default())?,
            ),
        }?;
        crate::symbolic::latest_image::LatestImage::wire_words(
            self.units[index].latest_image(),
            image,
            self.units[index].frozen.code(),
            &self.tables,
            mobs,
        )
    }
    pub(super) fn helper_words(
        &mut self,
        index: usize,
        mobs: &dm_link::MobBindings,
    ) -> Result<Vec<u32>, IntegrationError> {
        let image = match self {
            Self::Borrowed(batch) => Ok::<dm_link::ProcedureImage, IntegrationError>(
                batch.link_helper(&batch.helpers[index])?,
            ),
            Self::Owned(batch) => {
                Ok::<dm_link::ProcedureImage, IntegrationError>(batch.take_helper_image(index)?)
            }
        }?;
        crate::symbolic::latest_image::LatestImage::wire_words(
            self.helpers[index].latest_image(),
            image,
            self.helpers[index].frozen.code(),
            &self.tables,
            mobs,
        )
    }
    pub(super) fn initializer_words(
        &mut self,
        index: usize,
        mobs: &dm_link::MobBindings,
    ) -> Result<Vec<u32>, IntegrationError> {
        let image = match self {
            Self::Borrowed(batch) => Ok::<dm_link::ProcedureImage, IntegrationError>(
                batch.link_initializer(&batch.initializers[index])?,
            ),
            Self::Owned(batch) => Ok::<dm_link::ProcedureImage, IntegrationError>(
                batch.take_initializer_image(index)?,
            ),
        }?;
        crate::symbolic::latest_image::LatestImage::wire_words(
            self.initializers[index].latest_image(),
            image,
            self.initializers[index].frozen.code(),
            &self.tables,
            mobs,
        )
    }
    pub(super) fn certified_features(&self) -> HashMap<u32, (&[u32], BytecodeFeatures)> {
        match self {
            Self::Borrowed(batch) => batch.feature_images(),
            // Mutable stages may change code. The consuming path runs the shared
            // complete borrowed instruction visitor on the actual final image.
            Self::Owned(_) => HashMap::new(),
        }
    }
}
pub(super) fn validate_projected(
    batch: &FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
    projection: &crate::class_projection::ClassProjection,
    stage: Option<&dyn NonTextOutputStage>,
) -> Result<(), CompositionError> {
    if projection.tree_identity != frontend.snapshot.tree.identity()
        || projection.occurrence_count != frontend.snapshot.occurrences.source_order().len()
    {
        return Err(unsupported(
            "class projection does not cover this source model",
        ));
    }
    if frontend
        .plan
        .items
        .iter()
        .any(|item| matches!(item, dm_preprocess::regions::OrderedItem::NonText { .. }))
        && stage.is_none()
    {
        return Err(unsupported("map/skin materialization is not supplied"));
    }
    if let Some(stage) = stage {
        stage.validate_source(frontend).map_err(unsupported)?;
    }
    let covered: HashSet<_> = batch
        .units
        .iter()
        .map(|unit| unit.lowered.origin.declaration)
        .collect();
    if covered.len() != batch.units.len()
        || frontend.bodies.len() != batch.units.len()
        || frontend
            .bodies
            .iter()
            .any(|body| !covered.contains(&body.declaration))
    {
        return Err(unsupported("source procedure coverage mismatch"));
    }
    Ok(())
}
/// Consume request-local linked images, preserving the shared writer and all gates.
pub fn compose_projected_owned_with_symbols(
    engine_bytes: &[u8],
    batch: FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
    projection: &crate::class_projection::ClassProjection,
    values: &dyn crate::class_projection::TypeValuePolicy,
    stage: Option<&dyn NonTextOutputStage>,
    symbols: &SymbolTable,
) -> Result<Vec<u8>, CompositionError> {
    validate_projected(&batch, frontend, projection, stage)?;
    compose_records_access(
        engine_bytes,
        BatchAccess::Owned(batch),
        symbols,
        Some((projection, values)),
        stage,
        None,
    )
    .map(byond_dmb::dmb::EncodedDmb::into_bytes)
}
#[allow(clippy::too_many_arguments)] // Explicit captured composition inputs and request-owned executor.
pub fn compose_projected_owned_with_symbols_on_executor(
    engine_bytes: &[u8],
    batch: FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
    projection: &crate::class_projection::ClassProjection,
    values: &dyn crate::class_projection::TypeValuePolicy,
    stage: Option<&dyn NonTextOutputStage>,
    symbols: &SymbolTable,
    executor: &dm_exec::BuildExecutor,
) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
    validate_projected(&batch, frontend, projection, stage)?;
    compose_records_access(
        engine_bytes,
        BatchAccess::Owned(batch),
        symbols,
        Some((projection, values)),
        stage,
        Some(executor),
    )
}
/// Consuming counterpart to the bounded reference/global fixture writer.
pub fn compose_global_fixture_owned(
    engine_bytes: &[u8],
    batch: FrozenBatch,
    symbols: &SymbolTable,
) -> Result<Vec<u8>, CompositionError> {
    compose_records_access(
        engine_bytes,
        BatchAccess::Owned(batch),
        symbols,
        None,
        None,
        None,
    )
    .map(byond_dmb::dmb::EncodedDmb::into_bytes)
}
