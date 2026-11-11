//! Chunked copy-on-write storage (`rust_core.md` §3.3).
//!
//! A [`CowStore`] holds one value per cell in fixed-size chunks, each behind
//! an `Arc`. [`CowStore::snapshot`] clones only the chunk pointers, so a
//! published view shares every chunk with the live store. The first write to
//! a shared chunk copies it (`Arc::make_mut`), so the memory a new view costs
//! scales with the amount of change. A chunk is freed when neither the store
//! nor any view holds it.
//!
//! A chunk is default (every cell `T::default()`, never allocated), uniform (every cell one other value:
//! one shared allocation) or dense. The first write to a default or uniform chunk densifies it;
//! [`CowStore::compact_chunks`] turns an exactly uniform dense chunk back.

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

/// One chunk of a [`CowStore`].
#[derive(Debug)]
enum Slot<T> {
    /// Every cell holds `T::default()`; nothing is allocated.
    Default,
    /// Every cell holds this one value; one allocation however many chunks share it (the usual
    /// state of vacuum, a settled room, a block of identical geometry). The first write densifies.
    Uniform(Arc<T>),
    /// One value per cell.
    Dense(Arc<Vec<T>>),
}

impl<T> Clone for Slot<T> {
    fn clone(&self) -> Self {
        match self {
            Self::Default => Self::Default,
            Self::Uniform(v) => Self::Uniform(Arc::clone(v)),
            Self::Dense(v) => Self::Dense(Arc::clone(v)),
        }
    }
}

impl<T> Slot<T> {
    /// Same allocation (two default chunks are the same).
    fn same(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Default, Self::Default) => true,
            (Self::Uniform(a), Self::Uniform(b)) => Arc::ptr_eq(a, b),
            (Self::Dense(a), Self::Dense(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }
}

/// A read-only view of an allocated chunk: one shared value, or one value per cell.
#[derive(Debug)]
pub struct ChunkView<'a, T> {
    cells: Cells<'a, T>,
    len: usize,
}

#[derive(Debug)]
enum Cells<'a, T> {
    Uniform(&'a T),
    Dense(&'a [T]),
}

impl<T> Clone for ChunkView<'_, T> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<T> Copy for ChunkView<'_, T> {}
impl<T> Clone for Cells<'_, T> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<T> Copy for Cells<'_, T> {}

impl<'a, T> ChunkView<'a, T> {
    /// Cells in the chunk.
    #[must_use]
    pub const fn len(&self) -> usize {
        self.len
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// The cell at `cell` (panics past the chunk, as a slice does).
    #[must_use]
    pub fn get(&self, cell: usize) -> &'a T {
        match self.cells {
            Cells::Uniform(v) => {
                assert!(
                    cell < self.len,
                    "cell {cell} outside a chunk of {}",
                    self.len
                );
                v
            }
            Cells::Dense(c) => &c[cell],
        }
    }

    /// The one value every cell holds, when the chunk is stored as uniform.
    #[must_use]
    pub const fn uniform(&self) -> Option<&'a T> {
        match self.cells {
            Cells::Uniform(v) => Some(v),
            Cells::Dense(_) => None,
        }
    }

    /// Every cell, in order.
    pub fn iter(&self) -> impl ExactSizeIterator<Item = &'a T> + Clone + 'a {
        let (cells, len) = (self.cells, self.len);
        (0..len).map(move |i| match cells {
            Cells::Uniform(v) => v,
            Cells::Dense(c) => &c[i],
        })
    }

    /// Whether both views are the same allocation (so their values are equal without looking).
    #[must_use]
    pub fn same_alloc(&self, other: &ChunkView<'_, T>) -> bool {
        match (self.cells, other.cells) {
            (Cells::Uniform(a), Cells::Uniform(b)) => std::ptr::eq(a, b),
            (Cells::Dense(a), Cells::Dense(b)) => std::ptr::eq(a.as_ptr(), b.as_ptr()),
            _ => false,
        }
    }
}

/// What a [`CowStore`] holds, by chunk kind ([`CowStore::memory`]): distinct allocations only, so a chunk several
/// slots share is counted once for the store.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CowMemory {
    /// Chunks in the layout.
    pub chunks: usize,
    /// Chunks that are all `T::default()` (no allocation).
    pub default_chunks: usize,
    /// Uniform chunks (one value).
    pub uniform_chunks: usize,
    /// Dense chunks (one value per cell).
    pub dense_chunks: usize,
    /// Dense chunks whose cells all hold one value (they could be uniform: `compact_chunks` has not run on them).
    pub dense_but_uniform: usize,
    /// Distinct allocations: uniform values and dense vectors.
    pub allocations: usize,
    /// Bytes of those allocations plus the slot table.
    pub bytes: usize,
}

