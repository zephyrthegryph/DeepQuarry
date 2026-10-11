//! Current local input proof attached to the same admitted symbolic record.
use super::*;
#[derive(Clone)]
pub(in crate::lowering) struct Certificate {
    selected: Option<std::sync::Weak<crate::driver_facts::abi_artifacts::UnitArtifact>>,
    graph: Option<std::sync::Weak<dm_tree::frontend::CallableAbiGraph>>,
    inputs: std::sync::Weak<dm_codegen_byond::lower_resolver::ProcedureInputs>,
    abi: std::sync::Weak<crate::procedure_policy::PreparedAbi>,
    identity: UnitIdentity,
    policy: u128,
    termination: u8,
    key: Option<Arc<[u8]>>,
    code: std::sync::Weak<dm_tree::frontend::BodyCodeIdentity>,
}
#[cfg(test)]
#[path = "symbolic_local_modified_tests.rs"]
mod modified_tests;
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
        let selected = roster.selected(row).map(Arc::downgrade);
        let graph = if selected.is_none() {
            Some(Arc::downgrade(roster.graph()?))
        } else {
            None
        };
        Some(Self {
            selected,
            graph,
            inputs: Arc::downgrade(&prepared.inputs),
            abi: Arc::downgrade(prepared.abi.as_ref()?),
            identity: row.source().identity,
            policy,
            termination: row.termination().canonical_tag(),
            code: Arc::downgrade(row.code_identity()),
            key: None,
        })
    }
    pub(super) fn bind_key(mut self, key: &Arc<[u8]>) -> Self {
        self.key = Some(Arc::clone(key));
        self
    }
    fn matches(
        &self,
        roster: &LocalInputRoster<'_>,
        row: &PreparedBody<'_>,
        policy: u128,
        record: &Record,
    ) -> Option<PreparedUnit> {
        // The current ABI producer has replayed this exact unit's Inputs and
        // semantic receipt before retaining its strong artifact owner. Custom
        // or uncaptured preparation keeps the conservative whole-graph guard.
        if self.policy != policy
            || self.identity != row.source().identity
            || self.termination != row.termination().canonical_tag()
        {
            return None;
        }
        match (&self.selected, roster.selected(row)) {
            (Some(previous), Some(current)) if Arc::ptr_eq(&previous.upgrade()?, current) => {}
            (None, None) if Arc::ptr_eq(&self.graph.as_ref()?.upgrade()?, roster.graph()?) => {}
            _ => return None,
        }
        let prepared = roster.prepared(row)?;
        if !Arc::ptr_eq(&self.inputs.upgrade()?, &prepared.inputs)
            || !Arc::ptr_eq(&self.abi.upgrade()?, prepared.abi.as_ref()?)
            || record.recipe.as_ref()?.metadata.as_ref() != roster.metadata(row)?.as_ref()
            || (!(self
                .code
                .upgrade()
                .is_some_and(|code| Arc::ptr_eq(&code, row.code_identity()))
                && self
                    .key
                    .as_ref()
                    .is_some_and(|key| Arc::ptr_eq(key, &record.key)))
                && !record
                    .recipe
                    .as_ref()?
                    .source_matches(&record.key, row.input().source().as_bytes()))
        {
            return None;
        }
        Some(prepared)
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        // Weak witnesses keep their allocation shells, not nested live payloads.
        fn shell<T>(census: &mut crate::heap_census::HeapCensus, value: &std::sync::Weak<T>) {
            let bytes = std::mem::size_of::<T>();
            census.exposed_buffer(
                "procedure.local_weak_shell",
                value.as_ptr() as usize,
                bytes,
                bytes,
            );
        }
        shell(census, &self.code);
        shell(census, &self.inputs);
        shell(census, &self.abi);
        if let Some(selected) = &self.selected {
            shell(census, selected);
        }
        if let Some(graph) = &self.graph {
            shell(census, graph);
        }
        if let Some(key) = &self.key {
            census.slice("procedure.local_key", key.as_ref(), true);
        }
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
        // A failed weak issuer witness cannot consume the semantic certificate
        // needed by ordinary exact-key/ABI admission later in this same request.
        for candidate in candidates.take_identity_if(row.source().identity, |record| {
            record
                .local
                .as_ref()
                .is_some_and(|local| local.matches(roster, row, policy, record).is_some())
        }) {
            let mut completed = None;
            let claimed = attempt
                .with_pending(|leases| {
                    leases.records.claim_current(
                        candidate,
                        |_, record| {
                            let Some(prepared) = record
                                .local
                                .as_ref()
                                .and_then(|local| local.matches(roster, row, policy, record))
                            else {
                                return false;
                            };
                            // Modified descriptors are reissued against the current parsed
                            // body by the same admission path as ordinary candidates.
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
