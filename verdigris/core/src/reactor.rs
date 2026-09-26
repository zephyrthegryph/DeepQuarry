//! The main-side reactor (`rust_core.md` §7, `reactor.md`): the timer wheel,
//! wake lanes, rate models and DM-owned keys. Everything here is plain
//! main-thread data with no locks; SSreactor (S1) drives it once per tick:
//!
//! ```text
//! sim.begin_tick();
//! for each domain: reactor.ingest(sim.drain(domain).wakes());
//! reactor.tick(world.time);          // timers, rate crossings, key publications
//! reactor.drain(budget, &mut wakes); // urgent first, then normal and background
//! for each wake: subscriber.react(reason, source)
//! ```
//!
//! S1 binds this through `#[auxmacros::bind]`, roughly (subscribers are the
//! DM-side registry index; timer ids, model ids and tokens cross as exact
//! `f32`s):
//!
//! ```text
//! vg_react_at(subscriber, lane, tick, token)                -> timer id     REACT_AT
//! vg_react_cancel_timer(timer)                                               REACT_CANCEL
//! vg_react_publish(key, mask)                                                REACT_PUBLISH
//! vg_react_on_key(subscriber, key, mask, lane)                               REACT_ON_KEY
//! vg_react_clear(subscriber)                                                 REACT_CLEAR
//! vg_rate_linear(v0, rate, min, max)                        -> model id
//! vg_rate_relax(v0, target, k)                              -> model id
//! vg_rate_sum(v0, min, max)                                 -> model id
//! vg_rate_set_term(model, key, rate) / vg_rate_set_rate(model, rate) / vg_rate_set(model, value)
//! vg_rate_read(model)                                       -> value now
//! vg_rate_watch(model, subscriber, lane, cmp, level)        -> token
//! vg_react_tick(now) ; vg_react_drain(budget)              -> flat [subscriber, lane, reason, source] list
//! ```

use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::hash::BuildHasherDefault;

use crate::overlay::{CellHasher, CellMap};

use crate::outbox::{Lane, Subscriber, Wake, WatchId, reason};
use crate::rate::RateModel;
use crate::timer::{Tick, TimerId, TimerWheel};
use crate::watch::Cmp;

// --- Wake lanes ------------------------------------------------------------

#[derive(Clone, Copy, Debug)]
struct Pending {
    reason: u32,
    source: u32,
}

#[derive(Debug, Default)]
struct LaneQueue {
    pending: CellMap<Pending>,
    order: VecDeque<Subscriber>,
    delivered: HashSet<Subscriber, BuildHasherDefault<CellHasher>>,
}

impl LaneQueue {
    fn push(&mut self, sub: Subscriber, reason: u32, source: u32) -> bool {
        match self.pending.get_mut(&sub) {
            Some(p) => {
                p.reason |= reason;
                false
            }
            None => {
                self.pending.insert(sub, Pending { reason, source });
                self.order.push_back(sub);
                true
            }
        }
    }

    /// Delivers up to `budget` subscribers not yet woken this tick.
    fn drain(
        &mut self,
        lane: Lane,
        budget: usize,
        out: &mut Vec<Wake>,
        deferred: &mut u64,
    ) -> usize {
        let mut delivered = 0;
        let mut skipped = Vec::new();
        while delivered < budget {
            let Some(sub) = self.order.pop_front() else {
                break;
            };
            let Some(p) = self.pending.get(&sub).copied() else {
                continue; // cleared
            };
            if self.delivered.contains(&sub) {
                skipped.push(sub);
                *deferred += 1;
                continue;
            }
            self.pending.remove(&sub);
            self.delivered.insert(sub);
            out.push(Wake {
                subscriber: sub,
                lane,
                reason: p.reason,
                source: p.source,
                watch: WatchId::NONE,
            });
            delivered += 1;
        }
        for sub in skipped.into_iter().rev() {
            self.order.push_front(sub);
        }
        delivered
    }

    fn len(&self) -> usize {
        self.pending.len()
    }
}

