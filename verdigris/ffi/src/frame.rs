//! The one driver: `vg_frame(elapsed, budget)`.
//!
//! DM makes exactly one call into the simulation per tick. In it Rust
//!
//! 1. paces the [`World`](vg_core::world::World) (laws, heat, gas, power and
//!    the pipe devices: `PipeDeviceStep` is a law on the pacer's period,
//!    [`PIPE_DEVICE_PERIOD`] seconds per step),
//! 2. ticks the hosts that are not on the world's pacer,
//! 3. runs the scheduler (timers, rate crossings, keys, every watch port), and
//! 4. hands back **one outbox page** of records.
//!
//! Nothing else drains the simulation: the old `vg_world_tick`,
//! `vg_world_events`, `vg_world_step`, `vg_entity_tick_all`,
//! `vg_heat_take_wakes`, `vg_heat_tick`, `vg_drain_dirty_gas_observations`
//! and `vg_pipe_step_devices` are internal to this module now.
//!
//! # The outbox
//!
//! A flat list of records, every number exact as an `f32`:
//!
//! ```text
//! kind, a, b, n, payload[0], ..., payload[n - 1]
//! ```
//!
//! | kind | a | b | payload |
//! |---|---|---|---|
//! | [`REC_CHANGED`] | the entity (a watch handle for a gas watch, an entity for a plain change) | the key: a channel mask | gas: `mixture, mask, revision, pressure, ...` (the observation, from the mixture id on); a change wake: `lane, source` |
//! | [`REC_NOTICE`] | the entity the event is about (0: none) | the event header (`domain << 16 \| kind << 8 \| variant`, or a `NATIVE_NOTICE_*`) | the event's fields |
//! | [`REC_CROSSED`] | the watch's subscriber | the band: a wake's class bits, or a set entry's payload | wake: `lane, reason, source, source_kind`; set crossing: `entered, generation` |
//!
//! Records of one kind keep their emission order; occurrences are never
//! merged here (a wake is already merged per subscriber by the scheduler).
//! The DM side is `/datum/system/native` (`code/datums/native/system.dm`).

use std::cell::RefCell;

use byondapi::prelude::*;
use eyre::{Result, bail};
use vg_core::timer::Tick;

use crate::world::{list, num, whole};
use crate::{entity, gas, heat, sched, world};

/// Record kind: something changed (`entity`, `key`).
/// @dm-define NATIVE_REC_CHANGED
pub const REC_CHANGED: u32 = 1;
/// Record kind: something happened (`entity`, `header`, fields).
/// @dm-define NATIVE_REC_NOTICE
pub const REC_NOTICE: u32 = 2;
/// Record kind: a watch crossed a band (`watch`, `band`, detail).
/// @dm-define NATIVE_REC_CROSSED
pub const REC_CROSSED: u32 = 3;

/// The notice a pipe device's step raises: `moles, power_w, target_reached`.
/// Above every `domain << 16` event header.
/// @dm-define NATIVE_NOTICE_PIPE_DEVICE
pub const NOTICE_PIPE_DEVICE: u32 = 0x00FF_0001;

/// Seconds of one World step, which is the period of the pipe devices' flow law (`PipeDeviceStep`, one run per
/// step).
/// @dm-define NATIVE_PIPE_DEVICE_PERIOD
pub const PIPE_DEVICE_PERIOD: f32 = 0.5;

/// The most game time one frame gives the pacer (an overloaded server, or the
/// first frame, whose `elapsed` is the whole wheel tick count, must not owe a
/// flood of steps).
pub const MAX_PACE_SECONDS: f64 = 2.0;

/// A crossing record (set entry) carries two detail numbers, a wake four.
/// @dm-define NATIVE_CROSSED_SET_DETAIL
pub const CROSSED_SET_DETAIL: u32 = 2;

