//! One dependency-recording path shared by all semantic artifact consumers.
use crate::{Observation, ObservationLedger};
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
/// Versions are immutable issuer facts. Missing/different receipts require every
/// original positive or negative answer to be checked exactly.
pub fn matching_domains<R: Resolver>(
    versions: &[(ReadDomain, u128)],
    resolver: &R,
) -> std::collections::BTreeSet<ReadDomain> {
    crate::observations::certified_domains(versions, |domain| resolver.domain_version(*domain))
}

pub type ResolverRead = Observation<ResolveQuery, ResolvedMeaning, ReadDomain>;

pub struct RecordingResolver<'a, R: Resolver> {
    resolver: &'a R,
    ledger: ObservationLedger<ResolveQuery, ResolvedMeaning, ReadDomain>,
}
impl<'a, R: Resolver> RecordingResolver<'a, R> {
    pub fn new(resolver: &'a R) -> Self {
        Self {
            resolver,
            ledger: ObservationLedger::default(),
        }
    }
    pub fn reads(&self) -> Vec<ResolverRead> {
        self.ledger.reads()
    }
    pub fn domain_receipts(&self) -> Vec<(ReadDomain, u128)> {
        self.ledger.domain_receipts()
    }
    /// These reads are mandatory even for bodies that use no inherited names.
    pub fn record_occurrence(&self, identity: dm_ir::ProcedureIdentity) {
        self.resolve(ResolveQuery::Ancestry(identity.owner));
        self.resolve(ResolveQuery::OverrideChain {
            owner: identity.owner,
            name: identity.name,
            verb: identity.verb,
        });
    }
}
impl<R: Resolver> Resolver for RecordingResolver<'_, R> {
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.resolver.domain_version(domain)
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let version = self
            .ledger
            .domain_receipt(&query.domain())
            .unwrap_or_else(|| self.resolver.domain_version(query.domain()));
        let answer = self.resolver.resolve(query);
        self.ledger
            .record(query, answer.clone(), query.domain(), version);
        answer
    }
}
