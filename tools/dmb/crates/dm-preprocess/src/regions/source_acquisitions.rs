//! Occurrence ordinal lookup shared by ordinary and Original directive plans.
//! The Original branch owns one admitted dense array. Its holes are actual
//! missing acquisitions, never manufactured source identities.
use crate::{macro_expansion::OriginalMacroRows, SourceAcquisitionLease};
use dm_syntax::{SettingAdmission, SettingRootLease};
use std::{collections::BTreeMap, fmt, io, mem, sync::Arc};

#[derive(Clone)]
pub struct SourceAcquisitions(Storage);

#[derive(Clone)]
enum Storage {
    Ordinary(BTreeMap<usize, SourceAcquisitionLease>),
    Original(Arc<OriginalRows>),
}

struct OriginalRows {
    rows: OriginalMacroRows<Option<SourceAcquisitionLease>>,
    count: usize,
    // The fixed owner survives through the last shared array reference.
    _control: SettingRootLease,
}

impl Default for SourceAcquisitions {
    fn default() -> Self {
        Self(Storage::Ordinary(BTreeMap::new()))
    }
}

impl fmt::Debug for SourceAcquisitions {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SourceAcquisitions").field("len", &self.len()).finish()
    }
}

impl SourceAcquisitions {
    pub(super) fn original(a: &SettingAdmission<'_>) -> io::Result<Self> {
        let control = a
            .reserve(mem::size_of::<OriginalRows>() + 2 * mem::size_of::<usize>())
            .map_err(|error| a.take_operational_error().unwrap_or(error))?;
        Ok(Self(Storage::Original(Arc::new(OriginalRows {
            rows: OriginalMacroRows::new(a)?,
            count: 0,
            _control: control,
        }))))
    }

    pub fn get(&self, occurrence: &usize) -> Option<&SourceAcquisitionLease> {
        match &self.0 {
            Storage::Ordinary(rows) => rows.get(occurrence),
            Storage::Original(owner) => owner.rows.as_slice().get(*occurrence)?.as_ref(),
        }
    }

    pub fn contains_key(&self, occurrence: &usize) -> bool {
        self.get(occurrence).is_some()
    }

    pub fn len(&self) -> usize {
        match &self.0 {
            Storage::Ordinary(rows) => rows.len(),
            Storage::Original(owner) => owner.count,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn values(&self) -> impl Iterator<Item = &SourceAcquisitionLease> {
        let (ordinary, original) = match &self.0 {
            Storage::Ordinary(rows) => (Some(rows.values()), None),
            Storage::Original(owner) => (None, Some(owner.rows.as_slice().iter())),
        };
        ordinary.into_iter().flatten().chain(
            original.into_iter().flatten().filter_map(Option::as_ref),
        )
    }

    pub(super) fn clear(&mut self) {
        *self = Self::default();
    }

    /// Ordinary plans expose mutable compatibility data. Actual Original plans
    /// expose only shared borrows and use the funded append path below.
    pub fn insert(
        &mut self,
        occurrence: usize,
        acquisition: SourceAcquisitionLease,
    ) -> Option<SourceAcquisitionLease> {
        let Storage::Ordinary(rows) = &mut self.0 else {
            panic!("Original source acquisitions require funded insertion");
        };
        rows.insert(occurrence, acquisition)
    }

    pub(super) fn append_original(
        &mut self,
        occurrence: usize,
        acquisition: SourceAcquisitionLease,
        a: &SettingAdmission<'_>,
    ) -> io::Result<()> {
        let Storage::Original(owner) = &mut self.0 else {
            return Err(io::ErrorKind::InvalidInput.into());
        };
        let owner = Arc::get_mut(owner).ok_or(io::ErrorKind::InvalidInput)?;
        let skipped = occurrence
            .checked_sub(owner.rows.len())
            .ok_or(io::ErrorKind::InvalidInput)?;
        let added = skipped.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
        owner.rows.ensure(added, a)?;
        for _ in 0..skipped {
            owner.rows.push(None, a)?;
        }
        owner.rows.push(Some(acquisition), a)?;
        owner.count += 1;
        Ok(())
    }

    pub(super) fn visit_original_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        if let Storage::Original(owner) = &self.0 {
            let bytes = mem::size_of::<OriginalRows>() + 2 * mem::size_of::<usize>();
            visit(Arc::as_ptr(owner) as usize, bytes, bytes);
            let logical = owner.rows.len() * mem::size_of::<Option<SourceAcquisitionLease>>();
            owner.rows.visit_allocation(|address, capacity| visit(address, logical, capacity));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn dense_source_rows_keep_real_acquisition_identity_under_low_cap() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 64 << 10, &|| Ok(()));
        let first = crate::AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 1);
        let second = crate::AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 2);
        let mut rows = SourceAcquisitions::original(&a).unwrap();
        for ordinal in (0..4096).filter(|&ordinal| ordinal != 7) {
            let source = if ordinal == 4095 { &second } else { &first };
            rows.append_original(ordinal, source.lease().clone(), &a).unwrap();
        }
        assert_eq!(rows.len(), 4095);
        assert!(!rows.contains_key(&7));
        assert!(!rows.contains_key(&4096));
        assert!(rows.get(&8).unwrap().same_binding(first.lease()));
        assert!(rows.get(&4095).unwrap().same_binding(second.lease()));
        assert!(!rows.get(&4095).unwrap().same_binding(first.lease()));
        assert_eq!(rows.values().count(), rows.len());
        let reserved = used.load(Ordering::Acquire);
        let alias = rows.clone();
        assert_eq!(used.load(Ordering::Acquire), reserved);
        assert!(rows.append_original(4096, first.lease().clone(), &a).is_err());
        drop(rows);
        assert_eq!(used.load(Ordering::Acquire), reserved);
        drop(alias);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn failed_original_growth_keeps_the_prior_actual_occurrence() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 256, &|| Ok(()));
        let source = crate::AcquiredSource::from_original_bytes(b"/datum/a\n".to_vec(), 1);
        let mut rows = SourceAcquisitions::original(&a).unwrap();
        rows.append_original(0, source.lease().clone(), &a).unwrap();
        let before = used.load(Ordering::Acquire);
        let denied = rows.append_original(1024, source.lease().clone(), &a).unwrap_err();
        assert_eq!(denied.kind(), io::ErrorKind::OutOfMemory);
        assert!(rows.get(&0).unwrap().same_binding(source.lease()));
        assert!(rows.get(&1024).is_none());
        assert_eq!(used.load(Ordering::Acquire), before);
        drop(rows);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}
