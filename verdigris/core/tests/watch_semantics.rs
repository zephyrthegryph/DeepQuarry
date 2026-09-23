//! Watch semantics (`rust_core.md` §6.2–§6.4): every kind, its edge cases,
//! hysteresis, merged and spurious wakes, stale records, and validation at
//! registration and at boot.

use proptest::prelude::*;
use vg_core::channel::{ChannelId, Quantity, Unit};
use vg_core::channels;
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::outbox::{EventKind, Lane, Outbox, Wake, WatchId, reason};
use vg_core::owner::{Applied, Domain};
use vg_core::reactor::WakeLanes;
use vg_core::sim::{BootError, BuildError, SimBuilder, SimConfig};
use vg_core::watch::{Cmp, Cond, Edge, Level, SetEntry, WatchError, WatchPort, WatchState};

#[derive(Clone, Debug, Default, PartialEq)]
struct Cell {
    kpa: f32,
    temp: f32,
    moles: [f32; 2],
    mode: u8,
}

struct Air;

impl Domain for Air {
    type Value = Cell;
    type Command = ();
    const NAME: &'static str = "air";
    fn apply(_: &mut Cell, (): &()) -> Applied {
        Applied::default()
    }
}

channels! { mod ch for Air {
    PRESSURE: Scalar<Kpa> hysteresis 0.5 => |c, o| o[0] = c.kpa,
    TEMPERATURE: Scalar<Kelvin> hysteresis 1.0 => |c, o| o[0] = c.temp,
    COMPOSITION: Vector(2)<Moles> hysteresis 0.01 => |c, o| o.copy_from_slice(&c.moles),
    MODE: Enum(3)<None> hysteresis 0.0 => |c, o| o[0] = f32::from(c.mode),
}}

const CELLS: u32 = 64;
const CHUNK: u32 = 8;

const fn kpa(v: f32) -> Quantity {
    Quantity::new(v, Unit::Kpa)
}

/// A domain store plus its watches, evaluated one frame at a time.
struct Harness {
    store: CowStore<Cell>,
    state: WatchState<Air>,
    port: WatchPort<Air>,
    out: Outbox<Cell>,
}

impl Harness {
    fn new() -> Self {
        let layout = ChunkLayout::linear_with_chunk(CELLS, CHUNK);
        Self {
            store: CowStore::new(layout),
            state: WatchState::new(layout),
            port: WatchPort::new(layout),
            out: Outbox::default(),
        }
    }

    fn watch(&mut self, sub: u32, cond: Cond) -> WatchId {
        self.port.watch(sub, Lane::Normal, &cond).unwrap()
    }

    fn set(&mut self, cell: u32, f: impl FnOnce(&mut Cell)) {
        f(self.store.get_mut(cell).unwrap());
    }

    fn kpa(&mut self, cell: u32, v: f32) {
        self.set(cell, |c| c.kpa = v);
    }

    /// One frame: registrations in, evaluate, filter; returns the wakes.
    fn frame(&mut self) -> Vec<Wake> {
        self.port.dispatch(&mut self.state);
        self.state.evaluate(&self.store, &mut self.out);
        self.drain().wakes().to_vec()
    }

    fn drain(&mut self) -> Outbox<Cell> {
        let mut out = std::mem::take(&mut self.out);
        self.port.filter(&mut out);
        out
    }
}

fn threshold(cell: u32, level: Level) -> Cond {
    Cond::Threshold { cell, level }
}

#[test]
fn changed_fires_past_hysteresis_from_the_last_fire() {
    let mut h = Harness::new();
    h.kpa(3, 100.0);
    h.watch(
        1,
        Cond::Changed {
            cell: 3,
            mask: ch::PRESSURE.bit() | ch::TEMPERATURE.bit(),
        },
    );
    assert!(h.frame().is_empty(), "registration primes the baseline");
    h.kpa(3, 100.3);
    assert!(h.frame().is_empty(), "within hysteresis");
    h.kpa(3, 100.6);
    let w = h.frame();
    assert_eq!(w.len(), 1, "drift accumulates against the baseline");
    assert_eq!(
        w[0].reason,
        ch::PRESSURE.bit(),
        "only the channel that moved"
    );
    assert_eq!(w[0].source, 3);
    h.kpa(3, 100.9);
    assert!(h.frame().is_empty(), "baseline moved to 100.6");
    h.set(3, |c| {
        c.kpa = 102.0;
        c.temp = 5.0;
    });
    let w = h.frame();
    assert_eq!(w.len(), 1, "one wake per watch per frame");
    assert_eq!(w[0].reason, ch::PRESSURE.bit() | ch::TEMPERATURE.bit());
}

