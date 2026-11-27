//! Declaration order of the member slots.
//!
//! A `MemberId` is a storage slot in the `MemberArena`: it says where a member
//! lives, never where it was declared. Every reader that needs declaration
//! order (the authored order of member rows) walks this array. Positions are
//! chunked so an insert or removal copies one chunk and the chunk start table,
//! never the whole array; unchanged chunks stay shared between revisions.
use crate::MemberId;
use std::sync::Arc;

/// Rows per chunk when an array is built whole; a chunk that grows past twice
/// this splits in two.
const CHUNK: usize = 256;

#[derive(Clone, Debug, Default)]
pub struct MemberOrder {
    chunks: Vec<Arc<[MemberId]>>,
    /// Position of each chunk's first row.
    starts: Arc<[usize]>,
    len: usize,
    /// Declaration position by slot, built on first `position_of`; cleared by every change.
    positions: std::sync::OnceLock<Arc<[u32]>>,
}

impl MemberOrder {
    /// Slots `0..len` in that order (a tree built whole numbers its slots in
    /// declaration order; nothing may rely on it).
    pub fn identity(len: usize) -> Self {
        Self::from_ids((0..len).map(|index| MemberId(index as u32)).collect())
    }
    pub fn from_ids(ids: Vec<MemberId>) -> Self {
        let len = ids.len();
        let mut chunks = Vec::with_capacity(len.div_ceil(CHUNK));
        let mut starts = Vec::with_capacity(chunks.capacity());
        for (index, chunk) in ids.chunks(CHUNK).enumerate() {
            starts.push(index * CHUNK);
            chunks.push(Arc::from(chunk));
        }
        Self {
            chunks,
            starts: starts.into(),
            len,
            positions: Default::default(),
        }
    }
    pub fn len(&self) -> usize {
        self.len
    }
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
    fn chunk_at(&self, position: usize) -> usize {
        self.starts.partition_point(|&start| start <= position) - 1
    }
    /// The slot declared at `position`.
    pub fn get(&self, position: usize) -> Option<MemberId> {
        if position >= self.len {
            return None;
        }
        let chunk = self.chunk_at(position);
        self.chunks[chunk].get(position - self.starts[chunk]).copied()
    }
    /// Slots in declaration order.
    pub fn iter(&self) -> impl DoubleEndedIterator<Item = MemberId> + ExactSizeIterator + Clone + '_ {
        OrderIter {
            chunks: &self.chunks,
            front: (0, 0),
            remaining: self.len,
            back: (self.chunks.len(), 0),
        }
    }
    /// The backing chunks (shared between revisions that did not touch them).
    pub fn chunks(&self) -> &[Arc<[MemberId]>] {
        &self.chunks
    }
    pub fn chunk_starts(&self) -> &Arc<[usize]> {
        &self.starts
    }
    /// Declaration position of every slot (`u32::MAX` for a slot not in the
    /// order, such as a freed one). One pass; for readers that need the
    /// declaration rank of an arbitrary slot.
    pub fn positions(&self, slots: usize) -> Vec<u32> {
        let mut positions = vec![u32::MAX; slots];
        for (position, id) in self.iter().enumerate() {
            positions[id.index()] = position as u32;
        }
        positions
    }
    /// Declaration position of slot `id` (one O(n) pass on the first call
    /// for this order, then a lookup); `None` for a slot not in the order.
    pub fn position_of(&self, id: MemberId) -> Option<usize> {
        let positions = self.positions.get_or_init(|| {
            let slots = self.iter().map(|id| id.index() + 1).max().unwrap_or(0);
            self.positions(slots).into()
        });
        positions
            .get(id.index())
            .filter(|&&position| position != u32::MAX)
            .map(|&position| position as usize)
    }
    /// Insert `id` so it is declared at `position`; copies one chunk.
    pub fn insert(&mut self, position: usize, id: MemberId) {
        self.positions = Default::default();
        assert!(position <= self.len, "member order insert out of bounds");
        if self.chunks.is_empty() {
            self.chunks.push(Arc::from([id]));
            self.starts = Arc::from([0]);
            self.len = 1;
            return;
        }
        // An append goes into the last chunk.
        let chunk = if position == self.len {
            self.chunks.len() - 1
        } else {
            self.chunk_at(position)
        };
        let offset = position - self.starts[chunk];
        let mut rows = self.chunks[chunk].to_vec();
        rows.insert(offset, id);
        self.replace_chunk(chunk, rows);
        self.len += 1;
    }
    /// Remove the row at `position` and return its slot; copies one chunk.
    pub fn remove(&mut self, position: usize) -> MemberId {
        self.positions = Default::default();
        assert!(position < self.len, "member order remove out of bounds");
        let chunk = self.chunk_at(position);
        let mut rows = self.chunks[chunk].to_vec();
        let id = rows.remove(position - self.starts[chunk]);
        self.replace_chunk(chunk, rows);
        self.len -= 1;
        id
    }
    fn replace_chunk(&mut self, chunk: usize, rows: Vec<MemberId>) {
        if rows.is_empty() {
            self.chunks.remove(chunk);
        } else if rows.len() > 2 * CHUNK {
            let (head, tail) = rows.split_at(rows.len() / 2);
            self.chunks[chunk] = Arc::from(head);
            self.chunks.insert(chunk + 1, Arc::from(tail));
        } else {
            self.chunks[chunk] = rows.into();
        }
        let mut start = 0;
        self.starts = self
            .chunks
            .iter()
            .map(|chunk| {
                let here = start;
                start += chunk.len();
                here
            })
            .collect();
    }
}

