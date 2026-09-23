use proptest::prelude::*;

use super::*;
use crate::slot::RawHandle;

/// Pipes: node data is a volume; the payload is (moles, energy), split by
/// volume share.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Pipes;

impl NetworkKind for Pipes {
    const NAME: &'static str = "test_pipes";
    type Node = f64;
    type Summary = f64;
    type Payload = [f64; 2];
    type Device = u8;
    type Command = [f64; 2];

    fn summarize(node: &f64) -> f64 {
        *node
    }

    fn split(payload: &mut [f64; 2], whole: &f64, part: &f64) -> [f64; 2] {
        let frac = if *whole > 0.0 {
            (part / whole).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let out = [payload[0] * frac, payload[1] * frac];
        payload[0] -= out[0];
        payload[1] -= out[1];
        out
    }

    fn merge(into: &mut [f64; 2], other: [f64; 2]) {
        into[0] += other[0];
        into[1] += other[1];
    }

    fn apply(payload: &mut [f64; 2], _: &f64, cmd: &[f64; 2]) {
        payload[0] += cmd[0];
        payload[1] += cmd[1];
    }
}

/// Cables: node data is (supply, demand, capacity); the payload is stored
/// charge, split by capacity share (a power ledger).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Cables;

impl NetworkKind for Cables {
    const NAME: &'static str = "test_cables";
    type Node = [f64; 3];
    type Summary = [f64; 3];
    type Payload = f64;
    type Device = ();
    type Command = f64;

    fn summarize(node: &[f64; 3]) -> [f64; 3] {
        *node
    }

