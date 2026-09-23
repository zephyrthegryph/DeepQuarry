//! Chunked copy-on-write storage (`rust_core.md` §3.3).
//!
//! A [`CowStore`] holds one value per cell in fixed-size chunks, each behind
//! an `Arc`. [`CowStore::snapshot`] clones only the chunk pointers, so a
//! published view shares every chunk with the live store. The first write to
//! a shared chunk copies it (`Arc::make_mut`), so the memory a new view costs
//! scales with the amount of change. A chunk is freed when neither the store
//! nor any view holds it.
//!
//! Chunks whose cells all hold `T::default()` are never allocated.

use std::sync::Arc;

use crate::grid::{CHUNK_CELLS, CHUNK_EDGE, GridDims};

/// Slots per chunk for [`ChunkLayout::linear`] (arena-shaped stores).
pub const LINEAR_CHUNK: u32 = 4096;

/// How cell indices map onto chunks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChunkLayout {
    /// Indices `0..len` in runs of `chunk_len` (arenas, network regions).
    Linear { len: u32, chunk_len: u32 },
    /// Grid cells (as [`GridDims::index`]) in spatial 16x16 chunks per z-level.
    Spatial {
        dims: GridDims,
        chunks_x: u32,
        chunks_per_z: u32,
    },
}

impl ChunkLayout {
    /// `len` slots in [`LINEAR_CHUNK`]-slot chunks.
    #[must_use]
    pub const fn linear(len: u32) -> Self {
        Self::linear_with_chunk(len, LINEAR_CHUNK)
    }

    /// `len` slots in `chunk_len`-slot chunks (`chunk_len` is clamped to >= 1).
    #[must_use]
    pub const fn linear_with_chunk(len: u32, chunk_len: u32) -> Self {
        Self::Linear {
            len,
            chunk_len: if chunk_len == 0 { 1 } else { chunk_len },
        }
    }

    /// One cell per grid cell, in 16x16 chunks.
    #[must_use]
    pub const fn spatial(dims: GridDims) -> Self {
        let chunks_x = dims.max_x().div_ceil(CHUNK_EDGE);
        let chunks_y = dims.max_y().div_ceil(CHUNK_EDGE);
        Self::Spatial {
            dims,
            chunks_x,
            chunks_per_z: chunks_x * chunks_y,
        }
    }

    /// Addressable cells.
    #[must_use]
    pub const fn len(self) -> u32 {
        match self {
            Self::Linear { len, .. } => len,
            Self::Spatial { dims, .. } => dims.layer_len() * dims.max_z(),
        }
    }

    #[must_use]
    pub const fn is_empty(self) -> bool {
        self.len() == 0
    }

    /// Cells per chunk.
    #[must_use]
    pub const fn chunk_len(self) -> usize {
        match self {
            Self::Linear { chunk_len, .. } => chunk_len as usize,
            Self::Spatial { .. } => CHUNK_CELLS,
        }
    }

    /// Number of chunks.
    #[must_use]
    pub const fn chunk_count(self) -> usize {
        match self {
            Self::Linear { len, chunk_len } => len.div_ceil(chunk_len) as usize,
            Self::Spatial {
                dims, chunks_per_z, ..
            } => (chunks_per_z * dims.max_z()) as usize,
        }
    }

    /// `(chunk, cell in chunk)`, or `None` outside the layout.
    #[must_use]
    pub const fn locate(self, index: u32) -> Option<(usize, usize)> {
        match self {
            Self::Linear { len, chunk_len } => {
                if index >= len {
                    return None;
                }
                Some(((index / chunk_len) as usize, (index % chunk_len) as usize))
            }
            Self::Spatial {
                dims,
                chunks_x,
                chunks_per_z,
            } => {
                let Some((x, y, z)) = dims.coords(index) else {
                    return None;
                };
                let chunk = z * chunks_per_z + (y / CHUNK_EDGE) * chunks_x + x / CHUNK_EDGE;
                let cell = (y % CHUNK_EDGE) * CHUNK_EDGE + x % CHUNK_EDGE;
                Some((chunk as usize, cell as usize))
            }
        }
    }

    /// The cell index at `(chunk, cell)`; `None` for padding cells past the
    /// grid edge or past `len`.
    #[must_use]
    #[allow(clippy::cast_possible_truncation)]
    pub const fn index_of(self, chunk: usize, cell: usize) -> Option<u32> {
        match self {
            Self::Linear { len, chunk_len } => {
                if cell >= chunk_len as usize {
                    return None;
                }
                let index = chunk as u64 * chunk_len as u64 + cell as u64;
                if index >= len as u64 {
                    None
                } else {
                    Some(index as u32)
                }
            }
            Self::Spatial {
                dims,
                chunks_x,
                chunks_per_z,
            } => {
                if cell >= CHUNK_CELLS {
                    return None;
                }
                let chunk = chunk as u32;
                let cell = cell as u32;
                let z = chunk / chunks_per_z;
                let rem = chunk % chunks_per_z;
                let x = (rem % chunks_x) * CHUNK_EDGE + cell % CHUNK_EDGE;
                let y = (rem / chunks_x) * CHUNK_EDGE + cell / CHUNK_EDGE;
                dims.index(x, y, z)
            }
        }
    }
}

