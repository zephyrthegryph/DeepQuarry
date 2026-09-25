//! R6 field framework: conservation properties, reference solutions,
//! determinism across thread counts, sleeping and waking, and the sim
//! integration (commands, `Take`, watches) on the toy heat and gas fields.

use std::sync::Arc;

use proptest::prelude::*;
use vg_core::channel::{Quantity, Unit};
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::field::toy::{
    GasCell, GasCmd, GasToy, HEAT_CONDUCTANCE, HeatCell, HeatCmd, HeatToy, heat_ch,
};
use vg_core::field::{FieldConfig, FieldKind, FieldState, Geom, GeomCmd, add_field};
use vg_core::grid::{Dir, Face, GridDims};
use vg_core::outbox::Lane;
use vg_core::owner::apply_op;
use vg_core::sim::{SimBuilder, SimConfig};
use vg_core::watch::{Cond, Level};

/// A field outside the sim: stores, state and a pool.
struct World<K: FieldKind> {
    dims: GridDims,
    cells: CowStore<K::Value>,
    geom: CowStore<Geom>,
    field: FieldState<K>,
}

impl<K: FieldKind> World<K> {
    fn new(dims: GridDims, config: FieldConfig) -> Self {
        let layout = ChunkLayout::spatial(dims);
        Self {
            dims,
            cells: CowStore::new(layout),
            geom: CowStore::new(layout),
            field: FieldState::new(dims, config),
        }
    }

    fn len(&self) -> u32 {
        self.dims.layer_len() * self.dims.max_z()
    }

    fn step(&mut self, pool: &rayon::ThreadPool) {
        pool.install(|| self.field.step(&mut self.cells, &self.geom, None));
    }

    fn cell(&self, i: u32) -> K::Value {
        self.cells.get(i).unwrap()
    }

    fn totals(&self) -> Vec<f64> {
        FieldState::<K>::totals(&self.cells, &self.geom)
    }

    /// Cell totals plus what went into reservoirs.
    fn conserved(&self) -> Vec<f64> {
        self.totals()
            .iter()
            .zip(self.field.ledger())
            .map(|(a, b)| a + b)
            .collect()
    }
}

fn pool(threads: usize) -> rayon::ThreadPool {
    rayon::ThreadPoolBuilder::new()
        .num_threads(threads)
        .build()
        .unwrap()
}

fn temperature(w: &World<HeatToy>, i: u32) -> f64 {
    f64::from(w.cell(i).energy) / f64::from(w.geom.get(i).unwrap().capacity)
}

// ---------------------------------------------------------------- reference

/// One explicit step of `dT/dt = (G/C) * laplacian(T)` with no-flux ends.
fn reference_step(t: &[f64], r: f64) -> Vec<f64> {
    let n = t.len();
    (0..n)
        .map(|i| {
            let mut lap = 0.0;
            if i > 0 {
                lap += t[i - 1] - t[i];
            }
            if i + 1 < n {
                lap += t[i + 1] - t[i];
            }
            t[i] + r * lap
        })
        .collect()
}

#[test]
fn conduction_1d_matches_the_explicit_reference_step() {
    const N: u32 = 40;
    let dims = GridDims::new(N, 1, 1).unwrap();
    // r = G dt / C = 0.2: one sub-step (dt * faces * stiffness = 0.8).
    let config = FieldConfig {
        dt: 0.2,
        max_substeps: 16,
    };
    let mut w = World::<HeatToy>::new(dims, config);
    let mut reference = Vec::new();
    for i in 0..N {
        let t = 300.0 + 80.0 * (f64::from(i) * 0.7).sin() + if i == 17 { 500.0 } else { 0.0 };
        #[allow(clippy::cast_possible_truncation)]
        let cell = HeatCell::at(1.0, t as f32);
        w.geom.set(i, Geom::cell(1.0));
        w.cells.set(i, cell);
        reference.push(f64::from(cell.energy));
    }
    let pool = pool(2);
    let r = f64::from(HEAT_CONDUCTANCE * config.dt);
    for _ in 0..60 {
        // Keep every chunk awake so sleeping cannot freeze a region.
        w.field.wake_all();
        w.step(&pool);
        assert_eq!(w.field.stats().substeps, 1);
        reference = reference_step(&reference, r);
    }
    for i in 0..N {
        let got = temperature(&w, i);
        assert!(
            (got - reference[i as usize]).abs() < 2e-3,
            "cell {i}: {got} vs {}",
            reference[i as usize]
        );
    }
}

