//! Request-borrowed observations, issued only after complete disk admission.
use super::{Arc, LoweredUnit};
use crate::lowering_memo::ResolverRead;
use dm_ir::{ResolveQuery, Resolver};
#[derive(Default)]
pub(crate) struct ResidentPromotion<'host> {
    pub current: Option<CurrentReads<'host>>,
    pub queries: Vec<ResolveQuery>,
    pub versions: Vec<(dm_ir::ReadDomain, u128)>,
    pub relative_debug: Vec<crate::debug_sources::RelativeDebugAnchor>,
}
#[derive(Default)]
pub(crate) struct ProcedureLookup<'host> {
    pub verification_reads: Option<Vec<(ResolveQuery, Vec<u8>)>>,
    pub unit: Option<LoweredUnit>,
    pub selections: Option<Arc<dm_ir::SelectedReferences>>,
    pub prepared: Option<crate::symbolic::PreparedContribution>,
    pub resident: Option<ResidentPromotion<'host>>,
    pub errors: Option<Vec<dm_codegen_byond::LowerError>>,
    pub changed_query: Option<ResolveQuery>,
    pub miss: Option<crate::lowering_memo::MemoMissReason>,
}

pub(crate) struct CurrentReads<'host> {
    host: &'host dyn Resolver,
    reads: Vec<ResolverRead>,
}
impl<'host> CurrentReads<'host> {
    fn admissible(host: &dyn Resolver, reads: &[ResolverRead]) -> bool {
        !(host.observes_reads() && host.transparent_receipt_observer().is_none())
            && reads.iter().all(|read| read.domain == read.query.domain())
    }
    /// Reads whose every answer was just compared with `host`'s.
    pub(super) fn accepted(host: &'host dyn Resolver, reads: Vec<ResolverRead>) -> Option<Self> {
        Self::admissible(host, &reads).then_some(Self { host, reads })
    }
    /// Reads proven by the session's answer table (`crate::query_db`).
    pub(crate) fn answered(host: &'host dyn Resolver, reads: Vec<ResolverRead>) -> Option<Self> {
        Self::admissible(host, &reads).then_some(Self { host, reads })
    }
    /// Reads of a record the dependency index certified for `world` (`crate::dep_index`): `host` must answer in it.
    pub(crate) fn certified(
        host: &'host dyn Resolver,
        reads: Vec<ResolverRead>,
        world: u128,
    ) -> Option<Self> {
        (Self::admissible(host, &reads) && host.answer_world() == Some(world)).then_some(Self { host, reads })
    }
    pub(crate) fn for_host(&self, host: &dyn Resolver) -> Option<&[ResolverRead]> {
        // Borrowed identity cannot outlive the request provider. No persisted
        // pointer, token or hash can authorize this handoff.
        // Compare the object, not the vtable: one provider type has a vtable per codegen unit.
        std::ptr::addr_eq(self.host, host).then_some(self.reads.as_slice())
    }
}

impl super::ResidentPromotion<'_> {
    /// The record's reads as the resident store keeps them: proven for this host already, or resolved now.
    pub(crate) fn current_observations(&self, host: &dyn Resolver) -> Vec<ResolverRead> {
        if let Some(reads) = self.current.as_ref().and_then(|reads| reads.for_host(host)) {
            return reads.to_vec();
        }
        self.queries
            .iter()
            .map(|query| ResolverRead {
                query: *query,
                domain: query.domain(),
                answer: host.resolve(*query),
            })
            .collect()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ResolvedMeaning, SymbolId};
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Provider {
        calls: AtomicUsize,
        opaque: bool,
    }
    impl Provider {
        fn new(opaque: bool) -> Self {
            Self {
                calls: AtomicUsize::new(0),
                opaque,
            }
        }
    }
    impl Resolver for Provider {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.calls.fetch_add(1, Ordering::Relaxed);
            ResolvedMeaning::Missing
        }
        fn observes_reads(&self) -> bool {
            self.opaque
        }
    }
    fn promotion<'a>(
        host: &'a dyn Resolver,
        queries: Vec<ResolveQuery>,
    ) -> super::super::ResidentPromotion<'a> {
        let reads: Vec<_> = queries
            .iter()
            .map(|query| ResolverRead {
                query: *query,
                domain: query.domain(),
                answer: host.resolve(*query),
            })
            .collect();
        // The production issuer invokes this only after complete rebind. Here
        // ordinary current resolution supplies the exact reference observations.
        let current = CurrentReads::accepted(host, reads);
        super::super::ResidentPromotion {
            current,
            queries,
            versions: Vec::new(),
            relative_debug: Vec::new(),
        }
    }
    #[test]
    fn accepted_current_promotion_preserves_callbacks_and_negative_output_without_second_resolve() {
        let provider = Provider::new(false);
        let inner = dm_session::RecordingResolver::new(&provider);
        let host = dm_session::RecordingResolver::new(&inner);
        let query = ResolveQuery::GlobalProc(SymbolId::of("missing"));
        let accepted = promotion(&host, vec![query, query]);
        assert_eq!(provider.calls.load(Ordering::Relaxed), 2);
        let original = host.reads();
        assert_eq!(original, inner.reads());
        let transferred = accepted.current_observations(&host);
        assert_eq!(transferred.len(), 2);
        assert!(transferred
            .iter()
            .all(|read| read.answer == ResolvedMeaning::Missing));
        assert_eq!(host.reads(), original);
        assert_eq!(provider.calls.load(Ordering::Relaxed), 2);
        // Independent ordinary resolution gives the same exact semantic output.
        let fresh: Vec<_> = [query, query]
            .into_iter()
            .map(|query| ResolverRead {
                query,
                domain: query.domain(),
                answer: provider.resolve(query),
            })
            .collect();
        assert_eq!(transferred, fresh);
    }
    #[test]
    fn promotion_for_another_provider_or_an_opaque_observer_keeps_ordinary_replay() {
        let provider = Provider::new(false);
        let query = ResolveQuery::GlobalProc(SymbolId::of("missing"));
        let accepted = promotion(&provider, vec![query]);
        let other = Provider::new(false);
        let _ = accepted.current_observations(&other);
        assert_eq!(other.calls.load(Ordering::Relaxed), 1);
        let opaque = Provider::new(true);
        let accepted = promotion(&opaque, vec![query]);
        assert!(accepted.current.is_none());
        let _ = accepted.current_observations(&opaque);
        assert_eq!(opaque.calls.load(Ordering::Relaxed), 2);
    }
}
