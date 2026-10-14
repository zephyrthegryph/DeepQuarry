//! Shared finite variable coverage, admitted through the existing host-facts store.
use super::*;
use dm_session::ObservationHost;
pub(super) const KEY: &[u8] = b"host-variable-coverage-v1";
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
                                || selection.declared_variable_names
                                    == other.declared_variable_names)
                    },
                ))
    }
}
impl Eq for Roster {}
impl Roster {
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("host.variable_coverage.roster", &self.0) {
            census.observe_items("host.variable_coverage.roster", self.0.len());
            census.unknown(
                "host.variable_coverage.roster",
                "private BTreeMap node backing excluded",
            );
            for selection in self.0.values() {
                if census.arc_object("host.variable_coverage.selection", selection) {
                    census.slice(
                        "host.variable_coverage.callables",
                        &selection.callable_names,
                        true,
                    );
                    census.slice(
                        "host.variable_coverage.variables",
                        &selection.declared_variable_names,
                        true,
                    );
                    census.slice(
                        "host.variable_coverage.scalars",
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
    constants: &'a Arc<catalogs::Constants>,
}
impl ObservationHost<Query, Answer, Domain> for Host<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::VariableRoster => Answer::VariableRoster(Roster(Arc::clone(
                self.current
                    .frontend
                    .snapshot
                    .tree
                    .host_declaration_selection_storage(),
            ))),
            Query::CallableProvider => Answer::CallableProvider(Arc::clone(self.provider)),
            Query::ConstantOwner => Answer::ConstantOwner(Arc::clone(self.constants)),
            _ => unreachable!("only exact variable coverage observations"),
        }
    }
}
impl RetainedHostFacts {
    pub(super) fn variable_coverage(
        &self,
        current: &Current<'_>,
        provider: &Arc<crate::engine_host::PinnedEngineProviders>,
    ) -> Result<Arc<crate::engine_host::VariableCoverage>, String> {
        let constants = self.constants(current)?;
        let host = Host {
            current,
            provider,
            constants: &constants,
        };
        if let Some(value) = self.values.lookup(KEY, &host) {
            if let Artifact::VariableCoverage(names) = value.as_ref() {
                return Ok(Arc::clone(names));
            }
        }
        let ledger = dm_session::ObservationLedger::default();
        for query in [
            Query::VariableRoster,
            Query::CallableProvider,
            Query::ConstantOwner,
        ] {
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
                    Artifact::VariableCoverage(
                        EngineResolverHost::<dm_tree::SemanticTree>::capture_variable_coverage(
                            current.frontend,
                            provider,
                            &constants.catalog,
                        ),
                    )
                },
            )
            .expect("current-revision store admits the current variable coverage stage");
        match owner.as_ref() {
            Artifact::VariableCoverage(names) => Ok(Arc::clone(names)),
            _ => unreachable!("private stage key"),
        }
    }
}
pub(super) fn inspect_constants(
    constants: &Arc<catalogs::Constants>,
    census: &mut crate::heap_census::HeapCensus,
) {
    if census.arc_object("host.constants.stage", constants) {
        census.unknown(
            "host.constants.stage",
            "catalog/spelling private backing excluded",
        );
    }
}
#[cfg(test)]
#[path = "runner_facts_variable_coverage_tests.rs"]
mod tests;