impl PartialEq for MemberOrder {
    fn eq(&self, other: &Self) -> bool {
        self.len == other.len && self.iter().eq(other.iter())
    }
}
impl Eq for MemberOrder {}

#[derive(Clone)]
struct OrderIter<'a> {
    chunks: &'a [Arc<[MemberId]>],
    /// (chunk, offset) of the next front row.
    front: (usize, usize),
    remaining: usize,
    /// (chunk, offset) one past the next back row: the back row is
    /// `chunks[back.0 - 1][..]` when `back.1 == 0`.
    back: (usize, usize),
}
impl Iterator for OrderIter<'_> {
    type Item = MemberId;
    fn next(&mut self) -> Option<MemberId> {
        if self.remaining == 0 {
            return None;
        }
        while self.front.1 >= self.chunks[self.front.0].len() {
            self.front = (self.front.0 + 1, 0);
        }
        let id = self.chunks[self.front.0][self.front.1];
        self.front.1 += 1;
        self.remaining -= 1;
        Some(id)
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.remaining, Some(self.remaining))
    }
}
impl DoubleEndedIterator for OrderIter<'_> {
    fn next_back(&mut self) -> Option<MemberId> {
        if self.remaining == 0 {
            return None;
        }
        while self.back.1 == 0 {
            self.back = (self.back.0 - 1, self.chunks[self.back.0 - 1].len());
        }
        self.back.1 -= 1;
        self.remaining -= 1;
        Some(self.chunks[self.back.0][self.back.1])
    }
}
impl ExactSizeIterator for OrderIter<'_> {}

