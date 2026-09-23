//! Conservation, ledger, topology and storage tests for the power domain.

use proptest::prelude::*;

use crate::apc::{ApcConfig, ApcState, CELLRATE, chan, status};
use crate::geom::{CableShape, EAST, NORTH, WEST, pos};
use crate::smes::{SMESRATE, SmesConfig};
use crate::world::{PowerWorld, ev};

/// Records of one type in an event list: `(type, values)`.
fn records(events: &[f32], kind: u32) -> Vec<Vec<f32>> {
    let mut out = Vec::new();
    let mut i = 0;
    while i + 1 < events.len() {
        let t = events[i] as u32;
        let n = events[i + 1] as usize;
        if t == kind {
            out.push(events[i + 2..i + 2 + n].to_vec());
        }
        i += 2 + n;
    }
    out
}

fn wire(d1: u8, d2: u8) -> CableShape {
    CableShape {
        d1,
        d2,
        ..CableShape::default()
    }
}

/// A straight east-west run of `n` cables at y = 5 from x = 1, keys 1..=n,
/// with knots at both ends (keys 100, 101) and machine nodes there.
fn line(w: &mut PowerWorld, n: u32) {
    for x in 1..=n {
        w.add_cable(x, pos(x, 5, 1), wire(EAST, WEST).normalized()).unwrap();
    }
    w.add_cable(100, pos(1, 5, 1), wire(0, EAST)).unwrap();
    w.add_cable(101, pos(n, 5, 1), wire(0, WEST)).unwrap();
}

impl CableShape {
    fn normalized(mut self) -> Self {
        if self.d1 > self.d2 {
            std::mem::swap(&mut self.d1, &mut self.d2);
        }
        self
    }
}

#[test]
fn cutting_splits_and_repairing_merges() {
    let mut w = PowerWorld::new();
    line(&mut w, 10);
    w.add_machine(200, pos(1, 5, 1)).unwrap();
    w.add_machine(201, pos(10, 5, 1)).unwrap();
    w.commit();
    let a = w.region_info(200).unwrap().region;
    assert_eq!(w.region_info(201).unwrap().region, a, "one network end to end");

    w.remove(5);
    w.commit();
    let (ra, rb) = (w.region_info(200).unwrap().region, w.region_info(201).unwrap().region);
    assert_ne!(ra, rb, "a cut splits the network");

    w.add_cable(5, pos(5, 5, 1), wire(EAST, WEST).normalized()).unwrap();
    w.commit();
    assert_eq!(
        w.region_info(200).unwrap().region,
        w.region_info(201).unwrap().region,
        "a repair merges it again"
    );
    let events = w.step();
    let binds = records(&events, ev::BIND);
    assert!(!binds.is_empty(), "machines hear their new regions");
}

#[test]
fn machines_join_knots_only() {
    let mut w = PowerWorld::new();
    w.add_cable(1, pos(3, 3, 1), wire(EAST, WEST).normalized()).unwrap();
    w.add_machine(2, pos(3, 3, 1)).unwrap();
    w.commit();
    assert_ne!(w.region_info(1).unwrap().region, w.region_info(2).unwrap().region);
    w.add_cable(3, pos(3, 3, 1), wire(0, EAST)).unwrap();
    w.commit();
    assert_eq!(w.region_info(1).unwrap().region, w.region_info(2).unwrap().region);
}

#[test]
fn draws_never_exceed_supply() {
    let mut w = PowerWorld::new();
    line(&mut w, 4);
    w.add_machine(200, pos(1, 5, 1)).unwrap();
    w.add_machine(201, pos(4, 5, 1)).unwrap();
    w.set_supply(200, 1000.0);
    w.step();
    assert_eq!(w.draw(201, 600.0), 600.0);
    assert_eq!(w.draw(201, 600.0), 400.0, "only what is left");
    assert_eq!(w.draw(201, 1.0), 0.0);
    w.step();
    assert_eq!(w.draw(201, 10.0), 10.0, "the next step has its supply again");
    let info = w.region_info(201).unwrap();
    assert_eq!(info.summary[0], 1000.0, "summary carries the supply");
}

#[test]
fn a_split_side_loses_the_supply_at_once() {
    let mut w = PowerWorld::new();
    line(&mut w, 6);
    w.add_machine(200, pos(1, 5, 1)).unwrap();
    w.add_machine(201, pos(6, 5, 1)).unwrap();
    w.set_supply(200, 1000.0);
    w.step();
    w.remove(3);
    assert_eq!(w.draw(201, 100.0), 0.0, "cut off from the generator");
    assert_eq!(w.draw(200, 100.0), 100.0);
}

