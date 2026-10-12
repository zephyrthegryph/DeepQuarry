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
    /// Preserve every edge after exact replay against this same immutable host.
    /// Opaque observing hosts resolve normally. Transparent recorders import
    /// admitted answers through the SAME nested ledgers; nonobserving providers
    /// can reuse the validated answer owner without another evaluation.
    pub fn record_admitted(&self, reads: &[ResolverRead]) {
        for read in reads {
            if self.resolver.observes_reads()
                && self.resolver.transparent_receipt_observer().is_none()
            {
                self.resolve(read.query);
            } else {
                let version = self
                    .ledger
                    .domain_receipt(&read.domain)
                    .unwrap_or_else(|| self.resolver.domain_version(read.domain));
                if self.transparent_receipt_observer().is_some() {
                    dm_ir::ResolvedReadObserver::record_answer(
                        self,
                        read.query,
                        &read.answer,
                        read.domain,
                        version,
                    );
                } else {
                    self.ledger
                        .record(read.query, read.answer.clone(), read.domain, version);
                }
            }
        }
    }

    /// These reads are mandatory even for bodies that use no inherited names.
    /// Structural ABI consumers observe declarations, not executable bodies.
    /// Body-sensitive consumers must continue using record_occurrence.
    pub fn record_declaration_occurrence(&self, identity: dm_ir::ProcedureIdentity) {
        self.resolve(ResolveQuery::Ancestry(identity.owner));
        self.resolve(ResolveQuery::DeclarationChain {
            owner: identity.owner,
            name: identity.name,
            verb: identity.verb,
        });
    }
    pub fn record_occurrence(&self, identity: dm_ir::ProcedureIdentity) {
        self.resolve(ResolveQuery::Ancestry(identity.owner));
        self.resolve(ResolveQuery::OverrideChain {
            owner: identity.owner,
            name: identity.name,
            verb: identity.verb,
        });
    }
}
impl<R: Resolver> dm_ir::ResolvedReadObserver for RecordingResolver<'_, R> {
    fn record_answer(
        &self,
        query: ResolveQuery,
        answer: &ResolvedMeaning,
        domain: ReadDomain,
        version: Option<u128>,
    ) {
        // Only transparent nested recorders participate. Semantic interceptors
        // cannot license this interface; ordinary resolve remains their path.
        if let Some(inner) = self.resolver.transparent_receipt_observer() {
            inner.record_answer(query, answer, domain, version);
        }
        self.ledger.record(query, answer.clone(), domain, version);
    }
}
impl<R: Resolver> Resolver for RecordingResolver<'_, R> {
    fn transparent_receipt_observer(&self) -> Option<dm_ir::TransparentReceiptObserver<'_>> {
        let provider: &dyn Resolver = if self.resolver.observes_reads() {
            self.resolver.transparent_receipt_observer()?.provider()
        } else {
            self.resolver
        };
        dm_ir::TransparentReceiptObserver::new(provider, self)
    }

    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.resolver.domain_version(domain)
    }
    fn resolve_with_canonical(&self, query: ResolveQuery) -> dm_ir::CanonicalResolvedAnswer {
        let version = self
            .ledger
            .domain_receipt(&query.domain())
            .unwrap_or_else(|| self.resolver.domain_version(query.domain()));
        let answer = self.resolver.resolve_with_canonical(query);
        self.ledger
            .record(query, answer.answer.clone(), query.domain(), version);
        answer
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

#[cfg(test)]
#[path = "reads_observer_tests.rs"]
mod observer_tests;
