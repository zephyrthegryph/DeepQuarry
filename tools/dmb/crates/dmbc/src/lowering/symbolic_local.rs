//! Current local input proof attached to the same admitted symbolic record.
use super::*;
use std::sync::atomic::Ordering;
/// Why a retained record's local certificate declined the current body. Counted
/// process-wide so the memo summary can say why the unchanged-local path missed.
#[derive(Clone, Copy)]
enum Decline {
    Policy,
    SelectedGone,
    SelectedChanged,
    GraphGone,
    GraphChanged,
    NoPrepared,
    InputsGone,
    InputsChanged,
    AbiGone,
    AbiChanged,
    NoRecipe,
    MetadataChanged,
    SourceChanged,
    NoCandidate,
    IssueNoPrepared,
    IssueNoGraph,
    IssueNoAbi,
    NoRecordAtAll,
    RecordWithoutCertificate,
}
const DECLINE_NAMES: [&str; 19] = [
    "policy_or_identity",
    "selected_unit_dropped",
    "selected_unit_changed",
    "graph_dropped",
    "graph_changed",
    "no_prepared_unit",
    "inputs_dropped",
    "inputs_changed",
    "abi_dropped",
    "abi_changed",
    "no_recipe",
    "metadata_changed",
    "source_changed",
    "no_qualified_record_for_identity",
    "issue_no_prepared_unit",
    "issue_no_graph",
    "issue_no_abi",
    "no_record_at_all",
    "record_without_certificate",
];
static DECLINES: [std::sync::atomic::AtomicU64; 19] =
    [const { std::sync::atomic::AtomicU64::new(0) }; 19];
