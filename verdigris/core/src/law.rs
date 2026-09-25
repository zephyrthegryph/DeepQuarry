//! Laws (`doc/rewrite/rust_architecture.md` §4.3): the only simulation code a
//! domain writes.
//!
//! A law is a pure step over the row, region, device or singleton it is
//! anchored on: [`Law::step`] gets a [`LawCtx`] holding that item's declared
//! `Reads` and `Writes` plus the side channels ([`Effects`]) every law uses
//! instead of returning `Vec<f32>` or touching globals: typed events,
//! wakes, timers and conservation sources/sinks.
//!
//! A law is written and tested as a plain function over plain values
//! (`LawCtx::new(&reads, &mut writes, &mut effects)`); nothing here needs a
//! world. [`crate::world::WorldBuilder::add_law`] is what runs it: the
//! driver turns it into a [`crate::frame::Task`] whose reads and writes come
//! from the law's [`crate::query::Query`] types, iterates only the awake
//! items of its anchor, fetches `Reads`/`Writes` per item, steps, writes
//! `Writes` back, and applies the [`Settle`] result to the law's activity.
//!
//! This module also holds the two driver pieces that are plain values:
//! [`order_laws`] (declared `after` ordering) and [`Pacer`] (the fixed-dt
//! accumulator, idle skip and backlog cap). [`crate::world::World`] owns the
//! only `Pacer`.

use crate::conservation::Ledger;
use crate::entity::EntityId;
use crate::event::{Event, EventSink};
use crate::rate::RateModel;
use crate::units::Seconds;

/// How often a law runs.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Period {
    /// Every frame.
    Frame,
    /// Every `n` frames (APC/SMES-style slow cadence). `0` is treated as `1`.
    Ticks(u32),
}

impl Period {
    /// Whether a law on this period is due at `frame` (frame `0` is always
    /// due, so a law runs on its first opportunity).
    #[must_use]
    pub const fn due(self, frame: u64) -> bool {
        frame % self.frames() as u64 == 0
    }

    /// Frames per run (at least 1).
    #[must_use]
    pub const fn frames(self) -> u32 {
        match self {
            Period::Frame => 1,
            Period::Ticks(n) => {
                if n == 0 {
                    1
                } else {
                    n
                }
            }
        }
    }
}

/// What a law's step decided about its own future activity, for the item
/// it just ran on (§4.4).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Settle {
    /// Keep running every period.
    Active,
    /// Stop scheduling this item until something wakes it: a DM write to
    /// the row, a bind, a region payload or topology change, a timer
    /// ([`LawCtx::schedule`]), or an explicit wake from another law.
    Sleep,
}

/// A physical law: a pure step function over its declared reads and writes.
///
/// ```
/// use vg_core::law::{Effects, Law, LawCtx, Settle};
/// use vg_core::units::{Seconds, Watts};
///
/// struct Room { draw: Watts }
/// struct Breaker { tripped: bool }
///
/// struct TripOnOverdraw;
/// impl Law for TripOnOverdraw {
///     type Reads = Room;
///     type Writes = Breaker;
///     const NAME: &'static str = "trip_on_overdraw";
///     fn step(ctx: &mut LawCtx<'_, Room, Breaker>, _dt: Seconds) -> Settle {
///         if ctx.reads.draw.0 > 1000.0 {
///             ctx.writes.tripped = true;
///             Settle::Sleep
///         } else {
///             Settle::Active
///         }
///     }
/// }
///
/// let room = Room { draw: Watts(1500.0) };
/// let mut breaker = Breaker { tripped: false };
/// let mut fx = Effects::default();
/// let mut ctx = LawCtx::new(&room, &mut breaker, &mut fx);
/// assert_eq!(TripOnOverdraw::step(&mut ctx, Seconds(1.0)), Settle::Sleep);
/// assert!(breaker.tripped);
/// ```
///
/// `Reads`/`Writes` are unconstrained here so a law's own tests can use any
/// plain type; registering the law with the driver requires them to be
/// [`crate::query::Query`]s (component types, `Option<C>`, network
/// payloads, tuples of those).
pub trait Law: 'static {
    /// What this law reads.
    type Reads: 'static;
    /// What this law writes (read back after the step).
    type Writes: 'static;
    /// A stable name: ordering declarations, the CI check and diagnostics
    /// key on it, not the Rust type name.
    const NAME: &'static str;
    /// How often this law runs.
    const PERIOD: Period = Period::Frame;
    /// Runs one step for one item. `dt` is the law's own elapsed time (its
    /// period times the driver's fixed step).
    fn step(ctx: &mut LawCtx<'_, Self::Reads, Self::Writes>, dt: Seconds) -> Settle;
}