impl CowMemory {
    /// Adds another store's figures.
    pub const fn add(&mut self, o: &Self) {
        self.chunks += o.chunks;
        self.default_chunks += o.default_chunks;
        self.uniform_chunks += o.uniform_chunks;
        self.dense_chunks += o.dense_chunks;
        self.dense_but_uniform += o.dense_but_uniform;
        self.allocations += o.allocations;
        self.bytes += o.bytes;
    }
}

/// A chunked copy-on-write per-cell store. Cloning (or [`snapshot`]) is
/// O(chunks) pointer copies.
///
/// [`snapshot`]: CowStore::snapshot
#[derive(Clone, Debug)]
pub struct CowStore<T> {
    layout: ChunkLayout,
    chunks: Vec<Slot<T>>,
    /// `T::default()`, what a default chunk reads as.
    default: Arc<T>,
    /// Which store this is (a snapshot keeps its source's), and how many mutating calls it has had: two stores
    /// with the same pair are a snapshot and its unchanged source ([`unchanged_since`](Self::unchanged_since)).
    lineage: u64,
    writes: u64,
}

static NEXT_LINEAGE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

impl<T: Clone + Default> CowStore<T> {
    #[must_use]
    pub fn new(layout: ChunkLayout) -> Self {
        Self {
            layout,
            chunks: vec![Slot::Default; layout.chunk_count()],
            default: Arc::new(T::default()),
            lineage: NEXT_LINEAGE.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
            writes: 0,
        }
    }

    /// TRUE when nothing was written to `self` since `base` was snapshotted from it, in O(1) (no chunk sweep).
    /// `base` must be a snapshot nobody writes to (a watch state's previous view); a FALSE answer only means the
    /// chunks have to be compared ([`chunks_differing_from`](Self::chunks_differing_from)).
    #[must_use]
    pub const fn unchanged_since(&self, base: &Self) -> bool {
        self.lineage == base.lineage && self.writes == base.writes
    }

    #[must_use]
    pub const fn layout(&self) -> ChunkLayout {
        self.layout
    }

    fn cell_ref(&self, chunk: usize, cell: usize) -> &T {
        match &self.chunks[chunk] {
            Slot::Default => &self.default,
            Slot::Uniform(v) => v,
            Slot::Dense(c) => &c[cell],
        }
    }

    /// The value at `index` (`T::default()` in a default chunk), or
    /// `None` outside the layout.
    #[must_use]
    pub fn get(&self, index: u32) -> Option<T> {
        let (chunk, cell) = self.layout.locate(index)?;
        Some(self.cell_ref(chunk, cell).clone())
    }

    /// Calls `f` with a reference to the value at `index` without cloning it.
    pub fn with<R>(&self, index: u32, f: impl FnOnce(&T) -> R) -> Option<R> {
        let (chunk, cell) = self.layout.locate(index)?;
        Some(f(self.cell_ref(chunk, cell)))
    }

    /// The dense cells of a slot, copying a shared chunk and expanding a default or uniform one.
    fn dense_mut(slot: &mut Slot<T>, len: usize) -> &mut Vec<T> {
        match slot {
            Slot::Dense(_) => {}
            Slot::Default => *slot = Slot::Dense(Arc::new(vec![T::default(); len])),
            Slot::Uniform(v) => *slot = Slot::Dense(Arc::new(vec![T::clone(v); len])),
        }
        match slot {
            Slot::Dense(c) => Arc::make_mut(c),
            _ => unreachable!("densified above"),
        }
    }

    /// A mutable reference to the value at `index`, densifying its chunk, or
    /// copying it if a snapshot still shares it.
    pub fn get_mut(&mut self, index: u32) -> Option<&mut T> {
        let (chunk, cell) = self.layout.locate(index)?;
        self.writes += 1;
        let len = self.layout.chunk_len();
        Some(&mut Self::dense_mut(&mut self.chunks[chunk], len)[cell])
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

    /// The cells of chunk `chunk`, if it is not a default chunk.
    #[must_use]
    pub fn chunk(&self, chunk: usize) -> Option<ChunkView<'_, T>> {
        let len = self.layout.chunk_len();
        match self.chunks.get(chunk)? {
            Slot::Default => None,
            Slot::Uniform(v) => Some(ChunkView {
                cells: Cells::Uniform(v),
                len,
            }),
            Slot::Dense(c) => Some(ChunkView {
                cells: Cells::Dense(c),
                len,
            }),
        }
    }

