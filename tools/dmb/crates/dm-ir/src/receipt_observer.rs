//! Optional transparent observer delivery, never a separate resolver authority.
use crate::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
/// A recorder that accepts already admitted answers from its own immutable
/// provider. Calls preserve original positive, negative and opaque obligations.
/// This interface itself performs no admission and issues no reusable verdict.
pub trait ResolvedReadObserver: Sync {
    fn record_answer(
        &self,
        query: ResolveQuery,
        answer: &ResolvedMeaning,
        domain: ReadDomain,
        version: Option<u128>,
    );
}
/// Transparent observation must not intercept/change any provider answer.
/// Semantic overlays must decline unless they supply their actual full provider.
/// The descriptor is borrowed; it cannot outlive the current immutable host.
#[derive(Clone, Copy)]
pub struct TransparentReceiptObserver<'a> {
    provider: &'a dyn Resolver,
    observer: &'a dyn ResolvedReadObserver,
}
impl<'a> TransparentReceiptObserver<'a> {
    pub fn new(provider: &'a dyn Resolver, observer: &'a dyn ResolvedReadObserver) -> Option<Self> {
        (!provider.observes_reads()).then_some(Self { provider, observer })
    }
    pub fn provider(&self) -> &'a dyn Resolver {
        self.provider
    }
    /// Only caller-established exact admission licenses this delivery. This
    /// cannot be used as proof that a candidate's stored answer is current.
    pub fn record_answer(
        &self,
        query: ResolveQuery,
        answer: &ResolvedMeaning,
        domain: ReadDomain,
        version: Option<u128>,
    ) {
        self.observer.record_answer(query, answer, domain, version);
    }
}