/// Wake lanes (§7): each subscriber appears at most once per lane, with its
/// reasons merged, and is delivered at most once per lane per tick
/// (`reactor.md` §1). A wake for a subscriber already delivered this tick
/// waits for the next tick, merged with anything else that arrives.
#[derive(Debug, Default)]
pub struct WakeLanes {
    lanes: [LaneQueue; 3],
    /// Wakes received and merged into an already-pending entry.
    pub merged: u64,
    pub received: u64,
    pub delivered: u64,
    /// Pops skipped because the subscriber was already woken this tick.
    pub deferred: u64,
}

/// The share of the budget reserved for the background lane when it has
/// work, so it never starves behind a busy normal lane.
pub const BACKGROUND_SHARE: usize = 8;

impl WakeLanes {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, sub: Subscriber, lane: Lane, reason: u32, source: u32) {
        self.received += 1;
        if !self.lanes[lane.index()].push(sub, reason, source) {
            self.merged += 1;
        }
    }

    /// Queues a wake from an outbox.
    pub fn push_wake(&mut self, w: &Wake) {
        self.push(w.subscriber, w.lane, w.reason, w.source);
    }

    /// Starts a new tick: every subscriber may be woken once more per lane.
    pub fn begin_tick(&mut self) {
        for l in &mut self.lanes {
            l.delivered.clear();
        }
    }

    /// Delivers wakes for this tick into `out`. The urgent lane drains in
    /// full; the normal and background lanes share `budget`, with at least
    /// `budget / BACKGROUND_SHARE` (and at least one) reserved for
    /// background when it has work. Anything left waits for the next drain.
    pub fn drain(&mut self, budget: usize, out: &mut Vec<Wake>) {
        let start = out.len();
        let mut deferred = 0;
        self.lanes[0].drain(Lane::Urgent, usize::MAX, out, &mut deferred);
        let reserve = if self.lanes[2].len() > 0 {
            (budget / BACKGROUND_SHARE).max(1).min(budget)
        } else {
            0
        };
        let normal = self.lanes[1].drain(Lane::Normal, budget - reserve, out, &mut deferred);
        self.lanes[2].drain(Lane::Background, budget - normal, out, &mut deferred);
        self.deferred += deferred;
        self.delivered += (out.len() - start) as u64;
    }

    /// Drops every pending wake of `sub` (`REACT_CLEAR`).
    pub fn clear(&mut self, sub: Subscriber) {
        for l in &mut self.lanes {
            l.pending.remove(&sub);
        }
    }

    /// Pending subscribers per lane.
    #[must_use]
    pub fn backlog(&self) -> [usize; 3] {
        [
            self.lanes[0].len(),
            self.lanes[1].len(),
            self.lanes[2].len(),
        ]
    }
}

// --- Rate models ------------------------------------------------------------
//
// RateModel itself moved to `core::rate` (`rust_architecture.md` §4.10);
// callers use `vg_core::rate::RateModel` directly (see `use` below and
// `vg_ffi::reactor`'s own imports) -- no re-export shim.

/// A rate model, as index plus generation.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct ModelId {
    pub index: u32,
    pub generation: u32,
}

#[derive(Clone, Debug)]
struct RateWatch {
    token: u32,
    subscriber: Subscriber,
    lane: Lane,
    cmp: Cmp,
    level: f64,
    inside: bool,
    timer: Option<TimerId>,
}

impl RateWatch {
    fn holds(&self, v: f64) -> bool {
        match self.cmp {
            Cmp::Above => v >= self.level,
            Cmp::Below => v <= self.level,
        }
    }
}

#[derive(Clone, Debug)]
struct ModelSlot {
    model: RateModel,
    generation: u32,
    alive: bool,
    watches: Vec<RateWatch>,
}

/// Something the wheel holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Due {
    /// A `REACT_AT` timer.
    Timer {
        subscriber: Subscriber,
        lane: Lane,
        token: u32,
    },
    /// A rate model's predicted crossing.
    Crossing { model: ModelId, token: u32 },
}

// --- DM-owned keys --------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct KeySub {
    subscriber: Subscriber,
    mask: u32,
    lane: Lane,
}

/// Mask bits a key publication may carry (below the reason class flags).
pub const KEY_MASK: u32 = (1 << 20) - 1;

// --- The reactor ------------------------------------------------------------

/// Reactor counters (`reactor.md` §7). Bounded: no per-type tables here.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ReactorMetrics {
    pub timers_fired: u64,
    pub crossings_fired: u64,
    pub publications: u64,
    pub timers_pending: usize,
    pub models: usize,
}