#[test]
fn a_cosine_mode_decays_at_the_discrete_and_analytic_rate() {
    const N: u32 = 64;
    let dims = GridDims::new(N, 1, 1).unwrap();
    let dt = 0.1;
    let mut w = World::<HeatToy>::new(
        dims,
        FieldConfig {
            dt,
            max_substeps: 16,
        },
    );
    // The first no-flux eigenmode: cos(pi (i + 1/2) / N).
    let k = std::f64::consts::PI / f64::from(N);
    let mode = |i: u32| (k * (f64::from(i) + 0.5)).cos();
    for i in 0..N {
        w.geom.set(i, Geom::cell(1.0));
        #[allow(clippy::cast_possible_truncation)]
        w.cells
            .set(i, HeatCell::at(1.0, (1000.0 + 100.0 * mode(i)) as f32));
    }
    let pool = pool(1);
    let steps = 400;
    for _ in 0..steps {
        w.field.wake_all();
        w.step(&pool);
    }
    // Project onto the mode to measure its amplitude.
    let norm: f64 = (0..N).map(|i| mode(i) * mode(i)).sum();
    let amp = (0..N)
        .map(|i| (temperature(&w, i) - 1000.0) * mode(i))
        .sum::<f64>()
        / norm;
    let r = f64::from(HEAT_CONDUCTANCE) * f64::from(dt);
    let discrete = 100.0 * (1.0 - 2.0 * r * (1.0 - k.cos())).powi(steps);
    let t = f64::from(dt) * f64::from(steps);
    let analytic = 100.0 * (-f64::from(HEAT_CONDUCTANCE) * k * k * t).exp();
    assert!(
        (amp - discrete).abs() < 1e-3 * 100.0,
        "{amp} vs discrete {discrete}"
    );
    assert!(
        (amp - analytic).abs() / analytic < 0.01,
        "{amp} vs analytic {analytic}"
    );
}

/// Steps until every chunk sleeps (or `max` steps), returning the steps run.
fn run_to_sleep<K: FieldKind>(w: &mut World<K>, pool: &rayon::ThreadPool, max: u32) -> u32 {
    for n in 1..=max {
        w.step(pool);
        if w.field.active_chunks().next().is_none() {
            return n;
        }
    }
    panic!("the field never settled in {max} steps");
}

#[test]
fn walled_regions_equilibrate_separately_then_together_when_opened() {
    let dims = GridDims::new(24, 16, 1).unwrap();
    let mut w = World::<HeatToy>::new(
        dims,
        FieldConfig {
            dt: 2.0,
            max_substeps: 64,
        },
    );
    let wall_x = 10;
    let mut region = [(0.0f64, 0.0f64); 2];
    for y in 0..16 {
        for x in 0..24 {
            let i = dims.index(x, y, 0).unwrap();
            let cap = 0.5 + f32::from(u8::try_from((x * 7 + y * 3) % 5).unwrap()) * 0.4;
            let t = 100.0 + f32::from(u8::try_from((x * 13 + y * 29) % 17).unwrap()) * 40.0;
            let mut g = Geom::cell(cap);
            if x == wall_x {
                g.blocked = Dir::NONE.with(Face::East);
            }
            w.geom.set(i, g);
            w.cells.set(i, HeatCell::at(cap, t));
            let side = usize::from(x > wall_x);
            region[side].0 += f64::from(cap * t);
            region[side].1 += f64::from(cap);
        }
    }
    let pool = pool(3);
    run_to_sleep(&mut w, &pool, 3000);
    for y in 0..16 {
        for x in 0..24 {
            let (e, c) = region[usize::from(x > wall_x)];
            let got = temperature(&w, dims.index(x, y, 0).unwrap());
            assert!((got - e / c).abs() < 0.3, "({x},{y}): {got} vs {}", e / c);
        }
    }
    // Open the wall with one geometry command: its chunk wakes.
    let door = dims.index(wall_x, 5, 0).unwrap();
    let mut g = w.geom.get(door).unwrap();
    apply_op::<vg_core::field::Geometry<HeatToy>>(
        &mut g,
        &vg_core::command::Op::Apply(GeomCmd::Blocked(Dir::NONE)),
    );
    w.geom.set(door, g);
    let before = w.totals()[0];
    run_to_sleep(&mut w, &pool, 5000);
    let all = (region[0].0 + region[1].0) / (region[0].1 + region[1].1);
    for i in 0..w.len() {
        let t = temperature(&w, i);
        assert!((t - all).abs() < 0.5, "cell {i}: {t} vs {all}");
    }
    // Every step conserves to f32 rounding (the property tests check each
    // step at 2e-6); over thousands of steps near equilibrium the rounding
    // random-walks, so the long-run bound is looser.
    let after = w.totals()[0];
    assert!(
        (after - before).abs() < 1e-4 * before,
        "{after} vs {before}"
    );
}

