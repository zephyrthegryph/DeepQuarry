//! Container-only migration. NOT a source endpoint or value-lifetime bound.
use super::*;
use std::{hash::Hash, io};
/// Caller holds the ORIGINAL map mutex; use fallible reserve before insert.
/// No duplicate map, payload scan or infallible map clone is involved.
pub(super) fn insert_source_map<K: Hash + Eq, V>(
    map: &mut AnswerMap<K, V>,
    key: K,
    value: V,
) -> io::Result<Option<V>> {
    let handle = map.allocator().clone();
    let mode = handle.source_mode().map_err(|_| {
        io::Error::other("source Answers map operation overlaps another source mode")
    })?;
    map.try_reserve(usize::from(!map.contains_key(&key)))
        .map_err(|_| io::Error::other("source Answers map allocation refused"))?;
    let old = map.insert(key, value);
    debug_assert!(!mode.denied(), "insertion must not allocate after reserve");
    Ok(old)
}
impl AnswerRequest {
    /// Reserve only, before final publication fence. Caller holds current.write
    /// through final bind. Cancellation leaves exact history/binding unchanged.
    pub(super) fn reserve_source_stamp(&mut self, pair: (u128, u128)) -> io::Result<u32> {
        self.stamps
            .len()
            .checked_mul(std::mem::size_of::<(u128, u128)>())
            .filter(|bytes| *bytes <= SOURCE_ANSWERS_BUDGET)
            .ok_or_else(|| {
                io::Error::other("source Answers original history exceeds bounded search")
            })?;
        if let Some(index) = self.stamps.iter().rposition(|entry| *entry == pair) {
            return u32::try_from(index)
                .map_err(|_| io::Error::other("source stamp index overflow"));
        }
        let index = u32::try_from(self.stamps.len())
            .map_err(|_| io::Error::other("source stamp index overflow"))?;
        let handle = self.stamps.allocator().clone();
        let _mode = handle
            .source_mode()
            .map_err(|_| io::Error::other("source stamp allocation overlaps another mode"))?;
        self.stamps
            .try_reserve(1)
            .map_err(|_| io::Error::other("source stamp allocation refused"))?;
        Ok(index)
    }
}