/// A handle DM keeps to cancel one subscription.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Token {
    Timer(TimerId),
    Key { key: u64 },
    Rate { model: ModelId, token: u32 },
}

/// The main-thread reactor.
pub struct Reactor {
    wheel: TimerWheel<Due>,
    lanes: WakeLanes,
    models: Vec<ModelSlot>,
    free_models: Vec<u32>,
    next_token: u32,
    key_subs: HashMap<u64, Vec<KeySub>>,
    published: BTreeMap<u64, u32>,
    by_subscriber: HashMap<Subscriber, Vec<Token>>,
    metrics: ReactorMetrics,
    fired: Vec<(TimerId, Due)>,
    fired_timers: Vec<(Subscriber, u32)>,
}

impl Reactor {
    #[must_use]
    pub fn new(now: Tick) -> Self {
        Self {
            wheel: TimerWheel::new(now),
            lanes: WakeLanes::new(),
            models: Vec::new(),
            free_models: Vec::new(),
            next_token: 1,
            key_subs: HashMap::new(),
            published: BTreeMap::new(),
            by_subscriber: HashMap::new(),
            metrics: ReactorMetrics::default(),
            fired: Vec::new(),
            fired_timers: Vec::new(),
        }
    }

    #[must_use]
    pub const fn now(&self) -> Tick {
        self.wheel.now()
    }

    #[must_use]
    pub fn metrics(&self) -> ReactorMetrics {
        ReactorMetrics {
            timers_pending: self.wheel.len(),
            models: self.models.iter().filter(|m| m.alive).count(),
            ..self.metrics
        }
    }

    #[must_use]
    pub const fn lanes(&self) -> &WakeLanes {
        &self.lanes
    }

    fn own(&mut self, sub: Subscriber, token: Token) {
        let owned = self.by_subscriber.entry(sub).or_default();
        if !owned.contains(&token) {
            owned.push(token);
        }
    }

    /// Forgets one owned token, so a long-lived subscriber's bookkeeping
    /// stays bounded by its live subscriptions (not by every timer it ever
    /// set).
    fn disown(&mut self, sub: Subscriber, token: Token) {
        if let Some(owned) = self.by_subscriber.get_mut(&sub) {
            if let Some(i) = owned.iter().position(|t| *t == token) {
                owned.swap_remove(i);
            }
            if owned.is_empty() {
                self.by_subscriber.remove(&sub);
            }
        }
    }

    /// Live subscriptions (timers, key subscriptions, model watches) that
    /// `sub` owns.
    #[must_use]
    pub fn owned(&self, sub: Subscriber) -> usize {
        self.by_subscriber.get(&sub).map_or(0, Vec::len)
    }

    /// Subscribers that own at least one live subscription.
    #[must_use]
    pub fn subscribers(&self) -> usize {
        self.by_subscriber.len()
    }

    /// Timers that fired since the last call, as `(subscriber, token)`, so a
    /// host that maps tokens to its own handles can release them.
    pub fn take_fired_timers(&mut self, out: &mut Vec<(Subscriber, u32)>) {
        out.append(&mut self.fired_timers);
    }

    /// Queues watch wakes drained from a domain outbox.
    pub fn ingest(&mut self, wakes: &[Wake]) {
        for w in wakes {
            self.lanes.push_wake(w);
        }
    }

    /// `REACT_AT`: wakes `subscriber` at tick `at` with reason `TIMER` and
    /// source `token`.
    pub fn at(&mut self, subscriber: Subscriber, lane: Lane, at: Tick, token: u32) -> TimerId {
        let id = self.wheel.insert(
            at,
            Due::Timer {
                subscriber,
                lane,
                token,
            },
        );
        self.own(subscriber, Token::Timer(id));
        id
    }

    /// Cancels a timer; `false` if it already fired or was cancelled.
    pub fn cancel_timer(&mut self, id: TimerId) -> bool {
        match self.wheel.cancel(id) {
            Some(Due::Timer { subscriber, .. }) => {
                self.disown(subscriber, Token::Timer(id));
                true
            }
            Some(_) => true,
            None => false,
        }
    }