#[test]
fn an_explosion_is_one_commit() {
    let mut w = PowerWorld::new();
    line(&mut w, 200);
    w.add_machine(200_000, pos(1, 5, 1)).unwrap();
    w.step();
    for x in (2..200).step_by(2) {
        w.remove(x);
    }
    let before = w.network().revision();
    w.commit();
    assert_eq!(w.network().revision(), before + 1, "one commit for the batch");
    assert!(w.network().region_count() >= 100);
}

fn apc_config(max: f64) -> ApcConfig {
    ApcConfig {
        max_charge: max,
        ..ApcConfig::default()
    }
}

/// An APC on a terminal at the end of a line, a generator at the start.
fn apc_world(supply: f64, charge: f64) -> PowerWorld {
    let mut w = PowerWorld::new();
    line(&mut w, 4);
    w.add_machine(200, pos(1, 5, 1)).unwrap();
    w.add_machine(201, pos(4, 5, 1)).unwrap();
    w.set_supply(200, supply);
    w.set_apc(
        300,
        apc_config(1000.0),
        Some(201),
        Some(ApcState {
            charge,
            ..ApcState::default()
        }),
    );
    w.set_area_load(300, [2000.0, 1000.0, 1000.0]);
    w.step();
    w
}

#[test]
fn an_apc_drains_browns_out_restores_and_charges() {
    // No supply: the cell carries the area and sheds channels as it drains.
    let mut w = apc_world(0.0, 1000.0);
    let mut shed_equipment = false;
    let mut dark = false;
    for _ in 0..400 {
        let events = w.step();
        for r in records(&events, ev::APC) {
            if r[2] as u8 == chan::OFF_AUTO {
                shed_equipment = true;
            }
            if r[14] as u8 == 0 {
                dark = true;
            }
        }
        if dark {
            break;
        }
    }
    assert!(shed_equipment, "equipment is shed first");
    assert!(dark, "the area goes dark once the cell is empty");
    let apc = w.apc(300).unwrap();
    assert!(apc.state.charge < 1000.0 * 0.15);
    assert_eq!(apc.state.main_status, status::NOT_CONNECTED);

    // Supply returns: channels come back and the cell charges.
    w.set_supply(200, 100_000.0);
    let mut restored = false;
    let mut charged = false;
    for _ in 0..3000 {
        let events = w.step();
        for r in records(&events, ev::APC) {
            if r[14] as u8 == 7 {
                restored = true;
            }
            if r[5] as u8 == 2 {
                charged = true;
            }
        }
        if restored && charged {
            break;
        }
    }
    assert!(restored, "all three channels come back");
    assert!(charged, "the cell charges to full");
    assert_eq!(w.apc(300).unwrap().state.charge, 1000.0);
}

#[test]
fn an_idle_apc_and_smes_report_nothing() {
    let mut w = apc_world(100_000.0, 1000.0);
    w.add_machine(400, pos(2, 5, 1)).unwrap();
    // Wire the SMES output onto the line: a knot under it.
    w.add_cable(102, pos(2, 5, 1), wire(0, EAST)).unwrap();
    w.set_smes(
        400,
        SmesConfig {
            capacity: 1e6,
            input_enabled: true,
            output_enabled: false,
            ..SmesConfig::default()
        },
        vec![201],
        Some(1e6),
    );
    // The monitor view settles geometrically (0.8 per step).
    for _ in 0..80 {
        w.step();
    }
    for _ in 0..20 {
        let events = w.step();
        assert!(records(&events, ev::APC).is_empty(), "a settled APC is silent");
        assert!(records(&events, ev::SMES).is_empty(), "a full idle SMES is silent");
        assert!(records(&events, ev::REGION).is_empty(), "a settled region is silent");
    }
}

#[test]
fn smes_carries_the_grid_and_conserves() {
    let mut w = PowerWorld::new();
    line(&mut w, 4);
    w.add_machine(400, pos(1, 5, 1)).unwrap();
    w.add_machine(201, pos(4, 5, 1)).unwrap();
    w.set_smes(
        400,
        SmesConfig {
            capacity: 1e6,
            output_level: 10_000.0,
            ..SmesConfig::default()
        },
        vec![],
        Some(1e6),
    );
    w.step();
    let start = w.smes(400).unwrap().state.charge;
    let mut drawn = 0.0;
    for _ in 0..10 {
        drawn += w.draw(201, 4000.0);
        w.step();
    }
    assert_eq!(drawn, 40_000.0);
    let end = w.smes(400).unwrap().state.charge;
    assert!((start - end - drawn * SMESRATE).abs() < 1e-6, "charge pays for the draws exactly");
    let b = w.books();
    assert!((b.storage_out - drawn).abs() < 1e-9);
}