    /// Chunks that hold an allocation (uniform or dense).
    #[must_use]
    pub fn allocated_chunks(&self) -> usize {
        self.chunks
            .iter()
            .filter(|c| !matches!(c, Slot::Default))
            .count()
    }

    /// Chunks stored as one shared value.
    #[must_use]
    pub fn uniform_chunks(&self) -> usize {
        self.chunks
            .iter()
            .filter(|c| matches!(c, Slot::Uniform(_)))
            .count()
    }

    /// Allocated chunks this store shares (same allocation) with `other`.
    #[must_use]
    pub fn shared_chunks_with(&self, other: &Self) -> usize {
        self.chunks
            .iter()
            .zip(&other.chunks)
            .filter(|(a, b)| !matches!(a, Slot::Default) && a.same(b))
            .count()
    }

    /// Whether chunk `chunk` is not the same allocation in `self` and `base` (same layout).
    #[must_use]
    pub fn chunk_differs(&self, base: &Self, chunk: usize) -> bool {
        !self.chunks[chunk].same(&base.chunks[chunk])
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
            .filter(|(_, (a, b))| !a.same(b))
            .map(|(i, _)| i)
    }

    /// Calls `f(chunk, cells)` for every allocated chunk, in chunk order (a uniform chunk is expanded first).
    pub fn for_each_chunk_mut(&mut self, mut f: impl FnMut(usize, &mut [T])) {
        self.writes += 1;
        let len = self.layout.chunk_len();
        for (i, slot) in self.chunks.iter_mut().enumerate() {
            if !matches!(slot, Slot::Default) {
                f(i, Self::dense_mut(slot, len).as_mut_slice());
            }
        }
    }

    /// Densifies every chunk (e.g. before a field step that touches all
    /// cells, so the chunk iterators reach them).
    pub fn allocate_all(&mut self) {
        self.writes += 1;
        let len = self.layout.chunk_len();
        for slot in &mut self.chunks {
            Self::dense_mut(slot, len);
        }
    }

    /// Frees chunks whose cells are all default, and stores a chunk whose cells all hold one other value
    /// as uniform. Values are unchanged.
    pub fn compact(&mut self)
    where
        T: PartialEq,
    {
        let all: Vec<usize> = (0..self.chunks.len()).collect();
        self.compact_chunks(&all);
    }

    /// [`compact`](Self::compact) for the listed chunks: a dense chunk whose cells all hold exactly the default is
    /// freed, one whose cells all hold one other value becomes a uniform chunk (sharing one allocation with every
    /// other uniform chunk of that value), and every other chunk is left alone. Equality is `T`'s `==` (an `f32`
    /// NaN is never equal, so never compacts). A snapshot keeps the chunk it shared. Values and the write count are
    /// unchanged. Returns how many dense allocations were released.
    pub fn compact_chunks(&mut self, candidates: &[usize]) -> usize
    where
        T: PartialEq,
    {
        fn uniform<T: PartialEq>(c: &[T]) -> Option<&T> {
            let first = c.first()?;
            c.iter().all(|v| v == first).then_some(first)
        }
        // Canonical values: those already stored as uniform, collected on first need.
        let mut canon: Vec<Arc<T>> = Vec::new();
        let mut canon_ready = false;
        let mut released = 0;
        for &i in candidates {
            let value = match self.chunks.get(i) {
                Some(Slot::Dense(c)) => match uniform(c) {
                    Some(v) => v.clone(),
                    None => continue,
                },
                _ => continue,
            };
            if value == *self.default {
                self.chunks[i] = Slot::Default;
                released += 1;
                continue;
            }
            if !canon_ready {
                canon_ready = true;
                for slot in &self.chunks {
                    if let Slot::Uniform(v) = slot {
                        if !canon.iter().any(|k| Arc::ptr_eq(k, v)) {
                            canon.push(Arc::clone(v));
                        }
                    }
                }
            }
            let shared = if let Some(k) = canon.iter().find(|k| ***k == value) {
                Arc::clone(k)
            } else {
                let k = Arc::new(value);
                canon.push(Arc::clone(&k));
                k
            };
            self.chunks[i] = Slot::Uniform(shared);
            released += 1;
        }
        released
    }