/// Everything a law produces besides its `Writes`: collected per law by the
/// driver and routed after the frame.
#[derive(Debug, Default)]
pub struct Effects {
    /// Typed events, already encoded (§4.8).
    pub events: EventSink,
    /// Items of this law's own anchor to run next time the law is due.
    pub wakes: Vec<u32>,
    /// Entities to wake in *every* row law, from the next frame on.
    pub entity_wakes: Vec<EntityId>,
    /// `(simulated time in s, item)`: wake this law's item then.
    pub timers: Vec<(f64, u32)>,
    /// Explicit sources and sinks of conserved quantities (§4.9).
    pub ledger: Ledger,
    /// The `vg_entity` value of the item being stepped (`0.0`: none), which
    /// [`LawCtx::emit`] attributes events to.
    pub entity: f32,
    /// The item being stepped.
    pub index: u32,
    /// Simulated time at the start of this step, s.
    pub now: f64,
}

impl Effects {
    /// Sets the item a step is about to run on (the driver calls this; law
    /// tests may too, to check attribution).
    pub fn begin(&mut self, index: u32, entity: f32, now: f64) {
        self.index = index;
        self.entity = entity;
        self.now = now;
    }
}

/// A law's step context: its reads and writes for one item, plus
/// [`Effects`].
pub struct LawCtx<'a, R, W> {
    pub reads: &'a R,
    pub writes: &'a mut W,
    fx: &'a mut Effects,
}

impl<'a, R, W> LawCtx<'a, R, W> {
    pub fn new(reads: &'a R, writes: &'a mut W, fx: &'a mut Effects) -> Self {
        Self { reads, writes, fx }
    }

    /// Emits a typed event about the current item's entity.
    pub fn emit<E: Event>(&mut self, event: E) {
        let entity = self.fx.entity;
        self.fx.events.push(entity, &event);
    }

    /// Emits a typed event about a specific entity.
    pub fn emit_for<E: Event>(&mut self, entity: EntityId, event: E) {
        self.fx.events.push(entity.to_f32() + 1.0, &event);
    }

    /// Wakes `index` of this law's own anchor (a row's entity index, a
    /// region or device index) for its next run.
    pub fn wake(&mut self, index: u32) {
        self.fx.wakes.push(index);
    }

    /// Wakes `entity` in every row law from the next frame on.
    pub fn wake_entity(&mut self, entity: EntityId) {
        self.fx.entity_wakes.push(entity);
    }

    /// Wakes the current item of this law at simulated time `at` (s): the
    /// reactor timer path (§4.3). A sleeping APC schedules its next
    /// `RateModel` crossing this way instead of polling.
    pub fn schedule(&mut self, at: f64) {
        let index = self.fx.index;
        self.fx.timers.push((at, index));
    }

    /// Schedules the current item for when `model` next reaches `level`,
    /// if it ever does. Returns the crossing time.
    pub fn schedule_crossing(&mut self, model: &RateModel, level: f64) -> Option<f64> {
        let at = model.crossing(level, self.fx.now)?;
        self.schedule(at);
        Some(at)
    }

    /// Schedules the current item for when `store` would fill or empty at
    /// `external_rate` watts ([`crate::rate::RateStore::next_bound`]): how
    /// an APC or SMES sleeps between rate changes. Returns the time.
    pub fn schedule_store(
        &mut self,
        store: &crate::rate::RateStore,
        external_rate: f64,
    ) -> Option<f64> {
        let at = store.next_bound(external_rate, self.fx.now)?;
        self.schedule(at);
        Some(at)
    }

    /// Explicit external sources/sinks for conserved quantities this step
    /// (§4.9): see [`Ledger::source`]/[`Ledger::sink`].
    pub fn ledger(&mut self) -> &mut Ledger {
        &mut self.fx.ledger
    }

