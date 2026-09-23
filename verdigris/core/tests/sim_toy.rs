//! End-to-end tests of owners, commands, views, the overlay, frames and
//! replay (`rust_core.md` §3) on a toy heat domain.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::Duration;

use proptest::prelude::*;
use vg_core::Arena;
use vg_core::channel::{Quantity, Unit};
use vg_core::channels;
use vg_core::cow::ChunkLayout;
use vg_core::frame::Task;
use vg_core::outbox::{Lane, reason};
use vg_core::owner::{Applied, Domain, DomainKey, View};
use vg_core::rate::RateModel;
use vg_core::reactor::Reactor;
use vg_core::rng::{Rng, StreamId};
use vg_core::sim::{Mode, Sim, SimBuilder, SimConfig};
use vg_core::watch::{Cmp, Cond, Level};

/// One cell of the toy field.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Heat {
    energy: f32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum HeatCmd {
    /// Add this much energy (absolute, computed on the main thread).
    Add(f32),
    /// Remove this much energy; clamps at zero and reports the shortfall.
    Remove(f32),
}

struct HeatDomain;

impl Domain for HeatDomain {
    type Value = Heat;
    type Command = HeatCmd;
    const NAME: &'static str = "toy_heat";

    fn apply(value: &mut Heat, cmd: &HeatCmd) -> Applied {
        match *cmd {
            HeatCmd::Add(e) => {
                value.energy += e;
                Applied::default()
            }
            HeatCmd::Remove(e) => {
                let taken = e.min(value.energy);
                value.energy -= taken;
                Applied {
                    shortfall: e - taken,
                }
            }
        }
    }
}

channels! { mod heat_ch for HeatDomain {
    ENERGY: Scalar<Joules> hysteresis 0.5 => |c, o| o[0] = c.energy,
}}

/// A second domain that only frame tasks write: per-frame statistics read
/// from heat's previous view (an exchange buffer, §3.6).
struct TallyDomain;

impl Domain for TallyDomain {
    type Value = u64;
    type Command = u64;
    const NAME: &'static str = "toy_tally";

    fn apply(value: &mut u64, cmd: &u64) -> Applied {
        *value = *cmd;
        Applied::default()
    }
}

const CELLS: u32 = 200;
const CHUNK: u32 = 16;

struct Keys {
    heat: DomainKey<HeatDomain>,
    tally: DomainKey<TallyDomain>,
}

fn layout() -> ChunkLayout {
    ChunkLayout::linear_with_chunk(CELLS, CHUNK)
}

/// Diffusion over the 1D field, per-cell deterministic and chunk-parallel,
/// plus a random spark and a tally of the previous frame.
fn toy_builder(config: SimConfig, physics: bool) -> (SimBuilder, Keys) {
    let mut b = SimBuilder::new(config);
    let heat = b.add_domain::<HeatDomain>(layout());
    let tally = b.add_domain::<TallyDomain>(ChunkLayout::linear(4));
    if physics {
        let state = heat.state();
        b.add_task(
            Task::new("diffuse", move |ctx| {
                let mut st = ctx.write(state);
                st.store.allocate_all();
                let old = st.store.snapshot();
                let layout = old.layout();
                st.store.par_for_each_chunk_mut(|chunk, cells| {
                    for (i, cell) in cells.iter_mut().enumerate() {
                        let Some(index) = layout.index_of(chunk, i) else {
                            continue;
                        };
                        let here = old.get(index).unwrap().energy;
                        let left = index
                            .checked_sub(1)
                            .and_then(|j| old.get(j))
                            .map_or(here, |c| c.energy);
                        let right = old.get(index + 1).map_or(here, |c| c.energy);
                        cell.energy = here + 0.1 * (left + right - 2.0 * here);
                    }
                });
            })
            .writes(state.id()),
        );
        b.add_task(
            Task::new("spark", move |ctx| {
                let mut rng = ctx.rng(StreamId::named("spark"));
                let cell = u32::try_from(rng.next_u64() % u64::from(CELLS)).unwrap();
                let mut st = ctx.write(state);
                st.store.get_mut(cell).unwrap().energy += 1.0;
            })
            .writes(state.id())
            .every(3),
        );
        let tally_state = tally.state();
        b.add_task(
            Task::new("tally", move |ctx| {
                let sum = ctx.prev_view(heat).map_or(0.0, |v| {
                    (0..CELLS)
                        .map(|i| f64::from(v.get(i).unwrap().energy))
                        .sum::<f64>()
                });
                let mut st = ctx.write(tally_state);
                st.store.set(0, sum.to_bits());
                st.store.set(1, ctx.frame());
            })
            .writes(tally_state.id()),
        );
    }
    (b, Keys { heat, tally })
}

