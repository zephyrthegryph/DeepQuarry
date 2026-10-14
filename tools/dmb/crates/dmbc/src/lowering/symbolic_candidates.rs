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
        if std::env::var_os("DMB_TIMINGS_DETAIL").is_some_and(|value| value == "2") {
            for (reason, members) in owner.values.rejection_summary(admission, 8) {
                eprintln!("detail unchanged-roster rejection: {members} variants: {reason}");
            }
        }
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
        self.take_identity_if(identity, |_| true)
    }
    pub(super) fn take_identity_if(
        &self,
        identity: UnitIdentity,
        qualify: impl FnMut(&Arc<Record>) -> bool,
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
        let prefix = crate::symbolic::shared_procedure_code::main_key(identity);
        // The routing predicate compares weak issuer witnesses and metadata; it
        // must not run under the roster lock or every worker serializes on it.
        // Only this identity's body asks for these slots, so none is consumed
        // between the snapshot and the take; a vanished slot is simply skipped.
        let present = self
            .values
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .prefix_values(&prefix);
        let mut qualify = qualify;
        let slots: Vec<usize> = present
            .iter()
            .rev()
            .filter(|(_, value)| qualify(value))
            .map(|(slot, _)| *slot)
            .collect();
        if slots.is_empty() {
            return Vec::new();
        }
        self.values
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take_slots(&slots)
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