#[test]
fn changed_compares_vectors_per_component_and_enums_exactly() {
    let mut h = Harness::new();
    h.watch(
        1,
        Cond::Changed {
            cell: 0,
            mask: ch::COMPOSITION.bit(),
        },
    );
    h.watch(
        2,
        Cond::Changed {
            cell: 0,
            mask: ch::MODE.bit(),
        },
    );
    h.frame();
    h.set(0, |c| c.moles = [0.005, 0.005]);
    assert!(h.frame().is_empty());
    h.set(0, |c| c.moles = [0.005, 0.02]);
    let w = h.frame();
    assert_eq!((w.len(), w[0].subscriber), (1, 1));
    h.set(0, |c| c.mode = 1);
    let w = h.frame();
    assert_eq!(
        (w.len(), w[0].subscriber, w[0].reason),
        (1, 2, ch::MODE.bit())
    );
}

#[test]
fn threshold_is_edge_triggered_with_hysteresis() {
    let mut h = Harness::new();
    h.kpa(0, 90.0);
    h.watch(
        1,
        threshold(0, Level::above(ch::PRESSURE, kpa(100.0)).hysteresis(5.0)),
    );
    assert!(h.frame().is_empty());
    h.kpa(0, 99.9);
    assert!(h.frame().is_empty());
    h.kpa(0, 100.0);
    let w = h.frame();
    assert_eq!(w.len(), 1, "enters at the limit");
    assert_eq!(w[0].reason, reason::CONDITION | ch::PRESSURE.bit());
    for v in [120.0, 96.0, 101.0, 95.0] {
        h.kpa(0, v);
        assert!(
            h.frame().is_empty(),
            "no refire while inside the band ({v})"
        );
    }
    h.kpa(0, 94.9);
    assert!(h.frame().is_empty(), "leaving is silent on an Enter edge");
    h.kpa(0, 99.0);
    assert!(h.frame().is_empty());
    h.kpa(0, 100.5);
    assert_eq!(h.frame().len(), 1, "fires again after a full uncross");

    // Below, with both edges and the channel's default hysteresis (0.5).
    let mut h = Harness::new();
    h.kpa(1, 50.0);
    h.watch(
        2,
        threshold(1, Level::below(ch::PRESSURE, kpa(10.0)).both_edges()),
    );
    h.frame();
    h.kpa(1, 10.0);
    assert_eq!(h.frame().len(), 1, "entered");
    h.kpa(1, 10.5);
    assert!(h.frame().is_empty(), "within the default hysteresis");
    h.kpa(1, 10.6);
    assert_eq!(h.frame().len(), 1, "left (Both)");
}

#[test]
fn a_condition_that_already_holds_fires_on_the_first_evaluation() {
    let mut h = Harness::new();
    h.kpa(5, 500.0);
    h.watch(1, threshold(5, Level::above(ch::PRESSURE, kpa(100.0))));
    assert_eq!(h.frame().len(), 1);
    // An Enter-only watch registered while outside does not fire.
    h.watch(2, threshold(5, Level::below(ch::PRESSURE, kpa(100.0))));
    assert!(h.frame().is_empty());
}

#[test]
fn a_crossing_undone_within_one_frame_is_invisible() {
    let mut h = Harness::new();
    h.kpa(0, 50.0);
    h.watch(
        1,
        threshold(0, Level::above(ch::PRESSURE, kpa(100.0)).both_edges()),
    );
    h.watch(
        2,
        Cond::Changed {
            cell: 0,
            mask: ch::PRESSURE.bit(),
        },
    );
    h.watch(
        3,
        Cond::Band {
            cell: 0,
            ch: ch::PRESSURE,
            unit: Unit::Kpa,
            levels: vec![75.0],
            hysteresis: None,
        },
    );
    assert_eq!(h.frame().len(), 1, "the band reports its start");
    h.kpa(0, 150.0);
    h.kpa(0, 50.0);
    assert!(
        h.frame().is_empty(),
        "crossed and uncrossed before the frame ended"
    );
    // Same within the hysteresis band of an inside threshold.
    h.kpa(0, 150.0);
    assert_eq!(h.frame().len(), 3);
    h.kpa(0, 10.0);
    h.kpa(0, 150.0);
    assert!(h.frame().is_empty());
}

