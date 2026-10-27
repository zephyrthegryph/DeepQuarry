//! One dependency-recording path shared by all semantic artifact consumers.
use crate::{Observation, ObservationLedger};
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
pub type ResolverRead = Observation<ResolveQuery, ResolvedMeaning, ReadDomain>;

/// Records every answer it gives; a receipt is proven later by its answers (an answer table or exact replay).
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
            } else if self.transparent_receipt_observer().is_some() {
                dm_ir::ResolvedReadObserver::record_answer(self, read.query, &read.answer, read.domain);
            } else {
                self.ledger.record(read.query, read.answer.clone(), read.domain);
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
    ) {
        // Only transparent nested recorders participate. Semantic interceptors
        // cannot license this interface; ordinary resolve remains their path.
        if let Some(inner) = self.resolver.transparent_receipt_observer() {
            inner.record_answer(query, answer, domain);
        }
        self.ledger.record(query, answer.clone(), domain);
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

    fn answer_world(&self) -> Option<u128> {
        self.resolver.answer_world()
    }
    fn resolve_with_canonical(&self, query: ResolveQuery) -> dm_ir::CanonicalResolvedAnswer {
        let answer = self.resolver.resolve_with_canonical(query);
        self.ledger.record(query, answer.answer().clone(), query.domain());
        answer
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let answer = self.resolver.resolve(query);
        self.ledger.record(query, answer.clone(), query.domain());
        answer
    }
}

#[cfg(test)]
#[path = "reads_observer_tests.rs"]
mod observer_tests;
