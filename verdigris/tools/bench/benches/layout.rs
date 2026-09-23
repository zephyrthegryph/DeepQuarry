use criterion::{Criterion, black_box, criterion_group, criterion_main};
use vg_layout::random_map::generate_automata;

fn cave_automata(c: &mut Criterion) {
    c.bench_function("random_map/automata_64x64x5", |b| {
        b.iter(|| generate_automata(black_box(64.0), 64.0, 5.0, 45.0).unwrap())
    });
}

criterion_group!(benches, cave_automata);
criterion_main!(benches);
