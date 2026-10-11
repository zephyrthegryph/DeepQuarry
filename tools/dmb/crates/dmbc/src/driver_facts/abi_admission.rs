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
            if semantic && !leaf.iter().all(|read| matching.contains(&read.domain)) {
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
