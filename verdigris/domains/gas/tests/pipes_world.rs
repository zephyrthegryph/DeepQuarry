//! End-to-end test of `vg-gas`'s pipe network over `vg_core::world::World`
//! (`rust_architecture.md` §8.5, step 5): topology, merge, a region<->
//! region device edge, and conservation, all `byondapi`-free
//! (`verdigris/ffi/src/pipes.rs`'s own binds only wrap this same
//! `NetworkHost<Pipes>`/`connect_entities` machinery in `ByondValue`
//! plumbing, which needs a live BYOND VM to test directly -- this is the
//! host-testable core the step 3/step 4 `tests/world.rs` files already
//! established the pattern for).

use vg_core::component::Ownership;
use vg_core::conservation::Tolerance;
use vg_core::world::{WorldBuilder, WorldConfig};
use vg_gas::device::{self, DeviceParams};
use vg_gas::pipes::{PipeGas, Pipes};

fn builder() -> WorldBuilder {
    let mut b = WorldBuilder::new(WorldConfig {
        check_conservation: true,
        ..WorldConfig::default()
    });
    b.add_network::<Pipes>(Ownership::Main);
    b.conserve_network::<Pipes>();
    b.conserve("pipe_moles", Tolerance::default());
    b.conserve("pipe_energy", Tolerance::default());
    b
}

fn gas(oxygen: f64, temperature: f64) -> PipeGas {
    let mut g = PipeGas::default();
    g.moles[vg_gas::gas::ids::GAS_OXYGEN] = oxygen;
    g.energy = oxygen * 20.0 * temperature;
    g
}

#[test]
fn connecting_ports_merges_their_regions_and_conserves() {
    let b = builder();
    let mut world = b.build().expect("builds");

    let ports: Vec<_> = (0..4).map(|_| world.entities_mut().bind().unwrap()).collect();
    for (i, &e) in ports.iter().enumerate() {
        world
            .edit_network::<Pipes>(move |host| {
                let _ = host.bind_node(e, 0, 0, 100.0);
                if i == 0 {
                    let region = host.region_of(e).expect("just bound");
                    let _ = host.set_payload(region, gas(30.0, 293.0));
                }
            })
            .unwrap();
    }
    world.commit_network::<Pipes>();

    let before_regions: std::collections::HashSet<_> = ports.iter().map(|&p| world.network::<Pipes>().unwrap().region_of(p)).collect();
    assert_eq!(before_regions.len(), 4, "every port starts in its own region");

    for w in ports.windows(2) {
        let (a, b) = (w[0], w[1]);
        world.edit_network::<Pipes>(move |host| host.connect_entities(a, b).unwrap()).unwrap();
    }
    world.commit_network::<Pipes>();

    let after_regions: std::collections::HashSet<_> = ports.iter().map(|&p| world.network::<Pipes>().unwrap().region_of(p)).collect();
    assert_eq!(after_regions.len(), 1, "connecting every port merges them into one region");

    let violations = world.violations();
    assert!(violations.is_empty(), "pipe_moles/pipe_energy conserved across the merge: {violations:?}");
}

#[test]
fn a_device_edge_moves_gas_between_regions_and_conserves() {
    let b = builder();
    let mut world = b.build().expect("builds");

    let a = world.entities_mut().bind().unwrap();
    let bp = world.entities_mut().bind().unwrap();
    world
        .edit_network::<Pipes>(move |host| {
            let _ = host.bind_node(a, 0, 0, 1000.0);
            let _ = host.bind_node(bp, 0, 0, 1000.0);
            let region = host.region_of(a).expect("just bound");
            let _ = host.set_payload(region, gas(1000.0, 293.0));
        })
        .unwrap();
    world.commit_network::<Pipes>();

    let device_e = world.entities_mut().bind().unwrap();
    let params = DeviceParams::decode(1, [101.325, 5000.0, 0.0, 0.0]); // pump
    world
        .edit_network::<Pipes>(move |host| {
            let _ = host.bind_device(device_e, a, bp, 0, params).unwrap();
        })
        .unwrap();

    let before = {
        let host = world.network::<Pipes>().unwrap();
        let ra = host.region_of(a).unwrap();
        let rb = host.region_of(bp).unwrap();
        host.payload(ra).unwrap().total() + host.payload(rb).unwrap().total()
    };

    // Step the device edge imperatively (`verdigris/ffi/src/pipes.rs`'s
    // `pipe_step_devices` shape, minus the `ByondValue` plumbing): resolve
    // both sides' regions, run the pure flow law, write the results back.
    for _ in 0..50 {
        let (ra, rb, vol_a, vol_b, mut pa, mut pb) = {
            let host = world.network::<Pipes>().unwrap();
            let ra = host.region_of(a).unwrap();
            let rb = host.region_of(bp).unwrap();
            let (ra_region, rb_region) = (host.network().region(ra).unwrap(), host.network().region(rb).unwrap());
            (ra, rb, *ra_region.summary(), *rb_region.summary(), *ra_region.payload(), *rb_region.payload())
        };
        let report = device::step(&params, &mut pa, vol_a, &mut pb, vol_b, 1.0);
        if report.moles == 0.0 && report.power_w == 0.0 {
            break;
        }
        world
            .edit_network::<Pipes>(move |host| {
                let _ = host.set_payload(ra, pa);
                let _ = host.set_payload(rb, pb);
            })
            .unwrap();
    }

    let after = {
        let host = world.network::<Pipes>().unwrap();
        let ra = host.region_of(a).unwrap();
        let rb = host.region_of(bp).unwrap();
        let (pa, pb) = (host.payload(ra).unwrap(), host.payload(rb).unwrap());
        assert!(pb.total() > 0.0, "the pump moved gas into the empty region");
        pa.total() + pb.total()
    };
    assert!((after - before).abs() < 1e-3, "conserves mass: {before} vs {after}");
}