    /// The item being stepped.
    #[must_use]
    pub fn index(&self) -> u32 {
        self.fx.index
    }

    /// Simulated time at the start of this step, s.
    #[must_use]
    pub fn now(&self) -> f64 {
        self.fx.now
    }

    /// The effects buffer (for helpers that take it by reference).
    pub fn effects(&mut self) -> &mut Effects {
        self.fx
    }
}

/// A cycle in the declared `after` ordering.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OrderCycle(pub Vec<&'static str>);

impl std::fmt::Display for OrderCycle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "law ordering cycle: {}", self.0.join(" -> "))
    }
}
impl std::error::Error for OrderCycle {}

/// Orders `names` so every `(a, b)` edge in `after` (read "`a` runs after
/// `b`") is satisfied, breaking ties by the input order (stable), so
/// declaring no edges at all keeps registration order. This is
/// `add_law::<B>().after::<A>()` compiled down to a flat run order.
///
/// # Errors
/// [`OrderCycle`] if `after` has no valid order.
pub fn order_laws(
    names: &[&'static str],
    after: &[(&'static str, &'static str)],
) -> Result<Vec<&'static str>, OrderCycle> {
    use std::collections::BTreeMap;
    let index: BTreeMap<&'static str, usize> =
        names.iter().enumerate().map(|(i, &n)| (n, i)).collect();
    // deps[i] = the set of positions that must come before i.
    let mut deps: Vec<Vec<usize>> = vec![Vec::new(); names.len()];
    for &(a, b) in after {
        let (Some(&ia), Some(&ib)) = (index.get(a), index.get(b)) else {
            continue; // an edge naming an unregistered law is ignored
        };
        deps[ia].push(ib);
    }
    let mut state = vec![0u8; names.len()]; // 0 unvisited, 1 visiting, 2 done
    let mut out = Vec::with_capacity(names.len());
    let mut stack = Vec::new();
    for start in 0..names.len() {
        if state[start] == 2 {
            continue;
        }
        visit(start, &deps, &mut state, &mut out, &mut stack, names)?;
    }
    Ok(out.into_iter().map(|i| names[i]).collect())
}

fn visit(
    node: usize,
    deps: &[Vec<usize>],
    state: &mut [u8],
    out: &mut Vec<usize>,
    stack: &mut Vec<usize>,
    names: &[&'static str],
) -> Result<(), OrderCycle> {
    match state[node] {
        2 => return Ok(()),
        1 => {
            let start = stack.iter().position(|&n| n == node).unwrap_or(0);
            let cycle = stack[start..]
                .iter()
                .chain([&node])
                .map(|&i| names[i])
                .collect();
            return Err(OrderCycle(cycle));
        }
        _ => {}
    }
    state[node] = 1;
    stack.push(node);
    for &dep in &deps[node] {
        visit(dep, deps, state, out, stack, names)?;
    }
    stack.pop();
    state[node] = 2;
    out.push(node);
    Ok(())
}

/// The fixed-dt accumulator, idle skip and backlog cap (§4.3: "one `Sim` per
/// DLL... the driver owns pacing"). [`crate::world::World`] holds the only
/// one; no domain paces itself.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pacer {
    dt: Seconds,
    backlog_cap: u32,
    accumulated: f64,
}

impl Pacer {
    /// `dt`: the fixed step every due law advances by. `backlog_cap`: the
    /// most steps [`advance`](Self::advance) grants in one call; owed time
    /// beyond it is dropped (the sim runs slow instead of spiralling).
    #[must_use]
    pub const fn new(dt: Seconds, backlog_cap: u32) -> Self {
        Self {
            dt,
            backlog_cap,
            accumulated: 0.0,
        }
    }

    #[must_use]
    pub const fn dt(&self) -> Seconds {
        self.dt
    }

    /// Real time still owed a step, not yet enough for one.
    #[must_use]
    pub const fn carry(&self) -> f64 {
        self.accumulated
    }