#[test]
fn bands_move_up_at_the_level_and_down_past_the_hysteresis() {
    let mut h = Harness::new();
    h.kpa(0, 5.0);
    let band = |levels: Vec<f32>| Cond::Band {
        cell: 0,
        ch: ch::PRESSURE,
        unit: Unit::Kpa,
        levels,
        hysteresis: Some(2.0),
    };
    h.watch(1, band(vec![10.0, 20.0, 30.0]));
    assert_eq!(h.frame().len(), 1, "initial band 0");
    h.kpa(0, 10.0);
    assert_eq!(h.frame().len(), 1, "band 1 at the level");
    h.kpa(0, 8.5);
    assert!(h.frame().is_empty(), "held by hysteresis");
    h.kpa(0, 7.9);
    assert_eq!(h.frame().len(), 1, "back to band 0");
    h.kpa(0, 35.0);
    assert_eq!(h.frame().len(), 1, "a jump across bands is one wake");
    h.kpa(0, 19.0);
    assert_eq!(
        h.frame().len(),
        1,
        "19 < 30 - 2 leaves band 3; 19 >= 20 - 2 holds band 2"
    );
    h.kpa(0, 18.5);
    assert!(h.frame().is_empty(), "band 2 is held down to 18");
    h.kpa(0, 17.9);
    assert_eq!(h.frame().len(), 1, "band 1");
}

#[test]
fn difference_watches_two_cells_across_chunks() {
    let mut h = Harness::new();
    // Cells 1 and 60 are in different chunks: a change in either chunk
    // alone must evaluate the watch.
    h.kpa(1, 100.0);
    h.kpa(60, 100.0);
    let firedoor = Cond::Difference {
        a: 1,
        b: 60,
        level: Level::above(ch::PRESSURE, kpa(20.0))
            .hysteresis(5.0)
            .both_edges(),
        abs: true,
    };
    h.watch(7, firedoor);
    assert!(h.frame().is_empty());
    h.kpa(60, 75.0);
    let w = h.frame();
    assert_eq!(w.len(), 1, "|100 - 75| crossed 20 via the remote chunk");
    assert_eq!(w[0].source, 1);
    h.kpa(1, 70.0);
    assert_eq!(
        h.frame().len(),
        1,
        "|70 - 75| = 5 < 20 - 5: left (Both edges)"
    );
}

#[test]
fn threshold_sets_emit_payloads_and_drop_stale_generations() {
    let mut h = Harness::new();
    h.set(4, |c| c.temp = 300.0);
    let set = h.watch(
        9,
        Cond::ThresholdSet {
            cell: 4,
            ch: ch::TEMPERATURE,
        },
    );
    let entry = |payload, generation, limit| SetEntry {
        payload,
        generation,
        cmp: Cmp::Above,
        limit: Quantity::new(limit, Unit::Kelvin),
        hysteresis: Some(0.0),
        edge: Edge::Enter,
    };
    h.port.add_entry(set, entry(100, 1, 350.0)).unwrap(); // melts at 350
    h.port.add_entry(set, entry(200, 1, 400.0)).unwrap(); // boils at 400
    h.port.add_entry(set, entry(300, 1, 250.0)).unwrap(); // already past
    h.port.dispatch(&mut h.state);
    h.state.evaluate(&h.store, &mut h.out);
    let out = h.drain();
    assert_eq!(out.wakes().len(), 1);
    assert_eq!(out.events().len(), 1);
    let e = out.events()[0];
    assert_eq!(
        (e.kind, e.key, e.extra, e.generation, e.value),
        (EventKind::ThresholdCrossed, set.index, 300, 1, 1.0)
    );

    h.set(4, |c| c.temp = 450.0);
    h.state.evaluate(&h.store, &mut h.out);
    let out = h.drain();
    let mut payloads: Vec<u32> = out.events().iter().map(|e| e.extra).collect();
    payloads.sort_unstable();
    assert_eq!(
        payloads,
        [100, 200],
        "both crossed in one frame: two events"
    );
    assert_eq!(out.wakes().len(), 1, "but one merged wake");

    // A crossing produced for generation 1, then the ledger replaces the
    // entry with generation 2 before DM drains: the record is stale.
    h.set(4, |c| c.temp = 300.0);
    h.state.evaluate(&h.store, &mut h.out);
    h.set(4, |c| c.temp = 360.0);
    h.state.evaluate(&h.store, &mut h.out);
    h.port.add_entry(set, entry(100, 2, 500.0)).unwrap();
    h.port.remove_entry(set, 200).unwrap();
    let out = h.drain();
    assert!(
        out.events().is_empty(),
        "stale generation and removed payload dropped: {:?}",
        out.events()
    );
    h.port.dispatch(&mut h.state);
    h.set(4, |c| c.temp = 600.0);
    h.state.evaluate(&h.store, &mut h.out);
    let out = h.drain();
    assert_eq!(out.events().len(), 1);
    assert_eq!(
        (out.events()[0].extra, out.events()[0].generation),
        (100, 2)
    );
}

