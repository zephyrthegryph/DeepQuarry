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

/// Cells written this tick (or earlier) that no pinned view includes yet.
#[derive(Clone, Debug)]
pub struct Overlay<V> {
    entries: CellMap<Entry<V>>,
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
            entries: CellMap::default(),
        }
    }

    /// The overlay value for `cell`, if DM wrote it and no pinned view
    /// includes that write yet.
    #[must_use]
    pub fn get(&self, cell: u32) -> Option<&V> {
        self.entries.get(&cell).map(|e| &e.value)
    }

    /// The value to update for a write with sequence number `seq`. On the
    /// first write to `cell` it is initialised from `base` (the pinned
    /// view's value).
    pub fn write(&mut self, cell: u32, seq: Seq, base: impl FnOnce() -> V) -> &mut V {
        let entry = self
            .entries
            .entry(cell)
            .or_insert_with(|| Entry { value: base(), seq });
        entry.seq = seq;
        &mut entry.value
    }

    /// Drops every entry whose last write is included in a view with this
    /// `applied_through`. Returns how many were dropped.
    pub fn prune(&mut self, applied_through: Seq) -> usize {
        let before = self.entries.len();
        self.entries.retain(|_, e| e.seq > applied_through);
        before - self.entries.len()
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
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
}