#[test]
fn a_reservoir_pulls_its_neighbours_to_its_temperature_and_books_the_flow() {
    let dims = GridDims::new(20, 1, 1).unwrap();
    let mut w = World::<HeatToy>::new(
        dims,
        FieldConfig {
            dt: 1.0,
            max_substeps: 16,
        },
    );
    w.geom.set(0, Geom::reservoir(1.0));
    w.cells.set(0, HeatCell::at(1.0, 100.0));
    for i in 1..20 {
        w.geom.set(i, Geom::cell(1.0));
        w.cells.set(i, HeatCell::at(1.0, 300.0));
    }
    let initial = w.conserved()[0];
    run_to_sleep(&mut w, &pool(2), 20_000);
    assert_eq!(
        w.cell(0),
        HeatCell::at(1.0, 100.0),
        "reservoirs never change"
    );
    for i in 1..20 {
        assert!((temperature(&w, i) - 100.0).abs() < 0.3);
    }
    assert!(w.field.ledger()[0] > 3700.0);
    // f32 cells: conserved to rounding over thousands of steps.
    assert!(
        (w.conserved()[0] - initial).abs() < 1e-5 * initial,
        "{:?} vs {initial}",
        w.conserved()
    );
}

#[test]
fn gas_reaches_uniform_pressure_and_composition() {
    let dims = GridDims::new(12, 8, 1).unwrap();
    let mut w = World::<GasToy>::new(
        dims,
        FieldConfig {
            dt: 1.0,
            max_substeps: 32,
        },
    );
    let mut sum = [0.0f64; 3];
    for i in 0..w.len() {
        let (x, _, _) = dims.coords(i).unwrap();
        w.geom.set(i, Geom::cell(2.5));
        // Left: dense, hot, pure A. Right: thin, cold, pure B.
        let cell = if x < 4 {
            GasCell {
                amounts: [10.0, 0.0, 10.0 * 1.5 * 400.0],
                pressure: 0.0,
            }
        } else {
            GasCell {
                amounts: [0.0, 2.0, 2.0 * 1.5 * 200.0],
                pressure: 0.0,
            }
        };
        for (s, v) in sum.iter_mut().zip(cell.amounts) {
            *s += f64::from(v);
        }
        w.cells.set(i, cell);
    }
    let initial = w.conserved();
    run_to_sleep(&mut w, &pool(2), 20_000);
    let n = f64::from(w.len());
    for i in 0..w.len() {
        let c = w.cell(i);
        for (q, total) in sum.iter().enumerate() {
            let want = total / n;
            assert!(
                (f64::from(c.amounts[q]) - want).abs() < 2e-3 * want.max(1.0),
                "cell {i} quantity {q}: {} vs {want}",
                c.amounts[q]
            );
        }
    }
    for (a, b) in w.conserved().iter().zip(&initial) {
        assert!((a - b).abs() < 1e-5 * b.abs().max(1.0));
    }
}

// ------------------------------------------------------------ conservation

/// A random world description for the property tests.
#[derive(Clone, Debug)]
struct Setup {
    x: u32,
    y: u32,
    z: u32,
    cells: Vec<(u8, u8, u8, u16)>,
    events: Vec<(u8, u16, u16)>,
    steps: u8,
}

fn setup() -> impl Strategy<Value = Setup> {
    (1u32..40, 1u32..40, 1u32..3, 1u8..8).prop_flat_map(|(x, y, z, steps)| {
        let n = (x * y * z) as usize;
        (
            proptest::collection::vec((any::<u8>(), any::<u8>(), any::<u8>(), any::<u16>()), n),
            proptest::collection::vec((any::<u8>(), any::<u16>(), any::<u16>()), 0..24),
        )
            .prop_map(move |(cells, events)| Setup {
                x,
                y,
                z,
                cells,
                events,
                steps,
            })
    })
}

