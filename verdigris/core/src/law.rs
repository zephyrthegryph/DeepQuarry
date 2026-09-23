//! Laws and the driver (`doc/rewrite/rust_architecture.md` §4.3, §7 Core A).
//!
//! A domain crate declares components, kinds and **laws** -- pure functions
//! over the rows/regions/cells they read and write -- and nothing else
//! (§2). This module is the stable shape domain agents write laws against:
//! [`Law`], [`LawCtx`], [`Settle`] and [`Period`]. It intentionally does
//! **not** yet wire a law's `Reads`/`Writes` to real component-store
//! columns: that plumbing is Core B's `EntityTable`/component-store work
//! (`rust_architecture.md` §4.1–§4.2), which this module's `Query` trait is
//! deliberately left open for. Until then, `Reads`/`Writes` can be any
//! `'static` type a domain constructs itself (a plain struct of borrowed
//! slices works fine for a law's own Rust tests today), so a law can be
//! written and tested **now**, before the entity/component stores exist,
//! exactly as `rust_architecture.md` §7 asks: "domains write their laws as
//! pure functions with Rust tests immediately, since laws don't need the
//! infrastructure."
//!
//! [`order_laws`] and [`Pacer`] are the two pieces of "one `Sim` per DLL...
//! the driver owns pacing" (§4.3) that don't need Reads/Writes plumbing to
//! be real and useful today: declared `after`/`before` ordering, and the
//! fixed-dt accumulator / idle skip / backlog cap every domain's `Sim`
//! currently reimplements for itself (gas's idle skip, heat's tick
//! accumulator and `MAX_BACKLOG_FRAMES`, ...). Wiring a heterogeneous set
//! of laws (each with its own `Reads`/`Writes` type) into the existing
//! [`crate::sim::Sim`]/[`crate::frame`] machinery as actual `frame::Task`s
//! is the integration step that follows once Core B's stores land; this
//! module is the stable surface that doesn't change shape under that work.

use crate::units::Seconds;

/// Marker for a law's declared read or write set: component columns,
/// network payloads, field cells, or (until those exist) any plain
/// `'static` type a law's own tests construct directly. Blanket-implemented
/// so writing a law is never blocked on this trait; Core B narrows or
/// extends it as real column-derived queries land, without changing
/// [`Law`]'s own shape.
pub trait Query: 'static {}
impl<T: 'static> Query for T {}

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
        match self {
            Period::Frame => true,
            Period::Ticks(n) => frame % (if n == 0 { 1 } else { n as u64 }) == 0,
        }
    }
}

/// What a law's step decided about its own future activity, for the row,
/// region or cell it just ran on (§4.4).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Settle {
    /// Keep running next period this index is due.
    Active,
    /// Stop scheduling this index until something wakes it: a command
    /// write, a region payload change, a watch/reactor timer, or an
    /// explicit [`LawCtx::wake`].
    Sleep,
}

/// A physical law: a pure step function over its declared reads and writes.
///
/// ```
/// use vg_core::law::{Law, LawCtx, Period, Settle};
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
///             ctx.emit(1);
///             Settle::Sleep
///         } else {
///             Settle::Active
///         }
///     }
/// }
///
/// let room = Room { draw: Watts(1500.0) };
/// let mut breaker = Breaker { tripped: false };
/// let mut events = Vec::new();
/// let mut wakes = Vec::new();
/// let mut ledger = vg_core::conservation::Ledger::new();
/// let mut ctx = LawCtx::new(&room, &mut breaker, &mut events, &mut wakes, &mut ledger);
/// assert_eq!(TripOnOverdraw::step(&mut ctx, Seconds(1.0)), Settle::Sleep);
/// assert!(breaker.tripped);
/// assert_eq!(events, vec![1]);
/// ```
pub trait Law: 'static {
    /// What this law reads.
    type Reads: Query;
    /// What this law writes.
    type Writes: Query;
    /// A stable name: the CI consolidation check, ordering declarations and
    /// diagnostics all key on this, not the Rust type name.
    const NAME: &'static str;
    /// How often this law runs. Most laws are [`Period::Frame`]; slow
    /// cadences (APC/SMES) use [`Period::Ticks`].
    const PERIOD: Period = Period::Frame;
    /// Runs one step. `dt` is the *law's own* elapsed time (its period's
    /// multiple of the driver's fixed step), not necessarily the driver's
    /// raw frame `dt`.
    fn step(ctx: &mut LawCtx<'_, Self::Reads, Self::Writes>, dt: Seconds) -> Settle;
}

