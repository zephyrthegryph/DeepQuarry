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
/// Borrow the producer's exact current order; only explicit/custom selections own rows.
enum CurrentBodies<'request, 'frontend> {
    Prepared(&'request PreparedBodyRoster<'frontend>),
    Selected(
        Vec<(
            &'frontend BodyOccurrence,
            Option<&'request PreparedBody<'frontend>>,
        )>,
    ),
}
impl<'request, 'frontend> CurrentBodies<'request, 'frontend> {
    fn len(&self) -> usize {
        match self {
            Self::Prepared(r) => r.len(),
            Self::Selected(v) => v.len(),
        }
    }
    fn at(
        &self,
        index: usize,
    ) -> (
        &'frontend BodyOccurrence,
        Option<&'request PreparedBody<'frontend>>,
    ) {
        match self {
            Self::Prepared(r) => {
                let roster: &'request PreparedBodyRoster<'frontend> = *r;
                let row = roster.at(index);
                (row.body(), Some(row))
            }
            Self::Selected(v) => v[index],
        }
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
    // A complete current body issuer is required alongside the already admitted
    // ABI graph. Custom policies and absent current rosters decline.
    let local_inputs = prepared.and_then(|_| {
        policy.current_local_inputs(
            frontend,
            startup.map_or(frontend.snapshot.tree.symbols(), |startup| {
                startup.plan().symbols.as_ref()
            }),
        )
    });
    let chunk = config.max_chunk.clamp(1, 256);
    let bodies = if execution.selected_bodies.is_none() && prepared.is_some() {
        CurrentBodies::Prepared(prepared.expect("checked current roster"))
    } else {
        let mut rows: Vec<_> = execution.selected_bodies.map_or_else(
            || frontend.bodies.iter().map(|body| (body, None)).collect(),
            |selected| {
                selected
                    .iter()
                    .map(|body| (*body, prepared.and_then(|roster| roster.selected(body))))
                    .collect()
            },
        );
        rows.sort_by_key(|(body, _)| {
            (
                body.source.encounter_ordinal,
                body.expanded_span.start,
                body.declaration.0,
            )
        });
        CurrentBodies::Selected(rows)
    };
    if execution.selected_bodies.is_some() {
        let mut seen = std::collections::BTreeSet::new();
        let mut invalid = Vec::new();
        for position in 0..bodies.len() {
            let (body, row) = bodies.at(position);
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
    let internal = |body: &BodyOccurrence, message: String| {
        vec![LoweringDiagnostic {
            related: Vec::new(),
            kind: DiagnosticKind::Internal,
            identity: None,
            origin: body.source.clone(),
            message,
        }]
    };
    // Summed worker elapsed time can exceed request wall time under parallelism.
    // These request-local counters are absent when progress is disabled.
    let worker_elapsed = execution.progress_enabled.then(|| {
        (
            std::sync::atomic::AtomicU64::new(0),
            std::sync::atomic::AtomicU64::new(0),
        )
    });
    let consume = |position: usize, input: Result<CompletedInput, Vec<LoweringDiagnostic>>| {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            input.map(|unit| {
                let identity = unit.identity();
                let effective = unit.effective();
                let started = worker_elapsed.as_ref().map(|_| std::time::Instant::now());
                let completed = complete(unit);
                if let (Some(started), Some((_, completion))) = (started, &worker_elapsed) {
                    completion.fetch_add(
                        started.elapsed().as_nanos().min(u64::MAX as u128) as u64,
                        std::sync::atomic::Ordering::Relaxed,
                    );
                }
                completed
                    .map(|value| CompletedUnit {
                        identity,
                        effective,
                        value,
                    })
                    .map_err(|error| Box::new((bodies.at(position).0.clone(), error)))
            })
        }))
        .unwrap_or_else(|_| {
            Err(internal(
                bodies.at(position).0,
                "procedure lowering worker panicked".into(),
            ))
        })
    };
    let mut outcomes: Vec<_> = (0..bodies.len()).map(|_| None).collect();
    // Bound live miss preparation to one worker-sized window. Cold requests
    // must not retain every parsed body and proof ledger before producing code.
    let window_size = chunk.saturating_mul(executor.workers().max(1)).max(1);
    let progress_started = execution.progress_enabled.then(std::time::Instant::now);
    let mut last_progress = progress_started;
    let mut last_completed = 0usize;
    let mut admission_elapsed = std::time::Duration::ZERO;
    let mut lowering_elapsed = std::time::Duration::ZERO;
    for start in (0..bodies.len()).step_by(window_size) {
        let end = start.saturating_add(window_size).min(bodies.len());
        let window: Vec<_> = (start..end).map(|position| bodies.at(position)).collect();
        // Current admission remains exhaustive. Only declined candidates enter the
        // cold lowering queue; neither phase creates another cache or model.
        let indexed: Vec<_> = window.iter().enumerate().collect();
        let admission_started = progress_started.map(|_| std::time::Instant::now());
        let admitted = memo::map_stage(executor, &indexed, chunk, &|(
            local_position,
            (body, prepared_body),
        )| {
            crate::daemon::control::checkpoint()
                .map_err(|error| internal(body, error.to_string()))?;
            // Fully qualified unchanged rows bypass key/ABI preparation. Current
            // origins/helpers are still rebound through the same contribution core.
            if symbolic && !execution.capture_references && !execution.selections_only {
                if let (Some(store), Some(roster), Some(candidates), Some(row), Some(memo)) = (
                    memo.and_then(|memo| memo.symbolic.as_ref()),
                    local_inputs.as_ref(),
                    candidate_roster.as_ref(),
                    *prepared_body,
                    memo,
                ) {
                    if !memo.verification.enabled() {
                        if let Some(input) = store.lookup_unchanged_local(
                            roster,
                            candidates,
                            memo.policy,
                            host,
                            frontend,
                            row,
                            execution.bodies,
                        ) {
                            memo.counts
                                .resident_hits
                                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                            return Ok((Some(consume(start + *local_position, Ok(input))), None));
                        }
                    }
                }
            }
            memo::admit_one_input(
                frontend,
                body,
                host,
                request_admission,
                candidate_roster.as_ref(),
                local_inputs.as_ref(),
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
        if let Some(started) = admission_started {
            admission_elapsed += started.elapsed();
        }
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
                        bodies.at(position).0,
                        "procedure admission worker panicked".into(),
                    )))
                }
            }
        }
        let lowering_started = progress_started.map(|_| std::time::Instant::now());
        let produced = memo::map_stage(executor, &pending, chunk, &|(position, slot)| {
            let _profile = dm_profile::stage("cold.procedure_lowering");
            let attempt = slot
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .take()
                .expect("each pending producer runs once");
            let input = crate::daemon::control::checkpoint()
                .map_err(|error| internal(bodies.at(*position).0, error.to_string()))
                .and_then(|_| {
                    let started = worker_elapsed.as_ref().map(|_| std::time::Instant::now());
                    let produced = attempt.finish();
                    if let (Some(started), Some((production, _))) = (started, &worker_elapsed) {
                        production.fetch_add(
                            started.elapsed().as_nanos().min(u64::MAX as u128) as u64,
                            std::sync::atomic::Ordering::Relaxed,
                        );
                    }
                    produced
                });
            consume(*position, input)
        });
        for ((position, _), result) in pending.into_iter().zip(produced) {
            outcomes[position] = Some(result.unwrap_or_else(|| {
                Err(internal(
                    bodies.at(position).0,
                    "procedure lowering worker panicked".into(),
                ))
            }));
        }
        if let Some(started) = lowering_started {
            lowering_elapsed += started.elapsed();
        }
        if let (Some(started), Some(previous)) = (progress_started, last_progress) {
            if end == bodies.len()
                || end.saturating_sub(last_completed) >= 1024
                || previous.elapsed() >= std::time::Duration::from_secs(2)
            {
                crate::daemon_eprintln!(
                    "native procedure lowering completed={}/{} elapsed={:.3}s admission_windows={:.3}s lowering_windows={:.3}s production_worker_elapsed_sum={:.3}s completion_worker_elapsed_sum={:.3}s",
                    end,
                    bodies.len(),
                    started.elapsed().as_secs_f64(),
                    admission_elapsed.as_secs_f64(),
                    lowering_elapsed.as_secs_f64(),
                    worker_elapsed.as_ref().map_or(0.0, |(production, _)| {
                        production.load(std::sync::atomic::Ordering::Relaxed) as f64 / 1e9
                    }),
                    worker_elapsed.as_ref().map_or(0.0, |(_, completion)| {
                        completion.load(std::sync::atomic::Ordering::Relaxed) as f64 / 1e9
                    })
                );
                last_completed = end;
                last_progress = Some(std::time::Instant::now());
            }
        }
    }
    let mut batch = CompletedLoweringBatch::default();
    for (position, outcome) in outcomes.into_iter().enumerate() {
        match outcome.unwrap_or_else(|| {
            Err(internal(
                bodies.at(position).0,
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