/// A chunked copy-on-write per-cell store. Cloning (or [`snapshot`]) is
/// O(chunks) pointer copies.
///
/// [`snapshot`]: CowStore::snapshot
#[derive(Clone, Debug)]
pub struct CowStore<T> {
    layout: ChunkLayout,
    chunks: Vec<Option<Arc<Vec<T>>>>,
}

impl<T: Clone + Default> CowStore<T> {
    #[must_use]
    pub fn new(layout: ChunkLayout) -> Self {
        Self {
            layout,
            chunks: vec![None; layout.chunk_count()],
        }
    }

    #[must_use]
    pub const fn layout(&self) -> ChunkLayout {
        self.layout
    }

    /// The value at `index` (`T::default()` in an unallocated chunk), or
    /// `None` outside the layout.
    #[must_use]
    pub fn get(&self, index: u32) -> Option<T> {
        let (chunk, cell) = self.layout.locate(index)?;
        Some(
            self.chunks[chunk]
                .as_ref()
                .map_or_else(T::default, |c| c[cell].clone()),
        )
    }

    /// Calls `f` with a reference to the value at `index` without cloning it
    /// (a default value is built for unallocated chunks).
    pub fn with<R>(&self, index: u32, f: impl FnOnce(&T) -> R) -> Option<R> {
        let (chunk, cell) = self.layout.locate(index)?;
        Some(match &self.chunks[chunk] {
            Some(c) => f(&c[cell]),
            None => f(&T::default()),
        })
    }

    /// A mutable reference to the value at `index`, allocating its chunk, or
    /// copying it if a snapshot still shares it.
    pub fn get_mut(&mut self, index: u32) -> Option<&mut T> {
        let (chunk, cell) = self.layout.locate(index)?;
        let len = self.layout.chunk_len();
        let slot = self.chunks[chunk].get_or_insert_with(|| Arc::new(vec![T::default(); len]));
        Some(&mut Arc::make_mut(slot)[cell])
    }

    /// Writes `value`; `false` outside the layout.
    pub fn set(&mut self, index: u32, value: T) -> bool {
        match self.get_mut(index) {
            Some(slot) => {
                *slot = value;
                true
            }
            None => false,
        }
    }

    /// A snapshot sharing every chunk with `self`.
    #[must_use]
    pub fn snapshot(&self) -> Self {
        self.clone()
    }

    /// The cells of chunk `chunk`, if allocated.
    #[must_use]
    pub fn chunk(&self, chunk: usize) -> Option<&[T]> {
        self.chunks.get(chunk)?.as_deref().map(Vec::as_slice)
    }

    /// Chunks currently allocated.
    #[must_use]
    pub fn allocated_chunks(&self) -> usize {
        self.chunks.iter().filter(|c| c.is_some()).count()
    }

    /// Allocated chunks this store shares (same allocation) with `other`.
    #[must_use]
    pub fn shared_chunks_with(&self, other: &Self) -> usize {
        self.chunks
            .iter()
            .zip(&other.chunks)
            .filter(|(a, b)| matches!((a, b), (Some(a), Some(b)) if Arc::ptr_eq(a, b)))
            .count()
    }

    /// Chunks that are not the same allocation in `self` and `base` (both
    /// must have the same layout). This is how a changed region is found
    /// without comparing values: an untouched chunk is still shared.
    pub fn chunks_differing_from<'a>(&'a self, base: &'a Self) -> impl Iterator<Item = usize> + 'a {
        debug_assert_eq!(self.layout, base.layout);
        self.chunks
            .iter()
            .zip(&base.chunks)
            .enumerate()
            .filter(|(_, (a, b))| match (a, b) {
                (Some(a), Some(b)) => !Arc::ptr_eq(a, b),
                (None, None) => false,
                _ => true,
            })
            .map(|(i, _)| i)
    }

    /// Calls `f(chunk, cells)` for every allocated chunk, in chunk order.
    pub fn for_each_chunk_mut(&mut self, mut f: impl FnMut(usize, &mut [T])) {
        for (i, chunk) in self.chunks.iter_mut().enumerate() {
            if let Some(chunk) = chunk {
                f(i, Arc::make_mut(chunk).as_mut_slice());
            }
        }
    }

    /// Allocates every chunk (e.g. before a field step that touches all
    /// cells, so the chunk iterators reach them).
    pub fn allocate_all(&mut self) {
        let len = self.layout.chunk_len();
        for chunk in &mut self.chunks {
            chunk.get_or_insert_with(|| Arc::new(vec![T::default(); len]));
        }
    }

    /// Frees chunks whose cells are all default.
    pub fn compact(&mut self)
    where
        T: PartialEq,
    {
        let default = T::default();
        for chunk in &mut self.chunks {
            if chunk
                .as_ref()
                .is_some_and(|c| c.iter().all(|v| *v == default))
            {
                *chunk = None;
            }
        }
    }

