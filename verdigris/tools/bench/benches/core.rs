use criterion::{Criterion, black_box, criterion_group, criterion_main};
use vg_core::grid::{Face, GridDims};

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

criterion_group!(benches, grid_neighbors);
criterion_main!(benches);