struct Clock {
    /// Seconds per wheel tick (`world.tick_lag / 10`).
    tick_seconds: f64,
    /// The wheel tick the scheduler is at: the sum of every `elapsed`.
    now: Tick,
    /// The next frame steps the world once, whatever the pacer owes ([`frame_force_devices`]).
    force_step: bool,
    frames: u64,
}

thread_local! {
    static CLOCK: RefCell<Clock> = const {
        RefCell::new(Clock { tick_seconds: 0.05, now: 0, force_step: false, frames: 0 })
    };
}

/// Tells the frame how long a wheel tick is: `tick_lag` in deciseconds
/// (`world.tick_lag`). Call at boot and whenever it changes.
#[auxmacros::bind("/proc/frame_set_tick_lag")]
fn frame_set_tick_lag(tick_lag: ByondValue) -> Result<ByondValue> {
    let lag = f64::from(num(&tick_lag)?);
    if lag.is_nan() || lag <= 0.0 {
        bail!("bad tick lag {lag}");
    }
    CLOCK.with_borrow_mut(|c| c.tick_seconds = lag / 10.0);
    Ok(ByondValue::null())
}

/// The frames run since boot (tests, the profiler).
#[auxmacros::bind("/proc/frame_count")]
fn frame_count() -> Result<ByondValue> {
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(CLOCK.with_borrow(|c| c.frames) as f32))
}

/// Test hook: makes the next frame step the world once, so the pipe devices' law
/// runs for a full [`PIPE_DEVICE_PERIOD`] (a deterministic step for a DM test that
/// built a device by hand).
#[auxmacros::bind("/proc/frame_force_devices")]
fn frame_force_devices() -> Result<ByondValue> {
    CLOCK.with_borrow_mut(|c| c.force_step = true);
    Ok(ByondValue::null())
}

/// One frame: see the module docs. `elapsed` is the wheel ticks since the
/// last frame (`0`: no pacing, just drain: a test that ran steps by hand),
/// `budget` how many normal/background wakes to take (urgent ones are never
/// limited). Returns the outbox page.
#[auxmacros::bind("/proc/frame")]
fn frame(elapsed: ByondValue, budget: ByondValue) -> Result<ByondValue> {
    let elapsed = whole(&elapsed, "elapsed")?;
    let budget = whole(&budget, "budget")? as usize;
    list(run(elapsed, budget)?)
}

/// Pushes one record.
fn record(out: &mut Vec<f32>, kind: u32, a: f32, b: f32, payload: &[f32]) {
    #[allow(clippy::cast_precision_loss)]
    out.extend_from_slice(&[kind as f32, a, b, payload.len() as f32]);
    out.extend_from_slice(payload);
}

