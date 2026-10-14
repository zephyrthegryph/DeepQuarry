//! Request-bound admission of exact shared ABI semantic leaves.
use super::observations::{Answer, Current, Domain, Query};
use dm_ir::Resolver;
use dm_session::{ObservationHost, Receipt, ReceiptAdmission, ReceiptStorageView};
pub(super) type Reads = Receipt<Query, Answer, Domain>;
pub(in crate::driver_facts) struct SemanticHost<'a>(pub &'a dyn Resolver);
impl ObservationHost<Query, Answer, Domain> for SemanticHost<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Inputs | Query::BatchInputs => Answer::Unissued,
            Query::Semantic(query) => Answer::Semantic(self.0.resolve(*query)),
        }
    }
    fn version(&self, domain: &Domain) -> Option<u128> {
        match domain {
            Domain::Inputs | Domain::BatchInputs => None,
            Domain::Semantic(domain) => self.0.domain_version(*domain),
        }
    }
    fn observes_answers(&self) -> bool {
        self.0.observes_reads()
    }
    fn supports_admitted_observation(&self) -> bool {
        self.0.transparent_receipt_observer().is_some()
    }
    fn answer_for_admission(&self, query: &Query) -> Answer {
        match (query, self.0.transparent_receipt_observer()) {
            (Query::Semantic(query), Some(observer)) => {
                Answer::Semantic(observer.provider().resolve(*query))
            }
            _ => self.answer(query),
        }
    }
    fn version_for_admission(&self, domain: &Domain) -> Option<u128> {
        match (domain, self.0.transparent_receipt_observer()) {
            (Domain::Semantic(domain), Some(observer)) => {
                observer.provider().domain_version(*domain)
            }
            _ => self.version(domain),
        }
    }
    fn observe_admitted(
        &self,
        read: &dm_session::Observation<Query, Answer, Domain>,
        version: Option<u128>,
    ) {
        if let (
            Query::Semantic(query),
            Answer::Semantic(answer),
            Domain::Semantic(domain),
            Some(observer),
        ) = (
            &read.query,
            &read.answer,
            &read.domain,
            self.0.transparent_receipt_observer(),
        ) {
            observer.record_answer(*query, answer, *domain, version);
        }
    }
    fn equivalent(&self, a: &Answer, b: &Answer) -> bool {
        a == b
            || match (a, b) {
                (Answer::Semantic(a), Answer::Semantic(b)) => {
                    a.canonical_bytes() == b.canonical_bytes()
                }
                _ => false,
            }
    }
}
pub(in crate::driver_facts) type Admission<'a> =
    ReceiptAdmission<'a, Query, Answer, Domain, SemanticHost<'a>>;
pub(in crate::driver_facts) fn changed(
    reads: &Reads,
    versions: &[(Domain, u128)],
    current: &Current<'_>,
    admission: Option<&Admission<'_>>,
) -> Option<Query> {
    let matching = match admission {
        Some(request) => request.certified_domains(versions),
        None => {
            dm_session::observations::certified_domains(versions, |domain| current.version(domain))
        }
    };
    let Some(admission) = admission else {
        return dm_session::observations::first_changed_iter(
            reads.iter(),
            &matching,
            |query| current.answer(query),
            |a, b| current.equivalent(a, b),
        )
        .cloned();
    };
    let mut changed = None;
    reads.visit_storage(|view| {
        if changed.is_some() {
            return;
        }
        if let ReceiptStorageView::Flat(leaf) = view {
            let semantic = leaf.iter().all(|read| {
                matches!(read.query, Query::Semantic(_))
                    && matches!(read.domain, Domain::Semantic(_))
            });
            if semantic && admission.allows_certificate_reuse() {
                changed =
                    admission.first_changed_receipted(&Reads::from(leaf.clone()), versions, |_| {});
            } else if semantic && !leaf.iter().all(|read| matching.contains(&read.domain)) {
                // No partial certificate becomes a shared leaf verdict.
                changed = admission.first_changed(&Reads::from(leaf.clone()), |_| {});
            } else {
                // Inputs and candidate-specific complete certificates remain local.
                changed = dm_session::observations::first_changed_iter(
                    leaf.iter(),
                    &matching,
                    |query| current.answer(query),
                    |a, b| current.equivalent(a, b),
                )
                .cloned();
            }
        }
    });
    changed
}

#[cfg(test)]
mod transparent_tests {
    use super::*;
    use dm_ir::{ResolveQuery, ResolvedMeaning, SymbolId};
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Provider(AtomicUsize);
    impl Resolver for Provider {
        fn observes_reads(&self) -> bool {
            false
        }
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.0.fetch_add(1, Ordering::Relaxed);
            ResolvedMeaning::Missing
        }
        fn domain_version(&self, _: dm_ir::ReadDomain) -> Option<u128> {
            Some(7)
        }
    }
    #[test]
    fn abi_transparent_receipt_delivers_original_negative_without_provider_replay() {
        let provider = Provider(AtomicUsize::new(0));
        let recorder = dm_session::RecordingResolver::new(&provider);
        let host = SemanticHost(&recorder);
        let admission = ReceiptAdmission::new(&host);
        let query = ResolveQuery::GlobalProc(SymbolId::of("absent"));
        let domain = query.domain();
        let reads = Reads::from(vec![dm_session::Observation {
            query: Query::Semantic(query),
            domain: Domain::Semantic(domain),
            answer: Answer::Semantic(ResolvedMeaning::Missing),
        }]);
        assert!(admission
            .first_changed_receipted(&reads, &[(Domain::Semantic(domain), 7)], |_| {})
            .is_none());
        assert_eq!(provider.0.load(Ordering::Relaxed), 0);
        let actual = recorder.reads();
        assert_eq!(actual.len(), 1);
        assert_eq!(actual[0].query, query);
        assert_eq!(actual[0].answer, ResolvedMeaning::Missing);
    }
}
