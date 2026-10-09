//! Consuming preparation result and source-independent output handoff.
use super::*;
use std::sync::Arc;

/// Complete linked source preparation. Its private fields cannot be fabricated
/// or deserialized into a source-validation certificate.
pub struct PreparedCold {
    pub(super) frozen: crate::symbolic::FrozenBatch,
    pub(super) projection: crate::class_projection::ClassProjection,
    pub(super) modified: Vec<(
        dm_ir::SymRef,
        dm_codegen_byond::lower_resolver::CapturedModifiedInstance,
    )>,
    pub(super) symbols: Arc<dm_ir::SymbolTable>,
    pub(super) startup: Option<Arc<crate::startup::StartupFacts>>,
    pub(super) timings: ColdTimings,
    pub(super) started: Instant,
}

/// Source-validated output work. No frontend, resolver or startup owner survives
/// this boundary; the existing composer still performs its downstream checks.
pub struct PreparedComposition {
    composition: crate::composition::ValidatedComposition,
    timings: ColdTimings,
    started: Instant,
}

impl PreparedCold {
    pub fn domains(&self) -> crate::type_values::PreparedValueDomains {
        let mut domains =
            crate::type_values::PreparedValueDomains::for_projection(&self.projection);
        for (_, captured) in &self.modified {
            domains.include_type(captured.descriptor.runtime_type());
        }
        domains
    }

    pub fn seal(
        self,
        frontend: &ColdFrontend,
        engine: Arc<[u8]>,
        values: Arc<dyn crate::class_projection::TypeValuePolicy>,
        stage: Option<Box<dyn crate::composition::NonTextOutputStage>>,
    ) -> Result<PreparedComposition, ColdError> {
        let modified = OwnedModifiedStage {
            descriptors: self.modified,
            types: Arc::clone(&values),
            next: stage,
        };
        let composition = crate::composition::ValidatedComposition::prepare(
            frontend,
            crate::composition::OwnedCompositionInputs {
                engine,
                batch: self.frozen,
                symbols: self.symbols,
                projection: self.projection,
                values,
                stage: Some(Box::new(modified)),
            },
        )
        .map_err(ColdError::Composition)?;
        // The one-shot path intentionally releases the shared semantic tree
        // held by StartupFacts before composition begins.
        drop(self.startup);
        Ok(PreparedComposition {
            composition,
            timings: self.timings,
            started: self.started,
        })
    }

    pub(crate) fn compose_borrowed(
        self,
        engine: &[u8],
        frontend: &ColdFrontend,
        values: &dyn crate::class_projection::TypeValuePolicy,
        stage: Option<&dyn crate::composition::NonTextOutputStage>,
        executor: &dm_exec::BuildExecutor,
        observer: Option<&ColdObserver<'_>>,
    ) -> Result<ColdOutput, ColdError> {
        let started = Instant::now();
        let measurement = StageMeasurement::new(observer, ColdStage::Composition);
        let modified = crate::modified_initializers::Stage {
            descriptors: &self.modified,
            types: values,
            next: stage,
        };
        let dmb = crate::composition::compose_projected_owned_with_symbols_on_executor(
            engine,
            self.frozen,
            frontend,
            &self.projection,
            values,
            Some(&modified),
            self.symbols.as_ref(),
            executor,
        )
        .map_err(ColdError::Composition)?;
        measurement.complete();
        let mut timings = self.timings;
        timings.composition = started.elapsed();
        timings.total = self.started.elapsed();
        Ok(ColdOutput {
            dmb,
            timings,
            startup: self.startup,
        })
    }
}

impl PreparedComposition {
    pub fn compose(
        self,
        executor: &dm_exec::BuildExecutor,
        observer: Option<&ColdObserver<'_>>,
    ) -> Result<ColdOutput, ColdError> {
        let started = Instant::now();
        let measurement = StageMeasurement::new(observer, ColdStage::Composition);
        let dmb = self
            .composition
            .compose(executor)
            .map_err(ColdError::Composition)?;
        measurement.complete();
        let mut timings = self.timings;
        timings.composition = started.elapsed();
        timings.total = self.started.elapsed();
        Ok(ColdOutput {
            dmb,
            timings,
            startup: None,
        })
    }
}

struct OwnedModifiedStage {
    descriptors: Vec<(
        dm_ir::SymRef,
        dm_codegen_byond::lower_resolver::CapturedModifiedInstance,
    )>,
    types: Arc<dyn crate::class_projection::TypeValuePolicy>,
    next: Option<Box<dyn crate::composition::NonTextOutputStage>>,
}
impl OwnedModifiedStage {
    fn view(&self) -> crate::modified_initializers::Stage<'_> {
        crate::modified_initializers::Stage {
            descriptors: &self.descriptors,
            types: self.types.as_ref(),
            next: self.next.as_deref(),
        }
    }
}
impl crate::composition::NonTextOutputStage for OwnedModifiedStage {
    fn required_types(&self) -> Vec<dm_ir::SymbolId> {
        self.view().required_types()
    }
    fn validate_source(&self, frontend: &ColdFrontend) -> Result<(), String> {
        self.view().validate_source(frontend)
    }
    fn apply(
        &self,
        dmb: &mut byond_dmb::dmb::Dmb,
        batch: &crate::symbolic::FrozenBatch,
    ) -> Result<std::collections::BTreeSet<dm_link::Key>, String> {
        self.view().apply(dmb, batch)
    }
}