    /// `REACT_ON_KEY`.
    pub fn subscribe_key(&mut self, subscriber: Subscriber, key: u64, mask: u32, lane: Lane) {
        let subs = self.key_subs.entry(key).or_default();
        match subs
            .iter_mut()
            .find(|s| s.subscriber == subscriber && s.lane == lane)
        {
            Some(s) => s.mask |= mask & KEY_MASK,
            None => subs.push(KeySub {
                subscriber,
                mask: mask & KEY_MASK,
                lane,
            }),
        }
        self.own(subscriber, Token::Key { key });
    }

    /// Drops `subscriber`'s subscriptions to `key`.
    pub fn unsubscribe_key(&mut self, subscriber: Subscriber, key: u64) {
        if let Some(subs) = self.key_subs.get_mut(&key) {
            subs.retain(|s| s.subscriber != subscriber);
            if subs.is_empty() {
                self.key_subs.remove(&key);
            }
        }
        self.disown(subscriber, Token::Key { key });
    }

    /// Keys with at least one subscriber.
    #[must_use]
    pub fn keys(&self) -> usize {
        self.key_subs.len()
    }

    /// `REACT_PUBLISH`: DM-owned state under `key` changed. Merged per tick
    /// and dispatched at [`tick`](Self::tick); a key nobody subscribes to is
    /// never stored.
    pub fn publish(&mut self, key: u64, mask: u32) {
        if self.key_subs.contains_key(&key) {
            *self.published.entry(key).or_default() |= mask & KEY_MASK;
        }
    }

    // --- rate models

    /// Adds a rate model (times are ticks).
    pub fn add_model(&mut self, model: RateModel) -> ModelId {
        if let Some(index) = self.free_models.pop() {
            let slot = &mut self.models[index as usize];
            slot.model = model;
            slot.alive = true;
            return ModelId {
                index,
                generation: slot.generation,
            };
        }
        let index = u32::try_from(self.models.len()).expect("model count fits u32");
        self.models.push(ModelSlot {
            model,
            generation: 0,
            alive: true,
            watches: Vec::new(),
        });
        ModelId {
            index,
            generation: 0,
        }
    }

    fn slot(&self, id: ModelId) -> Option<&ModelSlot> {
        self.models
            .get(id.index as usize)
            .filter(|m| m.alive && m.generation == id.generation)
    }

    fn slot_mut(&mut self, id: ModelId) -> Option<&mut ModelSlot> {
        self.models
            .get_mut(id.index as usize)
            .filter(|m| m.alive && m.generation == id.generation)
    }

    /// The model's value now.
    #[must_use]
    #[allow(clippy::cast_precision_loss)]
    pub fn read(&self, id: ModelId) -> Option<f64> {
        let now = self.now() as f64;
        self.slot(id).map(|m| m.model.value_at(now))
    }

    #[must_use]
    pub fn model(&self, id: ModelId) -> Option<&RateModel> {
        self.slot(id).map(|m| &m.model)
    }

    /// Changes a model's inputs: it is rebased at the current tick (so it
    /// continues from its current value), `change` edits it, and every
    /// crossing watch on it is re-evaluated and re-scheduled.
    ///
    /// Returns `false` for a stale id.
    #[allow(clippy::cast_precision_loss)]
    pub fn update_model(&mut self, id: ModelId, change: impl FnOnce(&mut RateModel)) -> bool {
        let now = self.now() as f64;
        let Some(slot) = self.slot_mut(id) else {
            return false;
        };
        slot.model.rebase(now);
        change(&mut slot.model);
        for i in 0..self.slot(id).map_or(0, |s| s.watches.len()) {
            self.rearm(id, i, true);
        }
        true
    }

    /// Removes a model and its watches.
    pub fn remove_model(&mut self, id: ModelId) -> bool {
        let Some(slot) = self.slot_mut(id) else {
            return false;
        };
        slot.alive = false;
        slot.generation = slot.generation.wrapping_add(1);
        let watches: Vec<RateWatch> = slot.watches.drain(..).collect();
        for w in watches {
            if let Some(t) = w.timer {
                self.wheel.cancel(t);
            }
            self.disown(
                w.subscriber,
                Token::Rate {
                    model: id,
                    token: w.token,
                },
            );
        }
        self.free_models.push(id.index);
        true
    }

