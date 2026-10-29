//! Immutable issued source-only host for the common ReceiptAdmission path.
//! Engine, resource, config and whole-tree certificates remain uncovered.
//! These certificates cover this source-tree resolver only. They must never
//! stand in for an engine, constant, runtime or ABI overlay's certificates merely
//! because the ReadDomain names match. Scheduling must bind the actual candidate
//! resolver/policy issuer; this host is not wired into production scheduling.
use super::FrontendRevision;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
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
        dm_ir::Resolver::resolve(self.revision.snapshot.tree.as_ref(), query)
    }
    fn observes_reads(&self) -> bool {
        false
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
    fn issued_read_host_names_no_world_and_keeps_exact_revision_binding() {
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
        assert_eq!(host.answer_world(), None);
        let query = ResolveQuery::GlobalProc(dm_ir::SymbolId::of("missing"));
        assert_eq!(
            dm_ir::Resolver::resolve(&host, query),
            dm_ir::Resolver::resolve(revision.snapshot.tree.as_ref(), query)
        );
    }
}
