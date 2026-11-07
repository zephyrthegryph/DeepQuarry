//! Allocation reservations versus cached-body estimates in ONE syntax domain.
//! Neither class is source/semantic authority. Aggregate admission is unchanged.
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
#[derive(Debug)]
pub struct SettingChargeCounter {
    aggregate: AtomicUsize,
    leased: AtomicUsize,
}
impl SettingChargeCounter {
    /// Fixed payload plus the existing two-word Arc-control allocation bound.
    pub const fn root_allocation_bytes() -> usize {
        std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>()
    }
    /// Establish funding on the stack BEFORE allocating this root's Arc.
    /// The root itself remains charged until its last lease/admission alias dies.
    pub fn try_new(limit: usize) -> Result<Arc<Self>, &'static str> {
        let fixed = Self::root_allocation_bytes();
        if fixed > limit {
            return Err("setting counter root allocation denied before Arc construction");
        }
        Ok(Arc::new(Self {
            aggregate: AtomicUsize::new(fixed),
            leased: AtomicUsize::new(fixed),
        }))
    }
    /// Existing authoritative aggregate, including fixed root storage.
    pub fn load(&self, ordering: Ordering) -> usize {
        self.aggregate.load(ordering)
    }
    /// Only root + real allocation reservations. NOT measured allocation size/RSS.
    /// Separate loads are not an atomic snapshot with aggregate/cache estimates.
    pub fn allocation_lease_reserved(&self) -> usize {
        self.leased.load(Ordering::Acquire)
    }
    /// A postparse SOFT estimate keeps the original nonrefusing publication policy.
    /// It can pass the cache-pressure threshold; the next preparation evicts as before.
    pub fn add_soft_estimate(&self, bytes: usize) {
        self.aggregate.fetch_add(bytes, Ordering::Relaxed);
    }
    /// Caller refunds the SAME previously published cache estimate after eviction.
    /// Never touches real lease classification or refunds fixed root metadata.
    pub fn release_soft_estimate(&self, bytes: usize) {
        let fixed = Self::root_allocation_bytes();
        let _ = self
            .aggregate
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |old| {
                Some(old.saturating_sub(bytes).max(fixed))
            });
    }
    pub(crate) fn reserve_lease(&self, limit: usize, bytes: usize) -> Result<(), &'static str> {
        self.aggregate
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |old| {
                old.checked_add(bytes).filter(|next| *next <= limit)
            })
            .map_err(|_| "setting root retained syntax admission denied")?;
        // Permission cannot escape before classification; no physical allocation here.
        self.leased.fetch_add(bytes, Ordering::AcqRel);
        Ok(())
    }
    pub(crate) fn release_lease(&self, bytes: usize) -> Result<(), &'static str> {
        let fixed = Self::root_allocation_bytes();
        self.leased
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |old| {
                old.checked_sub(bytes).filter(|next| *next >= fixed)
            })
            .map_err(|_| "setting allocation counter is below owned release")?;
        let old = self.aggregate.fetch_sub(bytes, Ordering::AcqRel);
        debug_assert!(old >= bytes + fixed);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SettingAdmission, SettingRootLease};
    #[test]
    fn soft_estimate_never_becomes_an_allocation_reservation() {
        let fixed = SettingChargeCounter::root_allocation_bytes();
        let counter = SettingChargeCounter::try_new(fixed + 300).unwrap();
        let real = SettingRootLease::reserve(&counter, fixed + 300, 100).unwrap();
        counter.add_soft_estimate(200);
        assert_eq!(counter.load(Ordering::Acquire), fixed + 300);
        assert_eq!(counter.allocation_lease_reserved(), fixed + 100);
        assert!(SettingRootLease::reserve(&counter, fixed + 300, 1).is_err());
        counter.release_soft_estimate(200);
        assert_eq!(counter.allocation_lease_reserved(), fixed + 100);
        let next = SettingRootLease::reserve(&counter, fixed + 300, 200).unwrap();
        drop(real);
        drop(next);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
        assert_eq!(counter.allocation_lease_reserved(), fixed);
    }
    #[test]
    fn root_is_prepaid_and_real_split_absorb_shrink_keep_classification() {
        let fixed = SettingChargeCounter::root_allocation_bytes();
        assert!(SettingChargeCounter::try_new(fixed - 1).is_err());
        let counter = SettingChargeCounter::try_new(fixed + 1000).unwrap();
        let a = SettingAdmission::new(&counter, fixed + 1000, &|| Ok(()));
        let mut owner = a.reserve(700).unwrap();
        let mut child = a.split(&mut owner, 200).unwrap();
        assert_eq!(
            (
                counter.load(Ordering::Acquire),
                counter.allocation_lease_reserved()
            ),
            (fixed + 700, fixed + 700)
        );
        a.absorb(&mut owner, &mut child).unwrap();
        drop(child);
        a.grow(&mut owner, 100).unwrap();
        a.shrink(&mut owner, 300).unwrap();
        assert_eq!(
            (
                counter.load(Ordering::Acquire),
                counter.allocation_lease_reserved()
            ),
            (fixed + 500, fixed + 500)
        );
        drop(owner);
        assert_eq!(
            (
                counter.load(Ordering::Acquire),
                counter.allocation_lease_reserved()
            ),
            (fixed, fixed)
        );
        assert_eq!(
            std::mem::size_of::<SettingRootLease>(),
            std::mem::size_of::<Arc<SettingChargeCounter>>() + std::mem::size_of::<usize>()
        );
    }
    #[test]
    fn foreign_and_cancelled_operations_preserve_both_counters() {
        let fixed = SettingChargeCounter::root_allocation_bytes();
        let counter = SettingChargeCounter::try_new(fixed + 100).unwrap();
        let other = SettingChargeCounter::try_new(fixed + 100).unwrap();
        let own = SettingAdmission::new(&counter, fixed + 100, &|| Ok(()));
        let foreign = SettingAdmission::new(&other, fixed + 100, &|| Ok(()));
        let mut payload = own.reserve(40).unwrap();
        assert!(foreign.grow(&mut payload, 1).is_err());
        let fail = || Err(std::io::Error::from_raw_os_error(1450));
        let failed = SettingAdmission::new(&counter, fixed + 100, &fail);
        assert!(failed.reserve(1).is_err());
        assert_eq!(
            failed.take_operational_error().unwrap().raw_os_error(),
            Some(1450)
        );
        assert_eq!(
            (
                counter.load(Ordering::Acquire),
                counter.allocation_lease_reserved()
            ),
            (fixed + 40, fixed + 40)
        );
        assert_eq!(
            (
                other.load(Ordering::Acquire),
                other.allocation_lease_reserved()
            ),
            (fixed, fixed)
        );
        drop(payload);
        assert_eq!(counter.allocation_lease_reserved(), fixed);
    }
    #[test]
    fn concurrent_real_reservations_and_exact_soft_refunds_keep_old_aggregate_cutoff() {
        let fixed = SettingChargeCounter::root_allocation_bytes();
        let limit = fixed + 256;
        let counter = SettingChargeCounter::try_new(limit).unwrap();
        let start = Arc::new(std::sync::Barrier::new(3));
        std::thread::scope(|scope| {
            for _ in 0..2 {
                let counter = Arc::clone(&counter);
                let start = Arc::clone(&start);
                scope.spawn(move || {
                    start.wait();
                    for _ in 0..1024 {
                        if let Ok(lease) = SettingRootLease::reserve(&counter, limit, 128) {
                            assert!(counter.allocation_lease_reserved() <= limit);
                            drop(lease);
                        }
                    }
                });
            }
            start.wait();
            for _ in 0..1024 {
                // The old soft publication policy may temporarily pass limit.
                // Its exact refund must never release real classification.
                counter.add_soft_estimate(64);
                counter.release_soft_estimate(64);
            }
        });
        assert_eq!(
            (
                counter.load(Ordering::Acquire),
                counter.allocation_lease_reserved()
            ),
            (fixed, fixed)
        );
        let all = SettingRootLease::reserve(&counter, limit, 256).unwrap();
        assert!(SettingRootLease::reserve(&counter, limit, 1).is_err());
        drop(all);
    }
}
