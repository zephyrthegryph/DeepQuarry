//! A hierarchical timer wheel at tick resolution (`rust_core.md` §7).
//!
//! Four levels of 64 slots cover 2^24 ticks ahead; later deadlines wait in
//! an overflow list that is re-sorted into the wheel every 2^24 ticks. Each
//! timer is a node in a slab, linked into its slot's list, so insert and
//! cancel are O(1) and no DM datum exists per timer. Advancing one tick
//! cascades at most one slot per level.
//!
//! Timers fire in `(deadline, insertion order)` order. A deadline at or
//! before the current tick fires on the next advance.

/// A tick number (DM's `world.time` in ticks).
pub type Tick = u64;

const BITS: u32 = 6;
const SLOTS: usize = 1 << BITS;
const LEVELS: usize = 4;
const OVERFLOW: usize = LEVELS * SLOTS;
const DUE: usize = OVERFLOW + 1;
const LISTS: usize = DUE + 1;
const NIL: u32 = u32::MAX;
const FREE: u32 = u32::MAX;

/// A timer, as slab index plus generation (a cancelled or fired timer's id
/// never matches a later one).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct TimerId {
    pub index: u32,
    pub generation: u32,
}

#[derive(Debug)]
struct Node<T> {
    deadline: Tick,
    seq: u64,
    payload: Option<T>,
    generation: u32,
    prev: u32,
    next: u32,
    list: u32,
}

/// The wheel. Main thread only.
#[derive(Debug)]
pub struct TimerWheel<T> {
    now: Tick,
    nodes: Vec<Node<T>>,
    free: Vec<u32>,
    heads: Vec<u32>,
    tails: Vec<u32>,
    /// Timers per class: one per level, then overflow, then due.
    counts: [usize; LEVELS + 2],
    len: usize,
    seq: u64,
}

const fn class(list: usize) -> usize {
    if list < OVERFLOW {
        list / SLOTS
    } else {
        LEVELS + (list - OVERFLOW)
    }
}

impl<T> TimerWheel<T> {
    /// An empty wheel whose current tick is `now`.
    #[must_use]
    pub fn new(now: Tick) -> Self {
        Self {
            now,
            nodes: Vec::new(),
            free: Vec::new(),
            heads: vec![NIL; LISTS],
            tails: vec![NIL; LISTS],
            counts: [0; LEVELS + 2],
            len: 0,
            seq: 0,
        }
    }

    #[must_use]
    pub const fn now(&self) -> Tick {
        self.now
    }

    #[must_use]
    pub const fn len(&self) -> usize {
        self.len
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.len == 0
    }

    fn list_for(&self, deadline: Tick) -> usize {
        if deadline <= self.now {
            return DUE;
        }
        let diff = deadline ^ self.now;
        let level = ((63 - diff.leading_zeros()) / BITS) as usize;
        if level >= LEVELS {
            return OVERFLOW;
        }
        #[allow(clippy::cast_possible_truncation)]
        let slot = ((deadline >> (BITS as usize * level)) as usize) & (SLOTS - 1);
        level * SLOTS + slot
    }

    fn link(&mut self, i: u32, list: usize) {
        let tail = self.tails[list];
        {
            let n = &mut self.nodes[i as usize];
            n.list = u32::try_from(list).expect("few lists");
            n.prev = tail;
            n.next = NIL;
        }
        if tail == NIL {
            self.heads[list] = i;
        } else {
            self.nodes[tail as usize].next = i;
        }
        self.tails[list] = i;
        self.counts[class(list)] += 1;
    }

    fn unlink(&mut self, i: u32) {
        let (prev, next, list) = {
            let n = &self.nodes[i as usize];
            (n.prev, n.next, n.list as usize)
        };
        if prev == NIL {
            self.heads[list] = next;
        } else {
            self.nodes[prev as usize].next = next;
        }
        if next == NIL {
            self.tails[list] = prev;
        } else {
            self.nodes[next as usize].prev = prev;
        }
        self.counts[class(list)] -= 1;
    }

