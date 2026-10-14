//! Read-only comparison of the existing request admission certificate owners.
//! Coverage is value-equivalence authority only, not permission to omit observer
//! edges. Existing receipt admission must deliver every accepted read edge, and
//! callers must bind the actual resolver/policy family on both request owners.
use super::{ObservationHost, ReceiptAdmission};
use std::collections::BTreeSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CertificateState {
    Unchanged,
    Uncovered,
}
pub struct CertificateDelta<'a, 'host, Q, A: Eq, D, H> {
    previous: &'a ReceiptAdmission<'host, Q, A, D, H>,
    current: &'a ReceiptAdmission<'host, Q, A, D, H>,
    // Comparison states only. Versions remain in the existing request caches.
    states: Vec<(D, CertificateState)>,
}
impl<'a, 'host, Q: Clone, A: Eq, D: Ord + Clone, H: ObservationHost<Q, A, D>>
    CertificateDelta<'a, 'host, Q, A, D, H>
{
    pub fn between(
        previous: &'a ReceiptAdmission<'host, Q, A, D, H>,
        current: &'a ReceiptAdmission<'host, Q, A, D, H>,
        demanded: impl IntoIterator<Item = D>,
    ) -> Self {
        let states = demanded
            .into_iter()
            .collect::<BTreeSet<_>>()
            .into_iter()
            .map(|domain| {
                let old = previous.current_version(&domain);
                let new = current.current_version(&domain);
                let state = if old.is_some() && old == new {
                    CertificateState::Unchanged
                } else {
                    CertificateState::Uncovered
                };
                (domain, state)
            })
            .collect();
        Self {
            previous,
            current,
            states,
        }
    }
    pub fn state(&self, domain: &D) -> CertificateState {
        self.states
            .binary_search_by(|(candidate, _)| candidate.cmp(domain))
            .ok()
            .map_or(CertificateState::Uncovered, |index| self.states[index].1)
    }
    /// Only the exact prior artifact certificate is covered. Different versions
    /// are not proof of changed answers; ordinary admission must replay them.
    pub fn certifies(&self, domain: &D, prior_version: u128) -> bool {
        self.state(domain) == CertificateState::Unchanged
            && self.previous.current_version(domain) == Some(prior_version)
            && self.current.current_version(domain) == Some(prior_version)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    struct Host {
        calls: AtomicUsize,
        version: Option<u128>,
    }
    impl ObservationHost<u32, u32, u32> for Host {
        fn answer(&self, query: &u32) -> u32 {
            *query
        }
        fn version(&self, domain: &u32) -> Option<u128> {
            self.calls.fetch_add(1, Ordering::Relaxed);
            (*domain == 1).then_some(self.version).flatten()
        }
    }
    #[test]
    fn certificate_delta_uses_existing_request_caches_and_declines_uncovered() {
        let old = Host {
            calls: AtomicUsize::new(0),
            version: Some(7),
        };
        let new = Host {
            calls: AtomicUsize::new(0),
            version: Some(7),
        };
        let previous = ReceiptAdmission::new(&old);
        let current = ReceiptAdmission::new(&new);
        let delta = CertificateDelta::between(&previous, &current, [1, 1, 2]);
        assert!(delta.certifies(&1, 7));
        assert!(!delta.certifies(&1, 8));
        assert_eq!(delta.state(&2), CertificateState::Uncovered);
        assert_eq!(delta.state(&3), CertificateState::Uncovered);
        assert_eq!(old.calls.load(Ordering::Relaxed), 2);
        assert_eq!(new.calls.load(Ordering::Relaxed), 2);
        let changed = Host {
            calls: AtomicUsize::new(0),
            version: Some(8),
        };
        let changed_request = ReceiptAdmission::new(&changed);
        assert_eq!(
            CertificateDelta::between(&previous, &changed_request, [1]).state(&1),
            CertificateState::Uncovered
        );
    }
}
