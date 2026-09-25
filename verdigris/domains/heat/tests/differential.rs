//! Differential tests: the old `Task`/`Sim`-driven path
//! ([`HeatWorld`]/[`Body`]/`couple::add_gas_coupling`) against the new
//! `Law`-driven path (`vg_heat::laws`), on identical randomized inputs.
//!
//! This is the verification the coordinator asked for in place of a live
//! DreamDaemon boot (`rust_architecture.md` §7's migration order: land the
//! new laws first, prove equivalence with differential tests, *then*
//! delete the old host): both paths ultimately call the same underlying
//! formula ([`couple::pair_exchange`]/[`couple::pair_exchange_at_rate`]),
//! so a mismatch here would mean the *wiring* around one of them is wrong
//! -- a stale read, a sign flip, a skipped step -- not that the physics
//! itself disagrees. Passing is the confidence needed to delete `world.rs`/
//! `body.rs`'s driver/`couple.rs`'s `Task` machinery once the new path has
//! everywhere it needs to run (Core A's scheduler, still landing).
//!
//! Every scenario picks capacities that keep the *old* path on its
//! **stepped** branch (not the analytic `RELAX` shortcut): `body.rs`'s
//! `advance()` only goes analytic when the environment's capacity is at
//! least `RELAX_CAPACITY_RATIO` (100x) the body's, which every proptest
//! range below stays well under. The analytic path is a *closed-form
//! solution* of the same stepped law (documented in `laws::relax_toward`,
//! itself differentially tested against `pair_exchange` in `laws.rs`), so
//! it doesn't need its own comparison here.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use proptest::prelude::*;
use vg_core::grid::GridDims;
use vg_core::law::{Law, LawCtx, Settle};
use vg_core::units::Seconds;
use vg_heat::couple::{GasExchange, GasProbe, GasRef};
use vg_heat::laws::{
    BodyEnvironmentExchange, BodyGasCoupling, PairCoupling, PairSides, SolidGasCoupling,
    ThermalSide,
};
use vg_heat::{Body, CellSpec, Coupling, HeatConfig, HeatWorld, Target};

#[derive(Default)]
struct MockGas {
    mixes: Mutex<HashMap<GasRef, (f32, f32, bool)>>, // (temperature, capacity, reservoir)
    /// Turf cells a fresh `add()` touched, not yet reported through
    /// `take_changed()`. `couple::add_gas_coupling`'s candidate set is
    /// `take_changed()` unioned with the field's own *active* AIR cells --
    /// and `HeatWorld::set_cell` seeds a brand-new cell via a plain `put()`
    /// (initial setup, not a wake-generating command), so a freshly created
    /// cell is *not* active on its own. Without this, the coupling would
    /// never get its first candidate and this mock would silently
    /// under-test the law it's meant to verify.
    changed: Mutex<Vec<u32>>,
}

impl MockGas {
    fn add(&self, r: GasRef, temperature: f32, capacity: f32, reservoir: bool) {
        self.mixes
            .lock()
            .unwrap()
            .insert(r, (temperature, capacity, reservoir));
        if let GasRef::Turf(cell) = r {
            self.changed.lock().unwrap().push(cell);
        }
    }
}

impl GasExchange for MockGas {
    fn probe(&self, gas: GasRef) -> Option<GasProbe> {
        self.mixes
            .lock()
            .unwrap()
            .get(&gas)
            .map(|&(t, c, r)| GasProbe {
                temperature: t,
                capacity: c,
                reservoir: r,
            })
    }
    fn exchange(&self, gas: GasRef, f: &mut dyn FnMut(GasProbe) -> f32) -> Option<f32> {
        let mut mixes = self.mixes.lock().unwrap();
        let &(t, c, r) = mixes.get(&gas)?;
        let e = f(GasProbe {
            temperature: t,
            capacity: c,
            reservoir: r,
        });
        if !r && c > 0.0 {
            mixes.get_mut(&gas).unwrap().0 = t + e / c;
        }
        Some(e)
    }
    fn take_changed(&self, out: &mut Vec<u32>) {
        out.append(&mut self.changed.lock().unwrap());
    }
}