    /// Feeds `elapsed` seconds in and returns how many fixed steps are now
    /// due (`0` is the idle-skip case). Capped at `backlog_cap`; owed time
    /// beyond the cap is dropped, not carried.
    pub fn advance(&mut self, elapsed: Seconds) -> u32 {
        if self.dt.0 <= 0.0 {
            return 0;
        }
        self.accumulated += elapsed.0.max(0.0);
        let due = (self.accumulated / self.dt.0).floor();
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let steps = (due as u64).min(u64::from(self.backlog_cap));
        #[allow(clippy::cast_precision_loss)]
        {
            self.accumulated -= steps as f64 * self.dt.0;
        }
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        if due as u64 > u64::from(self.backlog_cap) {
            self.accumulated = 0.0;
        }
        #[allow(clippy::cast_possible_truncation)]
        {
            steps as u32
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn period_frame_is_always_due() {
        assert!(Period::Frame.due(0));
        assert!(Period::Frame.due(1));
        assert!(Period::Frame.due(1_000_000));
    }

    #[test]
    fn period_ticks_is_due_every_n_frames() {
        let p = Period::Ticks(4);
        let due: Vec<bool> = (0..9).map(|f| p.due(f)).collect();
        assert_eq!(
            due,
            vec![true, false, false, false, true, false, false, false, true]
        );
        assert!(Period::Ticks(0).due(1), "0 behaves as 1");
    }

    #[test]
    fn law_ctx_records_effects() {
        struct Noop;
        impl Law for Noop {
            type Reads = ();
            type Writes = ();
            const NAME: &'static str = "noop";
            fn step(ctx: &mut LawCtx<'_, (), ()>, _dt: Seconds) -> Settle {
                ctx.wake(7);
                ctx.schedule(12.5);
                ctx.ledger().source("test_quantity", 1.0);
                Settle::Active
            }
        }
        let mut fx = Effects::default();
        fx.begin(3, 4.0, 10.0);
        fx.ledger.check("test_quantity", 0.0, 1e-9).unwrap();
        let mut unit = ();
        let mut ctx = LawCtx::new(&(), &mut unit, &mut fx);
        assert_eq!(Noop::step(&mut ctx, Seconds(1.0)), Settle::Active);
        assert_eq!(fx.wakes, vec![7]);
        assert_eq!(fx.timers, vec![(12.5, 3)]);
        assert!(fx.ledger.check("test_quantity", 1.0, 1e-9).is_ok());
    }

    #[test]
    fn schedule_crossing_uses_the_rate_model() {
        let mut fx = Effects::default();
        fx.begin(1, 0.0, 10.0);
        let model = RateModel::linear(100.0, -10.0, 10.0);
        let mut unit = ();
        let mut ctx = LawCtx::new(&(), &mut unit, &mut fx);
        assert_eq!(ctx.schedule_crossing(&model, 0.0), Some(20.0));
        assert_eq!(fx.timers, vec![(20.0, 1)]);
    }

    #[test]
    fn order_laws_respects_after_and_detects_cycles() {
        assert_eq!(
            order_laws(&["a", "b", "c"], &[]).unwrap(),
            vec!["a", "b", "c"]
        );
        let order = order_laws(
            &["power_balance", "apc_tick"],
            &[("power_balance", "apc_tick")],
        )
        .unwrap();
        assert_eq!(order, vec!["apc_tick", "power_balance"]);
        assert_eq!(
            order_laws(&["c", "a", "b"], &[("b", "a"), ("c", "b")]).unwrap(),
            vec!["a", "b", "c"]
        );
        assert!(order_laws(&["a", "b"], &[("a", "b"), ("b", "a")]).is_err());
        assert_eq!(order_laws(&["a"], &[("a", "ghost")]).unwrap(), vec!["a"]);
    }

    #[test]
    fn pacer_paces() {
        let mut p = Pacer::new(Seconds(1.0), 10);
        assert_eq!(p.advance(Seconds(0.3)), 0);
        assert!(p.carry() > 0.0);
        let mut p = Pacer::new(Seconds(0.5), 10);
        assert_eq!(p.advance(Seconds(0.5)), 1);
        assert_eq!(p.advance(Seconds(0.2)), 0);
        assert_eq!(p.advance(Seconds(0.3)), 1);
        let mut p = Pacer::new(Seconds(1.0), 3);
        assert_eq!(p.advance(Seconds(10.0)), 3);
        assert_eq!(p.carry(), 0.0);
    }
}
