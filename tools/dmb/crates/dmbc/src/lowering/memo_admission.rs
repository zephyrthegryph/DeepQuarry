//! Consuming admission result; only misses own a pending cold producer.
use super::*;
#[cfg(test)]
#[path = "memo_admission_tests.rs"]
mod tests;
pub(super) enum Admission<'a> {
    Admitted(CompletedInput),
    NeedsLowering(Box<dyn FnOnce() -> Result<CompletedInput, Vec<LoweringDiagnostic>> + Send + 'a>),
}
impl Admission<'_> {
    pub(super) fn finish(self) -> Result<CompletedInput, Vec<LoweringDiagnostic>> {
        match self {
            Self::Admitted(input) => Ok(input),
            Self::NeedsLowering(produce) => produce(),
        }
    }
}

/// Both phases use the existing bracketed executor and retain source positions.
/// A panicked phase leaves an empty slot for the caller's ordinary diagnostic.
pub(super) fn map_stage<I: Sync, O: Send>(
    executor: &dm_exec::BuildExecutor,
    inputs: &[I],
    chunk: usize,
    map: &(impl Fn(&I) -> O + Sync),
) -> Vec<Option<O>> {
    let slices: Vec<_> = inputs.chunks(chunk.clamp(1, 256)).collect();
    let results: Vec<_> = slices.iter().map(|_| std::sync::Mutex::new(None)).collect();
    let next = std::sync::atomic::AtomicUsize::new(0);
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for _ in 0..executor.workers().min(slices.len()) {
                let slices = &slices;
                let results = &results;
                let next = &next;
                scope.spawn(move |_| loop {
                    let index = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let Some(slice) = slices.get(index) else {
                        break;
                    };
                    let outcomes = slice
                        .iter()
                        .map(|input| {
                            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| map(input)))
                                .ok()
                        })
                        .collect::<Vec<_>>();
                    *results[index]
                        .lock()
                        .unwrap_or_else(|error| error.into_inner()) = Some(outcomes);
                });
            }
        });
    }));
    results
        .into_iter()
        .zip(slices)
        .flat_map(|(slot, slice)| {
            slot.into_inner()
                .unwrap_or_else(|error| error.into_inner())
                .unwrap_or_else(|| (0..slice.len()).map(|_| None).collect())
        })
        .collect()
}
pub(super) fn lower_one_input<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    request_admission: Option<&symbolic_input::RequestAdmission<'_, R>>,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    symbolic: bool,
    capture_references: bool,
    selections_only: bool,
    disk_replay_bindings: Option<DiskReplayBindings<'_>>,
    prepared_body: Option<&PreparedBody<'_>>,
) -> Result<CompletedInput, Vec<LoweringDiagnostic>> {
    super::admit_one_input(
        frontend,
        body,
        host,
        request_admission,
        policy,
        startup,
        memo,
        bodies,
        symbolic,
        capture_references,
        selections_only,
        disk_replay_bindings,
        prepared_body,
    )
    .and_then(Admission::finish)
}