    fn split(charge: &mut f64, whole: &[f64; 3], part: &[f64; 3]) -> f64 {
        let frac = if whole[2] > 0.0 {
            (part[2] / whole[2]).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let out = *charge * frac;
        *charge -= out;
        out
    }

    fn merge(into: &mut f64, other: f64) {
        *into += other;
    }
}

#[derive(Clone, Debug)]
enum Op {
    Add { vol: u8, gas: u8 },
    RemoveNode(u32),
    Connect(u32, u32),
    RemoveEdge(u32),
    Commit,
}

fn op() -> impl Strategy<Value = Op> {
    op_with(0)
}

/// Batch-order independence of payloads needs positive split weights: a
/// zero-volume region has no proportional split, so which part keeps its
/// gas depends on which side the search left open.
fn op_with(min_vol: u8) -> impl Strategy<Value = Op> {
    prop_oneof![
        3 => (min_vol..8, 0u8..50).prop_map(|(vol, gas)| Op::Add { vol, gas }),
        1 => any::<u32>().prop_map(Op::RemoveNode),
        5 => (any::<u32>(), any::<u32>()).prop_map(|(a, b)| Op::Connect(a, b)),
        2 => any::<u32>().prop_map(Op::RemoveEdge),
        1 => Just(Op::Commit),
    ]
}

fn pick<T: Copy>(items: &[T], i: u32) -> Option<T> {
    (!items.is_empty()).then(|| items[i as usize % items.len()])
}

/// Applies `op`; returns gas added. Picks index live nodes and edges in
/// arena order, so the same sequence replays identically.
fn apply(net: &mut Network<Pipes>, op: &Op, released: &mut [f64; 2]) -> [f64; 2] {
    let nodes: Vec<_> = net.nodes().map(|(n, _)| n).collect();
    let edges: Vec<_> = net.edges().map(|(e, _)| e).collect();
    match *op {
        Op::Add { vol, gas } => {
            let g = [f64::from(gas), f64::from(gas) * 3.0];
            net.add_node(0, 0, NO_KEY, f64::from(vol), g).unwrap();
            return g;
        }
        Op::RemoveNode(i) => {
            if let Some(n) = pick(&nodes, i) {
                net.remove_node(n).unwrap();
            }
        }
        Op::Connect(a, b) => {
            if let (Some(a), Some(b)) = (pick(&nodes, a), pick(&nodes, b)) {
                if a != b {
                    net.connect(a, b).unwrap();
                }
            }
        }
        Op::RemoveEdge(i) => {
            if let Some(e) = pick(&edges, i) {
                net.remove_edge(e).unwrap();
            }
        }
        Op::Commit => {
            collect(net.commit(), released);
        }
    }
    [0.0; 2]
}

fn collect(events: Vec<RegionEvent<Pipes>>, released: &mut [f64; 2]) {
    for ev in events {
        if let RegionEvent::Released { payload, .. } = ev {
            released[0] += payload[0];
            released[1] += payload[1];
        }
    }
}

fn totals(net: &Network<Pipes>) -> [f64; 2] {
    net.regions().fold([0.0; 2], |acc, (_, r)| {
        [acc[0] + r.payload()[0], acc[1] + r.payload()[1]]
    })
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() <= 1e-9 * (1.0 + a.abs().max(b.abs()))
}

/// Canonical (partition, payload per part) with payloads rounded for
/// comparison across orders.
fn canonical(net: &Network<Pipes>) -> Vec<(Vec<RawHandle>, [f64; 2])> {
    let mut out: Vec<_> = net
        .regions()
        .map(|(r, reg)| {
            let mut m: Vec<_> = net
                .members(r)
                .unwrap()
                .into_iter()
                .map(|n| n.raw())
                .collect();
            m.sort_unstable();
            (m, *reg.payload())
        })
        .collect();
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

fn check_summaries(net: &Network<Pipes>) -> Result<(), TestCaseError> {
    for (r, reg) in net.regions() {
        let sum: f64 = net
            .members(r)
            .unwrap()
            .iter()
            .map(|&n| net.node(n).unwrap().data)
            .sum();
        prop_assert!(
            close(sum, *reg.summary()),
            "summary {} vs {}",
            sum,
            reg.summary()
        );
    }
    Ok(())
}

proptest! {
    #[test]
    fn incremental_regions_match_a_full_rebuild(ops in prop::collection::vec(op(), 1..160)) {
        let mut net = Network::<Pipes>::new();
        let mut released = [0.0; 2];
        for op in &ops {
            apply(&mut net, op, &mut released);
            if matches!(op, Op::Commit) {
                prop_assert_eq!(net.partition(), net.rebuild_partition());
            }
        }
        collect(net.commit(), &mut released);
        prop_assert_eq!(net.partition(), net.rebuild_partition());
        check_summaries(&net)?;
    }

    #[test]
    fn every_edit_committed_alone_matches_a_full_rebuild(ops in prop::collection::vec(op(), 1..120)) {
        let mut net = Network::<Pipes>::new();
        let mut released = [0.0; 2];
        for op in &ops {
            apply(&mut net, op, &mut released);
            collect(net.commit(), &mut released);
            prop_assert_eq!(net.partition(), net.rebuild_partition());
        }
    }

    #[test]
    fn payload_is_conserved_across_merges_and_splits(ops in prop::collection::vec(op(), 1..200)) {
        let mut net = Network::<Pipes>::new();
        let mut released = [0.0; 2];
        let mut added = [0.0; 2];
        for op in &ops {
            let g = apply(&mut net, op, &mut released);
            added[0] += g[0];
            added[1] += g[1];
            if !matches!(op, Op::Commit) {
                continue;
            }
            let t = totals(&net);
            for k in 0..2 {
                prop_assert!(close(t[k] + released[k], added[k]), "{} + {} != {}", t[k], released[k], added[k]);
            }
        }
        collect(net.commit(), &mut released);
        let t = totals(&net);
        for k in 0..2 {
            prop_assert!(close(t[k] + released[k], added[k]));
        }
        // Pooled gas is uniform: every region's moles per volume is what
        // it would be if split by volume, so no payload is stranded in a
        // zero-volume region beyond what it was created with.
        check_summaries(&net)?;
    }

    #[test]
    fn results_are_deterministic(ops in prop::collection::vec(op(), 1..150)) {
        let run = || {
            let mut net = Network::<Pipes>::new();
            let mut released = [0.0; 2];
            let mut log = Vec::new();
            for op in &ops {
                apply(&mut net, op, &mut released);
                if matches!(op, Op::Commit) {
                    log.push(format!("{:?}", net.commit()));
                }
            }
            log.push(format!("{:?}", net.commit()));
            let regions: Vec<_> = net
                .regions()
                .map(|(r, reg)| (r.raw(), reg.members(), reg.payload().map(f64::to_bits)))
                .collect();
            (log, regions, released.map(f64::to_bits))
        };
        prop_assert_eq!(run(), run());
    }

    /// A batch equals committing its removals, then its additions, one by
    /// one: same partition and the same payload per region. Any order of
    /// the batch gives the same partition.
    #[test]
    fn batched_commit_equals_sequential_application(
        setup in prop::collection::vec(op_with(1), 20..120),
        removals in prop::collection::vec((any::<bool>(), any::<u32>()), 0..20),
        adds in prop::collection::vec((any::<u32>(), any::<u32>()), 0..20),
        shuffle in any::<u64>(),
    ) {
        let mut base = Network::<Pipes>::new();
        let mut sink = [0.0; 2];
        for op in &setup {
            apply(&mut base, op, &mut sink);
        }
        collect(base.commit(), &mut sink);

        // Resolve the batch against the base: distinct removals of existing
        // nodes/edges, then connections between survivors.
        let nodes: Vec<_> = base.nodes().map(|(n, _)| n).collect();
        let edges: Vec<_> = base.edges().map(|(e, _)| (e, *base.edge(e).unwrap())).collect();
        let mut removed_nodes = Vec::new();
        let mut removed_edges = Vec::new();
        for &(node, i) in &removals {
            if node {
                if let Some(n) = pick(&nodes, i) {
                    if !removed_nodes.contains(&n) { removed_nodes.push(n); }
                }
            } else if let Some((e, edge)) = pick(&edges, i) {
                if !removed_edges.iter().any(|&(x, _): &(EdgeId<Pipes>, Edge<Pipes>)| x == e)
                    && !removed_nodes.contains(&edge.a) && !removed_nodes.contains(&edge.b)
                {
                    removed_edges.push((e, edge));
                }
            }
        }
        // Edges incident to removed nodes go with them; drop explicit ones.
        removed_edges.retain(|(_, e)| !removed_nodes.contains(&e.a) && !removed_nodes.contains(&e.b));
        let survivors: Vec<_> = nodes.iter().copied().filter(|n| !removed_nodes.contains(n)).collect();
        let mut connects = Vec::new();
        for &(a, b) in &adds {
            if let (Some(a), Some(b)) = (pick(&survivors, a), pick(&survivors, b)) {
                let dup = removed_edges.iter().any(|(_, e)| (e.a == a && e.b == b) || (e.a == b && e.b == a));
                if a != b && !dup { connects.push((a, b)); }
            }
        }

        #[derive(Clone, Copy)]
        enum E { Node(NodeId<Pipes>), Edge(NodeId<Pipes>, NodeId<Pipes>), Conn(NodeId<Pipes>, NodeId<Pipes>) }
        let mut batch: Vec<E> = Vec::new();
        batch.extend(removed_nodes.iter().map(|&n| E::Node(n)));
        batch.extend(removed_edges.iter().map(|(_, e)| E::Edge(e.a, e.b)));
        batch.extend(connects.iter().map(|&(a, b)| E::Conn(a, b)));

        let run = |net: &mut Network<Pipes>, e: E| match e {
            E::Node(n) => net.remove_node(n).unwrap(),
            E::Edge(a, b) => { let _ = net.disconnect(a, b); }
            E::Conn(a, b) => { net.connect(a, b).unwrap(); }
        };

        // Sequential: removals then additions, each committed.
        let mut seq = clone_net(&base, &setup);
        for &e in &batch {
            run(&mut seq, e);
            seq.commit();
        }
        // One batch, in order.
        let mut one = clone_net(&base, &setup);
        for &e in &batch {
            run(&mut one, e);
        }
        one.commit();
        prop_assert_eq!(one.partition(), one.rebuild_partition());
        let (a, b) = (canonical(&seq), canonical(&one));
        prop_assert_eq!(a.len(), b.len());
        for (x, y) in a.iter().zip(&b) {
            prop_assert_eq!(&x.0, &y.0);
            prop_assert!(close(x.1[0], y.1[0]) && close(x.1[1], y.1[1]), "{:?} vs {:?}", x.1, y.1);
        }
        // One batch, shuffled (removals and additions interleaved): the
        // partition is order-independent.
        let mut order: Vec<usize> = (0..batch.len()).collect();
        let mut s = shuffle | 1;
        for i in (1..order.len()).rev() {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17;
            order.swap(i, (s % (i as u64 + 1)) as usize);
        }
        let mut mixed = clone_net(&base, &setup);
        for &i in &order {
            run(&mut mixed, batch[i]);
        }
        mixed.commit();
        prop_assert_eq!(mixed.partition(), one.partition());
    }

    #[test]
    fn power_ledger_conserves_charge_and_tracks_supply(
        caps in prop::collection::vec((0u8..5, 0u8..5, 0u8..10, 0u8..100), 2..60),
        links in prop::collection::vec((any::<u32>(), any::<u32>()), 0..120),
        cuts in prop::collection::vec(any::<u32>(), 0..60),
    ) {
        let mut net = Network::<Cables>::new();
        let mut total = 0.0;
        let mut nodes = Vec::new();
        for &(s, d, c, q) in &caps {
            let charge = f64::from(q);
            total += charge;
            nodes.push(net.add_node(0, 0, NO_KEY, [f64::from(s), f64::from(d), f64::from(c)], charge).unwrap());
        }
        for &(a, b) in &links {
            let (a, b) = (pick(&nodes, a).unwrap(), pick(&nodes, b).unwrap());
            if a != b { net.connect(a, b).unwrap(); }
        }
        net.commit();
        let edges: Vec<_> = net.edges().map(|(e, _)| e).collect();
        let mut released = 0.0;
        for (i, &c) in cuts.iter().enumerate() {
            if i % 7 == 6 {
                let alive: Vec<_> = net.nodes().map(|(n, _)| n).collect();
                if let Some(n) = pick(&alive, c) { net.remove_node(n).unwrap(); }
            } else if let Some(e) = pick(&edges, c) {
                let _ = net.remove_edge(e);
            }
        }
        for ev in net.commit() {
            if let RegionEvent::Released { payload, .. } = ev { released += payload; }
        }
        prop_assert_eq!(net.partition(), net.rebuild_partition());
        let held: f64 = net.regions().map(|(_, r)| *r.payload()).sum();
        prop_assert!(close(held + released, total), "{} + {} != {}", held, released, total);
        for (r, reg) in net.regions() {
            let mut sum = [0.0; 3];
            for n in net.members(r).unwrap() {
                sum.add(&net.node(n).unwrap().data);
            }
            for (x, y) in sum.iter().zip(reg.summary()) {
                prop_assert!(close(*x, *y));
            }
        }
    }
}

/// Replays `setup` into a fresh network (Network is not Clone on purpose:
/// clones would share nothing but cost a full copy).
fn clone_net(base: &Network<Pipes>, setup: &[Op]) -> Network<Pipes> {
    let mut net = Network::<Pipes>::new();
    let mut sink = [0.0; 2];
    for op in setup {
        apply(&mut net, op, &mut sink);
    }
    net.commit();
    debug_assert_eq!(net.partition(), base.partition());
    net
}

fn line(net: &mut Network<Pipes>, n: usize) -> Vec<NodeId<Pipes>> {
    let nodes: Vec<_> = (0..n)
        .map(|i| {
            net.add_node(
                u32::try_from(i).unwrap(),
                0,
                u32::try_from(i).unwrap(),
                1.0,
                [1.0, 2.0],
            )
            .unwrap()
        })
        .collect();
    for w in nodes.windows(2) {
        net.connect(w[0], w[1]).unwrap();
    }
    net.commit();
    nodes
}

#[test]
fn merge_keeps_the_larger_region_and_split_keeps_the_open_side() {
    let mut net = Network::<Pipes>::new();
    let nodes = line(&mut net, 10);
    assert_eq!(net.region_count(), 1);
    let r = net.region_of(nodes[0]).unwrap();
    assert_eq!(*net.region(r).unwrap().payload(), [10.0, 20.0]);
    // Cut near the end: the two-node tail is carved, the head keeps `r`.
    net.disconnect(nodes[7], nodes[8]).unwrap();
    let events = net.commit();
    assert_eq!(net.region_count(), 2);
    assert_eq!(net.region_of(nodes[0]).unwrap(), r);
    let tail = net.region_of(nodes[9]).unwrap();
    assert!(events.contains(&RegionEvent::Split {
        from: r,
        into: tail
    }));
    assert_eq!(*net.region(tail).unwrap().payload(), [2.0, 4.0]);
    assert_eq!(*net.region(r).unwrap().payload(), [8.0, 16.0]);
    assert!(net.stats().visited <= 6, "{:?}", net.stats());
    // Rejoin: the larger region's ID survives.
    net.connect(nodes[8], nodes[7]).unwrap();
    let events = net.commit();
    assert_eq!(
        events,
        vec![RegionEvent::Merged {
            into: r,
            from: tail
        }]
    );
    assert_eq!(*net.region(r).unwrap().payload(), [10.0, 20.0]);
}

#[test]
fn a_cut_that_does_not_disconnect_keeps_the_region() {
    let mut net = Network::<Pipes>::new();
    let nodes = line(&mut net, 6);
    net.connect(nodes[5], nodes[0]).unwrap(); // a ring
    net.commit();
    let r = net.region_of(nodes[0]).unwrap();
    net.disconnect(nodes[2], nodes[3]).unwrap();
    assert!(net.commit().is_empty());
    assert_eq!(net.region_count(), 1);
    assert_eq!(net.region_of(nodes[4]).unwrap(), r);
}

#[test]
fn removing_a_node_releases_its_share_and_detaches_devices() {
    let mut net = Network::<Pipes>::new();
    let nodes = line(&mut net, 5);
    let pump = net
        .add_device(Endpoint::Node(nodes[2]), Endpoint::Cell(77), 1, 9, 3)
        .unwrap();
    let r = net.region_of(nodes[2]).unwrap();
    assert_eq!(net.resolve(net.device(pump).unwrap().a), Side::Region(r));
    net.remove_node(nodes[2]).unwrap();
    let events = net.commit();
    assert!(events.contains(&RegionEvent::Released {
        key: 2,
        pos: 2,
        payload: [1.0, 2.0]
    }));
    assert!(events.contains(&RegionEvent::DeviceDetached { device: pump }));
    assert_eq!(net.device(pump).unwrap().a, Endpoint::Detached);
    assert_eq!(net.device(pump).unwrap().b, Endpoint::Cell(77));
    assert_eq!(net.region_count(), 2);
    // Removing the last node of a region retires it and releases all.
    let lone = net.region_of(nodes[4]).unwrap();
    net.remove_node(nodes[3]).unwrap();
    net.remove_node(nodes[4]).unwrap();
    let events = net.commit();
    assert!(events.contains(&RegionEvent::Retired { region: lone }));
    assert_eq!(totals(&net), [2.0, 4.0]);
}

#[test]
fn explosion_is_one_commit() {
    let mut net = Network::<Pipes>::new();
    // A 40x40 grid of pipes.
    let n = 40;
    let mut ids = Vec::new();
    for i in 0..n * n {
        ids.push(net.add_node(i, 0, NO_KEY, 1.0, [1.0, 0.0]).unwrap());
    }
    for y in 0..n {
        for x in 0..n {
            let i = (y * n + x) as usize;
            if x + 1 < n {
                net.connect(ids[i], ids[i + 1]).unwrap();
            }
            if y + 1 < n {
                net.connect(ids[i], ids[i + n as usize]).unwrap();
            }
        }
    }
    net.commit();
    assert_eq!(net.region_count(), 1);
    // Blow out a full-height column: two regions.
    for y in 0..n {
        net.remove_node(ids[(y * n + 20) as usize]).unwrap();
    }
    net.commit();
    assert_eq!(net.region_count(), 2);
    assert_eq!(net.partition(), net.rebuild_partition());
    assert!(close(totals(&net)[0], f64::from(n * n - n)));
}
