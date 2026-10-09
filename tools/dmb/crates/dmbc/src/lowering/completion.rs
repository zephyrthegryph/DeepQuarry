//! Same-worker consuming completion, after all memo capture, before aggregation.
use super::*;

pub struct CompletedUnit<T> {
    pub identity: UnitIdentity,
    pub effective: bool,
    pub value: T,
}
pub struct CompletedLoweringBatch<T, E> {
    pub units: Vec<CompletedUnit<T>>,
    pub diagnostics: Vec<LoweringDiagnostic>,
    /// Source ordered separately: callers report all lowering diagnostics first,
    /// then the first completion error at its original pipeline stage.
    pub completion_errors: Vec<(BodyOccurrence, E)>,
}
impl<T, E> Default for CompletedLoweringBatch<T, E> {
    fn default() -> Self {
        Self {
            units: Vec::new(),
            diagnostics: Vec::new(),
            completion_errors: Vec::new(),
        }
    }
}
impl<T, E> CompletedLoweringBatch<T, E> {
    pub fn identity_index(&self) -> Result<BTreeMap<UnitIdentity, usize>, UnitIdentity> {
        let mut index = BTreeMap::new();
        for (position, unit) in self.units.iter().enumerate() {
            if index.insert(unit.identity, position).is_some() {
                return Err(unit.identity);
            }
        }
        Ok(index)
    }
}
#[allow(clippy::too_many_arguments)]
pub fn lower_frontend_completed_on_execution<R: Resolver, P: AbiPolicy, T: Send, E: Send>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    execution: LoweringExecution<'_, '_>,
    complete: &(impl Fn(LoweredUnit) -> Result<T, E> + Sync),
) -> CompletedLoweringBatch<T, E> {
    let executor = execution.executor;
    let workers = executor.workers();
    let chunk = config.max_chunk.clamp(1, 256);
    let mut bodies: Vec<_> = frontend.bodies.iter().collect();
    bodies.sort_by_key(|body| {
        (
            body.source.encounter_ordinal,
            body.expanded_span.start,
            body.declaration.0,
        )
    });
    // Only final outputs occupy indexed slots. Each worker holds at most one
    // bounded chunk; publication remains inside the existing memo producer.
    let slices: Vec<_> = bodies.chunks(chunk).collect();
    let results: Vec<_> = (0..slices.len())
        .map(|_| std::sync::Mutex::new(None))
        .collect();
    let next = std::sync::atomic::AtomicUsize::new(0);
    let scheduling = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for _ in 0..workers.min(slices.len()) {
                let slices = &slices;
                let results = &results;
                let next = &next;
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("cold.procedure_lowering");
                    loop {
                        let index = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                        let Some(slice) = slices.get(index) else {
                            break;
                        };
                        let outcomes =
                            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                slice
                                    .iter()
                                    .map(|body| {
                                        lower_one_memo(
                                            frontend,
                                            body,
                                            host,
                                            policy,
                                            startup,
                                            memo,
                                            execution.bodies,
                                        )
                                        .map(|unit| {
                                            // Memo capture/remember already completed. The
                                            // consuming mapper cannot mutate persisted IR.
                                            let identity = unit.identity;
                                            let effective = unit.effective;
                                            let origin = unit.origin.clone();
                                            complete(unit)
                                                .map(|value| CompletedUnit {
                                                    identity,
                                                    effective,
                                                    value,
                                                })
                                                .map_err(|error| Box::new((origin, error)))
                                        })
                                    })
                                    .collect::<Vec<_>>()
                            }))
                            .unwrap_or_else(|_| {
                                slice
                                    .iter()
                                    .map(|body| {
                                        Err(vec![LoweringDiagnostic {
                                            kind: DiagnosticKind::Internal,
                                            identity: None,
                                            origin: body.source.clone(),
                                            message: "procedure lowering worker panicked".into(),
                                        }])
                                    })
                                    .collect()
                            });
                        *results[index]
                            .lock()
                            .unwrap_or_else(|error| error.into_inner()) = Some(outcomes);
                    }
                });
            }
        })
    }));
    // Every sibling job has joined before the scope propagates a panic. Missing
    // slots become source-ordered internal diagnostics rather than escaping.
    let scheduling_failed = scheduling.is_err();
    let mut batch = CompletedLoweringBatch::default();
    for (index, slot) in results.into_iter().enumerate() {
        let outcomes = slot.into_inner().unwrap_or_else(|error| error.into_inner());
        let outcomes = outcomes.unwrap_or_else(|| {
            slices[index]
                .iter()
                .map(|body| {
                    Err(vec![LoweringDiagnostic {
                        kind: DiagnosticKind::Internal,
                        identity: None,
                        origin: body.source.clone(),
                        message: if scheduling_failed {
                            "procedure scheduling worker panicked"
                        } else {
                            "procedure lowering job did not complete"
                        }
                        .into(),
                    }])
                })
                .collect()
        });
        for outcome in outcomes {
            match outcome {
                Ok(Ok(unit)) => batch.units.push(unit),
                Ok(Err(error)) => batch.completion_errors.push(*error),
                Err(errors) => batch.diagnostics.extend(errors),
            }
        }
    }
    batch
}