fn config(threads: usize) -> SimConfig {
    SimConfig {
        threads,
        seed: 0xDEC0DE,
        record: true,
        ..SimConfig::default()
    }
}

fn bits<V: Clone + Default>(view: &View<V>, len: u32, f: impl Fn(&V) -> u64) -> Vec<u64> {
    (0..len).map(|i| f(&view.get(i).unwrap())).collect()
}

#[test]
fn replay_reproduces_views_bit_for_bit() {
    let (builder, keys) = toy_builder(config(3), true);
    let mut sim = builder.build().unwrap();
    let mut rng = Rng::from_seed(7);
    for tick in 0..300u32 {
        sim.begin_tick();
        for _ in 0..(rng.next_u64() % 6) {
            let cell = u32::try_from(rng.next_u64() % u64::from(CELLS)).unwrap();
            let amount = f32::from(u16::try_from(rng.next_u64() % 1000).unwrap()) / 10.0;
            let port = sim.port(keys.heat);
            match rng.next_u64() % 4 {
                0 => port.put(cell, Heat { energy: amount }).unwrap(),
                1 => drop(port.submit(cell, HeatCmd::Remove(amount)).unwrap()),
                2 => drop(port.take(cell).unwrap()),
                _ => drop(port.submit(cell, HeatCmd::Add(amount)).unwrap()),
            }
        }
        if tick % 2 == 0 {
            sim.dispatch_frame();
        }
        // DM ticks are far apart compared with this loop; wait now and then
        // so frames complete at varying points in the command stream.
        if rng.next_u64() % 5 == 0 {
            sim.wait_for_frame();
        }
    }
    sim.settle();
    assert!(sim.metrics().frames_completed > 10);
    let heat = Arc::clone(sim.port(keys.heat).pinned());
    let tally = Arc::clone(sim.port(keys.tally).pinned());
    let log = sim.take_log().unwrap();
    assert_eq!(log.frames.len() as u64, sim.metrics().frames_dispatched);

    for threads in [1, 4] {
        let (builder, rkeys) = toy_builder(config(threads), true);
        let mut replayed = Sim::replay(builder, &log).unwrap();
        let rheat = replayed.port(rkeys.heat).pinned();
        assert_eq!(rheat.version(), heat.version());
        assert_eq!(rheat.applied_through(), heat.applied_through());
        assert_eq!(
            bits(rheat, CELLS, |c| u64::from(c.energy.to_bits())),
            bits(&heat, CELLS, |c| u64::from(c.energy.to_bits())),
            "heat differs on replay with {threads} threads"
        );
        assert_eq!(
            rheat.shortfall_total().to_bits(),
            heat.shortfall_total().to_bits()
        );
        let rtally = replayed.port(rkeys.tally).pinned();
        assert_eq!(bits(rtally, 4, |v| *v), bits(&tally, 4, |v| *v));
    }
}

