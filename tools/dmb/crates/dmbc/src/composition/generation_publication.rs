//! Request-local composition owners; publication never admits a model or skips validation.
use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
pub(super) struct Pending {
    pub(super) current: Arc<Mutex<Option<Arc<Generation>>>>,
    pub(super) plan: Arc<Mutex<Option<Arc<procedure_plan::CachedPlan>>>>,
    pub(super) headers: Arc<crate::class_projection::HeaderRecipes>,
}
impl Default for RetainedGeneration {
    fn default() -> Self {
        let current = Arc::new(Mutex::new(None));
        let plan = Arc::new(Mutex::new(None));
        let header_recipes = Arc::new(Default::default());
        let publication = Arc::new(dm_session::ArtifactPublication::default());
        let attempt = publication.begin(Pending {
            current: Arc::clone(&current),
            plan: Arc::clone(&plan),
            headers: Arc::clone(&header_recipes),
        });
        Self {
            current,
            plan,
            header_recipes,
            publication,
            attempt,
            wire_evictions: AtomicU64::new(0),
        }
    }
}
impl RetainedGeneration {
    pub(crate) fn for_request(&self, publishable: bool) -> Arc<Self> {
        let snapshot =
            |current: &Arc<Mutex<Option<Arc<Generation>>>>,
             plan: &Arc<Mutex<Option<Arc<procedure_plan::CachedPlan>>>>,
             headers: &Arc<crate::class_projection::HeaderRecipes>| {
                (
                    current.lock().unwrap_or_else(|e| e.into_inner()).clone(),
                    plan.lock().unwrap_or_else(|e| e.into_inner()).clone(),
                    headers.for_request(publishable),
                )
            };
        let (current, plan, header_recipes) = self
            .publication
            .with_published(|old| snapshot(&old.current, &old.plan, &old.headers))
            .unwrap_or_else(|| snapshot(&self.current, &self.plan, &self.header_recipes));
        let current = Arc::new(Mutex::new(current));
        let plan = Arc::new(Mutex::new(plan));
        let pending = Pending {
            current: Arc::clone(&current),
            plan: Arc::clone(&plan),
            headers: Arc::clone(&header_recipes),
        };
        let attempt = if publishable {
            self.publication.begin(pending)
        } else {
            self.publication.begin_ephemeral(pending)
        };
        Arc::new(Self {
            current,
            plan,
            header_recipes,
            publication: Arc::clone(&self.publication),
            attempt,
            wire_evictions: AtomicU64::new(0),
        })
    }
    pub(crate) fn publish_successful(&self) -> bool {
        let headers = self.header_recipes.publish_successful();
        let group = self.attempt.publish_successful();
        headers && group
    }
    /// Explicit bounded cache eviction. It changes no attempt generation or published output pair.
    pub(super) fn evict_published_wire_memo(&self) {
        self.publication.with_published(|old| {
            let detached = old.current.lock().unwrap_or_else(|e| e.into_inner()).take();
            if detached.is_some() {
                self.wire_evictions.fetch_add(1, Ordering::Relaxed);
            }
            drop(detached);
        });
    }
    pub(crate) fn wire_memo_evictions(&self) -> u64 {
        self.wire_evictions.load(Ordering::Relaxed)
    }
    pub(super) fn visit_published(&self, mut visit: impl FnMut(&Pending)) {
        self.publication.with_published(|old| {
            if !Arc::ptr_eq(&old.current, &self.current) {
                visit(old);
            }
        });
    }
    pub(super) fn encode(
        &self,
        inputs: CertifiedGenerationInputs,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Result<byond_dmb::dmb::EncodedDmb, CompositionError> {
        let mut inputs = Some(inputs);
        self.attempt
            .with_pending(|_| {
                self.encode_pending(inputs.take().expect("one pending encode"), executor)
            })
            .unwrap_or_else(|| {
                let encoded = encode_model(&inputs.take().expect("sealed input").model, executor)?;
                validate_encoded(&encoded)?;
                Ok(encoded)
            })
    }
    pub(super) fn bind_plan(
        &self,
        raw: procedure_plan::CompositionPlan,
        batch: &FrozenBatch,
    ) -> procedure_plan::BoundCompositionPlan {
        let mut raw = Some(raw);
        self.attempt
            .with_pending(|_| self.bind_plan_pending(raw.take().expect("one pending plan"), batch))
            .unwrap_or_else(|| {
                let mut raw = raw.take().expect("sealed plan");
                raw.canonicalize();
                raw.bind(batch)
            })
    }
    pub(super) fn argument_sources(
        &self,
        tables: &dm_link::LinkTables,
        start: usize,
        order: &[Key],
    ) -> Result<Arc<dm_link::ArgumentSourceReferences>, dm_link::LinkError> {
        self.attempt
            .with_pending(|_| self.argument_sources_pending(tables, start, order))
            .unwrap_or_else(|| {
                dm_link::ArgumentSourceReferences::assign(tables, start, order).map(Arc::new)
            })
    }
    pub(super) fn prepare_metadata(
        &self,
        slots: &[procedure_plan::Slot<crate::lowering::UnitIdentity>],
        batch: &FrozenBatch,
        projection: Option<&crate::class_projection::ClassProjection>,
        symbols: &SymbolTable,
        references: &Arc<dm_link::ArgumentSourceReferences>,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> Vec<Result<procedure_plan::PreparedMetadata, CompositionError>> {
        self.attempt
            .with_pending(|_| {
                self.prepare_metadata_pending(
                    slots, batch, projection, symbols, references, executor,
                )
            })
            .unwrap_or_else(|| {
                procedure_plan::prepare_metadata(
                    slots, batch, projection, symbols, references, executor, true,
                )
            })
    }
}
