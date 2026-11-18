//! Paid temporary ownership for the existing Pratt parser's suspended work.
//! This grants storage only: no tokens, grammar, or semantic authority.
use crate::{SettingAdmission, SettingRootLease};
use std::io;

pub(crate) struct PrattContinuations<'a, 'op, T> {
    // Declaration order is intentional: every T and the Vec allocation die
    // before their storage credit, including cancellation and error unwinds.
    rows: Vec<T>,
    credit: Option<SettingRootLease>,
    admission: Option<&'a SettingAdmission<'op>>,
}

impl<'a, 'op, T> PrattContinuations<'a, 'op, T> {
    pub(crate) fn new(admission: Option<&'a SettingAdmission<'op>>) -> Self {
        Self { rows: Vec::new(), credit: None, admission }
    }

    fn fail(&self, message: impl Into<String>) -> io::Error {
        if let Some(a) = self.admission {
            a.record_operational_error(io::Error::new(io::ErrorKind::OutOfMemory, message.into()));
        }
        io::ErrorKind::OutOfMemory.into()
    }

    pub(crate) fn push(&mut self, value: T) -> io::Result<()> {
        let required = self.rows.len().checked_add(1)
            .ok_or_else(|| self.fail("Pratt continuation length overflow"))?;
        self.reserve_total(required)?;
        self.rows.push(value);
        Ok(())
    }

    pub(crate) fn reserve_total(&mut self, required: usize) -> io::Result<()> {
        if let Some(a) = self.admission { a.checkpoint()?; }
        if required > self.rows.capacity() {
            let capacity = self.rows.capacity().max(2).checked_mul(2).map(|n|n.max(required))
                .ok_or_else(|| self.fail("Pratt continuation capacity overflow"))?;
            // Old credit remains live while the new buffer is allocated.
            // As in the primary frame buffer, the conservative growth grant
            // covers allocator capacity rounding before actual settlement.
            let peak = capacity.checked_mul(std::mem::size_of::<T>())
                .and_then(|n| n.checked_mul(4))
                .ok_or_else(|| self.fail("Pratt continuation storage overflow"))?;
            let mut next_credit = match self.admission {
                Some(a) => Some(a.reserve(peak)?),
                None => None,
            };
            let mut next = Vec::new();
            next.try_reserve_exact(capacity)
                .map_err(|error| self.fail(format!("Pratt continuation allocation failed: {error}")))?;
            let actual = next.capacity().checked_mul(std::mem::size_of::<T>())
                .ok_or_else(|| self.fail("Pratt continuation actual capacity overflow"))?;
            let excess = peak.checked_sub(actual)
                .ok_or_else(|| self.fail("Pratt allocator exceeded admitted capacity"))?;
            next.append(&mut self.rows);
            let old = std::mem::replace(&mut self.rows, next);
            drop(old); // Physically retire the old allocation before its credit.
            self.credit = next_credit.take();
            if let Some(credit) = &mut self.credit {
                // Settlement is cleanup only; do not consume/reset a first
                // operational error or insert a new cancellation checkpoint.
                if let Err(error) = credit.release_retired_bytes(excess) {
                    let kind = error.kind();
                    if let Some(a) = self.admission { a.record_operational_error(error); }
                    return Err(kind.into());
                }
            }
        }
        Ok(())
    }

    // Cleanup-only push. The private owner pre-admits a total-node bound;
    // this never reserves, polls or grows while destroying that root.
    pub(crate) fn push_preallocated(&mut self, value: T) {
        assert!(self.rows.len() < self.rows.capacity(), "pre-admitted Pratt cleanup frontier");
        self.rows.push(value);
    }

    pub(crate) fn pop(&mut self) -> Option<T> { self.rows.pop() }
    pub(crate) fn len(&self) -> usize { self.rows.len() }
    pub(crate) fn is_empty(&self) -> bool { self.rows.is_empty() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};

    #[test]
    fn pratt_continuation_storage_moves_values_and_refunds_exact_capacity() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let fixed = counter.load(Ordering::Acquire);
        let a = SettingAdmission::new(&counter, 1 << 20, &|| Ok(()));
        let mut work = PrattContinuations::new(Some(&a));
        for n in 0..67usize { work.push(n).unwrap(); }
        assert_eq!(work.len(), 67);
        assert!(counter.load(Ordering::Acquire) > fixed);
        for n in (0..67).rev() { assert_eq!(work.pop(), Some(n)); }
        assert!(work.is_empty());
        assert!(counter.load(Ordering::Acquire) > fixed, "empty capacity remains paid");
        drop(work);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn pratt_continuation_payload_drops_before_credit_and_keeps_first_io() {
        struct Payload<'a> { counter: Arc<crate::SettingChargeCounter>, drops: &'a AtomicUsize }
        impl Drop for Payload<'_> {
            fn drop(&mut self) {
                assert!(self.counter.load(Ordering::Acquire) > crate::SettingChargeCounter::root_allocation_bytes());
                self.drops.fetch_add(1, Ordering::AcqRel);
            }
        }
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let fixed = counter.load(Ordering::Acquire);
        let drops = AtomicUsize::new(0);
        let stop = Cell::new(false);
        let poll = || if stop.get() { Err(io::Error::from_raw_os_error(1450)) } else { Ok(()) };
        let a = SettingAdmission::new(&counter, 1 << 20, &poll);
        let mut work = PrattContinuations::new(Some(&a));
        for _ in 0..7 { work.push(Payload { counter: Arc::clone(&counter), drops: &drops }).unwrap(); }
        stop.set(true);
        let proxy = work.push(Payload { counter: Arc::clone(&counter), drops: &drops }).err().unwrap();
        assert_eq!(proxy.kind(), io::Error::from_raw_os_error(1450).kind());
        assert_eq!(a.take_operational_error().unwrap().raw_os_error(), Some(1450));
        assert_eq!(drops.load(Ordering::Acquire), 1);
        drop(work);
        assert_eq!(drops.load(Ordering::Acquire), 8);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
    }

    #[test]
    fn pratt_continuation_quota_failure_retains_old_storage_and_retry_works() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let fixed = counter.load(Ordering::Acquire);
        let denied = SettingAdmission::new(&counter, fixed, &|| Ok(()));
        let mut work = PrattContinuations::new(Some(&denied));
        assert_eq!(work.push(1usize).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert!(work.is_empty());
        assert_eq!(denied.take_operational_error().unwrap().kind(), io::ErrorKind::OutOfMemory);
        drop(work);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
        let growing = SettingAdmission::new(&counter, fixed + 128, &|| Ok(()));
        let mut work = PrattContinuations::new(Some(&growing));
        for n in 0..4usize { work.push(n).unwrap(); }
        let held = counter.load(Ordering::Acquire);
        assert_eq!(work.push(4usize).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(work.len(), 4, "denied growth preserves its old owners");
        assert_eq!(counter.load(Ordering::Acquire), held);
        assert_eq!(growing.take_operational_error().unwrap().kind(), io::ErrorKind::OutOfMemory);
        for n in (0..4).rev() { assert_eq!(work.pop(), Some(n)); }
        drop(work);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
        let retry = SettingAdmission::new(&counter, 1 << 20, &|| Ok(()));
        let mut work = PrattContinuations::new(Some(&retry));
        work.push(9usize).unwrap(); assert_eq!(work.pop(), Some(9));
        drop(work);
        assert_eq!(counter.load(Ordering::Acquire), fixed);
        let mut unadmitted = PrattContinuations::new(None);
        unadmitted.push(11usize).unwrap(); assert_eq!(unadmitted.pop(), Some(11));
    }
}
