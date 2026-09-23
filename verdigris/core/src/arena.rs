//! `Arena<T>`: generational slots with a free list (`rust_core.md` §5).
//!
//! - Slots live in fixed 4096-slot chunks; the arena never grows
//!   geometrically, so capacity is exactly `chunks * 4096`.
//! - A handle whose generation no longer matches its slot is rejected.
//! - Generations are 4 bits. Under [`GenerationPolicy::Wrap`] a slot freed
//!   16 times reuses generation 0, so a handle held across 16 recycles of the
//!   same slot would alias. [`GenerationPolicy::Retire`] instead takes a slot
//!   out of service once its generation is exhausted, which makes rejection
//!   unconditional at the cost of losing that slot.

use crate::slot::{Handle, MAX_GENERATION, MAX_SLOTS, RawHandle};
use std::fmt;

/// Slots per growth chunk.
pub const CHUNK_SLOTS: usize = 4096;

/// What to do when a slot's 4-bit generation is exhausted.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum GenerationPolicy {
    /// Wrap back to generation 0 and keep reusing the slot.
    #[default]
    Wrap,
    /// Stop reusing the slot, so no handle can ever alias.
    Retire,
}

/// Why a handle lookup failed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArenaError {
    /// The slot was freed (and maybe reused) since the handle was issued.
    Stale,
    /// The index was never allocated.
    OutOfRange,
    /// All 2^20 slots are in use or retired.
    Full,
}

impl fmt::Display for ArenaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            ArenaError::Stale => "stale handle",
            ArenaError::OutOfRange => "handle index out of range",
            ArenaError::Full => "arena is full",
        })
    }
}

impl std::error::Error for ArenaError {}

struct Slot<T> {
    generation: u8,
    value: Option<T>,
}

pub struct Arena<T> {
    chunks: Vec<Vec<Slot<T>>>,
    free: Vec<u32>,
    len: usize,
    retired: usize,
    policy: GenerationPolicy,
}

impl<T> Default for Arena<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> Arena<T> {
    #[must_use]
    pub const fn new() -> Self {
        Self::with_policy(GenerationPolicy::Wrap)
    }

    #[must_use]
    pub const fn with_policy(policy: GenerationPolicy) -> Self {
        Self {
            chunks: Vec::new(),
            free: Vec::new(),
            len: 0,
            retired: 0,
            policy,
        }
    }

