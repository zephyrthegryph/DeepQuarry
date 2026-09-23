//! R7 end to end: a network registered with a sim, driven by DM-style
//! batches and commands, publishing views and outboxes, with a region
//! channel mirrored into a cell domain so watches fire on regions.

use vg_core::channel::{Quantity, Unit};
use vg_core::channels;
use vg_core::cow::ChunkLayout;
use vg_core::frame::Task;
use vg_core::handle::MAX_SLOTS;
use vg_core::network::NetworkKind;
use vg_core::network::host::{Edit, EndKey, ViewSide, add_network, topo};
use vg_core::outbox::{EventKind, Lane};
use vg_core::owner::{Applied, Domain};
use vg_core::sim::{SimBuilder, SimConfig};
use vg_core::watch::{Cond, Level};

/// Pipes: volume per node; payload is moles, split by volume.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Pipes;

impl NetworkKind for Pipes {
    const NAME: &'static str = "pipes";
    type Node = f64;
    type Summary = f64;
    type Payload = f64;
    type Device = f32;
    type Command = f64;

    fn summarize(node: &f64) -> f64 {
        *node
    }
    fn split(moles: &mut f64, whole: &f64, part: &f64) -> f64 {
        let out = if *whole > 0.0 {
            *moles * (part / whole).clamp(0.0, 1.0)
        } else {
            0.0
        };
        *moles -= out;
        out
    }
    fn merge(into: &mut f64, other: f64) {
        *into += other;
    }
    fn apply(moles: &mut f64, _: &f64, add: &f64) {
        *moles += add;
    }
}

/// The region-channel mirror: one cell per region slot.
struct PipeRegions;

impl Domain for PipeRegions {
    type Value = f32;
    type Command = ();
    const NAME: &'static str = "pipe_regions";
    fn apply(_: &mut f32, (): &()) -> Applied {
        Applied::default()
    }
}

channels! { mod region_ch for PipeRegions {
    MOLES: Scalar<Moles> hysteresis 0.0 => |c, o| o[0] = *c,
}}

fn node(key: u32) -> Edit<Pipes> {
    Edit::AddNode {
        key,
        pos: 1000 + key,
        kind: 0,
        data: 10.0,
        payload: 5.0,
    }
}

/// One tick: the network port is not a sim port, so the host commits it
/// before dispatch and runs frames itself.
fn frame(sim: &mut vg_core::sim::Sim) {
    sim.begin_tick();
    assert!(sim.dispatch_frame());
    sim.wait_for_frame();
}

#[test]
fn batches_commands_views_outbox_and_region_watches() {
    let mut b = SimBuilder::new(SimConfig {
        threads: 2,
        ..SimConfig::default()
    });
    let (net, mut port) = add_network::<Pipes>(&mut b, "pipes");
    let mirror = b.add_domain::<PipeRegions>(ChunkLayout::linear(MAX_SLOTS));
    let mirror_state = mirror.state();
    b.add_task(
        Task::new("pipes:mirror", move |ctx| {
            let n = ctx.read(net);
            let mut st = ctx.write(mirror_state);
            #[allow(clippy::cast_possible_truncation)]
            n.mirror(&mut st.store, |e| e.payload as f32);
        })
        .reads(net.id())
        .writes(mirror_state.id()),
    );
    let watches = b.add_watches(mirror);
    let mut sim = b.build().unwrap();

    // Frame 1: a 6-pipe line (keys 0..6) and a pump from key 2 to turf 77,
    // as one transaction.
    for k in 0..6 {
        port.edit(node(k));
    }
    for k in 0..5 {
        port.edit(Edit::Connect { a: k, b: k + 1 });
    }
    port.edit(Edit::AddDevice {
        key: 3,
        a: EndKey::Node(2),
        b: EndKey::Cell(77),
        kind: 1,
        data: 101.3,
    });
    port.commit();
    frame(&mut sim);
    assert!(port.refresh());
    let view = port.pinned().clone();
    let r = view.region_of(0).unwrap();
    for k in 1..6 {
        assert_eq!(view.region_of(k), Some(r));
    }
    let entry = view.region(r).unwrap();
    assert_eq!(entry.members, 6);
    assert!((entry.summary - 60.0).abs() < 1e-9);
    assert!((entry.payload - 30.0).abs() < 1e-9);
    let pump = view.device(3).unwrap();
    assert_eq!((pump.a, pump.b), (ViewSide::Region(r), ViewSide::Cell(77)));
    let out = port.take_outbox();
    assert!(
        out.events()
            .iter()
            .all(|e| e.kind == EventKind::TopologyChanged)
    );
    assert!(out.events().iter().any(|e| e.value == topo::MERGED));

    // A watch on the region's moles channel.
    sim.begin_tick();
    sim.watches(watches)
        .watch(
            9,
            Lane::Normal,
            &Cond::Threshold {
                cell: r.index(),
                level: Level::above(region_ch::MOLES, Quantity::new(40.0, Unit::Moles)),
            },
        )
        .unwrap();

    // Frame 2: a command adds 20 moles through key 5; the watch fires.
    port.command(5, 20.0);
    frame(&mut sim);
    sim.begin_tick();
    let wakes = sim.drain(mirror);
    assert!(wakes.wakes().iter().any(|w| w.subscriber == 9), "{wakes:?}");
    port.refresh();
    assert!((port.pinned().region(r).unwrap().payload - 50.0).abs() < 1e-9);

    // Frame 3: an explosion removes key 2 (the pump's pipe) and cuts 4-5,
    // in one commit: three regions, the released share comes back as a
    // take, the pump detaches.
    port.edit(Edit::RemoveNode { key: 2 });
    port.edit(Edit::Disconnect { a: 4, b: 5 });
    port.edit(Edit::Connect { a: 99, b: 0 }); // unknown key: rejected
    port.commit();
    frame(&mut sim);
    port.refresh();
    let view = port.pinned().clone();
    assert_eq!(view.region_of(2), None);
    let (a, b, c) = (
        view.region_of(0).unwrap(),
        view.region_of(3).unwrap(),
        view.region_of(5).unwrap(),
    );
    assert!(a != b && b != c && a != c);
    assert_eq!(view.region_of(1), Some(a));
    assert_eq!(view.region_of(4), Some(b));
    let out = port.take_outbox();
    let released: f64 = out.takes().iter().map(|t| t.value).sum();
    assert!((released - 50.0 / 6.0).abs() < 1e-9);
    assert_eq!(out.takes()[0].cell, 2);
    let held: f64 = [a, b, c]
        .iter()
        .map(|&r| view.region(r).unwrap().payload)
        .sum();
    assert!((held + released - 50.0).abs() < 1e-9);
    assert_eq!(view.device(3).unwrap().a, ViewSide::Detached);
    assert!(
        out.events()
            .iter()
            .any(|e| e.value == topo::DEVICE_DETACHED && e.key == 3)
    );
    assert!(
        out.events()
            .iter()
            .filter(|e| e.value == topo::SPLIT)
            .count()
            >= 2
    );
}