/// A law's step context: its reads and writes, plus the side channels every
/// law gets instead of returning `Vec<f32>`/mutating globals directly (§4.3):
/// `emit` for events, `wake` for activity, `schedule` for the reactor timer
/// path, and `ledger` for conservation sources/sinks (§4.9).
///
/// `E` is left generic (not yet the `#[vg::events]`-generated typed enum of
/// §4.8, which is Core B's bindings/macro work) so this compiles and is
/// testable without that generator existing yet; a domain's own event type
/// works fine as `E` today.
pub struct LawCtx<'a, R, W, E = u32> {
    pub reads: &'a R,
    pub writes: &'a mut W,
    events: &'a mut Vec<E>,
    wakes: &'a mut Vec<u32>,
    ledger: &'a mut crate::conservation::Ledger,
}

impl<'a, R, W, E> LawCtx<'a, R, W, E> {
    pub fn new(
        reads: &'a R,
        writes: &'a mut W,
        events: &'a mut Vec<E>,
        wakes: &'a mut Vec<u32>,
        ledger: &'a mut crate::conservation::Ledger,
    ) -> Self {
        Self {
            reads,
            writes,
            events,
            wakes,
            ledger,
        }
    }

    /// Queues an event for this frame's outbox.
    pub fn emit(&mut self, event: E) {
        self.events.push(event);
    }

    /// Wakes a row, region or cell (by whatever index the law's own domain
    /// uses) so it runs again even if it would otherwise be asleep.
    pub fn wake(&mut self, index: u32) {
        self.wakes.push(index);
    }

    /// Records an explicit external source/sink for a conserved quantity
    /// this step (§4.9) -- see [`crate::conservation::Ledger::source`]/
    /// [`crate::conservation::Ledger::sink`].
    pub fn ledger(&mut self) -> &mut crate::conservation::Ledger {
        self.ledger
    }
}

/// A cycle in a law's declared `after`/`before` ordering.
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
/// `rust_architecture.md` §4.3's `add_law::<B>().after::<A>()` compiled
/// down to a flat run order; the driver runs the result top to bottom every
/// due frame.
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

#[allow(clippy::items_after_statements)]
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
            let cycle = stack[start..].iter().chain([&node]).map(|&i| names[i]).collect();
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

/// The fixed-dt accumulator, idle skip and backlog cap every domain's `Sim`
/// currently reimplements for itself (gas's idle skip, heat's tick
/// accumulator + `MAX_BACKLOG_FRAMES`, ...): `rust_architecture.md` §4.3,
/// "one `Sim` per DLL... the driver owns pacing."
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pacer {
    dt: Seconds,
    backlog_cap: u32,
    accumulated: f64,
}

impl Pacer {
    /// `dt`: the fixed step every due law advances by. `backlog_cap`: the
    /// most steps [`advance`](Self::advance) runs in one call -- excess
    /// accumulated time is dropped (the sim runs slow instead of spiralling
    /// trying to catch up), matching heat's existing `MAX_BACKLOG_FRAMES`.
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