/// Capacity (a fifth of cells are walls), reservoir flag, blocked mask.
fn geom_of(kind: u8, cap: u8, mask: u8) -> Geom {
    let capacity = if kind % 5 == 0 {
        0.0
    } else {
        0.2 + f32::from(cap) / 50.0
    };
    Geom {
        capacity,
        blocked: if mask % 4 == 0 {
            Dir(mask >> 2)
        } else {
            Dir::NONE
        },
        reservoir: kind % 23 == 1,
    }
}

/// Applies a command the way the owner does, returning it for replay.
fn command<K: FieldKind>(w: &mut World<K>, cell: u32, cmd: &K::Command) -> f32 {
    let value = w.cells.get_mut(cell).unwrap();
    K::apply(value, cmd).shortfall
}

/// Runs a setup, applying sources, sinks, takes and geometry changes
/// between steps, and checks cells + reservoirs + net transfers stay
/// constant. `make` builds a cell from a seed and capacity, `source`
/// turns an event into a source or sink command (the check measures
/// what it actually changed).
fn check_conservation<K: FieldKind>(
    s: &Setup,
    threads: usize,
    make: impl Fn(u16, f32) -> K::Value,
    source: impl Fn(u8, u16) -> K::Command,
) -> Result<(), TestCaseError> {
    let dims = GridDims::new(s.x, s.y, s.z).unwrap();
    let mut w = World::<K>::new(
        dims,
        FieldConfig {
            dt: 1.0,
            max_substeps: 8,
        },
    );
    for (i, &(kind, cap, mask, seed)) in s.cells.iter().enumerate() {
        let i = u32::try_from(i).unwrap();
        let g = geom_of(kind, cap, mask);
        w.geom.set(i, g);
        w.cells.set(i, make(seed, g.capacity.max(0.5)));
    }
    let pool = pool(threads);
    let mut expected = w.conserved();
    let scale: f64 = expected.iter().map(|v| v.abs()).sum::<f64>().max(1.0);
    let len = w.len();
    let mut events = s.events.iter();
    for _ in 0..s.steps {
        for &(what, at, amount) in events.by_ref().take(4) {
            let cell = u32::from(at) % len;
            let reservoir = w.geom.get(cell).unwrap().reservoir;
            match what % 4 {
                0 | 1 => {
                    // A source or sink. Removal clamps; count what it took.
                    let cmd = source(what, amount);
                    let before = w.cell(cell);
                    command(&mut w, cell, &cmd);
                    if !reservoir {
                        let mut b = vec![0.0; K::QUANTITIES];
                        let mut a = vec![0.0; K::QUANTITIES];
                        K::totals(&before, &mut b);
                        K::totals(&w.cell(cell), &mut a);
                        for q in 0..K::QUANTITIES {
                            expected[q] += a[q] - b[q];
                        }
                    }
                }
                2 => {
                    // Take: the exact value leaves.
                    let taken = w.cell(cell);
                    w.cells.set(cell, K::Value::default());
                    if !reservoir {
                        let mut t = vec![0.0; K::QUANTITIES];
                        K::totals(&taken, &mut t);
                        for q in 0..K::QUANTITIES {
                            expected[q] -= t[q];
                        }
                    }
                }
                _ => {
                    // Geometry: a new capacity or a new mask (never the
                    // reservoir flag, which moves a cell out of the sum).
                    let mut g = w.geom.get(cell).unwrap();
                    if amount % 2 == 0 {
                        g.capacity = if amount % 3 == 0 {
                            0.0
                        } else {
                            0.3 + f32::from(amount % 200) / 40.0
                        };
                    } else {
                        g.blocked = Dir(u8::try_from(amount % 64).unwrap());
                    }
                    w.geom.set(cell, g);
                }
            }
        }
        w.step(&pool);
        let got = w.conserved();
        for q in 0..K::QUANTITIES {
            prop_assert!(
                (got[q] - expected[q]).abs() <= 2e-6 * scale + 1e-3,
                "quantity {q}: {} vs {} (scale {scale})",
                got[q],
                expected[q]
            );
        }
        for i in 0..len {
            let mut t = vec![0.0; K::QUANTITIES];
            K::totals(&w.cell(i), &mut t);
            prop_assert!(
                t.iter().all(|v| v.is_finite() && *v >= -1e-3),
                "cell {i}: {t:?}"
            );
        }
    }
    Ok(())
}

