//! R6 field benches: one step of the toy gas field on a 255x255 level,
//! fully active and with one active chunk in an otherwise sleeping map.

use criterion::{Criterion, criterion_group, criterion_main};
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::field::toy::{GasCell, GasToy};
use vg_core::field::{FieldConfig, FieldState, Geom};
use vg_core::grid::GridDims;

struct World {
    cells: CowStore<GasCell>,
    geom: CowStore<Geom>,
    field: FieldState<GasToy>,
}

fn world() -> World {
    let dims = GridDims::new(255, 255, 1).unwrap();
    let layout = ChunkLayout::spatial(dims);
    let mut w = World {
        cells: CowStore::new(layout),
        geom: CowStore::new(layout),
        field: FieldState::new(dims, FieldConfig::default()),
    };
    for i in 0..dims.layer_len() {
        let (x, y, _) = dims.coords(i).unwrap();
        w.geom.set(i, Geom::cell(2.5));
        let n = 100.0 + f32::from(u8::try_from((x * 7 + y * 13) % 11).unwrap());
        w.cells.set(
            i,
            GasCell {
                amounts: [n * 0.8, n * 0.2, n * 1.5 * 293.0],
                pressure: 0.0,
            },
        );
    }
    w
}

fn gas_step(c: &mut Criterion) {
    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(4)
        .build()
        .unwrap();
    let mut w = world();
    c.bench_function("field/gas_255_all_active", |b| {
        b.iter(|| {
            w.field.wake_all();
            pool.install(|| w.field.step(&mut w.cells, &w.geom, None));
        });
    });
    let mut w = world();
    c.bench_function("field/gas_255_one_chunk_active", |b| {
        b.iter(|| {
            w.field.wake_cell(128 * 255 + 128);
            pool.install(|| w.field.step(&mut w.cells, &w.geom, None));
        });
    });
}

criterion_group!(benches, gas_step);
criterion_main!(benches);
