//! Immutable issued source-only host for the common ReceiptAdmission path.
//! Engine, resource, config and whole-tree certificates remain uncovered.
//! These certificates cover this source-tree resolver only. They must never
//! stand in for an engine, constant, runtime or ABI overlay's certificates merely
//! because the ReadDomain names match. Scheduling must bind the actual candidate
//! resolver/policy issuer; this host is not wired into production scheduling.
use super::FrontendRevision;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
pub struct FrontendReadHost<'a> {
    revision: &'a FrontendRevision,
}
impl<'a> FrontendReadHost<'a> {
    pub fn issue(revision: &'a FrontendRevision) -> Result<Self, String> {
        revision.callable_roster()?;
        Ok(Self { revision })
    }
    pub fn authenticates(&self, revision: &FrontendRevision) -> bool {
        self.revision.issuance().matches(revision)
    }
}
impl Resolver for FrontendReadHost<'_> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.revision.snapshot.tree.resolve(query)
    }
    fn observes_reads(&self) -> bool {
        false
    }
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        match domain {
            ReadDomain::OwnerHierarchy(_)
            | ReadDomain::OwnerCallable(_)
            | ReadDomain::OwnerVariable(_) => self.revision.snapshot.tree.domain_version(domain),
            _ => None,
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/proc/p()\n    return missing\n".into())
        }
    }
    #[test]
    fn issued_read_host_keeps_external_domains_uncovered_and_exact_revision_binding() {
        let revision = FrontendRevision::new(
            crate::frontend::build(Path::new("read.dme"), &Source, &Default::default(), 1).unwrap(),
        );
        let host = FrontendReadHost::issue(&revision).unwrap();
        assert!(host.authenticates(&revision));
        assert!(host.authenticates(&revision.clone()));
        let foreign = FrontendRevision::new(
            crate::frontend::build(Path::new("read.dme"), &Source, &Default::default(), 1).unwrap(),
        );
        assert!(!host.authenticates(&foreign));
        assert_eq!(host.domain_version(ReadDomain::Tree), None);
        let admission = dm_session::ReceiptAdmission::new(&host);
        let delta =
            dm_session::CertificateDelta::between(&admission, &admission, [ReadDomain::Tree]);
        assert_eq!(
            delta.state(&ReadDomain::Tree),
            dm_session::CertificateState::Uncovered
        );
        let query = ResolveQuery::GlobalProc(dm_ir::SymbolId::of("missing"));
        assert_eq!(host.resolve(query), revision.snapshot.tree.resolve(query));
    }
}
