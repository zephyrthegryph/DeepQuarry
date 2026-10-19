//! Request-local dispatch over candidates certified by the existing store.
use super::*;
#[cfg(test)]
#[path = "symbolic_candidates_tests.rs"]
mod tests;
/// Candidate shards. Every lookup routes by its unit's main-key prefix, so workers
/// lowering different units no longer serialize on one roster lock.
const CANDIDATE_SHARDS: usize = 64;
fn candidate_shard(key: &[u8]) -> usize {
    let prefix = &key[..key.len().min(crate::symbolic::shared_procedure_code::MAIN_KEY_BYTES)];
    xxhash_rust::xxh3::xxh3_64(prefix) as usize % CANDIDATE_SHARDS
}
pub(in crate::lowering) struct RequestCandidates<'request, 'host, R> {
    values: Vec<Mutex<
        dm_session::UnchangedCandidates<
            'request,
            'host,
            Record,
            dm_ir::ResolveQuery,
            dm_ir::ResolvedMeaning,
            dm_ir::ReadDomain,
            R,
        >,
    >>,
}
impl<'request, 'host, R> RequestCandidates<'request, 'host, R> {
    fn shard_for(
        &self,
        key: &[u8],
    ) -> &Mutex<
        dm_session::UnchangedCandidates<
            'request,
            'host,
            Record,
            dm_ir::ResolveQuery,
            dm_ir::ResolvedMeaning,
            dm_ir::ReadDomain,
            R,
        >,
    > {
        &self.values[candidate_shard(key)]
    }
}
/// Units of the last request proven unchanged by the session's query database: every recorded
/// answer equals the current one. Replaces the domain-version roster.
fn proven_roster<'request, 'host, R: Resolver>(
    db: &crate::query_db::QueryDb,
    store: &dm_session::ObservedArtifactStore<
        Record,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
    >,
    admission: &'request RequestAdmission<'host, R>,
    tree: Option<&dm_tree::SemanticTree>,
) -> Option<
    dm_session::UnchangedCandidates<
        'request,
        'host,
        Record,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
        R,
    >,
> {
    use dm_session::ObservationHost;
    if !admission.allows_certificate_reuse() {
        return None;
    }
    let host = admission.host();
    let workers = std::thread::available_parallelism().map_or(8, |n| n.get()).min(8);
    let proven = db.proven_unchanged(
        store.variant_snapshot(),
        &|query| host.answer_for_admission(query),
        tree,
        workers,
    );
    Some(dm_session::UnchangedCandidates::from_proven(admission, proven))
}
impl SessionSymbolicMemo {
    pub(in crate::lowering) fn candidate_roster<'request, 'host, R: Resolver>(
        &self,
        admission: &'request RequestAdmission<'host, R>,
    ) -> Option<RequestCandidates<'request, 'host, R>> {
        self.candidate_roster_in(admission, None)
    }
    /// As [`Self::candidate_roster`]; `tree` lets the query database skip answers the current
    /// tree's classified declaration change cannot reach.
    pub(in crate::lowering) fn candidate_roster_in<'request, 'host, R: Resolver>(
        &self,
        admission: &'request RequestAdmission<'host, R>,
        tree: Option<&dm_tree::SemanticTree>,
    ) -> Option<RequestCandidates<'request, 'host, R>> {
        self.attempt.as_ref()?;
        let owner = self.publication.as_ref()?;
        if std::env::var_os("DMB_TIMINGS_DETAIL").is_some_and(|value| value == "2") {
            let limit = std::env::var("DMB_ROSTER_REJECTIONS").ok().and_then(|value| value.parse().ok()).unwrap_or(8);
            for (reason, members) in owner.values.rejection_summary(admission, limit) {
                eprintln!("detail unchanged-roster rejection: {members} variants: {reason}");
            }
        }
        Some(RequestCandidates {
            values: self
                .query_db
                .as_deref()
                .and_then(|db| proven_roster(db, &owner.values, admission, tree))
                .unwrap_or_else(|| owner.values.unchanged_candidate_roster(admission))
                .split_by(CANDIDATE_SHARDS, candidate_shard)
                .into_iter()
                .map(Mutex::new)
                .collect(),
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
            .shard_for(&prefix)
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
        self.shard_for(&prefix)
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
        self.shard_for(key)
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take(key)
    }
}
