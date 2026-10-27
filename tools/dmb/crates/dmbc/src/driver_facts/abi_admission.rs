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
    fn observe_admitted(&self, read: &dm_session::Observation<Query, Answer, Domain>) {
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
            observer.record_answer(*query, answer, *domain);
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
/// Semantic reads answered by the session's answer table; producer inputs are compared exactly.
pub(in crate::driver_facts) struct SemanticAnswers<'a>(pub &'a crate::query_db::RequestAnswers<'a>);
impl dm_session::AnswerOracle<Query, Answer> for SemanticAnswers<'_> {
    fn unchanged(&self, query: &Query, recorded: &Answer) -> Option<bool> {
        match (query, recorded) {
            (Query::Semantic(query), Answer::Semantic(recorded)) => Some(
                self.0
                    .unchanged_hash(query, crate::query_db::answer_hash(recorded)),
            ),
            _ => None,
        }
    }
}
pub(in crate::driver_facts) type Admission<'a> =
    ReceiptAdmission<'a, Query, Answer, Domain, SemanticHost<'a>>;
pub(in crate::driver_facts) fn changed(
    reads: &Reads,
    current: &Current<'_>,
    admission: Option<&Admission<'_>>,
) -> Option<Query> {
    let Some(admission) = admission else {
        return dm_session::observations::first_changed_iter(
            reads.iter(),
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
                changed = admission.first_changed_receipted(&Reads::from(leaf.clone()), |_| {});
            } else {
                // Producer inputs are candidate-specific: compared here, never a shared leaf verdict.
                changed = dm_session::observations::first_changed_iter(
                    leaf.iter(),
                    |query| current.answer(query),
                    |a, b| current.equivalent(a, b),
                )
                .cloned();
            }
        }
    });
    changed
}
