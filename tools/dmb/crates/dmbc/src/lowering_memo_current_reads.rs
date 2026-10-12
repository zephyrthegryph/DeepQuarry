//! Request-borrowed observations, issued only after complete disk admission.
use super::{Arc, LoweredUnit};
use crate::lowering_memo::ResolverRead;
use dm_ir::{ReadDomain, ResolveQuery, Resolver};
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
    versions: Vec<(ReadDomain, Option<u128>)>,
}
impl<'host> CurrentReads<'host> {
    pub(super) fn versions(
        host: &dyn Resolver,
        queries: &[ResolveQuery],
    ) -> Vec<(ReadDomain, Option<u128>)> {
        let mut domains: Vec<_> = queries.iter().map(|query| query.domain()).collect();
        domains.sort();
        domains.dedup();
        domains
            .into_iter()
            .map(|domain| (domain, host.domain_version(domain)))
            .collect()
    }
    pub(super) fn accepted(
        host: &'host dyn Resolver,
        reads: Vec<ResolverRead>,
        versions: Vec<(ReadDomain, Option<u128>)>,
    ) -> Option<Self> {
        if host.observes_reads() && host.transparent_receipt_observer().is_none() {
            return None;
        }
        if reads.iter().any(|read| {
            read.domain != read.query.domain()
                || versions
                    .binary_search_by_key(&read.domain, |(domain, _)| *domain)
                    .is_err()
        }) {
            return None;
        }
        if versions
            .iter()
            .any(|(domain, version)| version.is_none() || host.domain_version(*domain) != *version)
        {
            return None;
        }
        Some(Self {
            host,
            reads,
            versions,
        })
    }
    pub(crate) fn for_host(
        &self,
        host: &dyn Resolver,
    ) -> Option<(&[ResolverRead], &[(ReadDomain, Option<u128>)])> {
        // Borrowed identity cannot outlive the request provider. No persisted
        // pointer, token or hash can authorize this handoff.
        if !std::ptr::eq(self.host, host)
            || self
                .versions
                .iter()
                .any(|(domain, version)| host.domain_version(*domain) != *version)
        {
            return None;
        }
        Some((&self.reads, &self.versions))
    }
}

impl super::ResidentPromotion<'_> {
    pub(crate) fn current_observations(
        &self,
        host: &dyn Resolver,
    ) -> (Vec<ResolverRead>, Vec<(ReadDomain, u128)>) {
        if let Some((reads, versions)) =
            self.current.as_ref().and_then(|reads| reads.for_host(host))
        {
            return (
                reads.to_vec(),
                versions
                    .iter()
                    .filter_map(|(domain, version)| version.map(|version| (*domain, version)))
                    .collect(),
            );
        }
        (
            self.queries
                .iter()
                .map(|query| ResolverRead {
                    query: *query,
                    domain: query.domain(),
                    answer: host.resolve(*query),
                })
                .collect(),
            self.versions.clone(),
        )
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ResolvedMeaning, SymbolId};
    use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
    struct Provider {
        calls: AtomicUsize,
        version: AtomicU64,
        opaque: bool,
    }
    impl Provider {
        fn new(opaque: bool) -> Self {
            Self {
                calls: AtomicUsize::new(0),
                version: AtomicU64::new(1),
                opaque,
            }
        }
    }
    impl Resolver for Provider {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.calls.fetch_add(1, Ordering::Relaxed);
            ResolvedMeaning::Missing
        }
        fn domain_version(&self, _: ReadDomain) -> Option<u128> {
            Some(self.version.load(Ordering::Relaxed) as u128)
        }
        fn observes_reads(&self) -> bool {
            self.opaque
        }
    }
    fn promotion<'a>(
        host: &'a dyn Resolver,
        queries: Vec<ResolveQuery>,
    ) -> super::super::ResidentPromotion<'a> {
        let versions = CurrentReads::versions(host, &queries);
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
        let current = CurrentReads::accepted(host, reads, versions.clone());
        super::super::ResidentPromotion {
            current,
            queries,
            versions: versions
                .into_iter()
                .filter_map(|(d, v)| v.map(|v| (d, v)))
                .collect(),
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
        let (transferred, versions) = accepted.current_observations(&host);
        assert_eq!(transferred.len(), 2);
        assert!(transferred
            .iter()
            .all(|read| read.answer == ResolvedMeaning::Missing));
        assert_eq!(versions, host.domain_receipts());
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
    fn promotion_changed_provider_stale_version_and_opaque_observer_keep_ordinary_replay() {
        let provider = Provider::new(false);
        let query = ResolveQuery::GlobalProc(SymbolId::of("missing"));
        let accepted = promotion(&provider, vec![query]);
        let other = Provider::new(false);
        let _ = accepted.current_observations(&other);
        assert_eq!(other.calls.load(Ordering::Relaxed), 1);
        provider.version.store(2, Ordering::Relaxed);
        let _ = accepted.current_observations(&provider);
        assert_eq!(provider.calls.load(Ordering::Relaxed), 2);
        let opaque = Provider::new(true);
        let accepted = promotion(&opaque, vec![query]);
        assert!(accepted.current.is_none());
        let _ = accepted.current_observations(&opaque);
        assert_eq!(opaque.calls.load(Ordering::Relaxed), 2);
        assert!(
            CurrentReads::accepted(&provider, Vec::new(), vec![(query.domain(), None)]).is_none()
        );
    }
}