    /// Live values.
    #[must_use]
    pub const fn len(&self) -> usize {
        self.len
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Slots taken out of service by [`GenerationPolicy::Retire`].
    #[must_use]
    pub const fn retired(&self) -> usize {
        self.retired
    }

    /// Slots ever allocated (live, free or retired).
    #[must_use]
    pub fn slots(&self) -> usize {
        self.chunks
            .last()
            .map_or(0, |last| (self.chunks.len() - 1) * CHUNK_SLOTS + last.len())
    }

    /// Bytes reserved for slot storage, for the allocator-tag report.
    #[must_use]
    pub fn reserved_bytes(&self) -> usize {
        self.chunks.len() * CHUNK_SLOTS * size_of::<Slot<T>>()
            + self.free.capacity() * size_of::<u32>()
    }

    fn slot(&self, index: u32) -> Option<&Slot<T>> {
        let index = index as usize;
        self.chunks
            .get(index / CHUNK_SLOTS)?
            .get(index % CHUNK_SLOTS)
    }

    fn slot_mut(&mut self, index: u32) -> Option<&mut Slot<T>> {
        let index = index as usize;
        self.chunks
            .get_mut(index / CHUNK_SLOTS)?
            .get_mut(index % CHUNK_SLOTS)
    }

    /// Stores `value` and returns its handle.
    ///
    /// # Errors
    /// [`ArenaError::Full`] once every one of the 2^20 slots is live or retired.
    pub fn insert(&mut self, value: T) -> Result<Handle<T>, ArenaError> {
        let index = if let Some(index) = self.free.pop() {
            index
        } else {
            let next = self.slots();
            if next >= MAX_SLOTS as usize {
                return Err(ArenaError::Full);
            }
            if self.chunks.last().is_none_or(|c| c.len() == CHUNK_SLOTS) {
                self.chunks.push(Vec::with_capacity(CHUNK_SLOTS));
            }
            let chunk = self.chunks.last_mut().expect("chunk just ensured");
            chunk.push(Slot {
                generation: 0,
                value: None,
            });
            u32::try_from(next).expect("below MAX_SLOTS")
        };
        let slot = self.slot_mut(index).expect("free index is allocated");
        debug_assert!(slot.value.is_none());
        slot.value = Some(value);
        let generation = slot.generation;
        self.len += 1;
        Ok(Handle::from_raw(
            RawHandle::new(index, generation).expect("index and generation in range"),
        ))
    }

    fn check(&self, handle: RawHandle) -> Result<&Slot<T>, ArenaError> {
        let slot = self.slot(handle.index()).ok_or(ArenaError::OutOfRange)?;
        if slot.generation != handle.generation() || slot.value.is_none() {
            return Err(ArenaError::Stale);
        }
        Ok(slot)
    }

    /// # Errors
    /// [`ArenaError::Stale`] or [`ArenaError::OutOfRange`].
    pub fn get(&self, handle: Handle<T>) -> Result<&T, ArenaError> {
        Ok(self
            .check(handle.raw())?
            .value
            .as_ref()
            .expect("checked live"))
    }

    /// # Errors
    /// [`ArenaError::Stale`] or [`ArenaError::OutOfRange`].
    pub fn get_mut(&mut self, handle: Handle<T>) -> Result<&mut T, ArenaError> {
        self.check(handle.raw())?;
        Ok(self
            .slot_mut(handle.index())
            .and_then(|slot| slot.value.as_mut())
            .expect("checked live"))
    }

    #[must_use]
    pub fn contains(&self, handle: Handle<T>) -> bool {
        self.check(handle.raw()).is_ok()
    }

    /// Frees the slot and returns its value. The handle, and every copy of
    /// it, is stale afterwards.
    ///
    /// # Errors
    /// [`ArenaError::Stale`] or [`ArenaError::OutOfRange`].
    pub fn remove(&mut self, handle: Handle<T>) -> Result<T, ArenaError> {
        self.check(handle.raw())?;
        let policy = self.policy;
        self.len -= 1;
        let slot = self.slot_mut(handle.index()).expect("checked");
        let value = slot.value.take().expect("checked live");
        let exhausted = slot.generation == MAX_GENERATION;
        if exhausted && policy == GenerationPolicy::Retire {
            // The slot stays empty forever, so no handle can resolve to it again.
            self.retired += 1;
        } else {
            slot.generation = if exhausted { 0 } else { slot.generation + 1 };
            self.free.push(handle.index());
        }
        Ok(value)
    }

    /// Live values with their handles, in index order.
    pub fn iter(&self) -> impl Iterator<Item = (Handle<T>, &T)> {
        self.chunks.iter().enumerate().flat_map(|(c, chunk)| {
            chunk.iter().enumerate().filter_map(move |(i, slot)| {
                slot.value
                    .as_ref()
                    .map(|value| (handle_at(c, i, slot.generation), value))
            })
        })
    }

    /// Live values with their handles, in index order.
    pub fn iter_mut(&mut self) -> impl Iterator<Item = (Handle<T>, &mut T)> {
        self.chunks.iter_mut().enumerate().flat_map(|(c, chunk)| {
            chunk.iter_mut().enumerate().filter_map(move |(i, slot)| {
                let generation = slot.generation;
                slot.value
                    .as_mut()
                    .map(|value| (handle_at(c, i, generation), value))
            })
        })
    }
}

fn handle_at<T>(chunk: usize, offset: usize, generation: u8) -> Handle<T> {
    let index = u32::try_from(chunk * CHUNK_SLOTS + offset).expect("slot index fits u32");
    Handle::from_raw(RawHandle::new(index, generation).expect("slot index in range"))
}

#[cfg(feature = "rayon")]
mod par {
    use super::{Arena, Handle, handle_at};
    use rayon::prelude::*;

    impl<T: Sync> Arena<T> {
        /// Parallel iteration, split by 4096-slot chunk.
        pub fn par_iter(&self) -> impl ParallelIterator<Item = (Handle<T>, &T)> {
            self.chunks
                .par_iter()
                .enumerate()
                .flat_map_iter(|(c, chunk)| {
                    chunk.iter().enumerate().filter_map(move |(i, slot)| {
                        slot.value
                            .as_ref()
                            .map(|value| (handle_at(c, i, slot.generation), value))
                    })
                })
        }
    }