fn world() -> (HeatWorld, Arc<MockGas>) {
    let gas = Arc::new(MockGas::default());
    let dims = GridDims::new(4, 4, 1).unwrap();
    let w = HeatWorld::new(
        HeatConfig::new(dims),
        Arc::clone(&gas) as Arc<dyn vg_heat::GasExchange>,
    )
    .unwrap();
    (w, gas)
}

/// Runs a [`Law`] with [`PairCoupling`] reads/[`PairSides`] writes for one
/// step, mirroring one old-path frame exactly (fresh `Ledger`/events/wakes
/// each call, since this harness only compares temperatures, not
/// conservation bookkeeping -- `laws.rs`'s own tests already cover that).
fn step_law<L: Law<Reads = PairCoupling, Writes = PairSides>>(
    sides: &mut PairSides,
    conductance: f32,
    dt: f32,
) -> Settle {
    let mut fx = vg_core::law::Effects::default();
    let reads = PairCoupling { conductance };
    let mut ctx = LawCtx::new(&reads, sides, &mut fx);
    L::step(&mut ctx, Seconds(f64::from(dt)))
}

proptest! {
    /// Body<->solid: HeatWorld's stepped `pair_exchange` against
    /// `BodyEnvironmentExchange`.
    #[test]
    fn body_solid_exchange_matches_the_old_stepped_path(
        body_t in 100.0f32..1000.0, body_c in 10.0f32..500.0,
        solid_t in 100.0f32..1000.0, solid_c in 500.0f32..5000.0,
        conductance in 0.5f32..50.0,
        frames in 1u32..30,
    ) {
        // Stay well clear of RELAX_CAPACITY_RATIO (100x): at or above it the
        // old path switches to its analytic closed-form shortcut instead of
        // stepping, which this test isn't comparing against (that shortcut
        // has its own differential coverage in laws.rs's relax_toward tests).
        prop_assume!(solid_c < 90.0 * body_c);

        let (mut w, _gas) = world();
        let cell = w.dims().index(1, 1, 0).unwrap();
        w.set_cell(cell, CellSpec::solid(solid_c, 0.0, solid_t));
        let h = w
            .create_body(Body::new(body_c, body_t).kept().with_coupling(0, Coupling::new(Target::Solid(cell), conductance)))
            .unwrap();
        w.settle();

        // Read the settled starting point back rather than reusing the raw
        // generated values: settle() may already need a dispatched frame to
        // publish the just-created body/cell, and the new (law-driven) side
        // must start from the exact same point the old side did, not from
        // pre-settle inputs that could already have drifted by one step.
        let mut sides = PairSides {
            a: ThermalSide::mutable(w.body(h).unwrap().temperature, body_c),
            b: ThermalSide::mutable(w.cell_temperature(cell).unwrap(), solid_c),
            quantity: "heat_energy",
        };

        for _ in 0..frames {
            w.run_frames(1);
            step_law::<BodyEnvironmentExchange>(&mut sides, conductance, 1.0);
        }

        let old_body_t = w.body(h).unwrap().temperature;
        let old_solid_t = w.cell_temperature(cell).unwrap();
        let tol = (body_t.max(solid_t)) * 1e-3 + 1e-2;
        prop_assert!(
            (old_body_t - sides.a.temperature).abs() < tol,
            "body: old={old_body_t} new={} (frames={frames})", sides.a.temperature
        );
        prop_assert!(
            (old_solid_t - sides.b.temperature).abs() < tol,
            "solid: old={old_solid_t} new={} (frames={frames})", sides.b.temperature
        );
    }

    /// Solid<->gas: HeatWorld's `add_gas_coupling` Task against
    /// `SolidGasCoupling`.
    #[test]
    fn solid_gas_exchange_matches_the_old_task_path(
        solid_t in 200.0f32..1500.0, solid_c in 500.0f32..5000.0,
        gas_t in 200.0f32..1500.0, gas_c in 100.0f32..5000.0,
        conductivity in 0.1f32..2.0,
        frames in 1u32..30,
    ) {
        // Skip inputs already inside the deadband: the old Task's
        // candidate-set bookkeeping (skips a pair within GAS_COUPLING_MIN_K)
        // and the law's own guard would both correctly do nothing, but the
        // old path also never re-adds a settled pair to its `pending` set
        // in that case, which isn't itself under test here.
        prop_assume!((solid_t - gas_t).abs() >= vg_heat::consts::GAS_COUPLING_MIN_K * 2.0);

        let (mut w, gas) = world();
        let cell = w.dims().index(2, 1, 0).unwrap();
        w.set_cell(cell, CellSpec::solid(solid_c, conductivity, solid_t).with_air());
        let turf = GasRef::Turf(cell);
        gas.add(turf, gas_t, gas_c, false);
        w.settle();

        // See body_solid_exchange_matches_the_old_stepped_path's comment:
        // read the settled starting point back instead of the raw inputs.
        let settled_gas_t = gas.mixes.lock().unwrap()[&turf].0;
        let mut sides = PairSides {
            a: ThermalSide::mutable(w.cell_temperature(cell).unwrap(), solid_c),
            b: ThermalSide::mutable(settled_gas_t, gas_c),
            quantity: "heat_energy",
        };

        for _ in 0..frames {
            w.run_frames(1);
            step_law::<SolidGasCoupling>(&mut sides, conductivity, 1.0);
        }

        let old_solid_t = w.cell_temperature(cell).unwrap();
        let old_gas_t = gas.mixes.lock().unwrap()[&turf].0;
        let tol = (solid_t.max(gas_t)) * 1e-3 + 1e-2;
        prop_assert!(
            (old_solid_t - sides.a.temperature).abs() < tol,
            "solid: old={old_solid_t} new={} (frames={frames})", sides.a.temperature
        );
        prop_assert!(
            (old_gas_t - sides.b.temperature).abs() < tol,
            "gas: old={old_gas_t} new={} (frames={frames})", sides.b.temperature
        );
    }

    /// Body<->gas: HeatWorld's `Stores::exchange` (a body's `Target::Gas`
    /// coupling) against `BodyGasCoupling` -- the law behind the hotspot
    /// fix (`laws.rs`'s `gas_cell_warms_item_body_through_the_hotspot_coupling_law`).
    #[test]
    fn body_gas_exchange_matches_the_old_stepped_path(
        body_t in 200.0f32..1500.0, body_c in 10.0f32..500.0,
        gas_t in 200.0f32..1500.0, gas_c in 500.0f32..5000.0,
        conductance in 0.5f32..50.0,
        frames in 1u32..30,
    ) {
        // See body_solid_exchange_matches_the_old_stepped_path's comment.
        prop_assume!(gas_c < 90.0 * body_c);

        let (mut w, gas) = world();
        let cell = w.dims().index(3, 1, 0).unwrap();
        let turf = GasRef::Turf(cell);
        gas.add(turf, gas_t, gas_c, false);
        let h = w
            .create_body(Body::new(body_c, body_t).kept().with_coupling(0, Coupling::new(Target::Gas(turf), conductance)))
            .unwrap();
        w.settle();

        let settled_gas_t = gas.mixes.lock().unwrap()[&turf].0;
        let mut sides = PairSides {
            a: ThermalSide::mutable(w.body(h).unwrap().temperature, body_c),
            b: ThermalSide::mutable(settled_gas_t, gas_c),
            quantity: "heat_energy",
        };

        for _ in 0..frames {
            w.run_frames(1);
            step_law::<BodyGasCoupling>(&mut sides, conductance, 1.0);
        }

        let old_body_t = w.body(h).unwrap().temperature;
        let old_gas_t = gas.mixes.lock().unwrap()[&turf].0;
        let tol = (body_t.max(gas_t)) * 1e-3 + 1e-2;
        prop_assert!(
            (old_body_t - sides.a.temperature).abs() < tol,
            "body: old={old_body_t} new={} (frames={frames})", sides.a.temperature
        );
        prop_assert!(
            (old_gas_t - sides.b.temperature).abs() < tol,
            "gas: old={old_gas_t} new={} (frames={frames})", sides.b.temperature
        );
    }
}