/// The frame itself, callable without DM (tests).
pub(crate) fn run(elapsed: u32, budget: usize) -> Result<Vec<f32>> {
    let (seconds, now, force) = CLOCK.with_borrow_mut(|c| {
        c.now = c.now.saturating_add(Tick::from(elapsed));
        c.frames += 1;
        let seconds = (f64::from(elapsed) * c.tick_seconds).min(MAX_PACE_SECONDS);
        (seconds, c.now, std::mem::take(&mut c.force_step))
    });
    let mut out: Vec<f32> = Vec::new();
    let mut timer = PhaseTimer::start();

    // 1-2. The world (the pipe devices are a law of it) and the hosts not yet on it.
    let mut devices = Vec::new();
    if elapsed > 0 || force {
        devices = world::pace(seconds, force)?;
    }
    timer.lap("pace");
    entity::tick_hosts();
    timer.lap("hosts");

    // 3. The scheduler: every watch port's wakes, timers, rates, keys.
    let (wakes, owners) = sched::step(now, budget)?;
    timer.lap("sched");

    // Set-watch crossings, and the retiring of settled heat bodies (read off
    // the events, so before they are taken).
    let crossings = heat::take_crossings(&owners)?;
    timer.lap("crossings");

    // 3. Typed events -> notices.
    let events = world::take_events()?;
    timer.lap("events");
    let mut at = 0;
    while at + 3 <= events.len() {
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let len = events[at + 2] as usize;
        let end = (at + 3 + len).min(events.len());
        record(
            &mut out,
            REC_NOTICE,
            events[at + 1],
            events[at],
            &events[at + 3..end],
        );
        at = end;
    }

    // What the pipe devices' law did this frame (one report per device that moved gas or drew power).
    #[allow(clippy::cast_precision_loss)]
    for r in devices.chunks_exact(4) {
        record(
            &mut out,
            REC_NOTICE,
            r[0],
            NOTICE_PIPE_DEVICE as f32,
            &[r[1], r[2], r[3]],
        );
    }

    // Gas dependency observations -> changes.
    let observations = gas::take_observations();
    timer.lap("observations");
    for o in observations.chunks_exact(gas::mix::GAS_OBSERVATION_STRIDE) {
        record(&mut out, REC_CHANGED, o[0], o[2], &o[1..]);
    }

    // Wakes: a plain channel change is CHANGED, everything else CROSSED.
    for w in wakes {
        #[allow(clippy::cast_precision_loss)]
        if w.reason & !sched::REASON_DETAIL == 0 {
            record(
                &mut out,
                REC_CHANGED,
                w.subscriber as f32,
                w.reason as f32,
                &[f32::from(w.lane), w.source],
            );
        } else {
            record(
                &mut out,
                REC_CROSSED,
                w.subscriber as f32,
                (w.reason & !sched::REASON_DETAIL) as f32,
                &[f32::from(w.lane), w.reason as f32, w.source, w.kind],
            );
        }
    }
    #[allow(clippy::cast_precision_loss)]
    for (sub, payload, entered, generation) in crossings {
        record(
            &mut out,
            REC_CROSSED,
            sub as f32,
            payload as f32,
            &[f32::from(u8::from(entered)), generation as f32],
        );
    }
    timer.lap("outbox");
    Ok(out)
}

/// Cumulative wall time of each frame phase (`frame.us.<phase>` counters in the metrics registry, read by
/// `verdigris_metrics_list()` and every bench mark), so a change in the frame's cost names the phase that moved.
struct PhaseTimer {
    at: std::time::Instant,
}

impl PhaseTimer {
    fn start() -> Self {
        crate::metrics::registry().counter("frame.count").inc();
        Self { at: std::time::Instant::now() }
    }

