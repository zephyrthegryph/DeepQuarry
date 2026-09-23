//! R4 benchmarks: command submission, view pinning and overlay reads on
//! the DM-facing path (`rust_core.md` §3.2–§3.4).

use std::time::{Duration, Instant};

use criterion::{Criterion, black_box, criterion_group, criterion_main};
use vg_core::cow::ChunkLayout;
use vg_core::owner::{Applied, Domain, DomainKey};
use vg_core::sim::{Sim, SimBuilder, SimConfig};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Mix {
    moles: [f32; 4],
    energy: f32,
}

struct Gasish;

impl Domain for Gasish {
    type Value = Mix;
    type Command = (u8, f32);
    const NAME: &'static str = "bench_gasish";

    fn apply(value: &mut Mix, &(gas, amount): &(u8, f32)) -> Applied {
        let slot = &mut value.moles[usize::from(gas & 3)];
        let next = *slot + amount;
        *slot = next.max(0.0);
        value.energy += amount;
        Applied {
            shortfall: (-next).max(0.0),
        }
    }
}

const CELLS: u32 = 255 * 255;
const OPS: u32 = 10_000;

fn sim() -> (Sim, DomainKey<Gasish>) {
    let mut b = SimBuilder::new(SimConfig {
        threads: 2,
        ..SimConfig::default()
    });
    let key = b.add_domain::<Gasish>(ChunkLayout::linear(CELLS));
    let mut sim = b.build().unwrap();
    sim.begin_tick();
    for cell in (0..CELLS).step_by(3) {
        sim.port(key)
            .put(
                cell,
                Mix {
                    moles: [1.0; 4],
                    energy: 300.0,
                },
            )
            .unwrap();
    }
    sim.settle();
    (sim, key)
}

/// Scattered cells, so the overlay sees realistic hashing.
fn cell(i: u32) -> u32 {
    i.wrapping_mul(2_654_435_761) % CELLS
}

fn command_submission(c: &mut Criterion) {
    let (mut sim, key) = sim();
    c.bench_function("sim/submit_10k_commands", |b| {
        b.iter_custom(|iters| {
            let mut total = Duration::ZERO;
            for _ in 0..iters {
                sim.begin_tick();
                let port = sim.port(key);
                let start = Instant::now();
                for i in 0..OPS {
                    black_box(port.submit(cell(i), (1, 0.5)).unwrap());
                }
                total += start.elapsed();
                sim.dispatch_frame();
                sim.settle();
            }
            total
        });
    });
}

fn view_pinning(c: &mut Criterion) {
    let (mut sim, key) = sim();
    c.bench_function("sim/pin_view_prune_1k_overlay", |b| {
        b.iter_custom(|iters| {
            let mut total = Duration::ZERO;
            for _ in 0..iters {
                for i in 0..1_000 {
                    sim.port(key).submit(cell(i), (2, 0.25)).unwrap();
                }
                sim.dispatch_frame();
                sim.wait_for_frame();
                let start = Instant::now();
                sim.begin_tick();
                total += start.elapsed();
                debug_assert_eq!(sim.port_ref(key).overlay_len(), 0);
            }
            total
        });
    });
}

fn overlay_reads(c: &mut Criterion) {
    let (mut sim, key) = sim();
    sim.begin_tick();
    for i in (0..OPS).step_by(2) {
        sim.port(key).submit(cell(i), (0, 1.0)).unwrap();
    }
    let port = sim.port_ref(key);
    assert_eq!(port.overlay_len(), 5_000);
    c.bench_function("sim/read_10k_half_overlay", |b| {
        b.iter(|| {
            let mut sum = 0.0f32;
            for i in 0..OPS {
                sum += port.read(black_box(cell(i))).unwrap().energy;
            }
            sum
        });
    });
    let pinned = port.pinned();
    c.bench_function("sim/read_10k_pinned_view_only", |b| {
        b.iter(|| {
            let mut sum = 0.0f32;
            for i in 0..OPS {
                sum += pinned.get(black_box(cell(i))).unwrap().energy;
            }
            sum
        });
    });
}

criterion_group!(benches, command_submission, view_pinning, overlay_reads);
criterion_main!(benches);
