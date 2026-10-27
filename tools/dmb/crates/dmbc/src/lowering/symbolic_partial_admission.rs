//! Candidate-specific certificate replay through the existing admission core.
use super::*;

pub(super) fn changed<R: Resolver>(
    admission: &RequestAdmission<'_, R>,
    reads: &receipt_groups::ProcedureReceipt,
    observer: &crate::lowering_memo::RecordingResolver<'_, R>,
) -> Option<dm_ir::ResolveQuery> {
    admission.first_changed_receipted(reads, |leaf| observer.record_admitted(leaf))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Host {
        positive: dm_ir::ResolveQuery,
        negative: dm_ir::ResolveQuery,
        positive_calls: AtomicUsize,
        negative_calls: AtomicUsize,
        appeared: bool,
    }
    impl Resolver for Host {
        fn observes_reads(&self) -> bool {
            false
        }
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            if query == self.positive {
                self.positive_calls.fetch_add(1, Ordering::Relaxed);
                dm_ir::ResolvedMeaning::Presence(false)
            } else {
                assert_eq!(query, self.negative);
                self.negative_calls.fetch_add(1, Ordering::Relaxed);
                if self.appeared {
                    dm_ir::ResolvedMeaning::Symbol(dm_ir::SymbolId::of("/proc/opaque"))
                } else {
                    dm_ir::ResolvedMeaning::Missing
                }
            }
        }
    }
    fn host(appeared: bool) -> Host {
        Host {
            positive: dm_ir::ResolveQuery::MemberCallableName(dm_ir::SymbolId::of("certified")),
            negative: dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of("opaque")),
            positive_calls: AtomicUsize::new(0),
            negative_calls: AtomicUsize::new(0),
            appeared,
        }
    }
    #[test]
    fn every_recorded_answer_is_replayed_and_admitted_edges_stay_recorded() {
        let host = host(false);
        let reads: receipt_groups::ProcedureReceipt = [host.positive, host.negative]
            .into_iter()
            .map(|query| ResolverRead {
                query,
                domain: query.domain(),
                answer: if query == host.negative {
                    dm_ir::ResolvedMeaning::Missing
                } else {
                    dm_ir::ResolvedMeaning::Presence(false)
                },
            })
            .collect::<Vec<_>>()
            .into();
        let request = RequestAdmission::new(&host);
        for _ in 0..2 {
            let observer = crate::lowering_memo::RecordingResolver::new(&host);
            assert_eq!(changed(&request, &reads, &observer), None);
            assert_eq!(observer.reads().len(), 2, "every admitted edge stays recorded");
        }
        assert_eq!(host.positive_calls.load(Ordering::Relaxed), 2);
        assert_eq!(host.negative_calls.load(Ordering::Relaxed), 2);
        let current = self::host(true);
        let request = RequestAdmission::new(&current);
        let observer = crate::lowering_memo::RecordingResolver::new(&current);
        assert_eq!(changed(&request, &reads, &observer), Some(current.negative));
        assert!(observer.reads().is_empty(), "failed flat leaf is never admitted");
    }
}
