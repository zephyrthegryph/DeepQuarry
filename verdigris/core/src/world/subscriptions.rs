//! DM subscriptions on the world (`rust_architecture.md` §8.5 step 7): the
//! reactor's timers, DM-owned keys and rate models, with every
//! subscription and every rate model an ordinary world entity
//! ([`World::spawn`]/[`World::despawn`]) instead of a private token slab.
//!
//! A subscription entity has no components; its record says what it holds.
//! Watches are registered by the caller on a watch port (a component kind,
//! a field) and recorded here only so cancelling the entity (or clearing
//! its subscriber) returns them to the caller to unregister.

use std::collections::HashMap;

use super::{World, WorldError};
use crate::entity::EntityId;
use crate::outbox::{Lane, Subscriber, Wake, WatchId, reason};
use crate::rate::RateModel;
use crate::reactor::{ModelId, Reactor, ReactorMetrics};
use crate::timer::Tick;
use crate::watch::Cmp;

/// What one subscription entity holds.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Subscription {
    /// A watch on a rate model.
    Rate { model: ModelId, token: u32 },
    /// A watch on port `port` of watchable `code` (the caller's).
    Watch { code: u32, port: u8, id: WatchId },
    /// A rate model itself (owned by no subscriber).
    Model(ModelId),
}

/// The world's DM scheduler state.
pub struct Subscriptions {
    reactor: Reactor,
    records: HashMap<u32, (EntityId, Subscriber, Subscription)>,
    by_sub: HashMap<Subscriber, Vec<EntityId>>,
    /// Rate model index -> its entity.
    models: HashMap<u32, EntityId>,
}

impl Default for Subscriptions {
    fn default() -> Self {
        Self {
            reactor: Reactor::new(0),
            records: HashMap::new(),
            by_sub: HashMap::new(),
            models: HashMap::new(),
        }
    }
}

impl World {
    fn record(&mut self, sub: Subscriber, what: Subscription) -> Result<EntityId, WorldError> {
        let e = self.spawn()?;
        self.subs.records.insert(e.index(), (e, sub, what));
        if sub != 0 {
            self.subs.by_sub.entry(sub).or_default().push(e);
        }
        Ok(e)
    }

    fn sub_record(&self, e: EntityId) -> Option<(Subscriber, Subscription)> {
        let &(id, sub, what) = self.subs.records.get(&e.index())?;
        (id == e).then_some((sub, what))
    }

    fn forget(&mut self, e: EntityId) -> Option<(Subscriber, Subscription)> {
        let (sub, what) = self.sub_record(e)?;
        self.subs.records.remove(&e.index());
        if let Some(list) = self.subs.by_sub.get_mut(&sub) {
            list.retain(|&x| x != e);
            if list.is_empty() {
                self.subs.by_sub.remove(&sub);
            }
        }
        let _ = self.despawn(e);
        Some((sub, what))
    }

    /// The DM tick the scheduler is at.
    #[must_use]
    pub const fn sched_now(&self) -> Tick {
        self.subs.reactor.now()
    }

    /// Scheduler counters.
    #[must_use]
    pub fn sched_metrics(&self) -> ReactorMetrics {
        self.subs.reactor.metrics()
    }

    /// `(received, merged, delivered, deferred, backlog)` of the wake lanes.
    #[must_use]
    pub fn sched_lanes(&self) -> (u64, u64, u64, u64, [usize; 3]) {
        let l = self.subs.reactor.lanes();
        (l.received, l.merged, l.delivered, l.deferred, l.backlog())
    }

    /// Live subscriptions: all of them, or `sub`'s.
    #[must_use]
    pub fn subscriptions(&self, sub: Option<Subscriber>) -> usize {
        match sub {
            Some(s) => self.subs.by_sub.get(&s).map_or(0, Vec::len),
            None => self.subs.records.values().filter(|r| r.1 != 0).count(),
        }
    }

    /// Records a watch the caller registered on its own port, so cancelling
    /// the entity (or clearing `sub`) hands it back.
    ///
    /// # Errors
    /// The entity table is full.
    pub fn sched_watch(
        &mut self,
        sub: Subscriber,
        code: u32,
        port: u8,
        id: WatchId,
    ) -> Result<EntityId, WorldError> {
        self.record(sub, Subscription::Watch { code, port, id })
    }

    /// The watch a subscription entity holds: `(code, port, id)`.
    #[must_use]
    pub fn sched_watch_of(&self, e: EntityId) -> Option<(u32, u8, WatchId)> {
        match self.sub_record(e)? {
            (_, Subscription::Watch { code, port, id }) => Some((code, port, id)),
            _ => None,
        }
    }