    /// Watches a model for entering `cmp level` (`Above`: `v >= level`).
    /// Fires at once if that already holds, then at each exact predicted
    /// crossing into it, scheduled on the wheel: nothing polls. Returns the
    /// watch token, or `None` for a stale model or non-finite level.
    pub fn watch_model(
        &mut self,
        id: ModelId,
        subscriber: Subscriber,
        lane: Lane,
        cmp: Cmp,
        level: f64,
    ) -> Option<u32> {
        if !level.is_finite() {
            return None;
        }
        let token = self.next_token;
        self.next_token = self.next_token.wrapping_add(1).max(1);
        let slot = self.slot_mut(id)?;
        slot.watches.push(RateWatch {
            token,
            subscriber,
            lane,
            cmp,
            level,
            inside: false,
            timer: None,
        });
        let i = slot.watches.len() - 1;
        self.rearm(id, i, true);
        self.own(subscriber, Token::Rate { model: id, token });
        Some(token)
    }

    /// Drops one model watch.
    pub fn unwatch_model(&mut self, id: ModelId, token: u32) -> bool {
        let Some(slot) = self.slot_mut(id) else {
            return false;
        };
        let Some(i) = slot.watches.iter().position(|w| w.token == token) else {
            return false;
        };
        let w = slot.watches.swap_remove(i);
        if let Some(t) = w.timer {
            self.wheel.cancel(t);
        }
        self.disown(w.subscriber, Token::Rate { model: id, token });
        true
    }

