//! Current local input proof attached to the same admitted symbolic record.
use super::*;
#[derive(Clone)]
pub(in crate::lowering) struct Certificate {
    graph: Arc<dm_tree::frontend::CallableAbiGraph>,
    inputs: Arc<dm_codegen_byond::lower_resolver::ProcedureInputs>,
    abi: Arc<crate::procedure_policy::PreparedAbi>,
    identity: UnitIdentity,
    policy: u128,
    termination: u8,
}
#[cfg(test)]
#[path = "symbolic_local_tests.rs"]
mod tests;

impl Certificate {
    pub(in crate::lowering) fn issue(
        roster: &LocalInputRoster<'_>,
        row: &PreparedBody<'_>,
        policy: u128,
    ) -> Option<Self> {
        let prepared = roster.prepared(row)?;
        Some(Self {
            graph: Arc::clone(roster.graph()?),
            inputs: prepared.inputs,
            abi: prepared.abi?,
            identity: row.source().identity,
            policy,
            termination: row.input().termination().canonical_tag(),
        })
    }
    fn matches(
        &self,
        roster: &LocalInputRoster<'_>,
        row: &PreparedBody<'_>,
        policy: u128,
        record: &Record,
    ) -> Option<PreparedUnit> {
        // Strong immutable owner identity is deliberately conservative: a new
        // graph owner declines, even if its semantic bytes could compare equal.
        if self.policy != policy
            || self.identity != row.source().identity
            || self.termination != row.input().termination().canonical_tag()
            || !Arc::ptr_eq(&self.graph, roster.graph()?)
        {
            return None;
        }
        let prepared = roster.prepared(row)?;
        if !Arc::ptr_eq(&self.inputs, &prepared.inputs)
            || !Arc::ptr_eq(&self.abi, prepared.abi.as_ref()?)
            || record.recipe.as_ref()?.metadata.as_ref() != roster.metadata(row)?.as_ref()
            || !record
                .recipe
                .as_ref()?
                .source_matches(&record.key, row.input().source().as_bytes())
        {
            return None;
        }
        Some(prepared)
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        census.shared_procedure_inputs(&self.inputs);
        census.abi(&self.abi);
        census.callable_abi_graph(&self.graph);
    }
}
impl SessionSymbolicMemo {
    #[allow(clippy::too_many_arguments)]
    pub(in crate::lowering) fn lookup_unchanged_local<R: Resolver>(
        &self,
        roster: &LocalInputRoster<'_>,
        candidates: &RequestCandidates<'_, '_, R>,
        policy: u128,
        host: &R,
        frontend: &ColdFrontend,
        row: &PreparedBody<'_>,
        bodies: &dm_tree::frontend::BodyArena<'_>,
    ) -> Option<CompletedInput> {
        if host.observes_reads() {
            return None;
        }
        let attempt = self.attempt.as_ref()?;
        let observer = crate::lowering_memo::RecordingResolver::new(host);
        for candidate in candidates.take_identity(row.source().identity) {
            let mut completed = None;
            let claimed = attempt
                .with_pending(|leases| {
                    leases.records.claim_current(
                        candidate,
                        |_, record| {
                            if !record.modified_recipes.is_empty() {
                                return false;
                            }
                            let Some(prepared) = record
                                .local
                                .as_ref()
                                .and_then(|local| local.matches(roster, row, policy, record))
                            else {
                                return false;
                            };
                            completed = self.rebind_record(
                                record,
                                host,
                                frontend,
                                row.body(),
                                &prepared,
                                bodies,
                                false,
                                false,
                                row,
                            );
                            completed.is_some()
                        },
                        |leaf| observer.record_admitted(leaf),
                    )
                })
                .flatten();
            if claimed.is_some() {
                let mut input = completed?;
                if let Input::Reused(value) = &mut input.inner {
                    self.share_current_code(value);
                }
                return Some(input);
            }
        }
        None
    }
}
