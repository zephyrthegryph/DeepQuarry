//! Stack-only failure routing; scheduler/order/worker-window algorithm is shared.
use super::*;
pub(super) trait CompletionDemand {
    type Failure: From<Vec<LoweringDiagnostic>> + Send;
    type Abort;
    fn split(error: Self::Failure) -> Result<Vec<LoweringDiagnostic>, Self::Abort>;
    fn checkpoint(
        diagnostic: impl FnOnce(std::io::Error) -> Vec<LoweringDiagnostic>,
    ) -> Result<(), Self::Failure>;
    fn admit<'a, 'frontend: 'a, R: Resolver, P: AbiPolicy>(
        frontend: &'frontend ColdFrontend,
        body: &'a BodyOccurrence,
        host: &'a R,
        request_admission: Option<&'a symbolic_input::RequestAdmission<'_, R>>,
        candidates: Option<&symbolic_input::RequestCandidates<'_, '_, R>>,
        local_inputs: Option<&LocalInputRoster<'_>>,
        policy: &'a P,
        startup: Option<&'a crate::startup::CapturedStartup<'frontend>>,
        memo: Option<&'a crate::lowering_memo::ProcedureMemo>,
        bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
        symbolic: bool,
        capture_references: bool,
        selections_only: bool,
        disk_replay_bindings: Option<DiskReplayBindings<'a>>,
        prepared_body: Option<&'a PreparedBody<'frontend>>,
    ) -> Result<memo::Admission<'a, Self::Failure>, Self::Failure>;
    fn local<R: Resolver>(
        store: &symbolic_input::SessionSymbolicMemo,
        roster: &LocalInputRoster<'_>,
        candidates: &symbolic_input::RequestCandidates<'_, '_, R>,
        policy: u128,
        host: &R,
        frontend: &ColdFrontend,
        row: &PreparedBody<'_>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
    ) -> Result<Option<CompletedInput>, Self::Failure>;
}
pub(super) struct CompatibilityCompletion;
pub(super) struct CheckedCompletion;
impl CompletionDemand for CompatibilityCompletion {
    type Failure = Vec<LoweringDiagnostic>;
    type Abort = std::convert::Infallible;
    fn split(error: Self::Failure) -> Result<Vec<LoweringDiagnostic>, Self::Abort> {
        Ok(error)
    }
    fn checkpoint(
        diagnostic: impl FnOnce(std::io::Error) -> Vec<LoweringDiagnostic>,
    ) -> Result<(), Self::Failure> {
        crate::daemon::control::checkpoint().map_err(diagnostic)
    }
    fn admit<'a, 'frontend: 'a, R: Resolver, P: AbiPolicy>(
        frontend: &'frontend ColdFrontend,
        body: &'a BodyOccurrence,
        host: &'a R,
        request_admission: Option<&'a symbolic_input::RequestAdmission<'_, R>>,
        candidates: Option<&symbolic_input::RequestCandidates<'_, '_, R>>,
        local_inputs: Option<&LocalInputRoster<'_>>,
        policy: &'a P,
        startup: Option<&'a crate::startup::CapturedStartup<'frontend>>,
        memo: Option<&'a crate::lowering_memo::ProcedureMemo>,
        bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
        symbolic: bool,
        capture_references: bool,
        selections_only: bool,
        disk_replay_bindings: Option<DiskReplayBindings<'a>>,
        prepared_body: Option<&'a PreparedBody<'frontend>>,
    ) -> Result<memo::Admission<'a, Self::Failure>, Self::Failure> {
        memo::admit_one_input(
            frontend,
            body,
            host,
            request_admission,
            candidates,
            local_inputs,
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
    }
    fn local<R: Resolver>(
        store: &symbolic_input::SessionSymbolicMemo,
        roster: &LocalInputRoster<'_>,
        candidates: &symbolic_input::RequestCandidates<'_, '_, R>,
        policy: u128,
        host: &R,
        frontend: &ColdFrontend,
        row: &PreparedBody<'_>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
    ) -> Result<Option<CompletedInput>, Self::Failure> {
        Ok(store.lookup_unchanged_local(roster, candidates, policy, host, frontend, row, bodies))
    }
}
impl CompletionDemand for CheckedCompletion {
    type Failure = LoweringFailure;
    type Abort = std::io::Error;
    fn split(error: Self::Failure) -> Result<Vec<LoweringDiagnostic>, Self::Abort> {
        match error {
            LoweringFailure::Diagnostics(errors) => Ok(errors),
            LoweringFailure::Operational(error) => Err(error),
        }
    }
    fn checkpoint(
        _diagnostic: impl FnOnce(std::io::Error) -> Vec<LoweringDiagnostic>,
    ) -> Result<(), Self::Failure> {
        crate::daemon::control::checkpoint().map_err(LoweringFailure::Operational)
    }
    fn admit<'a, 'frontend: 'a, R: Resolver, P: AbiPolicy>(
        frontend: &'frontend ColdFrontend,
        body: &'a BodyOccurrence,
        host: &'a R,
        request_admission: Option<&'a symbolic_input::RequestAdmission<'_, R>>,
        candidates: Option<&symbolic_input::RequestCandidates<'_, '_, R>>,
        local_inputs: Option<&LocalInputRoster<'_>>,
        policy: &'a P,
        startup: Option<&'a crate::startup::CapturedStartup<'frontend>>,
        memo: Option<&'a crate::lowering_memo::ProcedureMemo>,
        bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
        symbolic: bool,
        capture_references: bool,
        selections_only: bool,
        disk_replay_bindings: Option<DiskReplayBindings<'a>>,
        prepared_body: Option<&'a PreparedBody<'frontend>>,
    ) -> Result<memo::Admission<'a, Self::Failure>, Self::Failure> {
        memo::admit_one_input_checked(
            frontend,
            body,
            host,
            request_admission,
            candidates,
            local_inputs,
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
    }
    fn local<R: Resolver>(
        store: &symbolic_input::SessionSymbolicMemo,
        roster: &LocalInputRoster<'_>,
        candidates: &symbolic_input::RequestCandidates<'_, '_, R>,
        policy: u128,
        host: &R,
        frontend: &ColdFrontend,
        row: &PreparedBody<'_>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
    ) -> Result<Option<CompletedInput>, Self::Failure> {
        store
            .lookup_unchanged_local_checked(roster, candidates, policy, host, frontend, row, bodies)
            .map_err(LoweringFailure::Operational)
    }
}
