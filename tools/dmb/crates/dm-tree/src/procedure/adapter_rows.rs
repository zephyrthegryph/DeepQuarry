//! Temporary declaration adapter rows on their actual syntax allocation domain.
use super::original_primary_signatures::grow_funded_rows;
use dm_syntax::{SettingAdmission, SettingRootLease};
use std::{collections::TryReserveError, io, sync::Arc};

pub(crate) struct AdapterRows<T> {
    rows: Vec<T>,
    // The same buffer is moved with the receipt and always drops before credit.
    credit: Option<SettingRootLease>,
}
impl<T> Default for AdapterRows<T> {
    fn default() -> Self { Self { rows: Vec::new(), credit: None } }
}
impl<T> std::ops::Deref for AdapterRows<T> {
    type Target = [T];
    fn deref(&self) -> &[T] { &self.rows }
}
impl<T> std::ops::DerefMut for AdapterRows<T> {
    fn deref_mut(&mut self) -> &mut [T] { &mut self.rows }
}
impl<T> AdapterRows<T> {
    pub(crate) fn reserve_compatibility(&mut self) -> Result<(), TryReserveError> {
        assert!(self.credit.is_none(), "funded staging cannot use compatibility allocation");
        self.rows.try_reserve_exact(1)
    }

    pub(crate) fn reserve_checked(&mut self, a: &SettingAdmission<'_>) -> io::Result<()> {
        if self.credit.as_ref().is_some_and(|credit| !a.matches_lease_domain(credit)) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        if self.rows.len() == self.rows.capacity() {
            grow_funded_rows(&mut self.rows, &mut self.credit, a)?;
        }
        Ok(())
    }

    pub(crate) fn push_reserved(&mut self, value: T) {
        assert!(self.rows.len() < self.rows.capacity(), "adapter row must be reserved first");
        self.rows.push(value);
    }

    /// Caller preadmits the destination Arc if this is a checked adapter. The
    /// Vec is physically freed by the move conversion before staging is refunded.
    pub(crate) fn into_shared(self) -> Arc<[T]> {
        let Self { rows, credit } = self;
        let shared = Arc::from(rows);
        drop(credit);
        shared
    }

    #[cfg(test)]
    pub(crate) fn compatibility(rows: Vec<T>) -> Self { Self { rows, credit: None } }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{Ordering};

    #[test]
    fn actual_single_adapter_row_reserves_only_its_one_initialized_slot() {
        let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let used=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let unit=std::mem::size_of::<u64>();let a=SettingAdmission::new(&used,root+unit,&||Ok(()));let mut rows=AdapterRows::default();rows.reserve_checked(&a).unwrap();rows.push_reserved(19u64);assert_eq!(rows.rows.capacity(),1);assert_eq!(&*rows,[19]);assert_eq!(rows.credit.as_ref().unwrap().bytes(),unit);assert_eq!(used.load(Ordering::Acquire),root+unit);drop(rows);assert_eq!(used.load(Ordering::Acquire),root);
    }

    #[test]
    fn denied_adapter_growth_keeps_existing_rows_and_refunds_at_last_owner() {
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (95), &|| Ok(()));
        let mut rows = AdapterRows::default();
        for value in 0..4u64 {
            rows.reserve_checked(&a).unwrap();
            rows.push_reserved(value);
        }
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (32));
        assert_eq!(rows.reserve_checked(&a).unwrap_err().kind(), io::ErrorKind::OutOfMemory);
        assert_eq!(&*rows, [0,1,2,3]);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes() + (32));
        drop(rows);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn actual_stage_to_shared_keeps_overlap_and_releases_only_source_buffer() {
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 4096, &|| Ok(()));
        let mut rows = AdapterRows::default();
        rows.reserve_checked(&a).unwrap();
        rows.push_reserved(Arc::<str>::from("same existing payload"));
        let retained = a.reserve(std::mem::size_of::<Arc<str>>() + 2*std::mem::size_of::<usize>()).unwrap();
        let before = used.load(Ordering::Acquire);
        let shared = rows.into_shared();
        assert_eq!(shared[0].as_ref(), "same existing payload");
        assert_eq!(before - used.load(Ordering::Acquire), std::mem::size_of::<Arc<str>>());
        drop((shared,retained));
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
}