#[test]
fn dm_paths_never_wait_for_a_running_frame() {
    let gate = Arc::new(AtomicBool::new(false));
    let watchdog_fired = Arc::new(AtomicBool::new(false));
    let (mut builder, keys) = toy_builder(config(2), false);
    {
        let gate = Arc::clone(&gate);
        let heat = keys.heat.state();
        builder.add_task(
            Task::new("stall", move |ctx| {
                // Holds the heat state (the single writer) for the whole stall.
                let _st = ctx.write(heat);
                while !gate.load(Ordering::Acquire) {
                    std::thread::yield_now();
                }
            })
            .writes(heat.id()),
        );
    }
    let mut sim = builder.build().unwrap();
    sim.begin_tick();
    assert!(sim.dispatch_frame());
    let watchdog = {
        let gate = Arc::clone(&gate);
        let fired = Arc::clone(&watchdog_fired);
        std::thread::spawn(move || {
            for _ in 0..200 {
                if gate.load(Ordering::Acquire) {
                    return;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            fired.store(true, Ordering::Release);
            gate.store(true, Ordering::Release);
        })
    };

    // While the frame is stuck holding the writer, DM keeps going.
    for tick in 0..2_000u32 {
        sim.begin_tick();
        let cell = tick % CELLS;
        let port = sim.port(keys.heat);
        port.submit(cell, HeatCmd::Add(1.0)).unwrap();
        let seen = port.read(cell).unwrap().energy;
        assert!(seen >= 1.0, "DM reads its own write");
        assert!(!sim.dispatch_frame(), "no second frame while one runs");
    }
    gate.store(true, Ordering::Release);
    watchdog.join().unwrap();
    assert!(
        !watchdog_fired.load(Ordering::Acquire),
        "the main thread blocked"
    );

    assert_eq!(sim.port(keys.heat).backlog(), 2_000);
    let m = sim.metrics().clone();
    assert_eq!(m.command_backlog, 1_999, "as of the last begin_tick");
    assert!(m.view_age_ticks > sim.config().view_age_budget_ticks);
    assert!(m.view_age_over_budget > 0);
    assert!(m.dispatches_skipped >= 2_000);

    sim.settle();
    let port = sim.port(keys.heat);
    assert_eq!(port.overlay_len(), 0);
    for cell in 0..CELLS {
        assert_eq!(port.read(cell).unwrap().energy, 10.0);
    }
}

#[test]
fn fallback_applies_deltas_within_budget_and_rejects_dm_touched_pieces() {
    let config = SimConfig {
        mode: Mode::Fallback { budget_cells: 16 },
        record: false,
        ..config(2)
    };
    let (mut builder, keys) = toy_builder(config, false);
    let heat = keys.heat.state();
    builder.add_task(
        Task::new("double", move |ctx| {
            let mut st = ctx.write(heat);
            st.store.for_each_chunk_mut(|_, cells| {
                for c in cells {
                    c.energy *= 2.0;
                }
            });
        })
        .writes(heat.id()),
    );
    let mut sim = builder.build().unwrap();
    sim.begin_tick();
    for cell in 0..64 {
        sim.port(keys.heat).put(cell, Heat { energy: 1.0 }).unwrap();
    }
    // Writes apply synchronously: no overlay, no staleness.
    assert_eq!(sim.port(keys.heat).read(3).unwrap().energy, 1.0);
    assert_eq!(sim.port(keys.heat).backlog(), 0);
    assert!(sim.dispatch_frame());
    // DM touches chunk 0 after the snapshot: that piece must be rejected.
    sim.port(keys.heat).submit(5, HeatCmd::Add(0.5)).unwrap();
    sim.wait_for_frame();

    sim.begin_tick();
    let stats = sim.port(keys.heat).fallback_stats().unwrap();
    assert_eq!(
        stats.applied_pieces + stats.rejected_pieces,
        1,
        "one 16-cell piece per tick"
    );
    assert!(
        !sim.dispatch_frame(),
        "no new frame until the deltas are applied"
    );
    for _ in 0..3 {
        sim.begin_tick();
    }
    let stats = sim.port(keys.heat).fallback_stats().unwrap();
    assert_eq!(stats.pending_pieces, 0);
    assert_eq!(stats.applied_pieces, 3);
    assert_eq!(stats.rejected_pieces, 1);
    let port = sim.port(keys.heat);
    assert_eq!(port.read(5).unwrap().energy, 1.5, "DM's write survives");
    assert_eq!(
        port.read(6).unwrap().energy,
        1.0,
        "rejected piece left alone"
    );
    assert_eq!(port.read(20).unwrap().energy, 2.0, "applied piece");
    assert_eq!(port.read(100).unwrap().energy, 0.0);
    assert!(sim.dispatch_frame());
}

#[test]
fn scratch_values_transfer_out_and_back() {
    let (builder, keys) = toy_builder(config(1), false);
    let mut sim = builder.build().unwrap();
    sim.begin_tick();
    let port = sim.port(keys.heat);
    port.put(9, Heat { energy: 10.0 }).unwrap();
    // Remove-then-merge (§3.5): one command out, one command in.
    let scratch = port
        .extract(9, |cur| {
            let part = cur.energy / 4.0;
            (HeatCmd::Remove(part), Heat { energy: part })
        })
        .unwrap();
    assert_eq!(scratch.get().energy, 2.5);
    assert_eq!(port.read(9).unwrap().energy, 7.5);
    port.assume(10, scratch, |h| HeatCmd::Add(h.energy))
        .unwrap();
    assert_eq!(port.read(10).unwrap().energy, 2.5);
    // Transfer out to a main-owned slot, kept past the tick.
    let taken = port.take(9).unwrap();
    assert_eq!(port.read(9).unwrap(), Heat::default());
    let mut main_owned = Arena::new();
    let handle = taken.promote(&mut main_owned).unwrap();
    assert_eq!(main_owned.get(handle).unwrap().energy, 7.5);
    assert!(port.submit(CELLS, HeatCmd::Add(1.0)).is_err());
    sim.settle();
    assert_eq!(sim.port(keys.heat).pinned().get(10).unwrap().energy, 2.5);
    assert_eq!(
        sim.port(keys.heat).pinned().get(9).unwrap(),
        Heat::default()
    );
}

#[test]
fn a_panicking_task_is_reported_and_the_sim_continues() {
    let (mut builder, keys) = toy_builder(config(2), false);
    let calls = Arc::new(AtomicU32::new(0));
    {
        let calls = Arc::clone(&calls);
        builder.add_task(Task::new("flaky", move |ctx| {
            calls.fetch_add(1, Ordering::Relaxed);
            assert!(ctx.frame() != 1, "boom on frame 1");
        }));
    }
    let mut sim = builder.build().unwrap();
    for _ in 0..3 {
        sim.begin_tick();
        sim.port(keys.heat).submit(0, HeatCmd::Add(1.0)).unwrap();
        sim.dispatch_frame();
        sim.wait_for_frame();
    }
    sim.settle();
    assert_eq!(sim.metrics().frame_panics, 1);
    assert!(
        sim.metrics()
            .last_panic
            .as_deref()
            .unwrap()
            .contains("boom")
    );
    assert_eq!(sim.port(keys.heat).read(0).unwrap().energy, 3.0);
    assert!(calls.load(Ordering::Relaxed) >= 3);
}

// --- Overlay property tests (§3.4, §12) ---------------------------------

#[derive(Clone, Debug)]
enum Step {
    Add(u32, f32),
    Remove(u32, f32),
    Put(u32, f32),
    Take(u32),
    BeginTick,
    Dispatch,
    WaitForFrame,
}

fn step() -> impl Strategy<Value = Step> {
    let cell = 0..CELLS;
    let amount = (0u16..2000).prop_map(|a| f32::from(a) / 8.0);
    prop_oneof![
        4 => (cell.clone(), amount.clone()).prop_map(|(c, a)| Step::Add(c, a)),
        3 => (cell.clone(), amount.clone()).prop_map(|(c, a)| Step::Remove(c, a)),
        2 => (cell.clone(), amount).prop_map(|(c, a)| Step::Put(c, a)),
        1 => cell.prop_map(Step::Take),
        2 => Just(Step::BeginTick),
        2 => Just(Step::Dispatch),
        1 => Just(Step::WaitForFrame),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 96, ..ProptestConfig::default() })]

    /// Overlay-plus-view reads always equal a synchronous reference model,
    /// whatever the frame timing, and once every command is committed the
    /// pinned view alone equals the same model (reads after commit).
    #[test]
    fn overlay_reads_equal_reads_after_commit(steps in prop::collection::vec(step(), 1..200)) {
        let (builder, keys) = toy_builder(SimConfig { record: false, ..config(2) }, false);
        let mut sim = builder.build().unwrap();
        let mut reference = vec![Heat::default(); CELLS as usize];
        sim.begin_tick();
        for s in steps {
            match s {
                Step::Add(c, a) | Step::Remove(c, a) => {
                    let cmd = if matches!(s, Step::Add(..)) { HeatCmd::Add(a) } else { HeatCmd::Remove(a) };
                    let want = HeatDomain::apply(&mut reference[c as usize], &cmd);
                    let got = sim.port(keys.heat).submit(c, cmd).unwrap();
                    prop_assert_eq!(got, want, "DM sees the same result the owner applies");
                }
                Step::Put(c, a) => {
                    reference[c as usize] = Heat { energy: a };
                    sim.port(keys.heat).put(c, Heat { energy: a }).unwrap();
                }
                Step::Take(c) => {
                    let got = sim.port(keys.heat).take(c).unwrap().into_inner();
                    prop_assert_eq!(got, reference[c as usize]);
                    reference[c as usize] = Heat::default();
                }
                Step::BeginTick => sim.begin_tick(),
                Step::Dispatch => { sim.dispatch_frame(); }
                Step::WaitForFrame => sim.wait_for_frame(),
            }
            let port = sim.port_ref(keys.heat);
            for c in 0..CELLS {
                prop_assert_eq!(port.read(c).unwrap(), reference[c as usize], "cell {}", c);
            }
        }
        sim.settle();
        let port = sim.port_ref(keys.heat);
        prop_assert_eq!(port.overlay_len(), 0);
        prop_assert_eq!(port.backlog(), 0);
        for c in 0..CELLS {
            prop_assert_eq!(port.pinned().get(c).unwrap(), reference[c as usize], "cell {}", c);
        }
    }
}

