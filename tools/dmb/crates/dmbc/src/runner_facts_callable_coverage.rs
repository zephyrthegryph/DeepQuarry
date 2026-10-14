//! Shared finite callable coverage, admitted through the existing host-facts store.
use super::*;
use dm_session::ObservationHost;
pub(super) const KEY: &[u8] = b"host-callable-coverage-v1";
#[derive(Clone)]
pub(super) struct Roster(
    Arc<std::collections::BTreeMap<dm_ir::SymbolId, Arc<dm_tree::HostDeclarationSelection>>>,
);
impl PartialEq for Roster {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
            || (self.0.len() == other.0.len()
                && self.0.iter().zip(other.0.iter()).all(
                    |((owner, selection), (other_owner, other))| {
                        owner == other_owner
                            && (Arc::ptr_eq(selection, other)
                                || selection.callable_names == other.callable_names)
                    },
                ))
    }
}
impl Eq for Roster {}
impl Roster {
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("host.callable_coverage.roster", &self.0) {
            census.observe_items("host.callable_coverage.roster", self.0.len());
            census.unknown(
                "host.callable_coverage.roster",
                "private BTreeMap node backing excluded",
            );
            for selection in self.0.values() {
                if census.arc_object("host.callable_coverage.selection", selection) {
                    census.slice(
                        "host.callable_coverage.callables",
                        &selection.callable_names,
                        true,
                    );
                    census.slice(
                        "host.callable_coverage.variables",
                        &selection.declared_variable_names,
                        true,
                    );
                    census.slice(
                        "host.callable_coverage.scalars",
                        &selection.scalar_requests,
                        true,
                    );
                }
            }
        }
    }
}
struct Host<'a> {
    current: &'a Current<'a>,
    provider: &'a Arc<crate::engine_host::PinnedEngineProviders>,
}
impl ObservationHost<Query, Answer, Domain> for Host<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::CallableRoster => Answer::CallableRoster(Roster(Arc::clone(
                self.current
                    .frontend
                    .snapshot
                    .tree
                    .host_declaration_selection_storage(),
            ))),
            Query::CallableProvider => Answer::CallableProvider(Arc::clone(self.provider)),
            _ => unreachable!("only exact callable coverage observations"),
        }
    }
}
impl RetainedHostFacts {
    pub(super) fn callable_coverage(
        &self,
        current: &Current<'_>,
        provider: &Arc<crate::engine_host::PinnedEngineProviders>,
    ) -> Arc<std::collections::HashSet<dm_ir::SymbolId>> {
        let host = Host { current, provider };
        if let Some(value) = self.values.lookup(KEY, &host) {
            if let Artifact::CallableCoverage(names) = value.as_ref() {
                return Arc::clone(names);
            }
        }
        let ledger = dm_session::ObservationLedger::default();
        for query in [Query::CallableRoster, Query::CallableProvider] {
            ledger.record(
                query.clone(),
                host.answer(&query),
                Domain::ExactOwners,
                None,
            );
        }
        let owner = self
            .values
            .insert_with_owned(
                Arc::from(KEY),
                ledger.reads(),
                ledger.domain_receipts(),
                std::mem::size_of::<Artifact>(),
                || {
                    Artifact::CallableCoverage(
                        EngineResolverHost::<dm_tree::SemanticTree>::capture_callable_exclusions(
                            current.frontend,
                            provider,
                        ),
                    )
                },
            )
            .expect("current-revision store admits the current callable coverage stage");
        match owner.as_ref() {
            Artifact::CallableCoverage(names) => Arc::clone(names),
            _ => unreachable!("private stage key"),
        }
    }
}
pub(super) fn inspect_names(
    names: &Arc<std::collections::HashSet<dm_ir::SymbolId>>,
    census: &mut crate::heap_census::HeapCensus,
) {
    if census.arc_object("host.callable_absence", names) {
        census.observe_items("host.callable_absence", names.len());
        census.unknown("host.callable_absence", "private HashSet backing excluded");
    }
}
#[cfg(test)]
#[path = "runner_facts_callable_coverage_tests.rs"]
mod tests;
