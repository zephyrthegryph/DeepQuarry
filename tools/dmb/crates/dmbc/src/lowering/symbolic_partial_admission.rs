//! Candidate-specific certificate replay through the existing admission core.
use super::*;

/// Share only the immutable current issuer lookup, never a candidate verdict.
/// Stored versions are still compared separately for every candidate.
pub(super) fn matching_domains<R: Resolver>(
    versions: &[(dm_ir::ReadDomain, u128)],
    host: &R,
    admission: Option<&RequestAdmission<'_, R>>,
) -> std::collections::BTreeSet<dm_ir::ReadDomain> {
    match admission {
        Some(admission) => admission.certified_domains(versions),
        None => crate::lowering_memo::matching_domains(versions, host),
    }
}

pub(super) fn changed<R: Resolver>(
    admission: &RequestAdmission<'_, R>,
    reads: &receipt_groups::ProcedureReceipt,
    versions: &[(dm_ir::ReadDomain, u128)],
    observer: &crate::lowering_memo::RecordingResolver<'_, R>,
) -> Option<dm_ir::ResolveQuery> {
    admission.first_changed_receipted(reads, versions, |leaf| observer.record_admitted(leaf))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Host {
        certified: dm_ir::ResolveQuery,
        opaque: dm_ir::ResolveQuery,
        certified_calls: AtomicUsize,
        opaque_calls: AtomicUsize,
        appeared: bool,
        version_calls: AtomicUsize,
    }
    impl Resolver for Host {
        fn observes_reads(&self) -> bool {
            false
        }
        fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
            self.version_calls.fetch_add(1, Ordering::Relaxed);
            (domain == self.certified.domain()).then_some(7)
        }
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            if query == self.certified {
                self.certified_calls.fetch_add(1, Ordering::Relaxed);
                dm_ir::ResolvedMeaning::Presence(false)
            } else {
                assert_eq!(query, self.opaque);
                self.opaque_calls.fetch_add(1, Ordering::Relaxed);
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
            certified: dm_ir::ResolveQuery::MemberCallableName(dm_ir::SymbolId::of("certified")),
            opaque: dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of("opaque")),
            certified_calls: AtomicUsize::new(0),
            opaque_calls: AtomicUsize::new(0),
            appeared,
            version_calls: AtomicUsize::new(0),
        }
    }
    #[test]
    fn candidate_domain_checks_share_current_issuer_but_not_stored_versions() {
        let host = host(false);
        let request = RequestAdmission::new(&host);
        let versions = [(host.certified.domain(), 7), (host.opaque.domain(), 99)];
        for _ in 0..3 {
            let matching = matching_domains(&versions, &host, Some(&request));
            assert!(matching.contains(&host.certified.domain()));
            assert!(!matching.contains(&host.opaque.domain()));
        }
        assert_eq!(
            host.version_calls.load(Ordering::Relaxed),
            2,
            "each current issuer, including absent authority, is queried once"
        );
        assert!(
            matching_domains(&[(host.certified.domain(), 6)], &host, Some(&request)).is_empty()
        );
        assert_eq!(host.version_calls.load(Ordering::Relaxed), 2);
        assert_eq!(host.certified_calls.load(Ordering::Relaxed), 0);
        assert_eq!(host.opaque_calls.load(Ordering::Relaxed), 0);
        // Compatibility callers still request their current host's authority.
        assert!(matching_domains(&versions, &host, None).contains(&host.certified.domain()));
        assert_eq!(host.version_calls.load(Ordering::Relaxed), 4);
    }
    #[test]
    fn mixed_certificates_skip_current_domains_but_replay_negative_opaque_edges() {
        let host = host(false);
        let reads: receipt_groups::ProcedureReceipt = [host.certified, host.opaque]
            .into_iter()
            .map(|query| ResolverRead {
                query,
                domain: query.domain(),
                answer: if query == host.opaque {
                    dm_ir::ResolvedMeaning::Missing
                } else {
                    dm_ir::ResolvedMeaning::Presence(false)
                },
            })
            .collect::<Vec<_>>()
            .into();
        let versions = [(host.certified.domain(), 7)];
        let request = RequestAdmission::new(&host);
        for _ in 0..2 {
            let observer = crate::lowering_memo::RecordingResolver::new(&host);
            assert_eq!(changed(&request, &reads, &versions, &observer), None);
            assert_eq!(
                observer.reads().len(),
                2,
                "every admitted edge stays recorded"
            );
        }
        assert_eq!(host.certified_calls.load(Ordering::Relaxed), 0);
        assert_eq!(
            host.opaque_calls.load(Ordering::Relaxed),
            2,
            "partial success cannot seed a full-answer verdict"
        );
        // The same leaf with a changed issuer receipt must replay the certified
        // query too; prior partial success cannot license this candidate.
        let observer = crate::lowering_memo::RecordingResolver::new(&host);
        assert_eq!(
            changed(&request, &reads, &[(host.certified.domain(), 6)], &observer),
            None
        );
        assert_eq!(host.certified_calls.load(Ordering::Relaxed), 1);
        let current = self::host(true);
        let request = RequestAdmission::new(&current);
        let observer = crate::lowering_memo::RecordingResolver::new(&current);
        assert_eq!(
            changed(&request, &reads, &versions, &observer),
            Some(current.opaque)
        );
        assert_eq!(current.certified_calls.load(Ordering::Relaxed), 0);
        assert_eq!(current.opaque_calls.load(Ordering::Relaxed), 1);
        assert!(
            observer.reads().is_empty(),
            "failed flat leaf is never admitted"
        );
    }
}