    /// Feeds `elapsed` real seconds in and returns how many fixed steps are
    /// now due (`0` is the idle-skip case: nothing to run this call).
    /// Capped at `backlog_cap`; any further owed time beyond the cap is
    /// dropped, not carried to the next call.
    pub fn advance(&mut self, elapsed: Seconds) -> u32 {
        if self.dt.0 <= 0.0 {
            return 0;
        }
        self.accumulated += elapsed.0.max(0.0);
        let due = (self.accumulated / self.dt.0).floor();
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let steps = (due as u64).min(u64::from(self.backlog_cap));
        #[allow(clippy::cast_possible_truncation)]
        {
            self.accumulated -= steps as f64 * self.dt.0;
        }
        if due as u64 > u64::from(self.backlog_cap) {
            // Backlog exceeded: drop the rest instead of carrying it, so a
            // long stall doesn't cause a burst of catch-up steps later.
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
    }

    #[test]
    fn period_ticks_zero_behaves_as_one() {
        assert!(Period::Ticks(0).due(0));
        assert!(Period::Ticks(0).due(1));
        assert!(Period::Ticks(0).due(2));
    }

    #[test]
    fn law_ctx_records_events_wakes_and_ledger_use() {
        struct Noop;
        impl Law for Noop {
            type Reads = ();
            type Writes = ();
            const NAME: &'static str = "noop";
            fn step(ctx: &mut LawCtx<'_, (), ()>, _dt: Seconds) -> Settle {
                ctx.emit(42);
                ctx.wake(7);
                ctx.ledger().source("test_quantity", 1.0);
                Settle::Active
            }
        }
        let mut events = Vec::new();
        let mut wakes = Vec::new();
        let mut ledger = crate::conservation::Ledger::new();
        // Prime before any step runs (as a real driver would at boot).
        ledger.check("test_quantity", 0.0, 1e-9).unwrap();
        let mut writes = ();
        let mut ctx = LawCtx::new(&(), &mut writes, &mut events, &mut wakes, &mut ledger);
        assert_eq!(Noop::step(&mut ctx, Seconds(1.0)), Settle::Active);
        assert_eq!(events, vec![42]);
        assert_eq!(wakes, vec![7]);
        // The source the step recorded should explain a +1.0 delta.
        assert!(ledger.check("test_quantity", 1.0, 1e-9).is_ok());
    }

    #[test]
    fn order_laws_keeps_registration_order_with_no_edges() {
        let names = ["a", "b", "c"];
        let order = order_laws(&names, &[]).unwrap();
        assert_eq!(order, vec!["a", "b", "c"]);
    }

    #[test]
    fn order_laws_respects_after() {
        // "power_balance" after "apc_tick": apc_tick must come first.
        let names = ["power_balance", "apc_tick"];
        let order = order_laws(&names, &[("power_balance", "apc_tick")]).unwrap();
        assert_eq!(order, vec!["apc_tick", "power_balance"]);
    }

    #[test]
    fn order_laws_chain_of_three() {
        let names = ["c", "a", "b"];
        let order = order_laws(&names, &[("b", "a"), ("c", "b")]).unwrap();
        assert_eq!(order, vec!["a", "b", "c"]);
    }

    #[test]
    fn order_laws_detects_a_cycle() {
        let names = ["a", "b"];
        let err = order_laws(&names, &[("a", "b"), ("b", "a")]).unwrap_err();
        assert!(err.0.len() >= 2, "{err:?}");
    }

    #[test]
    fn order_laws_ignores_edges_naming_unregistered_laws() {
        let names = ["a"];
        let order = order_laws(&names, &[("a", "ghost")]).unwrap();
        assert_eq!(order, vec!["a"]);
    }

    #[test]
    fn pacer_idle_skips_when_nothing_is_owed() {
        let mut p = Pacer::new(Seconds(1.0), 10);
        assert_eq!(p.advance(Seconds(0.3)), 0);
        assert!(p.carry() > 0.0);
    }

    #[test]
    fn pacer_steps_once_a_full_dt_has_accumulated() {
        let mut p = Pacer::new(Seconds(0.5), 10);
        assert_eq!(p.advance(Seconds(0.5)), 1);
        assert_eq!(p.advance(Seconds(0.2)), 0);
        assert_eq!(p.advance(Seconds(0.3)), 1);
    }

    #[test]
    fn pacer_caps_the_backlog_and_drops_the_rest() {
        let mut p = Pacer::new(Seconds(1.0), 3);
        // 10 seconds owed at dt=1.0 would be 10 steps; capped at 3, and the
        // remaining 7 seconds of backlog is dropped, not carried.
        assert_eq!(p.advance(Seconds(10.0)), 3);
        assert_eq!(p.carry(), 0.0);
        assert_eq!(p.advance(Seconds(0.0)), 0);
    }

    #[test]
    fn pacer_carries_partial_time_across_calls() {
        // 0.25 is exact in binary floating point, so this isolates the
        // accumulator logic from float-rounding drift (a real concern for
        // the fixed-dt accumulator, just not what this test targets).
        let mut p = Pacer::new(Seconds(1.0), 100);
        let mut steps = 0u32;
        for _ in 0..12 {
            steps += p.advance(Seconds(0.25));
        }
        // 12 * 0.25 = 3.0s owed at dt=1.0 -> 3 steps total, spread over calls.
        assert_eq!(steps, 3);
    }
}
