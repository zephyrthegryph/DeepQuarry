//! Events out (`rust_core.md` §8): the per-frame outbox a domain hands the
//! main thread next to its view.
//!
//! A frame fills one [`Outbox`] per domain: watch wakes, typed domain events
//! (brownouts, melts, threshold crossings, ...) and the exact results of
//! `Take` commands. [`DomainState`](crate::owner::DomainState) publishes it
//! through an [`OutboxSlot`] at the end of the frame, and the main thread
//! collects it when it pins the view. Unlike a view, an outbox is never
//! replaced by a newer one: an unread batch is merged into the next, so no
//! record is lost however the frames and ticks interleave.
//!
//! Buffers are bounded. When one is over capacity it is merged by key
//! (wakes by subscriber, lane and watch; events by kind and key) instead of
//! dropping records. `Take` results are never merged: they carry mass and
//! energy (transfer-out must conserve).
//!
//! DM drains each kind as a flat numeric list with a fixed stride
//! ([`Outbox::wakes_flat`], [`Outbox::events_flat`]); every field is kept
//! below 2^24 so it is exact as a BYOND `f32`.

use crate::command::Seq;
use crate::mailbox::Latest;

/// Wake reason bits. Bits `0..MAX_CHANNELS` are channel bits
/// ([`ChannelId::bit`](crate::channel::ChannelId::bit)); the class flags
/// sit above them, and the whole mask stays below 2^24.
pub mod reason {
    /// A condition watch (Threshold, Band, Difference, ThresholdSet, All).
    pub const CONDITION: u32 = 1 << 20;
    /// A timer fired.
    pub const TIMER: u32 = 1 << 21;
    /// A DM-owned key was published.
    pub const KEY: u32 = 1 << 22;
    /// A rate model crossed a level.
    pub const RATE: u32 = 1 << 23;
    /// Every bit a reason may use.
    pub const ALL: u32 = (1 << 24) - 1;
}

/// Wake priority lanes (§7). Urgent drains first and in full.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum Lane {
    Urgent = 0,
    Normal = 1,
    Background = 2,
}

impl Lane {
    pub const ALL: [Self; 3] = [Self::Urgent, Self::Normal, Self::Background];

    #[must_use]
    pub fn from_id(id: u8) -> Option<Self> {
        Self::ALL.get(usize::from(id)).copied()
    }

    #[must_use]
    pub const fn index(self) -> usize {
        self as usize
    }
}

/// The subscriber's registry index on the DM side (one number per datum).
pub type Subscriber = u32;

/// Largest subscriber index (exact as an `f32`).
pub const MAX_SUBSCRIBER: Subscriber = (1 << 24) - 1;

/// A watch, as `index` plus `generation`. Allocated on the main thread so
/// DM gets it at registration.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct WatchId {
    pub index: u32,
    pub generation: u32,
}

impl WatchId {
    /// Wakes from timers, keys and rate models, which have no watch.
    pub const NONE: Self = Self {
        index: u32::MAX,
        generation: 0,
    };
}

/// A request to run a subscriber's `react(reason, source)`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Wake {
    pub subscriber: Subscriber,
    pub lane: Lane,
    /// Channel bits and [`reason`] class flags, OR-ed over merged wakes.
    pub reason: u32,
    /// What changed: a cell, timer token, key or model id. On a merged wake,
    /// the first source.
    pub source: u32,
    pub watch: WatchId,
}

/// Domain event kinds (§8). Numeric IDs are generated into DM defines.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[repr(u8)]
pub enum EventKind {
    PressureJump = 1,
    /// A cell's gating law found a reaction whose requirements hold. `key`
    /// = cell/region index, `extra` = the reaction's dense registry index
    /// (stable for one boot; DM resolves it against its own registration
    /// order, the same order it built the gate from - no id round-trips
    /// through Rust).
    ReactionReady = 2,
    VisualChange = 3,
    Ignite = 4,
    Melt = 5,
    /// A `ThresholdSet` entry crossed: key = watch index, `extra` = payload,
    /// `generation` = entry generation, `value` = 1 entered / 0 left.
    ThresholdCrossed = 6,
    Brownout = 7,
    Restore = 8,
    TopologyChanged = 9,
    Destroyed = 10,
}

/// One fixed-stride event record.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Event {
    pub kind: EventKind,
    /// The entity or group the event is about.
    pub key: u32,
    pub value: f32,
    pub extra: u32,
    /// For payload-carrying events, the payload's generation: a record whose
    /// generation no longer matches the ledger is stale and ignored (§6.4).
    pub generation: u32,
}

/// The exact value a `Take` removed on the worker (§3.1). DM's `take`
/// returned what the pinned view showed, which can be up to one frame old;
/// the difference between the two is what transfer-out must reconcile.
#[derive(Clone, Debug, PartialEq)]
pub struct TakeResult<V> {
    pub seq: Seq,
    pub cell: u32,
    pub value: V,
}

/// Default buffer bounds, per kind.
pub const WAKE_CAPACITY: usize = 1 << 16;
pub const EVENT_CAPACITY: usize = 1 << 14;

