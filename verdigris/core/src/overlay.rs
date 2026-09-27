//! The main-thread overlay (`rust_core.md` §3.4).
//!
//! DM expects to read its own writes immediately, but a write to a
//! worker-owned cell is only a queued command until the owner applies it.
//! The overlay holds, for each cell DM wrote that the pinned view does not
//! yet include, the value DM should see: the pinned value at the first
//! write, with every later command applied by the same function the worker
//! uses. An entry remembers the sequence number of its last command and is
//! dropped once a pinned view's `applied_through` reaches it.
//!
//! It is a plain hash map owned by the main thread; nothing else touches it.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

use crate::command::Seq;

/// A multiply-rotate hasher for `u32` cell keys (the `FxHash` scheme). Not
/// DoS-resistant; keys are cell indices, never user strings.
#[derive(Clone, Copy, Default)]
pub struct CellHasher(u64);

impl Hasher for CellHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.write_u64(u64::from(b));
        }
    }

    fn write_u32(&mut self, i: u32) {
        self.write_u64(u64::from(i));
    }

    fn write_u64(&mut self, i: u64) {
        self.0 = (self.0.rotate_left(5) ^ i).wrapping_mul(0x517c_c1b7_2722_0a95);
    }
}

/// A `HashMap` keyed by cell index.
pub type CellMap<V> = HashMap<u32, V, BuildHasherDefault<CellHasher>>;

#[derive(Clone, Debug)]
struct Entry<V> {
    value: V,
    seq: Seq,
}

/// Values per overlay slab chunk. The map holds only a cell -> slot index
/// (small entries); values live in fixed-size chunks, so neither ever needs
/// one large contiguous block (DreamDaemon is 32-bit, see `BATCH_CHUNK`).
const SLAB_CHUNK: usize = 1024;

/// Cells written this tick (or earlier) that no pinned view includes yet.
#[derive(Clone, Debug)]
pub struct Overlay<V> {
    index: CellMap<u32>,
    slab: Vec<Vec<Option<Entry<V>>>>,
    free: Vec<u32>,
}

impl<V> Default for Overlay<V> {
    fn default() -> Self {
        Self::new()
    }
}

impl<V> Overlay<V> {
    #[must_use]
    pub fn new() -> Self {
        Self {
            index: CellMap::default(),
            slab: Vec::new(),
            free: Vec::new(),
        }
    }

    fn slot(&self, slot: u32) -> Option<&Entry<V>> {
        let slot = slot as usize;
        self.slab.get(slot / SLAB_CHUNK)?.get(slot % SLAB_CHUNK)?.as_ref()
    }

    fn slot_mut(&mut self, slot: u32) -> &mut Option<Entry<V>> {
        let slot = slot as usize;
        &mut self.slab[slot / SLAB_CHUNK][slot % SLAB_CHUNK]
    }

    fn alloc(&mut self, entry: Entry<V>) -> u32 {
        if let Some(slot) = self.free.pop() {
            *self.slot_mut(slot) = Some(entry);
            return slot;
        }
        if self.slab.last().is_none_or(|c| c.len() == SLAB_CHUNK) {
            self.slab.push(Vec::with_capacity(SLAB_CHUNK));
        }
        let chunks = self.slab.len();
        let last = self.slab.last_mut().expect("just ensured");
        last.push(Some(entry));
        u32::try_from((chunks - 1) * SLAB_CHUNK + last.len() - 1).expect("overlay slots fit u32")
    }

    /// The overlay value for `cell`, if DM wrote it and no pinned view
    /// includes that write yet.
    #[must_use]
    pub fn get(&self, cell: u32) -> Option<&V> {
        let &slot = self.index.get(&cell)?;
        self.slot(slot).map(|e| &e.value)
    }

    /// The value to update for a write with sequence number `seq`. On the
    /// first write to `cell` it is initialised from `base` (the pinned
    /// view's value).
    pub fn write(&mut self, cell: u32, seq: Seq, base: impl FnOnce() -> V) -> &mut V {
        let slot = match self.index.get(&cell) {
            Some(&slot) => slot,
            None => {
                let slot = self.alloc(Entry { value: base(), seq });
                self.index.insert(cell, slot);
                slot
            }
        };
        let entry = self.slot_mut(slot).as_mut().expect("indexed slot is live");
        entry.seq = seq;
        &mut entry.value
    }

    /// Drops every entry whose last write is included in a view with this
    /// `applied_through`. Returns how many were dropped.
    pub fn prune(&mut self, applied_through: Seq) -> usize {
        let before = self.index.len();
        let mut freed = Vec::new();
        {
            let slab = &self.slab;
            self.index.retain(|_, &mut slot| {
                let s = slot as usize;
                let keep = slab[s / SLAB_CHUNK][s % SLAB_CHUNK]
                    .as_ref()
                    .is_some_and(|e| e.seq > applied_through);
                if !keep {
                    freed.push(slot);
                }
                keep
            });
        }
        for slot in freed {
            *self.slot_mut(slot) = None;
            self.free.push(slot);
        }
        if self.index.is_empty() {
            // Give the slab back once the overlay drains (a bulk write).
            self.slab = Vec::new();
            self.free = Vec::new();
            self.index = CellMap::default();
        }
        before - self.index.len()
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.index.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.index.is_empty()
    }

    /// Heap bytes the overlay holds (index buckets, slab chunks, free list).
    #[must_use]
    pub fn capacity_bytes(&self) -> usize {
        self.index.capacity() * (size_of::<(u32, u32)>() + 1)
            + self.slab.iter().map(Vec::capacity).sum::<usize>() * size_of::<Option<Entry<V>>>()
            + self.free.capacity() * 4
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_write_copies_base_and_prune_respects_last_seq() {
        let mut overlay = Overlay::new();
        *overlay.write(7, Seq(1), || 10) += 1;
        *overlay.write(7, Seq(3), || unreachable!()) += 1;
        *overlay.write(8, Seq(2), || 0) = 5;
        assert_eq!(overlay.get(7), Some(&12));
        assert_eq!(overlay.prune(Seq(2)), 1);
        assert_eq!(overlay.get(8), None);
        assert_eq!(overlay.get(7), Some(&12));
        assert_eq!(overlay.prune(Seq(3)), 1);
        assert!(overlay.is_empty());
    }

    #[test]
    fn slots_are_reused_and_values_survive_across_chunks() {
        let mut overlay = Overlay::new();
        let n = u32::try_from(SLAB_CHUNK * 2 + 3).unwrap();
        for cell in 0..n {
            *overlay.write(cell, Seq(u64::from(cell) + 1), || 0) = cell;
        }
        assert_eq!(overlay.len(), n as usize);
        assert_eq!(overlay.get(n - 1), Some(&(n - 1)));
        // Drop the first half, write new cells into the freed slots.
        assert_eq!(overlay.prune(Seq(u64::from(n / 2))), (n / 2) as usize);
        let slab_chunks = overlay.slab.len();
        for cell in n..n + n / 2 {
            *overlay.write(cell, Seq(u64::from(cell) + 1), || 0) = cell;
        }
        assert_eq!(overlay.slab.len(), slab_chunks, "freed slots are reused");
        for cell in (n / 2)..(n + n / 2) {
            assert_eq!(overlay.get(cell), Some(&cell));
        }
        assert_eq!(overlay.get(0), None);
        overlay.prune(Seq(u64::MAX));
        assert!(overlay.is_empty());
        assert_eq!(overlay.capacity_bytes(), 0);
    }
}
