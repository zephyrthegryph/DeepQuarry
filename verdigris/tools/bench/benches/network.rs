//! R7 network benches: a 50k-node build, single-edge cuts in a big region,
//! and a 1k-edit batched commit.

use criterion::{Criterion, black_box, criterion_group, criterion_main};
use vg_core::network::{EdgeId, NO_KEY, Network, NetworkKind, NodeId};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Pipes;

impl NetworkKind for Pipes {
    const NAME: &'static str = "bench_pipes";
    type Node = f64;
    type Summary = f64;
    type Payload = [f64; 2];
    type Device = ();
    type Command = ();

    fn summarize(node: &f64) -> f64 {
        *node
    }
    fn split(p: &mut [f64; 2], whole: &f64, part: &f64) -> [f64; 2] {
        let f = if *whole > 0.0 { part / whole } else { 0.0 };
        let out = [p[0] * f, p[1] * f];
        p[0] -= out[0];
        p[1] -= out[1];
        out
    }
    fn merge(into: &mut [f64; 2], other: [f64; 2]) {
        into[0] += other[0];
        into[1] += other[1];
    }
}

const SIDE: u32 = 224; // 50,176 nodes

/// A SIDE x SIDE grid of pipes, one commit.
fn grid() -> (Network<Pipes>, Vec<NodeId<Pipes>>) {
    let mut net = Network::new();
    let ids: Vec<_> = (0..SIDE * SIDE)
        .map(|i| net.add_node(i, 0, NO_KEY, 1.0, [1.0, 300.0]).unwrap())
        .collect();
    for y in 0..SIDE {
        for x in 0..SIDE {
            let i = (y * SIDE + x) as usize;
            if x + 1 < SIDE {
                net.connect(ids[i], ids[i + 1]).unwrap();
            }
            if y + 1 < SIDE {
                net.connect(ids[i], ids[i + SIDE as usize]).unwrap();
            }
        }
    }
    net.commit();
    (net, ids)
}

/// A 50k-node line (a tree: every cut disconnects).
fn line() -> (Network<Pipes>, Vec<NodeId<Pipes>>) {
    let mut net = Network::new();
    let ids: Vec<_> = (0..SIDE * SIDE)
        .map(|i| net.add_node(i, 0, NO_KEY, 1.0, [1.0, 300.0]).unwrap())
        .collect();
    for w in ids.windows(2) {
        net.connect(w[0], w[1]).unwrap();
    }
    net.commit();
    (net, ids)
}

fn build(c: &mut Criterion) {
    let mut g = c.benchmark_group("network");
    g.sample_size(10);
    g.bench_function("build_grid_50k", |b| {
        b.iter(|| black_box(grid().0.region_count()))
    });
    g.finish();
}

fn cut(c: &mut Criterion) {
    let mut g = c.benchmark_group("network");
    let (mut net, ids) = line();
    let n = ids.len();
    // Near a leaf: the carved side is 10 nodes, the 50k side is never walked.
    g.bench_function("cut_line_50k_near_leaf", |b| {
        b.iter(|| {
            net.disconnect(ids[n - 11], ids[n - 10]).unwrap();
            net.commit();
            net.connect(ids[n - 11], ids[n - 10]).unwrap();
            net.commit();
        });
    });
    // Mid-line: splits 25k/25k, and the rejoin relabels 25k.
    g.sample_size(20);
    g.bench_function("cut_line_50k_middle_and_rejoin", |b| {
        b.iter(|| {
            net.disconnect(ids[n / 2], ids[n / 2 + 1]).unwrap();
            net.commit();
            net.connect(ids[n / 2], ids[n / 2 + 1]).unwrap();
            net.commit();
        });
    });
    g.sample_size(100);
    // A grid cut that does not disconnect: the two searches meet at once.
    let (mut net, ids) = grid();
    let mid = (SIDE / 2 * SIDE + SIDE / 2) as usize;
    g.bench_function("cut_grid_50k_no_split", |b| {
        b.iter(|| {
            net.disconnect(ids[mid], ids[mid + 1]).unwrap();
            net.commit();
            net.connect(ids[mid], ids[mid + 1]).unwrap();
            net.commit();
        });
    });
    g.finish();
}

fn batch(c: &mut Criterion) {
    let mut g = c.benchmark_group("network");
    let (mut net, ids) = grid();
    // An explosion: every edge inside a 23x23 blob (~1k edges) removed in
    // one commit, which carves ~500 single-pipe regions out of the 50k
    // region, then restored in one commit.
    let (x0, y0, w) = (100u32, 100u32, 23u32);
    let blob: Vec<(NodeId<Pipes>, NodeId<Pipes>)> = (y0..y0 + w)
        .flat_map(|y| (x0..x0 + w).map(move |x| (x, y)))
        .flat_map(|(x, y)| {
            let i = (y * SIDE + x) as usize;
            [(i, i + 1), (i, i + SIDE as usize)]
        })
        .map(|(a, b)| (ids[a], ids[b]))
        .collect();
    assert!(blob.len() >= 1000);
    let _: Option<EdgeId<Pipes>> = None;
    g.sample_size(20);
    g.bench_function("batch_1k_edge_explosion_and_repair", |b| {
        b.iter(|| {
            for &(a, b) in &blob {
                net.disconnect(a, b).unwrap();
            }
            net.commit();
            for &(a, b) in &blob {
                net.connect(a, b).unwrap();
            }
            net.commit();
            black_box(net.region_count())
        });
    });
    g.finish();
}

criterion_group!(benches, build, cut, batch);
criterion_main!(benches);
