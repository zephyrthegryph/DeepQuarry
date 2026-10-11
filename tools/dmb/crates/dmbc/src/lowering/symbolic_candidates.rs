//! Request-local dispatch over candidates certified by the existing store.
use super::*;
#[cfg(test)]
#[path = "symbolic_candidates_tests.rs"]
mod tests;
pub(in crate::lowering) struct RequestCandidates<'request, 'host, R> {
    values: Mutex<
        dm_session::UnchangedCandidates<
            'request,
            'host,
            Record,
            dm_ir::ResolveQuery,
            dm_ir::ResolvedMeaning,
            dm_ir::ReadDomain,
            R,
        >,
    >,
}
impl SessionSymbolicMemo {
    pub(in crate::lowering) fn candidate_roster<'request, 'host, R: Resolver>(
        &self,
        admission: &'request RequestAdmission<'host, R>,
    ) -> Option<RequestCandidates<'request, 'host, R>> {
        self.attempt.as_ref()?;
        let owner = self.publication.as_ref()?;
        Some(RequestCandidates {
            values: Mutex::new(owner.values.unchanged_candidate_roster(admission)),
        })
    }
}
impl<'request, 'host, R> RequestCandidates<'request, 'host, R> {
    pub(super) fn take_identity(
        &self,
        identity: UnitIdentity,
    ) -> Vec<
        dm_session::UnchangedCandidate<
            'request,
            'host,
            Record,
            dm_ir::ResolveQuery,
            dm_ir::ResolvedMeaning,
            dm_ir::ReadDomain,
            R,
        >,
    > {
        let prefix = symbolic_publication::locator(identity, &[]);
        self.values
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take_prefix(&prefix)
    }
    #[cfg(test)]
    pub(super) fn take(
        &self,
        key: &[u8],
    ) -> Vec<
        dm_session::UnchangedCandidate<
            'request,
            'host,
            Record,
            dm_ir::ResolveQuery,
            dm_ir::ResolvedMeaning,
            dm_ir::ReadDomain,
            R,
        >,
    > {
        self.values
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take(key)
    }
}
