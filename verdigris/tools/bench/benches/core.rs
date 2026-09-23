use criterion::{Criterion, black_box, criterion_group, criterion_main};
use vg_core::Arena;
use vg_core::bitset::DenseBitSet;
use vg_core::grid::{BlockKind, DirMask, Face, Grid, GridDims};
use vg_core::intern::Interner;
use vg_core::rng::{RngStreams, StreamId};
use vg_core::thermo::{ThermalBody, exchange};
use vg_core::units::{HeatCapacity, Kelvin};

/// Neighbour lookups over one full 255x255 z-level, all six faces.
fn grid_neighbors(c: &mut Criterion) {
    let dims = GridDims::new(255, 255, 8).unwrap();
    let layer = dims.layer_len();
    c.bench_function("grid/neighbor_full_layer", |b| {
        b.iter(|| {
            let mut found = 0u32;
            for index in layer..2 * layer {
                for face in Face::ALL {
                    if dims.neighbor(black_box(index), face).is_some() {
                        found += 1;
                    }
                }
            }
            found
        })
    });
}

/// Open-neighbour lookups through the air block layer, with a wall every
/// eighth column so some chunks are allocated.
fn grid_open_neighbors(c: &mut Criterion) {
    let dims = GridDims::new(255, 255, 1).unwrap();
    let mut grid = Grid::new(dims);
    for y in 0..255 {
        for x in (0..255).step_by(8) {
            grid.set_blocked(BlockKind::Air, dims.index(x, y, 0).unwrap(), DirMask::ALL);
        }
    }
    c.bench_function("grid/open_neighbors_full_layer", |b| {
        b.iter(|| {
            let mut found = 0u32;
            for index in 0..dims.layer_len() {
                found += grid
                    .open_neighbors(BlockKind::Air, black_box(index))
                    .count() as u32;
            }
            found
        })
    });
}

fn arena(c: &mut Criterion) {
    c.bench_function("arena/insert_remove_65k", |b| {
        b.iter(|| {
            let mut arena = Arena::new();
            let handles: Vec<_> = (0..65_536u32).map(|i| arena.insert(i).unwrap()).collect();
            for h in handles {
                black_box(arena.remove(h).unwrap());
            }
        })
    });
    let mut arena = Arena::new();
    let handles: Vec<_> = (0..65_536u32).map(|i| arena.insert(i).unwrap()).collect();
    c.bench_function("arena/get_65k", |b| {
        b.iter(|| handles.iter().map(|h| *arena.get(*h).unwrap()).sum::<u32>())
    });
    c.bench_function("arena/iter_65k", |b| {
        b.iter(|| arena.iter().map(|(_, v)| *v).sum::<u32>())
    });
}

fn bitset(c: &mut Criterion) {
    let mut set = DenseBitSet::new(255 * 255 * 8);
    let mut rng = RngStreams::new(1).stream(StreamId::named("bench"));
    for _ in 0..20_000 {
        set.insert(rng.below(255 * 255 * 8));
    }
    c.bench_function("bitset/iter_520k_sparse", |b| b.iter(|| set.iter().count()));
}

fn thermo(c: &mut Criterion) {
    let mut bodies: Vec<_> = (0..65_536)
        .map(|i| {
            ThermalBody::new(
                HeatCapacity(100.0 + i as f64),
                Kelvin(200.0 + (i % 300) as f64),
            )
        })
        .collect();
    c.bench_function("thermo/exchange_chain_65k", |b| {
        b.iter(|| {
            for i in 0..bodies.len() - 1 {
                let (left, right) = bodies.split_at_mut(i + 1);
                exchange(&mut left[i], &mut right[0], 0.04);
            }
        })
    });
}

fn misc(c: &mut Criterion) {
    let mut rng = RngStreams::new(7).stream(StreamId::named("bench"));
    c.bench_function("rng/next_u64_1k", |b| {
        b.iter(|| (0..1000).fold(0u64, |acc, _| acc ^ rng.next_u64()))
    });
    let keys: Vec<String> = (0..1000).map(|i| format!("/datum/gas/kind_{i}")).collect();
    let mut interner = Interner::new();
    for k in &keys {
        interner.intern(k);
    }
    c.bench_function("intern/lookup_1k", |b| {
        b.iter(|| keys.iter().filter_map(|k| interner.get(k)).count())
    });
}

criterion_group!(
    benches,
    grid_neighbors,
    grid_open_neighbors,
    arena,
    bitset,
    thermo,
    misc
);
criterion_main!(benches);