#[derive(Clone, Debug)]
enum Op {
    Cable(u8, u8, u8),
    Remove(u8),
    Supply(u8, u16),
    Pulse(u8, u16),
    Draw(u8, u16),
    Step,
}

fn op() -> impl Strategy<Value = Op> {
    prop_oneof![
        4 => (0u8..8, 0u8..4, 0u8..6).prop_map(|(x, y, s)| Op::Cable(x, y, s)),
        1 => any::<u8>().prop_map(Op::Remove),
        1 => (0u8..4, any::<u16>()).prop_map(|(m, w)| Op::Supply(m, w)),
        1 => (0u8..4, any::<u16>()).prop_map(|(m, w)| Op::Pulse(m, w)),
        3 => (0u8..4, any::<u16>()).prop_map(|(m, w)| Op::Draw(m, w)),
        2 => Just(Op::Step),
    ]
}

proptest! {
    /// Whatever the edits, loads never get more than was offered, storage
    /// pays for exactly what it gave, and charges stay in bounds.
    #[test]
    fn the_ledger_conserves(ops in prop::collection::vec(op(), 1..200)) {
        let shapes = [
            wire(0, EAST), wire(0, WEST), wire(EAST, WEST), wire(0, NORTH),
            wire(NORTH, 2), wire(0, 2),
        ];
        let mut w = PowerWorld::new();
        // Four machines on a row, a SMES among them, an APC on machine 3.
        for m in 0..4u32 {
            w.add_machine(1000 + m, pos(m * 2 + 1, 2, 1)).unwrap();
        }
        w.set_smes(1001, SmesConfig { capacity: 1e5, input_enabled: true, output_level: 500.0, ..SmesConfig::default() }, vec![1002], Some(5e4));
        w.set_apc(2000, ApcConfig { max_charge: 500.0, ..ApcConfig::default() }, Some(1003), Some(ApcState { charge: 250.0, ..ApcState::default() }));
        w.set_area_load(2000, [300.0, 200.0, 100.0]);
        let smes0 = w.smes(1001).unwrap().state.charge;
        let mut delivered = 0.0;
        for o in ops {
            match o {
                Op::Cable(x, y, s) => {
                    let key = u32::from(x) + 8 * u32::from(y) + 1;
                    w.add_cable(key, pos(u32::from(x) + 1, u32::from(y) + 1, 1), shapes[s as usize].normalized()).unwrap();
                }
                Op::Remove(k) => w.remove(u32::from(k % 40) + 1),
                Op::Supply(m, v) => w.set_supply(1000 + u32::from(m), f64::from(v)),
                Op::Pulse(m, v) => w.pulse(1000 + u32::from(m), f64::from(v)),
                Op::Draw(m, v) => {
                    let d = w.draw(1000 + u32::from(m), f64::from(v));
                    prop_assert!(d >= 0.0 && d <= f64::from(v));
                    delivered += d;
                }
                Op::Step => { w.step(); }
            }
            let s = w.smes(1001).unwrap().state.charge;
            prop_assert!((0.0..=1e5).contains(&s));
            let a = w.apc(2000).unwrap().state.charge;
            prop_assert!((0.0..=500.0).contains(&a));
        }
        w.step();
        let b = w.books();
        prop_assert!(delivered <= b.delivered + 1e-6);
        prop_assert!(b.delivered <= b.generated + b.storage_out + 1e-6 * (1.0 + b.generated));
        prop_assert!(b.storage_out <= b.storage_offered + 1e-6 * (1.0 + b.storage_offered));
        let s = w.smes(1001).unwrap().state.charge;
        let expect = smes0 + (b.storage_in - b.storage_out) * SMESRATE;
        prop_assert!((s - expect).abs() < 1e-6 * (1.0 + smes0), "smes {s} vs books {expect}");
    }
}

#[test]
fn apc_parity_with_dm_distributor_constants() {
    // One tick of a full cell on a strong grid: the grid carries the area
    // and nothing else changes (the DM distributor's first branch).
    let mut w = apc_world(100_000.0, 1000.0);
    w.step();
    let apc = w.apc(300).unwrap();
    assert_eq!(apc.state.charge, 1000.0);
    assert_eq!(apc.state.lastused[4], 4000.0);
    assert_eq!(apc.state.main_status, status::GOOD);
    // Without supply, one tick uses CELLRATE per watt from the cell.
    let mut w = apc_world(0.0, 1000.0);
    let before = w.apc(300).unwrap().state.charge;
    w.step();
    let after = w.apc(300).unwrap().state.charge;
    assert!((before - after - 4000.0 * CELLRATE).abs() < 1e-9);
}