/// One domain's records since the main thread last collected them.
#[derive(Clone, Debug)]
pub struct Outbox<V> {
    /// First and last frame folded into this batch.
    pub frames: Option<(u64, u64)>,
    wakes: Vec<Wake>,
    events: Vec<Event>,
    takes: Vec<TakeResult<V>>,
    wake_capacity: usize,
    event_capacity: usize,
    /// Lengths that trigger the next merge. They start at the capacity and
    /// double past what a merge could not shrink (all keys distinct), so a
    /// buffer over capacity costs amortised O(log n) per record, not a sort
    /// per push.
    wake_merge_at: usize,
    event_merge_at: usize,
    /// Records merged away because a buffer was over capacity.
    pub merged_on_overflow: u64,
}

impl<V> Default for Outbox<V> {
    fn default() -> Self {
        Self::with_capacity(WAKE_CAPACITY, EVENT_CAPACITY)
    }
}

impl<V> Outbox<V> {
    #[must_use]
    pub const fn with_capacity(wakes: usize, events: usize) -> Self {
        Self {
            frames: None,
            wakes: Vec::new(),
            events: Vec::new(),
            takes: Vec::new(),
            wake_capacity: wakes,
            event_capacity: events,
            wake_merge_at: wakes,
            event_merge_at: events,
            merged_on_overflow: 0,
        }
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.wakes.is_empty() && self.events.is_empty() && self.takes.is_empty()
    }

    pub fn push_wake(&mut self, wake: Wake) {
        self.wakes.push(wake);
        if self.wakes.len() > self.wake_merge_at {
            self.merge_wakes();
        }
    }

    pub fn push_event(&mut self, event: Event) {
        self.events.push(event);
        if self.events.len() > self.event_merge_at {
            self.merge_events();
        }
    }

    pub fn push_take(&mut self, take: TakeResult<V>) {
        self.takes.push(take);
    }

    /// Marks `frame` as folded into this batch.
    pub fn stamp(&mut self, frame: u64) {
        self.frames = Some(match self.frames {
            None => (frame, frame),
            Some((first, _)) => (first, frame),
        });
    }

    #[must_use]
    pub fn wakes(&self) -> &[Wake] {
        &self.wakes
    }

    #[must_use]
    pub fn events(&self) -> &[Event] {
        &self.events
    }

    #[must_use]
    pub fn takes(&self) -> &[TakeResult<V>] {
        &self.takes
    }

    pub fn wakes_mut(&mut self) -> &mut Vec<Wake> {
        &mut self.wakes
    }

    pub fn events_mut(&mut self) -> &mut Vec<Event> {
        &mut self.events
    }

    /// Moves the take results out.
    pub fn take_takes(&mut self) -> Vec<TakeResult<V>> {
        std::mem::take(&mut self.takes)
    }

    /// Appends a later batch (frame order is kept).
    pub fn append(&mut self, mut later: Self) {
        match (self.frames, later.frames) {
            (Some((first, _)), Some((_, last))) => self.frames = Some((first, last)),
            (None, f) => self.frames = f,
            (Some(_), None) => {}
        }
        self.wakes.append(&mut later.wakes);
        self.events.append(&mut later.events);
        self.takes.append(&mut later.takes);
        self.merged_on_overflow += later.merged_on_overflow;
        if self.wakes.len() > self.wake_merge_at {
            self.merge_wakes();
        }
        if self.events.len() > self.event_merge_at {
            self.merge_events();
        }
    }

    /// Merges wakes with the same subscriber, lane and watch, keeping the
    /// first one's position and source and OR-ing the reasons. If that is
    /// still over capacity, merges by subscriber and lane alone.
    pub fn merge_wakes(&mut self) {
        let before = self.wakes.len();
        merge_by_key(
            &mut self.wakes,
            |w| (w.subscriber, w.lane, w.watch),
            |a, b| {
                a.reason |= b.reason;
            },
        );
        if self.wakes.len() > self.wake_capacity {
            merge_by_key(
                &mut self.wakes,
                |w| (w.subscriber, w.lane),
                |a, b| {
                    a.reason |= b.reason;
                    if a.watch != b.watch {
                        a.watch = WatchId::NONE;
                    }
                },
            );
        }
        self.merged_on_overflow += (before - self.wakes.len()) as u64;
        self.wake_merge_at = self.wake_capacity.max(self.wakes.len() * 2);
    }

    /// Merges events with the same kind and key; the latest record wins.
    pub fn merge_events(&mut self) {
        let before = self.events.len();
        merge_by_key(
            &mut self.events,
            |e| (e.kind, e.key, e.extra),
            |a, b| *a = *b,
        );
        self.merged_on_overflow += (before - self.events.len()) as u64;
        self.event_merge_at = self.event_capacity.max(self.events.len() * 2);
    }

    /// Wakes as `[subscriber, lane, reason, source]` quads.
    #[allow(clippy::cast_precision_loss)]
    pub fn wakes_flat(&self, out: &mut Vec<f32>) {
        out.reserve(self.wakes.len() * 4);
        for w in &self.wakes {
            out.extend_from_slice(&[
                w.subscriber as f32,
                f32::from(w.lane as u8),
                w.reason as f32,
                (w.source & 0x00ff_ffff) as f32,
            ]);
        }
    }