#[test]
fn any_merges_reasons_and_all_fires_on_the_conjunction() {
    let mut h = Harness::new();
    h.watch(
        1,
        Cond::Any(vec![
            threshold(0, Level::above(ch::PRESSURE, kpa(100.0))),
            Cond::Changed {
                cell: 0,
                mask: ch::TEMPERATURE.bit(),
            },
        ]),
    );
    h.watch(
        2,
        Cond::All(vec![
            threshold(0, Level::above(ch::PRESSURE, kpa(100.0))),
            Cond::Threshold {
                cell: 0,
                level: Level::above(ch::TEMPERATURE, Quantity::new(500.0, Unit::Kelvin)),
            },
        ]),
    );
    assert!(h.frame().is_empty());
    h.set(0, |c| {
        c.kpa = 150.0;
        c.temp = 10.0;
    });
    let w = h.frame();
    assert_eq!(w.len(), 1, "All still false");
    assert_eq!(
        w[0].reason,
        reason::CONDITION | ch::PRESSURE.bit() | ch::TEMPERATURE.bit()
    );
    h.set(0, |c| c.temp = 600.0);
    let w = h.frame();
    let subs: Vec<u32> = w.iter().map(|w| w.subscriber).collect();
    assert_eq!(subs, [1, 2], "Any: temperature moved; All: now both hold");
    h.set(0, |c| c.temp = 610.0);
    assert_eq!(
        h.frame().iter().filter(|w| w.subscriber == 2).count(),
        0,
        "All does not refire"
    );
}

#[test]
fn unchanged_chunks_are_not_evaluated_and_spurious_wakes_do_not_happen() {
    let mut h = Harness::new();
    for cell in 0..CELLS {
        h.watch(
            cell,
            threshold(cell, Level::above(ch::PRESSURE, kpa(100.0))),
        );
    }
    h.frame();
    assert_eq!(
        h.state.stats().evaluated,
        CELLS as usize,
        "every new watch once"
    );
    assert!(h.frame().is_empty());
    assert_eq!(h.state.stats().evaluated, 0, "nothing changed");
    h.kpa(17, 5.0);
    assert!(h.frame().is_empty(), "a change that crosses nothing");
    assert_eq!(h.state.stats().changed_chunks, 1);
    assert_eq!(
        h.state.stats().evaluated,
        CHUNK as usize,
        "only the changed chunk"
    );
}

#[test]
fn merged_wakes_reach_the_lanes_once_per_subscriber() {
    let mut h = Harness::new();
    h.watch(
        1,
        Cond::Changed {
            cell: 0,
            mask: ch::PRESSURE.bit(),
        },
    );
    h.watch(
        1,
        Cond::Changed {
            cell: 40,
            mask: ch::TEMPERATURE.bit(),
        },
    );
    h.frame();
    h.kpa(0, 5.0);
    h.set(40, |c| c.temp = 5.0);
    let wakes = h.frame();
    assert_eq!(wakes.len(), 2, "one per watch in the outbox");
    let mut lanes = WakeLanes::new();
    for w in &wakes {
        lanes.push_wake(w);
    }
    let mut out = Vec::new();
    lanes.drain(100, &mut out);
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].reason, ch::PRESSURE.bit() | ch::TEMPERATURE.bit());
}

#[test]
fn removed_watches_are_silent_and_ids_are_not_reused() {
    let mut h = Harness::new();
    let a = h.watch(
        1,
        Cond::Changed {
            cell: 0,
            mask: ch::PRESSURE.bit(),
        },
    );
    h.frame();
    h.kpa(0, 9.0);
    h.port.dispatch(&mut h.state);
    h.state.evaluate(&h.store, &mut h.out);
    // DM removes the watch after the frame produced a wake but before the drain.
    h.port.unwatch(a).unwrap();
    assert!(h.drain().wakes().is_empty());
    let b = h.watch(
        2,
        Cond::Changed {
            cell: 0,
            mask: ch::PRESSURE.bit(),
        },
    );
    assert_eq!(b.index, a.index);
    assert_ne!(b.generation, a.generation);
    assert_eq!(h.port.unwatch(a), Err(WatchError::StaleWatch(a)));
    h.frame();
    h.kpa(0, 20.0);
    let w = h.frame();
    assert_eq!((w.len(), w[0].subscriber), (1, 2));
}