fn heat_cell(seed: u16, capacity: f32) -> HeatCell {
    HeatCell::at(capacity, f32::from(seed % 2000))
}

fn heat_source(what: u8, amount: u16) -> HeatCmd {
    let e = f32::from(amount % 5000);
    if what % 4 == 0 {
        HeatCmd::Add(e)
    } else {
        HeatCmd::Remove(e)
    }
}

fn gas_cell(seed: u16, capacity: f32) -> GasCell {
    let a = f32::from(seed % 97) * capacity / 10.0;
    let b = f32::from(seed % 13) * capacity / 5.0;
    let t = 50.0 + f32::from(seed % 400);
    GasCell {
        amounts: [a, b, (a + b) * 1.5 * t],
        pressure: 0.0,
    }
}

fn gas_source(what: u8, amount: u16) -> GasCmd {
    let m = f32::from(amount % 300) / 10.0;
    let amounts = [m, m / 2.0, m * 1.5 * 300.0];
    if what % 4 == 0 {
        GasCmd::Add(amounts)
    } else {
        GasCmd::Remove(amounts)
    }
}

proptest! {
    #[test]
    fn heat_is_conserved_over_random_grids_blockers_sources_and_takes(s in setup()) {
        check_conservation::<HeatToy>(&s, 3, heat_cell, heat_source)?;
    }

    #[test]
    fn gas_is_conserved_over_random_grids_blockers_sources_and_takes(s in setup()) {
        check_conservation::<GasToy>(&s, 3, gas_cell, gas_source)?;
    }
}

// ------------------------------------------------------------- determinism

fn busy_gas_world() -> World<GasToy> {
    let dims = GridDims::new(70, 50, 2).unwrap();
    let mut w = World::<GasToy>::new(dims, FieldConfig::default());
    for i in 0..w.len() {
        let seed = u16::try_from((u64::from(i) * 2_654_435_761 % 65_521) as u32 % 60_000).unwrap();
        let g = geom_of(
            u8::try_from(seed % 251).unwrap(),
            (seed % 200) as u8,
            (seed % 97) as u8,
        );
        w.geom.set(i, g);
        w.cells.set(i, gas_cell(seed, g.capacity.max(0.5)));
    }
    w
}

#[test]
fn results_are_bit_identical_across_thread_counts() {
    let mut runs: Vec<World<GasToy>> = Vec::new();
    for threads in [1, 2, 3, 8] {
        let mut w = busy_gas_world();
        let pool = pool(threads);
        for _ in 0..6 {
            w.step(&pool);
        }
        runs.push(w);
    }
    let first = &runs[0];
    for w in &runs[1..] {
        assert!(w.cells.values_eq(&first.cells));
        let bits = |w: &World<GasToy>| {
            w.field
                .ledger()
                .iter()
                .map(|v| v.to_bits())
                .collect::<Vec<_>>()
        };
        assert_eq!(bits(w), bits(first));
        assert_eq!(w.field.stats(), first.field.stats());
    }
}

// ------------------------------------------------------------ sleep & wake