/// Cumulative per-process decline reasons of the local certificate.
pub fn local_decline_stats() -> String {
    DECLINE_NAMES
        .iter()
        .zip(DECLINES.iter())
        .filter_map(|(name, count)| {
            let count = count.load(std::sync::atomic::Ordering::Relaxed);
            (count > 0).then(|| format!("{name}={count}"))
        })
        .collect::<Vec<_>>()
        .join(",")
}
#[derive(Clone)]
pub(in crate::lowering) struct Certificate {
    selected: Option<std::sync::Weak<crate::driver_facts::abi_artifacts::UnitArtifact>>,
    graph: Option<std::sync::Weak<dm_tree::frontend::CallableAbiGraph>>,
    inputs: std::sync::Weak<dm_codegen_byond::lower_resolver::ProcedureInputs>,
    abi: std::sync::Weak<crate::procedure_policy::PreparedAbi>,
    identity: UnitIdentity,
    policy: u128,
    termination: u8,
    key: Option<SharedKey>,
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
        let refuse = |reason: Decline| {
            DECLINES[reason as usize].fetch_add(1, Ordering::Relaxed);
            None
        };
        let Some(prepared) = roster.prepared(row) else {
            return refuse(Decline::IssueNoPrepared);
        };
        let selected = roster.selected(row).map(Arc::downgrade);
        let graph = if selected.is_none() {
            match roster.graph() {
                Some(graph) => Some(Arc::downgrade(graph)),
                None => return refuse(Decline::IssueNoGraph),
            }
        } else {
            None
        };
        let Some(abi) = prepared.abi.as_ref() else {
            return refuse(Decline::IssueNoAbi);
        };
        Some(Self {
            selected,
            graph,
            inputs: Arc::downgrade(&prepared.inputs),
            abi: Arc::downgrade(abi),
            identity: row.source().identity,
            policy,
            termination: row.termination().canonical_tag(),
            code: Arc::downgrade(row.code_identity()),
            key: None,
        })
    }
    pub(super) fn bind_key(mut self, key: &SharedKey) -> Self {
        self.key = Some(key.clone());
        self
    }
    fn matches(
        &self,
        roster: &LocalInputRoster<'_>,
        row: &PreparedBody<'_>,
        policy: u128,
        record: &Record,
    ) -> Option<PreparedUnit> {
        let result = self.matches_reason(roster, row, policy, record);
        if let Err(reason) = &result {
            DECLINES[*reason as usize].fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        result.ok()
    }
    fn matches_reason(
        &self,
        roster: &LocalInputRoster<'_>,
        row: &PreparedBody<'_>,
        policy: u128,
        record: &Record,
    ) -> Result<PreparedUnit, Decline> {
        // The current ABI producer has replayed this exact unit's Inputs and
        // semantic receipt before retaining its strong artifact owner. Custom
        // or uncaptured preparation keeps the conservative whole-graph guard.
        if self.policy != policy
            || self.identity != row.source().identity
            || self.termination != row.termination().canonical_tag()
        {
            return Err(Decline::Policy);
        }
        match (&self.selected, roster.selected(row)) {
            (Some(previous), Some(current)) => {
                let previous = previous.upgrade().ok_or(Decline::SelectedGone)?;
                if !Arc::ptr_eq(&previous, current) {
                    return Err(Decline::SelectedChanged);
                }
            }
            (None, None) => {
                let graph = self
                    .graph
                    .as_ref()
                    .and_then(|graph| graph.upgrade())
                    .ok_or(Decline::GraphGone)?;
                if !Arc::ptr_eq(&graph, roster.graph().ok_or(Decline::GraphGone)?) {
                    return Err(Decline::GraphChanged);
                }
            }
            _ => return Err(Decline::SelectedChanged),
        }
        let prepared = roster.prepared(row).ok_or(Decline::NoPrepared)?;
        let inputs = self.inputs.upgrade().ok_or(Decline::InputsGone)?;
        if !Arc::ptr_eq(&inputs, &prepared.inputs) {
            return Err(Decline::InputsChanged);
        }
        let abi = self.abi.upgrade().ok_or(Decline::AbiGone)?;
        if !Arc::ptr_eq(&abi, prepared.abi.as_ref().ok_or(Decline::NoPrepared)?) {
            return Err(Decline::AbiChanged);
        }
        if record.recipe.as_ref().ok_or(Decline::NoRecipe)?.metadata.as_ref()
            != roster.metadata(row).ok_or(Decline::NoPrepared)?.as_ref()
        {
            return Err(Decline::MetadataChanged);
        }
        if !(self
            .code
            .upgrade()
            .is_some_and(|code| Arc::ptr_eq(&code, row.code_identity()))
            && self
                .key
                .as_ref()
                .is_some_and(|key| key.same_backing(&record.key)))
            && !record
                .recipe
                .as_ref()
                .ok_or(Decline::NoRecipe)?
                .source_matches(&record.key, row.input().source().as_bytes())
        {
            return Err(Decline::SourceChanged);
        }
        Ok(prepared)
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
            census.slice("procedure.local_key", key.owner(), true);
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
        let mut seen = 0usize;
        let mut with_local = 0usize;
        let qualified = candidates.take_identity_if(row.source().identity, |record| {
            seen += 1;
            with_local += usize::from(record.local.is_some());
            record
                .local
                .as_ref()
                .is_some_and(|local| local.matches(roster, row, policy, record).is_some())
        });
        if qualified.is_empty() {
            let reason = if seen == 0 {
                Decline::NoRecordAtAll
            } else if with_local == 0 {
                Decline::RecordWithoutCertificate
            } else {
                Decline::NoCandidate
            };
            let count = DECLINES[reason as usize].fetch_add(1, Ordering::Relaxed);
            if count < 6 && std::env::var_os("DMB_TIMINGS_DETAIL").is_some() {
                let symbols = frontend.snapshot.tree.symbols();
                let identity = row.source().identity;
                eprintln!(
                    "detail local-path miss {:?}: owner={:?} name={:?} namespace={:?} occurrence={} seen={seen} with_local={with_local}",
                    reason as usize,
                    symbols.text(identity.owner),
                    symbols.text(identity.name),
                    identity.namespace,
                    identity.occurrence,
                );
            }
        }
        for candidate in qualified {
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