#[test]
fn non_finite_values_hold_the_state() {
    let mut h = Harness::new();
    h.watch(1, threshold(0, Level::above(ch::PRESSURE, kpa(1.0))));
    h.watch(
        2,
        Cond::Changed {
            cell: 0,
            mask: ch::PRESSURE.bit(),
        },
    );
    h.frame();
    h.kpa(0, f32::NAN);
    assert!(h.frame().is_empty());
    h.kpa(0, 0.0);
    assert!(h.frame().is_empty());
}

#[test]
fn registration_rejects_bad_conditions() {
    let h = Harness::new();
    let p = kpa(1.0);
    let cases: Vec<(Cond, WatchError)> = vec![
        (
            threshold(0, Level::above(ChannelId(9), p)),
            WatchError::UnknownChannel(ChannelId(9)),
        ),
        (
            threshold(
                0,
                Level::above(ch::COMPOSITION, Quantity::new(1.0, Unit::Moles)),
            ),
            WatchError::NotScalar {
                channel: "COMPOSITION",
            },
        ),
        (
            threshold(0, Level::above(ch::TEMPERATURE, p)),
            WatchError::UnitMismatch {
                channel: "TEMPERATURE",
                expected: Unit::Kelvin,
                got: Unit::Kpa,
            },
        ),
        (
            threshold(0, Level::above(ch::PRESSURE, p).hysteresis(-1.0)),
            WatchError::BadHysteresis { hysteresis: -1.0 },
        ),
        (
            threshold(0, Level::above(ch::PRESSURE, kpa(f32::INFINITY))),
            WatchError::NonFinite {
                value: f32::INFINITY,
            },
        ),
        (
            threshold(CELLS, Level::above(ch::PRESSURE, p)),
            WatchError::CellOutOfRange {
                cell: CELLS,
                len: CELLS,
            },
        ),
        (
            Cond::Changed { cell: 0, mask: 0 },
            WatchError::BadMask { mask: 0 },
        ),
        (
            Cond::Changed {
                cell: 0,
                mask: 1 << 7,
            },
            WatchError::BadMask { mask: 1 << 7 },
        ),
        (
            Cond::Difference {
                a: 2,
                b: 2,
                level: Level::above(ch::PRESSURE, p),
                abs: false,
            },
            WatchError::SameCell { cell: 2 },
        ),
        (
            Cond::Band {
                cell: 0,
                ch: ch::PRESSURE,
                unit: Unit::Kpa,
                levels: vec![3.0, 2.0],
                hysteresis: None,
            },
            WatchError::BandLevels {
                reason: "must be strictly increasing",
            },
        ),
        (
            Cond::Band {
                cell: 0,
                ch: ch::PRESSURE,
                unit: Unit::Kpa,
                levels: vec![1.0, 1.4],
                hysteresis: None,
            },
            WatchError::BandLevels {
                reason: "must be further apart than the hysteresis",
            },
        ),
        (
            Cond::Band {
                cell: 0,
                ch: ch::PRESSURE,
                unit: Unit::Kpa,
                levels: vec![],
                hysteresis: None,
            },
            WatchError::BandLevels {
                reason: "are empty",
            },
        ),
        (Cond::Any(vec![]), WatchError::EmptyCombination),
        (
            Cond::All(vec![Cond::Changed { cell: 0, mask: 1 }]),
            WatchError::NotALevel,
        ),
        (
            Cond::Any(vec![Cond::Any(vec![Cond::Any(vec![Cond::Any(vec![
                Cond::Any(vec![Cond::Changed { cell: 0, mask: 1 }]),
            ])])])]),
            WatchError::TooDeep,
        ),
        (
            Cond::ThresholdSet {
                cell: 0,
                ch: ch::MODE,
            },
            WatchError::NotScalar { channel: "MODE" },
        ),
    ];
    for (cond, want) in cases {
        assert_eq!(h.port.check(&cond), Err(want.clone()), "{cond:?}");
        assert!(!want.to_string().is_empty());
    }
    let mut h = Harness::new();
    assert_eq!(
        h.port
            .watch(1 << 24, Lane::Normal, &Cond::Changed { cell: 0, mask: 1 }),
        Err(WatchError::BadSubscriber(1 << 24))
    );
    let plain = h.watch(1, Cond::Changed { cell: 0, mask: 1 });
    let e = SetEntry {
        payload: 1,
        generation: 0,
        cmp: Cmp::Above,
        limit: kpa(1.0),
        hysteresis: None,
        edge: Edge::Enter,
    };
    assert_eq!(h.port.add_entry(plain, e), Err(WatchError::NotASet(plain)));
}