    /// Bytes held by allocated chunks (a shared chunk is counted by every
    /// store that holds it).
    #[must_use]
    pub fn reserved_bytes(&self) -> usize {
        self.allocated_chunks() * self.layout.chunk_len() * size_of::<T>()
            + self.chunks.capacity() * size_of::<Option<Arc<Vec<T>>>>()
    }

    /// Value equality over every cell (an unallocated chunk equals an
    /// allocated all-default one).
    #[must_use]
    pub fn values_eq(&self, other: &Self) -> bool
    where
        T: PartialEq,
    {
        if self.layout != other.layout {
            return false;
        }
        let default = T::default();
        self.chunks
            .iter()
            .zip(&other.chunks)
            .all(|(a, b)| match (a, b) {
                (Some(a), Some(b)) => Arc::ptr_eq(a, b) || a == b,
                (Some(c), None) | (None, Some(c)) => c.iter().all(|v| *v == default),
                (None, None) => true,
            })
    }
}

impl<T: Clone + Default + Send + Sync> CowStore<T> {
    /// Calls `f(chunk, cells)` for every allocated chunk in parallel on the
    /// current rayon pool. `f` must be per-chunk deterministic (§3.9);
    /// combine cross-chunk sums in chunk order afterwards.
    pub fn par_for_each_chunk_mut(&mut self, f: impl Fn(usize, &mut [T]) + Sync + Send) {
        use rayon::prelude::*;
        self.chunks
            .par_iter_mut()
            .enumerate()
            .for_each(|(i, chunk)| {
                if let Some(chunk) = chunk {
                    f(i, Arc::make_mut(chunk).as_mut_slice());
                }
            });
    }

    /// Calls `f(chunk, cells)` in parallel for each chunk in `chunks`,
    /// allocating it first (and copying it if a snapshot shares it). Chunks
    /// not listed are not touched, so they stay shared with every snapshot:
    /// this is how a field step over its active chunks leaves sleeping
    /// regions alone. Out-of-range entries are ignored.
    pub fn par_for_listed_chunks_mut(
        &mut self,
        chunks: &[usize],
        f: impl Fn(usize, &mut [T]) + Sync + Send,
    ) {
        use rayon::prelude::*;
        let len = self.layout.chunk_len();
        let mut listed = vec![false; self.chunks.len()];
        for &c in chunks {
            if let Some(slot) = self.chunks.get_mut(c) {
                slot.get_or_insert_with(|| Arc::new(vec![T::default(); len]));
                listed[c] = true;
            }
        }
        self.chunks
            .par_iter_mut()
            .enumerate()
            .filter(|(i, _)| listed[*i])
            .for_each(|(i, chunk)| {
                if let Some(chunk) = chunk {
                    f(i, Arc::make_mut(chunk).as_mut_slice());
                }
            });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn snapshot_shares_until_written() {
        let mut store = CowStore::<u32>::new(ChunkLayout::linear_with_chunk(100, 10));
        for i in 0..100 {
            store.set(i, i);
        }
        let view = store.snapshot();
        assert_eq!(store.shared_chunks_with(&view), 10);
        store.set(15, 999);
        assert_eq!(store.shared_chunks_with(&view), 9);
        assert_eq!(view.get(15), Some(15));
        assert_eq!(store.get(15), Some(999));
        assert_eq!(
            store.chunks_differing_from(&view).collect::<Vec<_>>(),
            vec![1]
        );
        assert_eq!(store.get(100), None);
        drop(view);
        // With the view gone the chunk is unique again: no copy on write.
        let before = store.chunk(1).unwrap().as_ptr();
        store.set(16, 1);
        assert_eq!(store.chunk(1).unwrap().as_ptr(), before);
    }

    #[test]
    fn unallocated_reads_default_and_compacts() {
        let mut store = CowStore::<u8>::new(ChunkLayout::linear(10_000));
        assert_eq!(store.get(9_999), Some(0));
        store.set(5_000, 3);
        assert_eq!(store.allocated_chunks(), 1);
        store.set(5_000, 0);
        store.compact();
        assert_eq!(store.allocated_chunks(), 0);
        assert!(store.values_eq(&CowStore::new(ChunkLayout::linear(10_000))));
    }

    proptest! {
        #[test]
        fn spatial_layout_round_trips(x in 0u32..40, y in 0u32..40, z in 0u32..3) {
            let dims = GridDims::new(37, 21, 3).unwrap();
            let layout = ChunkLayout::spatial(dims);
            if let Some(index) = dims.index(x, y, z) {
                let (chunk, cell) = layout.locate(index).unwrap();
                prop_assert!(chunk < layout.chunk_count());
                prop_assert_eq!(layout.index_of(chunk, cell), Some(index));
            }
        }

        #[test]
        fn linear_layout_round_trips(len in 1u32..10_000, chunk_len in 1u32..600, i in 0u32..10_000) {
            let layout = ChunkLayout::linear_with_chunk(len, chunk_len);
            match layout.locate(i) {
                Some((c, cell)) => prop_assert_eq!(layout.index_of(c, cell), Some(i)),
                None => prop_assert!(i >= len),
            }
        }
    }
}