#[test]
fn settled_regions_sleep_untouched_and_wake_on_commands_and_neighbours() {
    let dims = GridDims::new(64, 64, 1).unwrap();
    let layout = ChunkLayout::spatial(dims);
    let mut w = World::<HeatToy>::new(
        dims,
        FieldConfig {
            dt: 1.0,
            max_substeps: 16,
        },
    );
    for i in 0..w.len() {
        w.geom.set(i, Geom::cell(1.0));
        w.cells.set(i, HeatCell::at(1.0, 300.0));
    }
    let pool = pool(2);
    // The first step wakes everything, finds it settled, and sleeps.
    w.step(&pool);
    assert_eq!(w.field.active_chunks().count(), 0);
    let quiet = w.cells.snapshot();
    w.step(&pool);
    assert_eq!(w.field.stats().touched_chunks, 0);
    assert_eq!(w.cells.shared_chunks_with(&quiet), layout.chunk_count());

    // A source in chunk (1,1) wakes that chunk only.
    let hot = dims.index(24, 24, 0).unwrap();
    let (hot_chunk, _) = layout.locate(hot).unwrap();
    let far = layout.locate(dims.index(60, 60, 0).unwrap()).unwrap().0;
    command(&mut w, hot, &HeatCmd::Add(50.0));
    let total = w.totals()[0];
    w.step(&pool);
    assert_eq!(w.field.stats().active_chunks, 1);
    assert!(w.field.is_active(hot_chunk));
    // Heat reaches the neighbouring chunks, which wake; the far corner
    // stays asleep and shared with the quiet snapshot.
    let mut ever = vec![false; layout.chunk_count()];
    for _ in 0..400 {
        for c in w.field.active_chunks() {
            ever[c] = true;
        }
        w.step(&pool);
        if w.field.active_chunks().next().is_none() {
            break;
        }
    }
    assert_eq!(w.field.active_chunks().count(), 0, "settles again");
    assert!(ever.iter().filter(|&&e| e).count() > 1, "activity spread");
    assert!(!ever[far]);
    assert_eq!(
        w.cells.chunk(far).unwrap().as_ptr(),
        quiet.chunk(far).unwrap().as_ptr(),
        "a sleeping chunk is never copied"
    );
    assert!((w.totals()[0] - total).abs() < 1e-6 * total);
}

// ------------------------------------------------------- sim integration

#[test]
fn a_field_runs_in_the_sim_with_commands_takes_and_watches() {
    let dims = GridDims::new(40, 20, 1).unwrap();
    let mut b = SimBuilder::new(SimConfig {
        threads: 2,
        seed: 7,
        ..SimConfig::default()
    });
    let key = add_field::<HeatToy>(
        &mut b,
        dims,
        FieldConfig {
            dt: 1.0,
            max_substeps: 16,
        },
        None,
    );
    let watches = b.add_watches(key.cells);
    let mut sim = b.build().unwrap();
    sim.begin_tick();
    let len = dims.layer_len();
    for i in 0..len {
        sim.port(key.geometry).put(i, Geom::cell(2.0)).unwrap();
        sim.port(key.cells)
            .put(i, HeatCell::at(2.0, 280.0))
            .unwrap();
    }
    let probe = dims.index(12, 10, 0).unwrap();
    let source = dims.index(10, 10, 0).unwrap();
    sim.watches(watches)
        .watch(
            1,
            Lane::Urgent,
            &Cond::Threshold {
                cell: probe,
                level: Level::above(heat_ch::TEMPERATURE, Quantity::new(290.0, Unit::Kelvin)),
            },
        )
        .unwrap();
    sim.settle();
    let total = |sim: &mut vg_core::sim::Sim| -> f64 {
        let v = Arc::clone(sim.port(key.cells).pinned());
        (0..len).map(|i| f64::from(v.get(i).unwrap().energy)).sum()
    };
    let before = total(&mut sim);
    let mut added = 0.0f64;
    let mut taken = 0.0f64;
    let mut fired = 0;
    for tick in 0..80u32 {
        sim.begin_tick();
        let out = sim.drain(key.cells);
        fired += out.wakes().iter().filter(|w| w.subscriber == 1).count();
        taken += out
            .takes()
            .iter()
            .map(|t| f64::from(t.value.energy))
            .sum::<f64>();
        if tick < 20 {
            sim.port(key.cells)
                .submit(source, HeatCmd::Add(400.0))
                .unwrap();
            added += 400.0;
        }
        if tick % 10 == 5 {
            let cell = (tick * 131) % len;
            let _ = sim.port(key.cells).take(cell).unwrap();
        }
        sim.dispatch_frame();
        sim.wait_for_frame();
    }
    sim.settle();
    taken += sim
        .drain(key.cells)
        .takes()
        .iter()
        .map(|t| f64::from(t.value.energy))
        .sum::<f64>();
    let after = total(&mut sim);
    assert!(fired >= 1, "the threshold watch saw heat arrive");
    assert!(taken > 0.0);
    assert!(
        (after + taken - before - added).abs() < 1e-5 * before,
        "field + taken = before + added: {after} + {taken} vs {before} + {added}"
    );
    let v = Arc::clone(sim.port(key.cells).pinned());
    assert!(
        v.get(probe).unwrap().temperature > 280.0,
        "refresh caches T"
    );
}
