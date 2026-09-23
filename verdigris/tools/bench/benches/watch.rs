//! R5 benchmarks: watch evaluation over 100k cells and outbox drain
//! (`rust_core.md` §6.4, §7, §8).

use std::time::{Duration, Instant};

use criterion::{Criterion, black_box, criterion_group, criterion_main};
use vg_core::channel::{Quantity, Unit};
use vg_core::channels;
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::outbox::{Lane, Outbox, Wake, WatchId};
use vg_core::owner::{Applied, Domain};
use vg_core::reactor::WakeLanes;
use vg_core::watch::{Cond, Level, WatchPort, WatchState};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Cell {
    kpa: f32,
    temp: f32,
}

struct Air;

impl Domain for Air {
    type Value = Cell;
    type Command = ();
    const NAME: &'static str = "bench_air";
    fn apply(_: &mut Cell, (): &()) -> Applied {
        Applied::default()
    }
}

channels! { mod ch for Air {
    PRESSURE: Scalar<Kpa> hysteresis 0.5 => |c, o| o[0] = c.kpa,
    TEMPERATURE: Scalar<Kelvin> hysteresis 0.5 => |c, o| o[0] = c.temp,
}}

const CELLS: u32 = 100_000;
const CHUNK: u32 = 256;

struct Setup {
    store: CowStore<Cell>,
    state: WatchState<Air>,
    out: Outbox<Cell>,
    pool: rayon::ThreadPool,
}

/// 100k cells, one watch each (`make`), primed by one evaluation.
fn setup(make: impl Fn(u32) -> Cond) -> Setup {
    let layout = ChunkLayout::linear_with_chunk(CELLS, CHUNK);
    let mut store = CowStore::new(layout);
    store.allocate_all();
    let mut state = WatchState::new(layout);
    let mut port = WatchPort::<Air>::new(layout);
    for cell in 0..CELLS {
        port.watch(cell, Lane::Normal, &make(cell)).unwrap();
    }
    port.dispatch(&mut state);
    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(
            std::env::var("R5_THREADS")
                .ok()
                .and_then(|t| t.parse().ok())
                .unwrap_or(4),
        )
        .build()
        .unwrap();
    let mut out = Outbox::default();
    pool.install(|| state.evaluate(&store, &mut out));
    Setup {
        store,
        state,
        out,
        pool,
    }
}

/// Moves every `stride`-th chunk's cells by `delta` (untouched chunks stay
/// shared with the watch's previous snapshot, so they are skipped).
fn touch(store: &mut CowStore<Cell>, stride: u32, delta: f32) {
    for chunk in (0..CELLS.div_ceil(CHUNK)).step_by(stride as usize) {
        for i in chunk * CHUNK..((chunk + 1) * CHUNK).min(CELLS) {
            store.get_mut(i).unwrap().kpa += delta;
        }
    }
}

fn bench_eval(c: &mut Criterion, name: &str, make: impl Fn(u32) -> Cond, stride: u32, delta: f32) {
    let mut s = setup(make);
    let mut sign = 1.0;
    c.bench_function(name, |b| {
        b.iter_custom(|iters| {
            let mut total = Duration::ZERO;
            for _ in 0..iters {
                touch(&mut s.store, stride, delta * sign);
                sign = -sign;
                let start = Instant::now();
                s.pool.install(|| s.state.evaluate(&s.store, &mut s.out));
                total += start.elapsed();
                black_box(s.out.wakes().len());
                s.out = Outbox::default();
            }
            total
        });
    });
}

fn watch_evaluation(c: &mut Criterion) {
    let changed = |cell| Cond::Changed {
        cell,
        mask: ch::PRESSURE.bit() | ch::TEMPERATURE.bit(),
    };
    let threshold = |cell| Cond::Threshold {
        cell,
        level: Level::above(ch::PRESSURE, Quantity::new(1.0, Unit::Kpa)),
    };
    // Every cell changes past hysteresis: 100k evaluations, 100k wakes.
    bench_eval(c, "watch_eval_100k_changed_all_fire", changed, 1, 1.0);
    // Every cell changes within hysteresis: 100k evaluations, no wakes.
    bench_eval(c, "watch_eval_100k_changed_quiet", changed, 1, 0.1);
    // Thresholds crossed back and forth on every cell.
    bench_eval(c, "watch_eval_100k_threshold_all_cross", threshold, 1, 2.0);
    // 1 chunk in 64 changes: the rest are skipped by chunk identity.
    bench_eval(c, "watch_eval_100k_changed_sparse", changed, 64, 1.0);
}

fn wakes(n: u32) -> Vec<Wake> {
    (0..n)
        .map(|i| Wake {
            subscriber: i % (n / 2).max(1),
            lane: Lane::ALL[(i % 3) as usize],
            reason: 1 << (i % 20),
            source: i,
            watch: WatchId {
                index: i,
                generation: 0,
            },
        })
        .collect()
}

fn outbox_drain(c: &mut Criterion) {
    let batch = wakes(100_000);
    c.bench_function("outbox_drain_100k_wakes_through_lanes", |b| {
        b.iter(|| {
            let mut lanes = WakeLanes::new();
            for w in &batch {
                lanes.push_wake(w);
            }
            let mut out = Vec::with_capacity(batch.len());
            lanes.drain(usize::MAX / 2, &mut out);
            black_box(out.len())
        });
    });
    c.bench_function("outbox_flat_encode_100k_wakes", |b| {
        let mut outbox = Outbox::<()>::default();
        for w in &batch {
            outbox.push_wake(*w);
        }
        let mut flat = Vec::with_capacity(batch.len() * 4);
        b.iter(|| {
            flat.clear();
            outbox.wakes_flat(&mut flat);
            black_box(flat.len())
        });
    });
    c.bench_function("outbox_merge_100k_wakes_on_overflow", |b| {
        b.iter(|| {
            let mut outbox = Outbox::<()>::with_capacity(50_000, 16);
            for w in &batch {
                outbox.push_wake(Wake {
                    watch: WatchId::NONE,
                    ..*w
                });
            }
            black_box(outbox.wakes().len())
        });
    });
}

criterion_group!(benches, watch_evaluation, outbox_drain);
criterion_main!(benches);
