//! Bounded admission and consuming cold completion before source-ordered aggregation.
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
pub fn lower_frontend_completed_on_execution<
    'frontend,
    R: Resolver,
    P: AbiPolicy,
    T: Send,
    E: Send,
>(
    frontend: &'frontend ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: Option<&crate::startup::CapturedStartup<'frontend>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    execution: LoweringExecution<'_, 'frontend>,
    complete: &(impl Fn(LoweredUnit) -> Result<T, E> + Sync),
) -> CompletedLoweringBatch<T, E> {
    lower_frontend_completed_input_on_execution(
        frontend,
        host,
        policy,
        config,
        startup,
        memo,
        execution,
        false,
        &|input| complete(input.into_lowered()),
    )
}
#[allow(clippy::too_many_arguments)]
pub fn lower_frontend_completed_input_on_execution<
    'frontend,
    R: Resolver,
    P: AbiPolicy,
    T: Send,
    E: Send,
>(
    frontend: &'frontend ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: Option<&crate::startup::CapturedStartup<'frontend>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    execution: LoweringExecution<'_, 'frontend>,
    symbolic: bool,
    complete: &(impl Fn(CompletedInput) -> Result<T, E> + Sync),
) -> CompletedLoweringBatch<T, E> {
    let executor = execution.executor;
    let prepared = execution
        .prepared_roster
        .filter(|roster| roster.authenticates(frontend));
    // A foreign request owner is never authority; compatibility callers take
    // the ordinary current-input path, including its own diagnostics.
    if symbolic {
        if let Some(store) = memo.and_then(|memo| memo.symbolic.as_ref()) {
            store.retain_current(frontend, prepared);
        }
    }
    let request_admission = memo
        .and_then(|memo| memo.symbolic.as_ref())
        .filter(|_| !host.observes_reads())
        .map(|_| symbolic_input::RequestAdmission::new(host));
    let request_admission = request_admission.as_ref();
    let candidate_roster = request_admission
        .filter(|_| (symbolic || execution.selections_only) && !execution.capture_references)
        .and_then(|admission| {
            memo.and_then(|memo| memo.symbolic.as_ref())?
                .candidate_roster(admission)
        });
    let chunk = config.max_chunk.clamp(1, 256);
    let mut bodies: Vec<_> = execution.selected_bodies.map_or_else(
        || {
            prepared.map_or_else(
                || frontend.bodies.iter().map(|body| (body, None)).collect(),
                |roster| {
                    roster
                        .ordered()
                        .map(|row| (row.body(), Some(row)))
                        .collect()
                },
            )
        },
        |selected| {
            selected
                .iter()
                .map(|body| (*body, prepared.and_then(|roster| roster.selected(body))))
                .collect()
        },
    );
    if execution.selected_bodies.is_some() {
        let mut seen = std::collections::BTreeSet::new();
        let mut invalid = Vec::new();
        for (body, row) in &bodies {
            let admitted = if prepared.is_some() {
                row.is_some()
            } else {
                frontend.body_input(body).is_ok()
            };
            if !admitted || !seen.insert(body.declaration.0) {
                invalid.push(LoweringDiagnostic {
                    related: Vec::new(),
                    kind: DiagnosticKind::Internal,
                    identity: None,
                    origin: body.source.clone(),
                    message: "reference query requires unique current body issuance".into(),
                });
            }
        }
        if !invalid.is_empty() {
            return CompletedLoweringBatch {
                diagnostics: invalid,
                ..Default::default()
            };
        }
    }
    if prepared.is_none() || execution.selected_bodies.is_some() {
        bodies.sort_by_key(|(body, _)| {
            (
                body.source.encounter_ordinal,
                body.expanded_span.start,
                body.declaration.0,
            )
        });
    }
    let internal = |body: &BodyOccurrence, message: String| {
        vec![LoweringDiagnostic {
            related: Vec::new(),
            kind: DiagnosticKind::Internal,
            identity: None,
            origin: body.source.clone(),
            message,
        }]
    };
    let consume = |position: usize, input: Result<CompletedInput, Vec<LoweringDiagnostic>>| {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            input.map(|unit| {
                let identity = unit.identity();
                let effective = unit.effective();
                complete(unit)
                    .map(|value| CompletedUnit {
                        identity,
                        effective,
                        value,
                    })
                    .map_err(|error| Box::new((bodies[position].0.clone(), error)))
            })
        }))
        .unwrap_or_else(|_| {
            Err(internal(
                bodies[position].0,
                "procedure lowering worker panicked".into(),
            ))
        })
    };
    let mut outcomes: Vec<_> = (0..bodies.len()).map(|_| None).collect();
    // Bound live miss preparation to one worker-sized window. Cold requests
    // must not retain every parsed body and proof ledger before producing code.
    let window_size = chunk.saturating_mul(executor.workers().max(1)).max(1);
    for (window_index, window) in bodies.chunks(window_size).enumerate() {
        let start = window_index * window_size;
        // Current admission remains exhaustive. Only declined candidates enter the
        // cold lowering queue; neither phase creates another cache or model.
        let indexed: Vec<_> = window.iter().enumerate().collect();
        let admitted = memo::map_stage(executor, &indexed, chunk, &|(
            local_position,
            (body, prepared_body),
        )| {
            crate::daemon::control::checkpoint()
                .map_err(|error| internal(body, error.to_string()))?;
            memo::admit_one_input(
                frontend,
                body,
                host,
                request_admission,
                candidate_roster.as_ref(),
                policy,
                startup,
                memo,
                execution.bodies,
                symbolic,
                execution.capture_references,
                execution.selections_only,
                execution.disk_replay_bindings,
                *prepared_body,
            )
            .map(|attempt| match attempt {
                memo::Admission::Admitted(input) => {
                    (Some(consume(start + *local_position, Ok(input))), None)
                }
                pending @ memo::Admission::NeedsLowering(_) => (None, Some(pending)),
            })
        });
        let mut pending = Vec::new();
        for (local_position, input) in admitted.into_iter().enumerate() {
            let position = start + local_position;
            match input {
                Some(Ok((Some(completed), None))) => outcomes[position] = Some(completed),
                Some(Ok((None, Some(attempt)))) => {
                    pending.push((position, std::sync::Mutex::new(Some(attempt))))
                }
                Some(Err(errors)) => outcomes[position] = Some(Err(errors)),
                None | Some(Ok(_)) => {
                    outcomes[position] = Some(Err(internal(
                        bodies[position].0,
                        "procedure admission worker panicked".into(),
                    )))
                }
            }
        }
        let produced = memo::map_stage(executor, &pending, chunk, &|(position, slot)| {
            let _profile = dm_profile::stage("cold.procedure_lowering");
            let attempt = slot
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .take()
                .expect("each pending producer runs once");
            let input = crate::daemon::control::checkpoint()
                .map_err(|error| internal(bodies[*position].0, error.to_string()))
                .and_then(|_| attempt.finish());
            consume(*position, input)
        });
        for ((position, _), result) in pending.into_iter().zip(produced) {
            outcomes[position] = Some(result.unwrap_or_else(|| {
                Err(internal(
                    bodies[position].0,
                    "procedure lowering worker panicked".into(),
                ))
            }));
        }
    }
    let mut batch = CompletedLoweringBatch::default();
    for (position, outcome) in outcomes.into_iter().enumerate() {
        match outcome.unwrap_or_else(|| {
            Err(internal(
                bodies[position].0,
                "procedure lowering job did not complete".into(),
            ))
        }) {
            Ok(Ok(unit)) => batch.units.push(unit),
            Ok(Err(error)) => batch.completion_errors.push(*error),
            Err(errors) => batch.diagnostics.extend(errors),
        }
    }
    batch
}