    /// Events as `[kind, key, value, extra, generation]` quintuples.
    #[allow(clippy::cast_precision_loss)]
    pub fn events_flat(&self, out: &mut Vec<f32>) {
        out.reserve(self.events.len() * 5);
        for e in &self.events {
            out.extend_from_slice(&[
                f32::from(e.kind as u8),
                (e.key & 0x00ff_ffff) as f32,
                e.value,
                (e.extra & 0x00ff_ffff) as f32,
                (e.generation & 0x00ff_ffff) as f32,
            ]);
        }
    }
}

/// Stable in-place merge: the first record per key keeps its position.
fn merge_by_key<T, K: Ord + Copy>(
    v: &mut Vec<T>,
    key: impl Fn(&T) -> K,
    merge: impl Fn(&mut T, &T),
) {
    if v.len() < 2 {
        return;
    }
    let mut order: Vec<usize> = (0..v.len()).collect();
    order.sort_by_key(|&i| (key(&v[i]), i));
    let mut keep = vec![true; v.len()];
    let mut head = order[0];
    for &i in &order[1..] {
        if key(&v[i]) == key(&v[head]) {
            let (a, b) = if head < i {
                let (l, r) = v.split_at_mut(i);
                (&mut l[head], &r[0])
            } else {
                unreachable!("sorted by index within a key")
            };
            merge(a, b);
            keep[i] = false;
        } else {
            head = i;
        }
    }
    let mut i = 0;
    v.retain(|_| {
        i += 1;
        keep[i - 1]
    });
}

/// The worker-to-main outbox mailbox. One writer (the frame, which runs one
/// at a time) and one reader (the main thread); an unread batch is merged
/// into the next rather than replaced, so nothing is lost. Both sides are
/// atomic swaps: the main thread never waits.
pub struct OutboxSlot<V> {
    slot: Latest<Outbox<V>>,
}

impl<V> Default for OutboxSlot<V> {
    fn default() -> Self {
        Self {
            slot: Latest::new(),
        }
    }
}

impl<V> OutboxSlot<V> {
    /// Publishes `batch`, folding in any batch the main thread has not
    /// collected yet. Frame side only.
    pub fn publish(&self, batch: Outbox<V>) {
        if batch.is_empty() && batch.frames.is_none() {
            return;
        }
        let batch = match self.slot.take() {
            Some(mut older) => {
                older.append(batch);
                older
            }
            None => batch,
        };
        self.slot.put(batch);
    }

    /// Collects everything published so far. Main thread only.
    pub fn collect(&self) -> Option<Outbox<V>> {
        self.slot.take()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wake(subscriber: u32, reason: u32, watch: u32) -> Wake {
        Wake {
            subscriber,
            lane: Lane::Normal,
            reason,
            source: subscriber * 10,
            watch: WatchId {
                index: watch,
                generation: 0,
            },
        }
    }

    #[test]
    fn overflow_merges_by_key_instead_of_dropping() {
        let mut out = Outbox::<()>::with_capacity(3, 2);
        for i in 0..4 {
            out.push_wake(wake(i % 2, 1 << i, 0));
        }
        assert_eq!(out.wakes().len(), 2);
        assert_eq!(out.wakes()[0].reason, 0b0101);
        assert_eq!(out.wakes()[1].reason, 0b1010);
        assert_eq!(out.merged_on_overflow, 2);
        for v in 0..3 {
            out.push_event(Event {
                kind: EventKind::Brownout,
                key: 7,
                value: v as f32,
                extra: 0,
                generation: 0,
            });
        }
        assert_eq!(out.events().len(), 1);
        assert_eq!(out.events()[0].value, 2.0, "latest wins");
    }

    #[test]
    fn an_unread_batch_is_merged_not_replaced() {
        let slot = OutboxSlot::<u8>::default();
        let mut a = Outbox::default();
        a.stamp(1);
        a.push_take(TakeResult {
            seq: Seq(1),
            cell: 0,
            value: 5,
        });
        slot.publish(a);
        let mut b = Outbox::default();
        b.stamp(2);
        b.push_wake(wake(3, 1, 0));
        slot.publish(b);
        let got = slot.collect().unwrap();
        assert_eq!(got.frames, Some((1, 2)));
        assert_eq!(got.takes().len(), 1);
        assert_eq!(got.wakes().len(), 1);
        assert!(slot.collect().is_none());
    }

    #[test]
    fn flat_encodings_have_fixed_strides() {
        let mut out = Outbox::<()>::default();
        out.push_wake(wake(9, 3, 0));
        out.push_event(Event {
            kind: EventKind::Melt,
            key: 4,
            value: 1.5,
            extra: 2,
            generation: 1,
        });
        let mut flat = Vec::new();
        out.wakes_flat(&mut flat);
        assert_eq!(flat, [9.0, 1.0, 3.0, 90.0]);
        flat.clear();
        out.events_flat(&mut flat);
        assert_eq!(flat, [5.0, 4.0, 1.5, 2.0, 1.0]);
    }
}