// --- Watches, the outbox and the reactor end to end (R5) ------------------

fn joules(v: f32) -> Quantity {
    Quantity::new(v, Unit::Joules)
}

#[test]
fn watches_wake_subscribers_through_the_outbox_and_reactor() {
    let (mut builder, keys) = toy_builder(config(2), true);
    let watches = builder.add_watches(keys.heat);
    builder.declare_condition(
        keys.heat,
        "hot cell",
        Cond::Threshold {
            cell: 0,
            level: Level::above(heat_ch::ENERGY, joules(1.0)),
        },
    );
    let mut sim = builder.build().unwrap();
    let mut reactor = Reactor::new(0);
    sim.begin_tick();
    // Subscriber 1: cell 100 gets hot. Subscriber 2: any change at cell 101.
    // Subscriber 3: the gradient across a door between cells 10 and 190.
    let hot = sim
        .watches(watches)
        .watch(
            1,
            Lane::Urgent,
            &Cond::Threshold {
                cell: 100,
                level: Level::above(heat_ch::ENERGY, joules(20.0)),
            },
        )
        .unwrap();
    sim.watches(watches)
        .watch(
            2,
            Lane::Normal,
            &Cond::Changed {
                cell: 101,
                mask: heat_ch::ENERGY.bit(),
            },
        )
        .unwrap();
    sim.watches(watches)
        .watch(
            3,
            Lane::Background,
            &Cond::Difference {
                a: 10,
                b: 190,
                level: Level::above(heat_ch::ENERGY, joules(50.0)),
                abs: true,
            },
        )
        .unwrap();
    assert!(
        sim.watches(watches)
            .check(&Cond::Changed {
                cell: CELLS,
                mask: 1
            })
            .is_err()
    );
    sim.port(keys.heat)
        .put(100, Heat { energy: 400.0 })
        .unwrap();
    sim.port(keys.heat).put(10, Heat { energy: 400.0 }).unwrap();

    let mut woken: Vec<(u32, u32)> = Vec::new();
    for tick in 1..=40u64 {
        sim.wait_for_frame();
        sim.begin_tick();
        let out = sim.drain(keys.heat);
        reactor.ingest(out.wakes());
        reactor.tick(tick);
        let mut wakes = Vec::new();
        reactor.drain(64, &mut wakes);
        woken.extend(wakes.iter().map(|w| (w.subscriber, w.reason)));
        sim.dispatch_frame();
    }
    let count = |s: u32| woken.iter().filter(|w| w.0 == s).count();
    assert_eq!(count(1), 1, "the threshold fires once and stays inside");
    assert!(count(2) >= 2, "diffusion keeps changing cell 101");
    assert_eq!(count(3), 1, "the door gradient appeared once");
    assert!(
        woken
            .iter()
            .any(|&(s, r)| s == 1 && r == reason::CONDITION | heat_ch::ENERGY.bit())
    );
    // Removing a watch silences it.
    sim.watches(watches).unwatch(hot).unwrap();
    sim.port(keys.heat).put(100, Heat { energy: 0.0 }).unwrap();
    sim.settle();
    sim.port(keys.heat)
        .put(100, Heat { energy: 900.0 })
        .unwrap();
    sim.settle();
    assert!(
        sim.drain(keys.heat)
            .wakes()
            .iter()
            .all(|w| w.subscriber != 1)
    );
}