    impl<T: Send> Arena<T> {
        /// Parallel mutable iteration, split by 4096-slot chunk.
        pub fn par_iter_mut(&mut self) -> impl ParallelIterator<Item = (Handle<T>, &mut T)> {
            self.chunks
                .par_iter_mut()
                .enumerate()
                .flat_map_iter(|(c, chunk)| {
                    chunk.iter_mut().enumerate().filter_map(move |(i, slot)| {
                        let generation = slot.generation;
                        slot.value
                            .as_mut()
                            .map(|value| (handle_at(c, i, generation), value))
                    })
                })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use std::collections::HashMap;

    #[test]
    fn stale_handle_is_rejected_after_reuse() {
        let mut arena = Arena::new();
        let a = arena.insert("a").unwrap();
        assert_eq!(arena.remove(a), Ok("a"));
        let b = arena.insert("b").unwrap();
        assert_eq!(a.index(), b.index());
        assert_eq!(arena.get(a), Err(ArenaError::Stale));
        assert_eq!(arena.remove(a), Err(ArenaError::Stale));
        assert_eq!(arena.get(b), Ok(&"b"));
    }

    #[test]
    fn grows_in_fixed_chunks() {
        let mut arena = Arena::new();
        for i in 0..=CHUNK_SLOTS {
            arena.insert(i).unwrap();
        }
        assert_eq!(arena.chunks.len(), 2);
        assert!(arena.chunks.iter().all(|c| c.capacity() == CHUNK_SLOTS));
    }

    #[test]
    fn retire_policy_never_aliases() {
        let mut arena = Arena::with_policy(GenerationPolicy::Retire);
        let first = arena.insert(0).unwrap();
        arena.remove(first).unwrap();
        let mut last = first;
        for i in 1..=u32::from(MAX_GENERATION) {
            last = arena.insert(i).unwrap();
            assert_eq!(last.index(), first.index());
            arena.remove(last).unwrap();
        }
        assert_eq!(arena.retired(), 1);
        let fresh = arena.insert(99).unwrap();
        assert_ne!(fresh.index(), first.index());
        assert_eq!(arena.get(first), Err(ArenaError::Stale));
        assert_eq!(arena.get(last), Err(ArenaError::Stale));
    }

    #[test]
    fn unknown_index_is_out_of_range() {
        let arena: Arena<u8> = Arena::new();
        let h = Handle::from_raw(RawHandle::new(7, 0).unwrap());
        assert_eq!(arena.get(h), Err(ArenaError::OutOfRange));
    }

    #[cfg(feature = "rayon")]
    #[test]
    fn par_iter_matches_iter() {
        use rayon::prelude::*;
        let mut arena = Arena::new();
        let handles: Vec<_> = (0..10_000u64).map(|i| arena.insert(i).unwrap()).collect();
        for h in handles.iter().step_by(3) {
            arena.remove(*h).unwrap();
        }
        arena.par_iter_mut().for_each(|(_, v)| *v *= 2);
        let serial: u64 = arena.iter().map(|(_, v)| *v).sum();
        let parallel: u64 = arena.par_iter().map(|(_, v)| *v).sum();
        assert_eq!(serial, parallel);
    }

    #[derive(Debug, Clone)]
    enum Op {
        Insert(u32),
        Remove(usize),
    }

    fn ops() -> impl Strategy<Value = Vec<Op>> {
        prop::collection::vec(
            prop_oneof![
                any::<u32>().prop_map(Op::Insert),
                any::<usize>().prop_map(Op::Remove),
            ],
            0..400,
        )
    }

    proptest! {
        /// Against a model: live handles resolve to their value; a dead
        /// handle is rejected if its slot was freed fewer than 15 more times
        /// since (always, under Retire).
        #[test]
        fn arena_matches_model(ops in ops(), retire in any::<bool>()) {
            let policy = if retire { GenerationPolicy::Retire } else { GenerationPolicy::Wrap };
            let mut arena = Arena::with_policy(policy);
            let mut live: Vec<(Handle<u32>, u32)> = Vec::new();
            let mut dead: Vec<(Handle<u32>, u32)> = Vec::new();
            let mut frees_per_slot: HashMap<u32, u32> = HashMap::new();
            for op in ops {
                match op {
                    Op::Insert(v) => {
                        let h = arena.insert(v).unwrap();
                        prop_assert!(!live.iter().any(|(l, _)| l.index() == h.index()));
                        live.push((h, v));
                    }
                    Op::Remove(i) if !live.is_empty() => {
                        let (h, v) = live.swap_remove(i % live.len());
                        prop_assert_eq!(arena.remove(h), Ok(v));
                        let frees = frees_per_slot.entry(h.index()).or_default();
                        *frees += 1;
                        dead.push((h, *frees));
                    }
                    Op::Remove(_) => {}
                }
                prop_assert_eq!(arena.len(), live.len());
            }
            for (h, v) in &live {
                prop_assert_eq!(arena.get(*h), Ok(v));
            }
            for (h, freed_at) in dead {
                let later = frees_per_slot[&h.index()] - freed_at;
                // The 16th free of a slot (its own plus 15 later) brings the
                // generation back round, so only fewer than 15 later frees are safe.
                if retire || later < 15 {
                    prop_assert_eq!(arena.get(h), Err(ArenaError::Stale));
                }
            }
            let mut seen: Vec<_> = arena.iter().map(|(h, v)| (h.raw(), *v)).collect();
            let mut expected: Vec<_> = live.iter().map(|(h, v)| (h.raw(), *v)).collect();
            seen.sort_unstable();
            expected.sort_unstable();
            prop_assert_eq!(seen, expected);
        }
    }
}