    /// Adds a rate model (times in ticks); the entity names it.
    ///
    /// # Errors
    /// The entity table is full.
    pub fn rate_add(&mut self, model: RateModel) -> Result<EntityId, WorldError> {
        let id = self.subs.reactor.add_model(model);
        let e = self.record(0, Subscription::Model(id))?;
        self.subs.models.insert(id.index, e);
        Ok(e)
    }

    fn model_of(&self, e: EntityId) -> Option<ModelId> {
        match self.sub_record(e)? {
            (_, Subscription::Model(id)) => Some(id),
            _ => None,
        }
    }

    /// The model's value now, `None` for a stale model.
    #[must_use]
    pub fn rate_read(&self, e: EntityId) -> Option<f64> {
        self.subs.reactor.read(self.model_of(e)?)
    }

    /// Changes a model; `false` for a stale one.
    pub fn rate_update(&mut self, e: EntityId, change: impl FnOnce(&mut RateModel)) -> bool {
        self.model_of(e)
            .is_some_and(|id| self.subs.reactor.update_model(id, change))
    }

    /// Wakes `sub` whenever the model enters `cmp level`, at the exact
    /// predicted crossing tick (at once if it already holds).
    ///
    /// # Errors
    /// A stale model or a non-finite level (`NoKind(0)`), or a full table.
    pub fn rate_watch(
        &mut self,
        e: EntityId,
        sub: Subscriber,
        lane: Lane,
        cmp: Cmp,
        level: f64,
    ) -> Result<EntityId, WorldError> {
        let model = self.model_of(e).ok_or(WorldError::NoKind(0))?;
        let token = self
            .subs
            .reactor
            .watch_model(model, sub, lane, cmp, level)
            .ok_or(WorldError::NoKind(0))?;
        self.record(sub, Subscription::Rate { model, token })
    }

    /// Removes a model and its watches; `false` if it was stale.
    pub fn rate_remove(&mut self, e: EntityId) -> bool {
        let Some(id) = self.model_of(e) else {
            return false;
        };
        let watches: Vec<EntityId> = self
            .subs
            .records
            .values()
            .filter(|r| matches!(r.2, Subscription::Rate { model, .. } if model == id))
            .map(|r| r.0)
            .collect();
        for w in watches {
            self.forget(w);
        }
        self.subs.models.remove(&id.index);
        self.forget(e);
        self.subs.reactor.remove_model(id)
    }

    /// Cancels one subscription. Returns it (a watch is the caller's to
    /// unregister), or `None` if it was stale.
    pub fn unsubscribe(&mut self, e: EntityId) -> Option<Subscription> {
        let (sub, what) = self.sub_record(e)?;
        match what {
            Subscription::Rate { model, token } => {
                self.subs.reactor.unwatch_model(model, token);
            }
            Subscription::Model(_) => {
                self.rate_remove(e);
                return Some(what);
            }
            Subscription::Watch { .. } => {}
        }
        self.forget(e);
        Some(what)
    }

    /// Drops every subscription and pending wake of `sub`. Returns its
    /// watches for the caller to unregister.
    pub fn clear_subscriber(&mut self, sub: Subscriber) -> Vec<Subscription> {
        let mut watches = Vec::new();
        for e in self.subs.by_sub.remove(&sub).unwrap_or_default() {
            if let Some((_, what)) = self.sub_record(e) {
                if matches!(what, Subscription::Watch { .. }) {
                    watches.push(what);
                }
                self.subs.records.remove(&e.index());
                let _ = self.despawn(e);
            }
        }
        self.subs.reactor.clear(sub);
        watches
    }

    /// One DM tick at `now`: fires due rate crossings, takes `watch_wakes`, and returns up to `budget`
    /// normal/background wakes (urgent ones always), each with the source
    /// DM knows: a rate wake's model entity, a watch's cell.
    pub fn sched_step(
        &mut self,
        now: Tick,
        budget: usize,
        watch_wakes: &[Wake],
    ) -> Vec<(Wake, Option<EntityId>)> {
        self.subs.reactor.tick(now);
        self.subs.reactor.ingest(watch_wakes);
        let mut out = Vec::new();
        self.subs.reactor.drain(budget, &mut out);
        out.into_iter()
            .map(|w| {
                let e = if w.reason & reason::RATE != 0 {
                    self.subs.models.get(&w.source).copied()
                } else {
                    None
                };
                (w, e)
            })
            .collect()
    }
}