#[test]
fn take_results_make_transfer_out_conserve() {
    let (builder, keys) = toy_builder(config(2), true);
    let mut sim = builder.build().unwrap();
    sim.begin_tick();
    for cell in 0..CELLS {
        sim.port(keys.heat)
            .put(
                cell,
                Heat {
                    energy: f32::from(u16::try_from(cell % 7).unwrap()) * 10.0,
                },
            )
            .unwrap();
    }
    sim.settle();
    let _ = sim.drain(keys.heat);
    let total = |sim: &mut Sim| -> f64 {
        let v = Arc::clone(sim.port(keys.heat).pinned());
        (0..CELLS)
            .map(|i| f64::from(v.get(i).unwrap().energy))
            .sum()
    };
    let before = total(&mut sim);
    let first_frame = sim.metrics().frames_completed;
    let mut seen = 0.0f64;
    let mut actual = 0.0f64;
    let mut takes = 0;
    for tick in 0..60u32 {
        sim.begin_tick();
        if tick % 3 == 0 {
            // DM takes what its pinned view shows; the worker has moved on.
            let cell = (tick * 37) % CELLS;
            seen += f64::from(sim.port(keys.heat).take(cell).unwrap().get().energy);
            takes += 1;
        }
        for t in sim.drain(keys.heat).takes() {
            actual += f64::from(t.value.energy);
        }
        sim.dispatch_frame();
    }
    sim.settle();
    let out = sim.drain(keys.heat);
    actual += out
        .takes()
        .iter()
        .map(|t| f64::from(t.value.energy))
        .sum::<f64>();
    let after = total(&mut sim);
    // Sparks add 1.0 on frames divisible by 3; count them in the frames run.
    let last_frame = sim.metrics().frames_completed;
    let sparks = (first_frame..last_frame).filter(|f| f % 3 == 0).count();
    let sparks = f64::from(u32::try_from(sparks).unwrap());
    let conserved = (after + actual - before - sparks).abs();
    assert!(takes > 10);
    assert!(
        conserved < 1e-2,
        "field + taken = before + sparks (off by {conserved})"
    );
    assert!(
        (seen - actual).abs() > 1e-3,
        "the pinned view lagged the worker, so the seen total alone does not conserve"
    );
}

#[test]
fn rate_models_schedule_crossings_on_the_wheel() {
    // A cell's worth of rot on the main side: no domain, no polling.
    let mut reactor = Reactor::new(1000);
    let rot = reactor.add_model(RateModel::linear(0.0, 0.25, 1000.0));
    reactor
        .watch_model(rot, 42, Lane::Background, Cmp::Above, 10.0)
        .unwrap();
    let mut fired_at = None;
    for tick in 1001..=1100 {
        reactor.tick(tick);
        let mut w = Vec::new();
        reactor.drain(8, &mut w);
        if !w.is_empty() {
            assert_eq!(w[0].reason, reason::RATE);
            fired_at.get_or_insert(tick);
        }
    }
    assert_eq!(fired_at, Some(1040));
}