    /// Memory held by this store, by chunk kind. An allocation several chunks share is counted once.
    #[must_use]
    pub fn memory(&self) -> CowMemory
    where
        T: PartialEq,
    {
        let mut seen = std::collections::HashSet::new();
        let mut m = CowMemory {
            chunks: self.chunks.len(),
            bytes: self.chunks.capacity() * size_of::<Slot<T>>(),
            ..CowMemory::default()
        };
        let len = self.layout.chunk_len();
        let header = 2 * size_of::<usize>();
        for slot in &self.chunks {
            match slot {
                Slot::Default => m.default_chunks += 1,
                Slot::Uniform(v) => {
                    m.uniform_chunks += 1;
                    if seen.insert(Arc::as_ptr(v) as usize) {
                        m.allocations += 1;
                        m.bytes += size_of::<T>() + header;
                    }
                }
                Slot::Dense(c) => {
                    m.dense_chunks += 1;
                    if c.first().is_some_and(|f| c.iter().all(|v| v == f)) {
                        m.dense_but_uniform += 1;
                    }
                    if seen.insert(Arc::as_ptr(c) as usize) {
                        m.allocations += 1;
                        m.bytes += len * size_of::<T>() + size_of::<Vec<T>>() + header;
                    }
                }
            }
        }
        m
    }

    /// Bytes held by allocated chunks (a shared chunk is counted by every
    /// slot that holds it); [`memory`](Self::memory) counts distinct allocations.
    #[must_use]
    pub fn reserved_bytes(&self) -> usize {
        let len = self.layout.chunk_len();
        let chunk_bytes: usize = self
            .chunks
            .iter()
            .map(|c| match c {
                Slot::Default => 0,
                Slot::Uniform(_) => size_of::<T>(),
                Slot::Dense(_) => len * size_of::<T>(),
            })
            .sum();
        chunk_bytes + self.chunks.capacity() * size_of::<Slot<T>>()
    }

    /// Value equality over every cell (a default chunk equals an
    /// all-default one however it is stored).
    #[must_use]
    pub fn values_eq(&self, other: &Self) -> bool
    where
        T: PartialEq,
    {
        if self.layout != other.layout {
            return false;
        }
        let len = self.layout.chunk_len();
        self.chunks
            .iter()
            .zip(&other.chunks)
            .enumerate()
            .all(|(c, (a, b))| {
                a.same(b) || (0..len).all(|i| self.cell_ref(c, i) == other.cell_ref(c, i))
            })
    }
}

impl<T: Clone + Default + Send + Sync> CowStore<T> {
    /// Calls `f(chunk, cells)` for every allocated chunk in parallel on the
    /// current rayon pool. `f` must be per-chunk deterministic (§3.9);
    /// combine cross-chunk sums in chunk order afterwards.
    pub fn par_for_each_chunk_mut(&mut self, f: impl Fn(usize, &mut [T]) + Sync + Send) {
        use rayon::prelude::*;
        self.writes += 1;
        let len = self.layout.chunk_len();
        self.chunks
            .par_iter_mut()
            .enumerate()
            .for_each(|(i, slot)| {
                if !matches!(slot, Slot::Default) {
                    f(i, Self::dense_mut(slot, len).as_mut_slice());
                }
            });
    }