    /// Schedules `payload` for `deadline`. O(1).
    ///
    /// # Panics
    /// If more than `u32::MAX - 1` timers are live.
    pub fn insert(&mut self, deadline: Tick, payload: T) -> TimerId {
        let seq = self.seq;
        self.seq += 1;
        let index = if let Some(i) = self.free.pop() {
            let n = &mut self.nodes[i as usize];
            n.deadline = deadline;
            n.seq = seq;
            n.payload = Some(payload);
            i
        } else {
            let i = u32::try_from(self.nodes.len()).expect("timer slab fits u32");
            assert!(i != NIL, "too many timers");
            self.nodes.push(Node {
                deadline,
                seq,
                payload: Some(payload),
                generation: 0,
                prev: NIL,
                next: NIL,
                list: FREE,
            });
            i
        };
        let list = self.list_for(deadline);
        self.link(index, list);
        self.len += 1;
        TimerId {
            index,
            generation: self.nodes[index as usize].generation,
        }
    }

    fn release(&mut self, i: u32) -> T {
        let n = &mut self.nodes[i as usize];
        n.list = FREE;
        n.generation = n.generation.wrapping_add(1);
        self.free.push(i);
        self.len -= 1;
        n.payload.take().expect("live timer has a payload")
    }

    fn live(&self, id: TimerId) -> bool {
        self.nodes
            .get(id.index as usize)
            .is_some_and(|n| n.list != FREE && n.generation == id.generation)
    }

    /// Cancels a pending timer, returning its payload. O(1).
    pub fn cancel(&mut self, id: TimerId) -> Option<T> {
        if !self.live(id) {
            return None;
        }
        self.unlink(id.index);
        Some(self.release(id.index))
    }

    /// A pending timer's deadline.
    #[must_use]
    pub fn deadline(&self, id: TimerId) -> Option<Tick> {
        self.live(id)
            .then(|| self.nodes[id.index as usize].deadline)
    }

    fn take_list(&mut self, list: usize) -> Vec<u32> {
        let mut out = Vec::new();
        let mut i = self.heads[list];
        while i != NIL {
            out.push(i);
            i = self.nodes[i as usize].next;
        }
        self.heads[list] = NIL;
        self.tails[list] = NIL;
        self.counts[class(list)] -= out.len();
        out
    }

    fn fire_list(&mut self, list: usize, out: &mut Vec<(TimerId, Tick, u64, T)>) {
        for i in self.take_list(list) {
            let (generation, deadline, seq) = {
                let n = &self.nodes[i as usize];
                (n.generation, n.deadline, n.seq)
            };
            let payload = self.release(i);
            out.push((
                TimerId {
                    index: i,
                    generation,
                },
                deadline,
                seq,
                payload,
            ));
        }
    }

    /// Advances to tick `to`, appending every timer due by then to `fired`
    /// in `(deadline, insertion)` order.
    pub fn advance(&mut self, to: Tick, fired: &mut Vec<(TimerId, T)>) {
        let mut batch = Vec::new();
        self.fire_list(DUE, &mut batch);
        while self.now < to && self.len > 0 {
            // Skip ahead to the next tick that can cascade or fire: with
            // every level below `lowest` empty, nothing happens before the
            // next multiple of 64^lowest.
            let lowest = (0..=LEVELS).find(|&l| self.counts[l] > 0).unwrap_or(LEVELS);
            if lowest > 0 {
                let span = 1u64 << (BITS as usize * lowest);
                let next = (self.now | (span - 1)) + 1;
                if next > to {
                    break;
                }
                self.now = next - 1;
            }
            self.now += 1;
            let t = self.now;
            if t & ((1 << (BITS as usize * LEVELS)) - 1) == 0 {
                for i in self.take_list(OVERFLOW) {
                    let list = self.list_for(self.nodes[i as usize].deadline);
                    self.link(i, list);
                }
            }
            for level in (1..LEVELS).rev() {
                let shift = BITS as usize * level;
                if t & ((1 << shift) - 1) == 0 {
                    #[allow(clippy::cast_possible_truncation)]
                    let slot = ((t >> shift) as usize) & (SLOTS - 1);
                    for i in self.take_list(level * SLOTS + slot) {
                        let list = self.list_for(self.nodes[i as usize].deadline);
                        self.link(i, list);
                    }
                }
            }
            self.fire_list(DUE, &mut batch);
            #[allow(clippy::cast_possible_truncation)]
            self.fire_list((t as usize) & (SLOTS - 1), &mut batch);
        }
        self.now = self.now.max(to);
        batch.sort_by_key(|&(_, deadline, seq, _)| (deadline, seq));
        fired.extend(batch.into_iter().map(|(id, _, _, p)| (id, p)));
    }