// --- Boot validation ------------------------------------------------------

struct Broken;

impl Domain for Broken {
    type Value = Cell;
    type Command = ();
    const NAME: &'static str = "broken";
    fn apply(_: &mut Cell, (): &()) -> Applied {
        Applied::default()
    }
}

channels! { mod broken_ch for Broken {
    OK: Scalar<Kpa> hysteresis 0.5 => |c, o| o[0] = c.kpa,
    lower_case: Scalar<Kpa> hysteresis -2.0 => |c, o| o[0] = c.kpa,
}}

#[test]
fn boot_validation_reports_every_bad_declaration() {
    let mut b = SimBuilder::new(SimConfig {
        threads: 1,
        ..SimConfig::default()
    });
    let air = b.add_domain::<Air>(ChunkLayout::linear(CELLS));
    let broken = b.add_domain::<Broken>(ChunkLayout::linear(CELLS));
    let unwatched = b.add_domain::<Air2>(ChunkLayout::linear(4));
    b.add_watches(air);
    b.add_watches(broken);
    b.declare_condition(
        air,
        "overpressure",
        threshold(0, Level::above(ch::PRESSURE, kpa(5000.0))),
    );
    b.declare_condition(
        air,
        "hot air",
        threshold(0, Level::above(ch::TEMPERATURE, kpa(5000.0))),
    );
    b.declare_condition(
        air,
        "far cell (templates skip cell checks)",
        threshold(u32::MAX, Level::above(ch::PRESSURE, kpa(1.0))),
    );
    b.declare_condition(unwatched, "orphan", Cond::Changed { cell: 0, mask: 1 });
    let errors = b.boot_errors();
    assert_eq!(errors.len(), 4, "{errors:#?}");
    assert!(matches!(&errors[0], BootError::Channel(_)));
    assert!(
        matches!(&errors[2], BootError::Condition { name, error: WatchError::UnitMismatch { .. }, .. } if name == "hot air")
    );
    assert!(matches!(&errors[3], BootError::NoWatches { name, .. } if name == "orphan"));
    match b.build() {
        Err(BuildError::Boot(e)) => {
            assert_eq!(e.len(), 4);
            assert!(BuildError::Boot(e).to_string().contains("hot air"));
        }
        other => panic!("boot must fail, got {:?}", other.map(|_| ())),
    }
    let _ = broken_ch::OK;
}

struct Air2;

impl Domain for Air2 {
    type Value = Cell;
    type Command = ();
    const NAME: &'static str = "air2";
    fn apply(_: &mut Cell, (): &()) -> Applied {
        Applied::default()
    }
}

// --- Property: exactly once per crossing -------------------------------------

proptest! {
    /// A threshold fires exactly once per crossing: once for each time the
    /// frame-end value enters the condition after having left it past the
    /// hysteresis (reference state machine), and never otherwise.
    #[test]
    fn thresholds_fire_exactly_once_per_crossing(
        values in prop::collection::vec(0.0f32..200.0, 1..120),
        limit in 50.0f32..150.0,
        hyst in 0.0f32..20.0,
        above in any::<bool>(),
    ) {
        let mut h = Harness::new();
        let level = if above { Level::above(ch::PRESSURE, kpa(limit)) } else { Level::below(ch::PRESSURE, kpa(limit)) };
        h.watch(1, threshold(0, level.hysteresis(hyst)));
        h.watch(2, threshold(0, level.hysteresis(hyst).both_edges()));
        let mut inside = false;
        for v in values {
            h.kpa(0, v);
            let wakes = h.frame();
            let enters = if above { v >= limit } else { v <= limit };
            let stays = if above { v >= limit - hyst } else { v <= limit + hyst };
            let now = if inside { stays } else { enters };
            let entered = now && !inside;
            let left = !now && inside;
            inside = now;
            prop_assert_eq!(wakes.iter().filter(|w| w.subscriber == 1).count(), usize::from(entered));
            prop_assert_eq!(wakes.iter().filter(|w| w.subscriber == 2).count(), usize::from(entered || left));
        }
    }
}