    /// Re-evaluates watch `i` of `id` at the current tick: fires if it just
    /// entered, then schedules its next crossing (in either direction).
    #[allow(
        clippy::cast_precision_loss,
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss
    )]
    fn rearm(&mut self, id: ModelId, i: usize, may_fire: bool) {
        let now = self.now();
        let nowf = now as f64;
        let (wake, next, old_timer, token) = {
            let slot = self.slot_mut(id).expect("live model");
            let v = slot.model.value_at(nowf);
            let model = slot.model.clone();
            let w = &mut slot.watches[i];
            let holds = w.holds(v);
            let wake = (may_fire && holds && !w.inside).then_some((w.subscriber, w.lane));
            w.inside = holds;
            (wake, model.crossing(w.level, nowf), w.timer.take(), w.token)
        };
        if let Some(t) = old_timer {
            self.wheel.cancel(t);
        }
        if let Some((sub, lane)) = wake {
            self.metrics.crossings_fired += 1;
            self.lanes.push(sub, lane, reason::RATE, id.index);
        }
        if let Some(t) = next {
            // The first tick at which the value has crossed.
            let tick = (t.ceil().max(nowf + 1.0)) as Tick;
            let timer = self.wheel.insert(tick, Due::Crossing { model: id, token });
            self.slot_mut(id).expect("live model").watches[i].timer = Some(timer);
        }
    }

    /// `REACT_CLEAR`: drops every timer, key subscription, model watch and
    /// pending wake of `subscriber`.
    pub fn clear(&mut self, subscriber: Subscriber) {
        for token in self.by_subscriber.remove(&subscriber).unwrap_or_default() {
            match token {
                Token::Timer(id) => {
                    self.wheel.cancel(id);
                }
                Token::Key { key } => self.unsubscribe_key(subscriber, key),
                Token::Rate { model, token } => {
                    self.unwatch_model(model, token);
                }
            }
        }
        self.lanes.clear(subscriber);
    }

    /// Start of a DM tick at `now`: fires due timers and rate crossings,
    /// dispatches this tick's key publications, and opens the lanes for a
    /// new round of deliveries.
    #[allow(clippy::cast_possible_truncation)]
    pub fn tick(&mut self, now: Tick) {
        self.lanes.begin_tick();
        let mut fired = std::mem::take(&mut self.fired);
        self.wheel.advance(now, &mut fired);
        for (id, due) in fired.drain(..) {
            match due {
                Due::Timer {
                    subscriber,
                    lane,
                    token,
                } => {
                    self.metrics.timers_fired += 1;
                    self.disown(subscriber, Token::Timer(id));
                    self.fired_timers.push((subscriber, token));
                    self.lanes.push(subscriber, lane, reason::TIMER, token);
                }
                Due::Crossing { model, token } => {
                    let i = self
                        .slot(model)
                        .and_then(|s| s.watches.iter().position(|w| w.token == token));
                    if let Some(i) = i {
                        self.slot_mut(model).expect("live").watches[i].timer = None;
                        self.rearm(model, i, true);
                    }
                }
            }
        }
        self.fired = fired;
        for (key, mask) in std::mem::take(&mut self.published) {
            self.metrics.publications += 1;
            if let Some(subs) = self.key_subs.get(&key) {
                for s in subs {
                    if s.mask & mask != 0 {
                        self.lanes.push(
                            s.subscriber,
                            s.lane,
                            reason::KEY | (s.mask & mask),
                            key as u32,
                        );
                    }
                }
            }
        }
    }

    /// Delivers this tick's wakes within `budget` (see [`WakeLanes::drain`]).
    pub fn drain(&mut self, budget: usize, out: &mut Vec<Wake>) {
        self.lanes.drain(budget, out);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn owned_tokens_stay_bounded_by_live_subscriptions() {
        let mut r = Reactor::new(0);
        for round in 0..100u64 {
            let t = r.at(9, Lane::Normal, round + 1, 1);
            if round % 2 == 0 {
                assert!(r.cancel_timer(t));
            }
            r.subscribe_key(9, 5, 1, Lane::Normal);
            r.tick(round + 1);
            let mut fired = Vec::new();
            r.take_fired_timers(&mut fired);
            assert_eq!(fired.len(), usize::from(round % 2 == 1));
        }
        // One key subscription, no timers left.
        assert_eq!(r.owned(9), 1);
        r.unsubscribe_key(9, 5);
        assert_eq!(r.owned(9), 0);
        assert_eq!(r.subscribers(), 0);
        let m = r.add_model(RateModel::linear(0.0, 1.0, 0.0));
        let tok = r
            .watch_model(m, 9, Lane::Normal, Cmp::Above, 1000.0)
            .unwrap();
        assert_eq!(r.owned(9), 1);
        assert!(r.unwatch_model(m, tok));
        assert_eq!(r.owned(9), 0);
    }

    #[test]
    fn lanes_merge_per_subscriber_and_deliver_once_per_tick() {
        let mut lanes = WakeLanes::new();
        lanes.push(1, Lane::Normal, 0b01, 7);
        lanes.push(1, Lane::Normal, 0b10, 8);
        lanes.push(1, Lane::Urgent, 0b100, 9);
        let mut out = Vec::new();
        lanes.drain(10, &mut out);
        assert_eq!(out.len(), 2, "once per lane");
        assert_eq!((out[0].lane, out[0].reason), (Lane::Urgent, 0b100));
        assert_eq!(
            (out[1].lane, out[1].reason, out[1].source),
            (Lane::Normal, 0b11, 7)
        );
        // Woken again in the same tick: held for the next tick.
        lanes.push(1, Lane::Normal, 0b1000, 1);
        out.clear();
        lanes.drain(10, &mut out);
        assert!(out.is_empty());
        lanes.begin_tick();
        lanes.drain(10, &mut out);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].reason, 0b1000);
    }

    #[test]
    fn budget_keeps_urgent_whole_and_background_alive() {
        let mut lanes = WakeLanes::new();
        for s in 0..50 {
            lanes.push(s, Lane::Urgent, 1, 0);
            lanes.push(100 + s, Lane::Normal, 1, 0);
            lanes.push(200 + s, Lane::Background, 1, 0);
        }
        let mut out = Vec::new();
        lanes.drain(16, &mut out);
        let count = |l| out.iter().filter(|w| w.lane == l).count();
        assert_eq!(count(Lane::Urgent), 50);
        assert_eq!(count(Lane::Normal), 14);
        assert_eq!(count(Lane::Background), 2);
        assert_eq!(lanes.backlog(), [0, 36, 48]);
        // FIFO: the next tick continues where this one stopped.
        lanes.begin_tick();
        out.clear();
        lanes.drain(16, &mut out);
        assert_eq!(out[0].subscriber, 114);
    }

    // RateModel's own tests (linear/relax/sum value_at/crossing/rebase) moved
    // to core::rate with the type itself; rate_watches_fire_at_the_predicted_
    // tick_without_polling below still covers the Reactor+RateModel integration.

    fn drained(r: &mut Reactor) -> Vec<Wake> {
        let mut out = Vec::new();
        r.drain(usize::MAX / 2, &mut out);
        out
    }

    #[test]
    fn rate_watches_fire_at_the_predicted_tick_without_polling() {
        let mut r = Reactor::new(0);
        // A charge falling 0.5 per tick from 100: below 20 at tick 160.
        let m = r.add_model(RateModel::linear(100.0, -0.5, 0.0));
        r.watch_model(m, 5, Lane::Normal, Cmp::Below, 20.0).unwrap();
        assert_eq!(
            r.metrics().timers_pending,
            1,
            "one scheduled crossing, no polling"
        );
        r.tick(159);
        assert!(drained(&mut r).is_empty());
        r.tick(160);
        let w = drained(&mut r);
        assert_eq!(w.len(), 1);
        assert_eq!((w[0].subscriber, w[0].reason), (5, reason::RATE));
        // Recharge: the input changes, the model rebases from its current
        // value (20) and the watch re-arms for the next fall.
        r.tick(170);
        assert!(r.update_model(m, |model| {
            if let RateModel::Linear { rate, .. } = model {
                *rate = 1.0;
            }
        }));
        assert_eq!(r.read(m), Some(15.0));
        r.tick(180);
        assert_eq!(r.read(m), Some(25.0));
        assert!(drained(&mut r).is_empty(), "leaving does not wake");
        r.update_model(m, |model| {
            if let RateModel::Linear { rate, .. } = model {
                *rate = -1.0;
            }
        });
        r.tick(184);
        assert!(drained(&mut r).is_empty());
        r.tick(185);
        assert_eq!(drained(&mut r).len(), 1, "fires again on re-entering");
    }

    #[test]
    fn timers_keys_and_clear() {
        let mut r = Reactor::new(0);
        let t = r.at(1, Lane::Urgent, 10, 42);
        r.at(2, Lane::Normal, 10, 43);
        r.subscribe_key(3, 0xABCD, 0b11, Lane::Normal);
        r.publish(0xABCD, 0b10);
        r.publish(0xABCD, 0b100);
        r.publish(0x9999, 1); // nobody listens: not stored
        r.tick(1);
        let w = drained(&mut r);
        assert_eq!(w.len(), 1);
        assert_eq!(w[0].reason, reason::KEY | 0b10);
        assert!(r.cancel_timer(t));
        r.clear(2);
        r.tick(10);
        assert!(drained(&mut r).is_empty());
        r.publish(0xABCD, 1);
        r.clear(3);
        r.tick(11);
        assert!(drained(&mut r).is_empty());
        assert_eq!(r.metrics().timers_fired, 0);
    }

    proptest! {
        /// Predicted linear and relaxation crossings land on the first tick
        /// at which a per-tick sampler sees the crossing.
        #[test]
        fn crossing_tick_matches_sampling(
            v0 in -1000.0f64..1000.0,
            rate in prop_oneof![-10.0f64..-0.01, 0.01f64..10.0],
            k in 0.001f64..0.5,
            target in -1000.0f64..1000.0,
            level in -1000.0f64..1000.0,
            relax in any::<bool>(),
        ) {
            let m = if relax {
                RateModel::Relax { target, v0, k, t0: 0.0 }
            } else {
                RateModel::linear(v0, rate, 0.0)
            };
            let start = m.value_at(0.0);
            let above = start < level;
            #[allow(clippy::cast_precision_loss)]
            let sampled = (1..20_000u32).map(f64::from).find(|&t| {
                let v = m.value_at(t);
                if above { v >= level } else { v <= level }
            });
            let predicted = m.crossing(level, 0.0).map(f64::ceil);
            match (predicted, sampled) {
                (Some(p), Some(s)) => {
                    // Rounding may put the exact crossing a hair either side
                    // of an integer tick.
                    prop_assert!((p - s).abs() <= 1.0, "predicted {p}, sampled {s}");
                }
                (None, Some(s)) => prop_assert!(false, "missed a crossing at {s}"),
                (Some(p), None) => prop_assert!(p >= 19_999.0, "phantom crossing at {p}"),
                (None, None) => {}
            }
        }
    }
}
