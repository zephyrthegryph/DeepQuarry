//! Allocation variants in the existing startup observation store.
use super::*;
use crate::startup_allocation::{
    AllocationInput, AllocationReceipt, FinalInput, FinalReceipt, ALLOCATION_KEY, FINAL_KEY,
};
struct Inputs<'a, R>(&'a R);
impl<R: dm_ir::Resolver> ObservationHost<Query, Answer, Option<dm_ir::ReadDomain>>
    for Inputs<'_, R>
{
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Resolver(query) => Answer::Resolver(self.0.resolve(*query)),
            Query::Static(_) => Answer::Unavailable,
        }
    }
    // Resolver domain tokens are deliberately not transplanted into this union
    // store: every positive/negative answer takes ordinary exact replay.
}
impl StartupArtifacts {
    pub(crate) fn allocation(&self, input: &AllocationInput) -> Option<Arc<AllocationReceipt>> {
        let mut result = None;
        self.values
            .visit_explained(ALLOCATION_KEY, &StaticInputs(Arc::from([])), &mut |value| {
                if let Artifact::Allocation(value) = value.as_ref() {
                    if value.input.as_ref() == Some(input) {
                        result = Some(Arc::clone(value));
                    }
                }
                result.is_some()
            });
        result
    }
    pub(crate) fn remember_allocation(
        &self,
        receipt: Arc<AllocationReceipt>,
    ) -> Arc<AllocationReceipt> {
        let owner = self.values.insert_with_owned(
            Arc::from(ALLOCATION_KEY),
            Vec::new(),
            Vec::new(),
            0,
            || Artifact::Allocation(Arc::clone(&receipt)),
        );
        match owner.as_deref() {
            Some(Artifact::Allocation(value)) => Arc::clone(value),
            _ => receipt,
        }
    }
    pub(crate) fn final_allocation(
        &self,
        input: &FinalInput,
        host: &impl dm_ir::Resolver,
    ) -> Option<Arc<FinalReceipt>> {
        let mut result = None;
        self.values
            .visit_explained(FINAL_KEY, &Inputs(host), &mut |value| {
                if let Artifact::AllocationFinal(value) = value.as_ref() {
                    if value.input.matches(input) {
                        result = Some(Arc::clone(value));
                    }
                }
                result.is_some()
            });
        result
    }
    pub(crate) fn remember_final_allocation<R: dm_ir::Resolver>(
        &self,
        receipt: FinalReceipt,
        recording: &crate::lowering_memo::RecordingResolver<'_, R>,
    ) -> Arc<crate::startup_allocation::OrderedRoster> {
        let ordered = Arc::clone(&receipt.ordered);
        let ledger = dm_session::observations::ObservationLedger::default();
        for read in recording.reads() {
            ledger.record(
                Query::Resolver(read.query),
                Answer::Resolver(read.answer),
                Some(read.domain),
                None,
            );
        }
        let owner = self.values.insert_with_owned(
            Arc::from(FINAL_KEY),
            ledger.reads(),
            ledger.domain_receipts(),
            0,
            || Artifact::AllocationFinal(Arc::new(receipt)),
        );
        match owner.as_deref() {
            Some(Artifact::AllocationFinal(value)) => Arc::clone(&value.ordered),
            _ => ordered,
        }
    }
}
