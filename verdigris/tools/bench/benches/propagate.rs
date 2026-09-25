//! R8 propagation benches: wavefront floods and rays on a 255x255 level.

use criterion::{Criterion, black_box, criterion_group, criterion_main};
use vg_core::grid::{BlockKind, Dir, Grid, GridDims};
use vg_core::propagate::{FloodLimits, Ray, Wavefront, line_of_sight};
use vg_core::rng::{RngStreams, StreamId};

/// A 255x255x1 station-ish grid: a wall every 16th row and column with a
/// door gap in each segment.
fn station() -> Grid {
    let dims = GridDims::new(255, 255, 1).unwrap();
    let mut grid = Grid::new(dims);
    for a in 0..255u32 {
        for b in (8..255u32).step_by(16) {
            if a % 16 == 4 {
                continue;
            }
            for kind in [BlockKind::Air, BlockKind::Opacity] {
                grid.set_blocked(kind, dims.index(a, b, 0).unwrap(), Dir::ALL);
                grid.set_blocked(kind, dims.index(b, a, 0).unwrap(), Dir::ALL);
            }
        }
    }
    grid
}

fn wavefront(c: &mut Criterion) {
    let grid = station();
    let dims = grid.dims();
    let mut wf = Wavefront::with_cells(dims.layer_len() as usize);
    let one = [(dims.index(127, 127, 0).unwrap(), 0)];
    c.bench_function("propagate/wavefront_255_1_source", |b| {
        b.iter(|| {
            wf.run(
                &grid,
                BlockKind::Air,
                black_box(&one),
                FloodLimits::UNLIMITED,
                |_, _, _| Some(1),
            );
            wf.settled().len()
        })
    });
    let mut rng = RngStreams::new(7).stream(StreamId::named("wavefront"));
    let many: Vec<(u32, u32)> = (0..50)
        .map(|_| (rng.next_u32() % dims.layer_len(), 0))
        .collect();
    c.bench_function("propagate/wavefront_255_50_sources", |b| {
        b.iter(|| {
            wf.run(
                &grid,
                BlockKind::Air,
                black_box(&many),
                FloodLimits::UNLIMITED,
                |_, _, _| Some(1),
            );
            wf.settled().len()
        })
    });
}

fn rays(c: &mut Criterion) {
    let grid = station();
    let dims = grid.dims();
    let mut rng = RngStreams::new(11).stream(StreamId::named("rays"));
    let pairs: Vec<(u32, u32)> = (0..10_000)
        .map(|_| {
            (
                rng.next_u32() % dims.layer_len(),
                rng.next_u32() % dims.layer_len(),
            )
        })
        .collect();
    // Short radiation-range rays: endpoints within 20 cells of each other.
    let short: Vec<(u32, u32)> = pairs
        .iter()
        .map(|&(a, b)| {
            let (ax, ay, _) = dims.coords(a).unwrap();
            let (bx, by, _) = dims.coords(b).unwrap();
            let x = (ax + bx % 41).saturating_sub(20).min(254);
            let y = (ay + by % 41).saturating_sub(20).min(254);
            (a, dims.index(x, y, 0).unwrap())
        })
        .collect();
    c.bench_function("propagate/rays_10k_attenuate_r20", |b| {
        b.iter(|| {
            let mut total = 0.0f32;
            for &(a, t) in black_box(&short) {
                let ray = Ray::new(dims, a, t).unwrap();
                total += ray
                    .attenuate(1.0, 0.0, |c| {
                        if grid.blocked(BlockKind::Air, c) == Dir::ALL {
                            0.5
                        } else {
                            0.99
                        }
                    })
                    .remaining;
            }
            total
        })
    });
    c.bench_function("propagate/rays_10k_line_of_sight_full_map", |b| {
        b.iter(|| {
            black_box(&pairs)
                .iter()
                .filter(|&&(a, t)| line_of_sight(&grid, BlockKind::Opacity, a, t))
                .count()
        })
    });
}

criterion_group!(benches, wavefront, rays);
criterion_main!(benches);