    /// Calls `f(chunk, cells)` in parallel for each chunk in `chunks`,
    /// densifying it first (and copying it if a snapshot shares it). Chunks
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
            if let Some(flag) = listed.get_mut(c) {
                *flag = true;
            }
        }
        self.chunks
            .par_iter_mut()
            .enumerate()
            .filter(|(i, _)| listed[*i])
            .for_each(|(i, slot)| f(i, Self::dense_mut(slot, len).as_mut_slice()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn unchanged_since_is_true_until_a_write_and_never_across_stores() {
        let layout = ChunkLayout::linear_with_chunk(100, 10);
        let mut store = CowStore::<u32>::new(layout);
        store.set(3, 1);
        let view = store.snapshot();
        assert!(store.unchanged_since(&view));
        store.set(4, 2);
        assert!(!store.unchanged_since(&view));
        let other = CowStore::<u32>::new(layout);
        assert!(
            !other.unchanged_since(&CowStore::<u32>::new(layout)),
            "two new stores are not one lineage"
        );
    }

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
        let before = std::ptr::from_ref(store.chunk(1).unwrap().get(0));
        store.set(16, 1);
        assert_eq!(std::ptr::from_ref(store.chunk(1).unwrap().get(0)), before);
    }

    #[test]
    fn uniform_chunks_share_one_allocation() {
        let mut store = CowStore::<u32>::new(ChunkLayout::linear_with_chunk(40, 10));
        for i in 0..40 {
            store.set(i, if i == 25 { 1 } else { 7 });
        }
        assert_eq!(store.compact_chunks(&[0, 1, 2, 3]), 3);
        assert_eq!(store.uniform_chunks(), 3);
        let m = store.memory();
        assert_eq!(
            (m.uniform_chunks, m.dense_chunks, m.allocations),
            (3, 1, 2),
            "one shared value plus the mixed chunk"
        );
        let (a, b) = (store.chunk(0).unwrap(), store.chunk(3).unwrap());
        assert!(a.same_alloc(&b) && a.uniform() == Some(&7));
        assert!(!a.same_alloc(&store.chunk(2).unwrap()));
        store.set(5, 9);
        assert_eq!(store.get(5), Some(9));
        assert_eq!(
            store.get(6),
            Some(7),
            "the rest of the densified chunk keeps the value"
        );
        assert_eq!(store.get(15), Some(7));
        assert_eq!(store.get(35), Some(7));
        assert_eq!(store.get(25), Some(1));
        assert_eq!(store.uniform_chunks(), 2);
    }

    #[test]
    fn uniform_chunk_is_copy_on_write_for_snapshots() {
        let mut store = CowStore::<u32>::new(ChunkLayout::linear_with_chunk(20, 10));
        for i in 0..20 {
            store.set(i, 4);
        }
        store.compact();
        assert_eq!(store.uniform_chunks(), 2);
        let view = store.snapshot();
        assert_eq!(store.shared_chunks_with(&view), 2);
        assert_eq!(store.chunks_differing_from(&view).count(), 0);
        store.set(3, 8);
        assert_eq!(view.get(3), Some(4));
        assert_eq!(store.get(3), Some(8));
        assert_eq!(
            store.chunks_differing_from(&view).collect::<Vec<_>>(),
            vec![0]
        );
        assert!(store.chunk_differs(&view, 0) && !store.chunk_differs(&view, 1));
        assert_eq!(
            view.uniform_chunks(),
            2,
            "the snapshot keeps its uniform chunk"
        );
        assert!(!store.values_eq(&view));
        store.set(3, 4);
        assert!(
            store.values_eq(&view),
            "equal values, different allocations"
        );
        assert_eq!(
            store.compact_chunks(&[0, 1]),
            1,
            "chunk 0 is uniform again; chunk 1 already was"
        );
        assert_eq!(store.uniform_chunks(), 2);
        assert!(
            !store.chunk_differs(&view, 0),
            "the canonical value is shared again"
        );
    }

    #[test]
    fn compaction_is_exact_and_leaves_mixed_chunks() {
        let mut store = CowStore::<f32>::new(ChunkLayout::linear_with_chunk(30, 10));
        for i in 0..30 {
            store.set(
                i,
                if i == 12 {
                    0.5
                } else if i < 10 {
                    0.0
                } else {
                    2.0
                },
            );
        }
        store.set(25, f32::NAN);
        assert_eq!(store.compact_chunks(&[0, 1, 2]), 1);
        assert!(store.chunk(0).is_none(), "all-default chunk is freed");
        assert!(
            store.chunk(1).unwrap().uniform().is_none(),
            "one cell differs"
        );
        assert!(
            store.chunk(2).unwrap().uniform().is_none(),
            "a NaN never compares equal"
        );
        assert_eq!(store.get(12), Some(0.5));
        assert!(store.get(25).unwrap().is_nan());
    }

    #[test]
    fn compaction_is_not_a_write_and_reads_are_unchanged() {
        let mut store = CowStore::<u8>::new(ChunkLayout::linear_with_chunk(100, 10));
        store.set(55, 3);
        let writes_before = store.writes;
        store.compact();
        assert_eq!(store.writes, writes_before, "compaction is not a write");
        for i in 0..100u32 {
            assert_eq!(store.get(i), Some(u8::from(i == 55) * 3));
        }
        store.for_each_chunk_mut(|_, cells| cells[0] = 1);
        assert_eq!(store.get(55), Some(3));
        assert_eq!(store.get(50), Some(1));
        assert_eq!(store.allocated_chunks(), 1);
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
