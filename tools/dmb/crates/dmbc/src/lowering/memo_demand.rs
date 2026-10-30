//! Zero-state native/compatibility routing through the SAME memo algorithm.
use super::*;
pub(super) trait MemoDemand: 'static {
    type Failure: From<Vec<LoweringDiagnostic>> + Send + 'static;
    fn choose<A, T>(
        argument: A,
        legacy: impl FnOnce(A) -> T,
        checked: impl FnOnce(A) -> Result<T, LoweringFailure>,
    ) -> Result<T, Self::Failure>;
    fn semantic_failure(error: &Self::Failure) -> bool;
    fn lower<R: Resolver, P: AbiPolicy>(
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        startup: Option<&crate::startup::CapturedStartup>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        capture_references: bool,
        current: Option<SourceUnitIdentity>,
    ) -> Result<LoweredUnit, Self::Failure>;
    fn captured<R: Resolver, P: AbiPolicy>(
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        captured: LoweringCapture<'_, '_>,
    ) -> Result<LoweredUnit, Self::Failure>;
    fn verify<R: Resolver, P: AbiPolicy>(
        memo: &crate::lowering_memo::ProcedureMemo,
        expected: verify::Expected<'_>,
        old_reads: Option<&[(dm_ir::ResolveQuery, Vec<u8>)]>,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        startup: Option<&crate::startup::CapturedStartup>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        capture_references: bool,
        current: &PreparedBody<'_>,
        bindings: Option<DiskReplayBindings<'_>>,
        hit: &'static str,
    ) -> Result<(), Self::Failure>;
}
pub(super) struct CompatibilityMemo;
pub(super) struct CheckedMemo;
impl MemoDemand for CompatibilityMemo {
    type Failure = Vec<LoweringDiagnostic>;
    fn choose<A, T>(
        argument: A,
        legacy: impl FnOnce(A) -> T,
        _checked: impl FnOnce(A) -> Result<T, LoweringFailure>,
    ) -> Result<T, Self::Failure> {
        Ok(legacy(argument))
    }
    fn semantic_failure(_error: &Self::Failure) -> bool {
        true
    }
    fn lower<R: Resolver, P: AbiPolicy>(
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        startup: Option<&crate::startup::CapturedStartup>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        capture_references: bool,
        current: Option<SourceUnitIdentity>,
    ) -> Result<LoweredUnit, Self::Failure> {
        lower_one(
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
            current,
        )
    }
    fn captured<R: Resolver, P: AbiPolicy>(
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        captured: LoweringCapture<'_, '_>,
    ) -> Result<LoweredUnit, Self::Failure> {
        lower_one_captured(frontend, body, host, policy, bodies, captured)
    }
    fn verify<R: Resolver, P: AbiPolicy>(
        memo: &crate::lowering_memo::ProcedureMemo,
        expected: verify::Expected<'_>,
        old_reads: Option<&[(dm_ir::ResolveQuery, Vec<u8>)]>,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        startup: Option<&crate::startup::CapturedStartup>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        capture_references: bool,
        current: &PreparedBody<'_>,
        bindings: Option<DiskReplayBindings<'_>>,
        hit: &'static str,
    ) -> Result<(), Self::Failure> {
        verify::verify(
            memo,
            expected,
            old_reads,
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
            current,
            bindings,
            hit,
        )
    }
}
impl MemoDemand for CheckedMemo {
    type Failure = LoweringFailure;
    fn choose<A, T>(
        argument: A,
        _legacy: impl FnOnce(A) -> T,
        checked: impl FnOnce(A) -> Result<T, LoweringFailure>,
    ) -> Result<T, Self::Failure> {
        checked(argument)
    }
    fn semantic_failure(error: &Self::Failure) -> bool {
        matches!(error, LoweringFailure::Diagnostics(_))
    }
    fn lower<R: Resolver, P: AbiPolicy>(
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        startup: Option<&crate::startup::CapturedStartup>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        capture_references: bool,
        current: Option<SourceUnitIdentity>,
    ) -> Result<LoweredUnit, Self::Failure> {
        lower_one_checked(
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
            current,
        )
    }
    fn captured<R: Resolver, P: AbiPolicy>(
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        captured: LoweringCapture<'_, '_>,
    ) -> Result<LoweredUnit, Self::Failure> {
        lower_one_captured_checked(frontend, body, host, policy, bodies, captured)
    }
    fn verify<R: Resolver, P: AbiPolicy>(
        memo: &crate::lowering_memo::ProcedureMemo,
        expected: verify::Expected<'_>,
        old_reads: Option<&[(dm_ir::ResolveQuery, Vec<u8>)]>,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
        host: &R,
        policy: &P,
        startup: Option<&crate::startup::CapturedStartup>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
        capture_references: bool,
        current: &PreparedBody<'_>,
        bindings: Option<DiskReplayBindings<'_>>,
        hit: &'static str,
    ) -> Result<(), Self::Failure> {
        verify::verify_checked(
            memo,
            expected,
            old_reads,
            frontend,
            body,
            host,
            policy,
            startup,
            bodies,
            capture_references,
            current,
            bindings,
            hit,
        )
    }
}
/// Preparation rejection remains a normal current cold miss. Actual IO can
/// never be demoted to that rejection or stored in a procedure-failure record.
pub(super) fn checked_abi<T>(
    value: Result<T, dm_codegen_byond::procedure_abi::AbiError>,
) -> Result<Option<T>, LoweringFailure> {
    match value {
        Ok(value) => Ok(Some(value)),
        Err(error) => match error.into_operational() {
            Ok(error) => Err(LoweringFailure::Operational(error)),
            Err(_) => Ok(None),
        },
    }
}
pub(super) fn checked_body<T>(
    value: Result<T, dm_tree::frontend::BodySyntaxFailure>,
) -> Result<Result<T, dm_tree::frontend::Diagnostic>, LoweringFailure> {
    match value {
        Ok(value) => Ok(Ok(value)),
        Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error)) => Ok(Err(error)),
        Err(dm_tree::frontend::BodySyntaxFailure::Operational(error)) => {
            Err(LoweringFailure::Operational(error))
        }
    }
}