    /// The earliest pending deadline (O(timers); for metrics and tests).
    #[must_use]
    pub fn next_deadline(&self) -> Option<Tick> {
        self.nodes
            .iter()
            .filter(|n| n.list != FREE)
            .map(|n| n.deadline)
            .min()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use std::collections::BTreeMap;

    #[test]
    fn fires_at_tick_precision_across_levels() {
        let mut w = TimerWheel::new(0);
        let deadlines = [
            1u64,
            63,
            64,
            65,
            4095,
            4096,
            300_000,
            (1 << 24) + 5,
            1 << 30,
        ];
        for (i, &d) in deadlines.iter().enumerate() {
            w.insert(d, i);
        }
        for &d in &deadlines {
            let mut fired = Vec::new();
            w.advance(d - 1, &mut fired);
            assert!(fired.is_empty(), "nothing before {d}");
            w.advance(d, &mut fired);
            assert_eq!(fired.len(), 1, "exactly one at {d}");
        }
        assert!(w.is_empty());
    }

    #[test]
    fn cancel_is_exact_and_ids_are_not_reused() {
        let mut w = TimerWheel::new(10);
        let a = w.insert(20, 'a');
        let b = w.insert(20, 'b');
        assert_eq!(w.cancel(a), Some('a'));
        assert_eq!(w.cancel(a), None);
        let c = w.insert(20, 'c');
        assert_eq!(c.index, a.index);
        assert_ne!(c, a);
        assert_eq!(w.cancel(a), None, "stale id does not cancel the new timer");
        let mut fired = Vec::new();
        w.advance(25, &mut fired);
        assert_eq!(fired, vec![(b, 'b'), (c, 'c')]);
    }

    #[test]
    fn past_deadlines_fire_on_the_next_advance() {
        let mut w = TimerWheel::new(100);
        w.insert(50, 1);
        w.insert(100, 2);
        let mut fired = Vec::new();
        w.advance(100, &mut fired);
        assert_eq!(fired.iter().map(|f| f.1).collect::<Vec<_>>(), [1, 2]);
    }

    #[derive(Clone, Debug)]
    enum Op {
        Insert(u64),
        Cancel(usize),
        Advance(u64),
    }

    fn op() -> impl Strategy<Value = Op> {
        prop_oneof![
            4 => prop_oneof![0u64..70, 0u64..5000, 0u64..400_000].prop_map(Op::Insert),
            1 => any::<usize>().prop_map(Op::Cancel),
            3 => prop_oneof![0u64..3, 0u64..100, 0u64..9000].prop_map(Op::Advance),
        ]
    }

    proptest! {
        /// The wheel matches a sorted-map reference: the same timers fire,
        /// at the same advance, in (deadline, insertion) order, and a
        /// cancelled timer never fires.
        #[test]
        fn matches_a_reference_model(start in 0u64..1_000_000, ops in prop::collection::vec(op(), 1..300)) {
            let mut w = TimerWheel::new(start);
            let mut reference: BTreeMap<(u64, u64), usize> = BTreeMap::new();
            let mut ids: Vec<(TimerId, u64, u64)> = Vec::new();
            let mut now = start;
            for (n, op) in ops.into_iter().enumerate() {
                match op {
                    Op::Insert(delta) => {
                        let deadline = now + delta;
                        let id = w.insert(deadline, n);
                        reference.insert((deadline, n as u64), n);
                        ids.push((id, deadline, n as u64));
                    }
                    Op::Cancel(pick) => {
                        if !ids.is_empty() {
                            let (id, deadline, key) = ids[pick % ids.len()];
                            let want = reference.remove(&(deadline, key));
                            prop_assert_eq!(w.cancel(id), want);
                        }
                    }
                    Op::Advance(by) => {
                        now += by;
                        let mut fired = Vec::new();
                        w.advance(now, &mut fired);
                        let due: Vec<(u64, u64)> = reference.range(..=(now, u64::MAX)).map(|(k, _)| *k).collect();
                        let want: Vec<usize> = due.iter().map(|k| reference.remove(k).unwrap()).collect();
                        let got: Vec<usize> = fired.iter().map(|f| f.1).collect();
                        prop_assert_eq!(got, want);
                    }
                }
                prop_assert_eq!(w.len(), reference.len());
            }
        }
    }
}
