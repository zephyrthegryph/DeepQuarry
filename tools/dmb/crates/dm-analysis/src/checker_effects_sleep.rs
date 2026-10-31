//! Blocking-call propagation over the SAME original effect plan.
//! Pinned DreamChecker call-tree order, including visited-before-skip.
use super::*;
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct SleepSettings {
    pub no_sleep: Option<Span>,
    pub exempt: Option<Span>,
    pub waitfor_disabled: bool,
}
pub(super) fn row(at: Span, message: String, notes: Vec<Note>) -> Diagnostic {
    Diagnostic {
        family: "must_not_sleep",
        severity: Severity::Error,
        span: at,
        expression_span: at,
        message,
        notes,
    }
}
impl EffectPlan {
    /// Borrows the existing BodyEffects, source-identity index and call edges.
    /// No second call graph, Proc table or source owner is materialized.
    pub fn sleep_report(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, String> {
        self.sleep_report_with::<crate::policy_body_demand::Compatibility>(
            input, resolver, policy, admission, checkpoint,
        )
        .map_err(|e| e.0)
    }
    pub fn sleep_report_checked(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, crate::policy_body_demand::PolicyFailure> {
        self.sleep_report_with::<crate::policy_body_demand::Checked>(
            input, resolver, policy, admission, checkpoint,
        )
    }
    fn sleep_report_with<D: crate::policy_body_demand::Demand>(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, D::Error> {
 self.validate(input)?;report_core::sleep(&report_core::LegacyReportAccess::<D>{input,plan:self,summary:None,demand:std::marker::PhantomData},resolver,policy,admission,||checkpoint().map_err(D::Error::from))
}
}
