//! One immutable provider context for both passes of a classification wave.
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
use dm_session::observations::ReceiptAdmission;
use std::sync::Arc;
pub(super) struct Host<'host>(pub(super) &'host dyn Resolver);
impl Resolver for Host<'_> {
    fn resolve_with_canonical(&self, query: ResolveQuery) -> dm_ir::CanonicalResolvedAnswer {
        self.0.resolve_with_canonical(query)
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.0.resolve(query)
    }
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.0.domain_version(domain)
    }
    fn observes_reads(&self) -> bool {
        self.0.observes_reads()
    }
    fn transparent_receipt_observer(&self) -> Option<dm_ir::TransparentReceiptObserver<'_>> {
        self.0.transparent_receipt_observer()
    }
}
pub(super) type Admission<'request, 'host> =
    ReceiptAdmission<'request, ResolveQuery, ResolvedMeaning, ReadDomain, Host<'host>>;
pub(super) fn visit<T: Send + Sync>(
    store: &crate::artifact_publication_store::Store<T, ResolveQuery, ResolvedMeaning, ReadDomain>,
    key: &[u8],
    resolver: &dyn Resolver,
    request: Option<&Admission<'_, '_>>,
    accept: &mut dyn FnMut(&Arc<T>) -> bool,
) -> (Option<Arc<T>>, Option<ResolveQuery>) {
    match request {
        Some(request) => store.visit_current_qualified_in(key, request, accept),
        None => store.visit_current_qualified(key, &Host(resolver), accept),
    }
}