    fn lap(&mut self, phase: &str) {
        let now = std::time::Instant::now();
        #[allow(clippy::cast_possible_truncation)]
        let us = (now - self.at).as_micros() as u64;
        crate::metrics::registry().counter(&format!("frame.us.{phase}")).add(us);
        self.at = now;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gas::mix::{self, MixRef};
    use crate::world::with_world;
    use vg_core::component::Component;
    use vg_core::outbox::Lane;
    use vg_core::registry::world_kind_domain;
    use vg_core::watch::{Cmp, Cond, Edge, SetEntry};
    use vg_gas::cell::gas_ch;
    use vg_gas::gas::Mixture;
    use vg_heat::HeatBody;

    /// Splits an outbox page into `(kind, a, b, payload)` records.
    fn records(page: &[f32]) -> Vec<(u32, f32, f32, Vec<f32>)> {
        let mut out = Vec::new();
        let mut at = 0;
        while at + 4 <= page.len() {
            let n = page[at + 3] as usize;
            out.push((
                page[at] as u32,
                page[at + 1],
                page[at + 2],
                page[at + 4..at + 4 + n].to_vec(),
            ));
            at += 4 + n;
        }
        assert_eq!(at, page.len(), "the page is whole records: {page:?}");
        out
    }

    #[test]
    fn an_idle_frame_reports_nothing() {
        with_world(|_| Ok(())).unwrap();
        assert!(records(&run(0, 100).unwrap()).is_empty());
    }

    #[test]
    fn a_gas_change_watch_leaves_as_a_changed_record() {
        with_world(|_| Ok(())).unwrap();
        let mut tank = Mixture::from_vol(70.0);
        tank.set_moles(0, 10.0);
        tank.set_temperature(293.15);
        let r = MixRef::Main(mix::alloc(tank.clone()).unwrap());
        let cond = Cond::Changed {
            cell: r.id(),
            mask: gas_ch::PRESSURE.bit(),
        };
        let code = crate::sched::GAS_HANDLES;
        let (port, id) = crate::registry::with_domain(world_kind_domain(code), |d| {
            d.watch(7, Lane::Urgent, &cond)
        })
        .unwrap()
        .unwrap();
        with_world(|w| {
            w.sched_watch(7, code, port, id)
                .map_err(|e| eyre::eyre!("{e}"))
        })
        .unwrap();
        assert!(
            records(&run(0, 100).unwrap()).is_empty(),
            "nothing changed yet"
        );
        let mut after = tank.clone();
        after.set_moles(0, 20.0);
        mix::store(r, &tank, &after);
        let page = records(&run(0, 100).unwrap());
        let changed: Vec<_> = page
            .iter()
            .filter(|r| r.0 == REC_CHANGED && r.1 == 7.0)
            .collect();
        assert_eq!(changed.len(), 1, "{page:?}");
        assert_ne!(
            changed[0].2 as u32 & gas_ch::PRESSURE.bit(),
            0,
            "the key is the channel mask"
        );
    }

    #[test]
    fn a_heat_set_crossing_leaves_as_a_crossed_record() {
        let code = vg_core::world::kind_code(HeatBody::DOMAIN_ID, HeatBody::KIND);
        let body = with_world(|w| {
            w.bind_value(
                None,
                HeatBody {
                    capacity: 1_000.0,
                    energy: 1_000.0 * 300.0,
                    keep: true,
                    ..Default::default()
                },
            )
            .map_err(|e| eyre::eyre!("{e}"))
        })
        .unwrap();
        let chans =
            crate::registry::with_domain(world_kind_domain(code), |d| d.channels()).unwrap();
        let ch = vg_core::channel::ChannelId(
            chans.iter().position(|c| c.name == "temperature").unwrap() as u8,
        );
        let (port, id) = crate::registry::with_domain(world_kind_domain(code), |d| {
            d.watch(
                9,
                Lane::Normal,
                &Cond::ThresholdSet {
                    cell: crate::entity::entity_value(body) as u32,
                    ch,
                },
            )
        })
        .unwrap()
        .unwrap();
        with_world(|w| {
            w.sched_watch(9, code, port, id)
                .map_err(|e| eyre::eyre!("{e}"))
        })
        .unwrap();
        crate::registry::with_domain(world_kind_domain(code), |d| {
            d.add_entry(
                port,
                id,
                SetEntry {
                    payload: 3,
                    generation: 1,
                    cmp: Cmp::Above,
                    limit: vg_core::channel::Quantity::new(320.0, vg_core::channel::Unit::Kelvin),
                    hysteresis: None,
                    edge: Edge::Enter,
                },
            )
        })
        .unwrap()
        .unwrap();
        with_world(|w| {
            w.step_blocking();
            Ok(())
        })
        .unwrap();
        let _ = run(0, 100).unwrap();
        with_world(|w| {
            let mut b = w.read::<HeatBody>(body).unwrap();
            b.relax = false;
            b.energy = 1_000.0 * 330.0;
            w.put(body, b).unwrap();
            crate::heat::wake_body_couplings(w, body.index());
            w.step_blocking();
            Ok(())
        })
        .unwrap();
        let page = records(&run(0, 100).unwrap());
        let crossed: Vec<_> = page
            .iter()
            .filter(|r| {
                r.0 == REC_CROSSED && r.1 == 9.0 && r.3.len() == CROSSED_SET_DETAIL as usize
            })
            .collect();
        assert_eq!(crossed.len(), 1, "{page:?}");
        assert_eq!(crossed[0].2, 3.0, "the band is the entry's payload");
        assert_eq!(crossed[0].3, vec![1.0, 1.0], "entered, generation");
    }
}