/// Test and verification guard: build trees with member slots deliberately
/// shuffled away from declaration order, so a reader that takes slot number
/// for declaration order changes its output. `DMB_MEMBER_SLOT_SHUFFLE=<seed>`
/// (a nonzero integer) turns it on for a process; `with_shuffled_slots` for
/// one thread's builds (unit tests).
pub mod shuffle {
    use std::cell::Cell;
    use std::sync::atomic::{AtomicU64, Ordering};
    thread_local! {
        static OVERRIDE: Cell<Option<u64>> = const { Cell::new(None) };
    }
    /// The process seed: `DMB_MEMBER_SLOT_SHUFFLE` until `set_process_seed`.
    static PROCESS: AtomicU64 = AtomicU64::new(u64::MAX);
    fn process_seed() -> u64 {
        let seed = PROCESS.load(Ordering::Relaxed);
        if seed != u64::MAX {
            return seed;
        }
        let from_env = std::env::var("DMB_MEMBER_SLOT_SHUFFLE")
            .ok()
            .and_then(|value| value.trim().parse::<u64>().ok())
            .filter(|seed| *seed != u64::MAX)
            .unwrap_or(0);
        let _ = PROCESS.compare_exchange(u64::MAX, from_env, Ordering::Relaxed, Ordering::Relaxed);
        PROCESS.load(Ordering::Relaxed)
    }
    /// The seed for every later build in this process (0 turns it off); for a
    /// verification command that builds the same tree both ways.
    pub fn set_process_seed(seed: u64) {
        PROCESS.store(seed, Ordering::Relaxed);
    }
    /// The seed in force for a build on this thread, if any.
    pub fn seed() -> Option<u64> {
        let seed = OVERRIDE.with(Cell::get).unwrap_or_else(process_seed);
        (seed != 0).then_some(seed)
    }
    /// Run `body` with slot shuffling at `seed` (0 turns it off) on this thread.
    pub fn with_shuffled_slots<T>(seed: u64, body: impl FnOnce() -> T) -> T {
        let previous = OVERRIDE.with(|cell| cell.replace(Some(seed)));
        struct Restore(Option<u64>);
        impl Drop for Restore {
            fn drop(&mut self) {
                OVERRIDE.with(|cell| cell.set(self.0));
            }
        }
        let _restore = Restore(previous);
        body()
    }
    /// A deterministic permutation of `0..len`: `slot[i]` is where row `i` goes.
    pub(crate) fn permutation(seed: u64, len: usize) -> Vec<u32> {
        let mut rows: Vec<u32> = (0..len as u32).collect();
        rows.sort_by_key(|&row| {
            xxhash_rust::xxh3::xxh3_64_with_seed(&row.to_le_bytes(), seed)
        });
        // rows[k] is the row placed at slot k; invert.
        let mut slot = vec![0; len];
        for (k, &row) in rows.iter().enumerate() {
            slot[row as usize] = k as u32;
        }
        slot
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn ids(order: &MemberOrder) -> Vec<u32> {
        order.iter().map(|id| id.0).collect()
    }
    #[test]
    fn inserts_and_removals_copy_one_chunk_and_keep_order() {
        let mut order = MemberOrder::identity(1000);
        let untouched = Arc::clone(&order.chunks()[3]);
        order.insert(10, MemberId(5000));
        assert!(Arc::ptr_eq(&untouched, &order.chunks()[3]));
        let mut expected: Vec<u32> = (0..1000).collect();
        expected.insert(10, 5000);
        assert_eq!(ids(&order), expected);
        assert_eq!(order.get(10), Some(MemberId(5000)));
        assert_eq!(order.remove(10), MemberId(5000));
        expected.remove(10);
        assert_eq!(ids(&order), expected);
        order.insert(order.len(), MemberId(7));
        expected.push(7);
        assert_eq!(ids(&order), expected);
        assert_eq!(order.iter().rev().map(|id| id.0).collect::<Vec<_>>(), expected.iter().rev().copied().collect::<Vec<_>>());
        for _ in 0..600 {
            order.insert(300, MemberId(9));
            expected.insert(300, 9);
        }
        assert_eq!(ids(&order), expected);
        assert!(order.chunks().iter().all(|chunk| chunk.len() <= 2 * CHUNK));
        assert_eq!(order.position_of(MemberId(5)), Some(5));
        assert_eq!(order.position_of(MemberId(4000)), None);
        let positions = order.positions(6000);
        assert_eq!(positions[5], 5);
        assert_eq!(positions[4000], u32::MAX);
        let mut empty = MemberOrder::default();
        empty.insert(0, MemberId(1));
        empty.insert(0, MemberId(0));
        assert_eq!(ids(&empty), vec![0, 1]);
        assert_eq!(empty.remove(1), MemberId(1));
        assert_eq!(empty.remove(0), MemberId(0));
        assert!(empty.is_empty() && empty.iter().next().is_none());
    }
    /// The tree's own declaration-order view is the same with slots shuffled.
    #[test]
    fn shuffled_slots_keep_every_declaration_order_view() {
        let source = "/var/global = 1\n/datum/base\n    var/static/shared = 2\n    var/instance = 3\n    proc/act()\n        return 1\n/datum/base/child\n    shared = 4\n    act()\n        return 2\n    var/extra = 5\n/datum/other\n    var/static/shared = 5\n    verb/look()\n        return\n/datum/base/act()\n    return 3\n";
        let build = |seed| {
            shuffle::with_shuffled_slots(seed, || {
                let adapted = crate::adapter::from_ast(&dm_syntax::parse(source), dm_ir::SymbolTable::default(), dm_ir::FileId(0), 0, 0).unwrap();
                crate::build(adapted.symbols, &adapted.skeletons).unwrap()
            })
        };
        let plain = build(0);
        let shuffled = build(11);
        assert!(plain.member_order().iter().enumerate().all(|(position, id)| id.index() == position));
        assert!(shuffled.member_order().iter().enumerate().any(|(position, id)| id.index() != position), "the fixture must actually move slots");
        // Compare by declaration position, never by slot.
        let view = |tree: &crate::SemanticTree| {
            let positions = tree.member_order().positions(tree.members().len());
            let at = |id: MemberId| positions[id.index()];
            let members: Vec<_> = tree
                .members_in_order()
                .map(|(_, node)| (node.owner, node.name, node.kind, node.definition, node.content, node.metadata.clone(), node.previous.map(at)))
                .collect();
            let owners: Vec<Vec<u32>> = tree.types().iter().map(|node| node.members.iter().map(|id| at(*id)).collect()).collect();
            let mut direct: Vec<_> = tree.direct.iter().map(|(key, id)| (key.0 .0, key.1.bits(), key.2, at(*id))).collect();
            direct.sort();
            let targets: Vec<_> = tree
                .declarations()
                .iter()
                .map(|target| match target {
                    crate::Target::Type(id) => (0, id.0),
                    crate::Target::Member(id) => (1, at(*id)),
                })
                .collect();
            (members, owners, direct, targets, tree.identity(), tree.host_selections.clone())
        };
        assert_eq!(view(&plain), view(&shuffled));
        // Storage facts read by name, the same either way.
        for (_, node) in plain.members_in_order() {
            if node.kind == crate::MemberKind::Var {
                let owner = plain.types()[node.owner.index()].path;
                let other = shuffled.lookup_type(owner).unwrap();
                assert_eq!(
                    plain.resolve(node.owner, node.name, node.kind).map(|id| plain.variable_storage_for_member(id)),
                    shuffled.resolve(other, node.name, node.kind).map(|id| shuffled.variable_storage_for_member(id)),
                );
            }
        }
    }
    #[test]
    fn shuffle_permutation_is_a_bijection() {
        let slot = shuffle::permutation(7, 500);
        let mut seen = vec![false; 500];
        for &s in &slot {
            assert!(!seen[s as usize]);
            seen[s as usize] = true;
        }
        assert_ne!(slot, (0..500).collect::<Vec<u32>>());
    }
}

impl crate::SemanticTree {
    /// Move every member to the slot `shuffle::permutation(seed)` names,
    /// keeping declaration order in `member_order`. Called on a tree whose
    /// members, owner rosters, selectors and declaration targets are
    /// published, before anything derived from slots (inventory) is built.
    pub(crate) fn shuffle_member_slots(&mut self, seed: u64) {
        let len = self.members.len();
        let slot = shuffle::permutation(seed, len);
        let moved = |id: MemberId| MemberId(slot[id.index()]);
        let mut nodes: Vec<Option<crate::MemberNode>> = vec![None; len];
        for (index, node) in self.members.iter().enumerate() {
            let mut node = node.clone();
            node.previous = node.previous.map(moved);
            nodes[slot[index] as usize] = Some(node);
        }
        self.members = nodes
            .into_iter()
            .map(|node| node.expect("member slot permutation is a bijection"))
            .collect::<Vec<_>>()
            .into();
        let mut types = self.types.to_vec();
        for node in &mut types {
            node.members = node.members.iter().copied().map(moved).collect();
        }
        self.types = types.into();
        self.direct = Arc::new(
            self.direct
                .iter()
                .map(|(key, id)| (*key, moved(*id)))
                .collect(),
        );
        self.declaration_targets = self
            .declaration_targets
            .iter()
            .map(|target| match target {
                crate::Target::Member(id) => crate::Target::Member(moved(*id)),
                other => *other,
            })
            .collect();
        self.member_order = MemberOrder::from_ids(self.member_order.iter().map(moved).collect());
    }
}
