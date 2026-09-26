//! End-to-end test of `vg-heat`'s laws over `vg_core::world::World`
//! (`rust_architecture.md` §8.5, step 4): a body↔solid-cell exchange, a
//! body↔body exchange and a regulator, all `byondapi`-free and driven the
//! same generic way DM's `vg_component_*`/`vg_world_*` binds would.

use std::sync::Arc;

use vg_core::conservation::Tolerance;
use vg_core::field::{FieldConfig, Geom};
use vg_core::grid::GridDims;
use vg_core::world::{WorldBuilder, WorldConfig};
use vg_heat::couple::{GasHandle, NoGas};
use vg_heat::laws::{BodyBodyExchange, BodyGasExchange, RegulatorHeatPump, SolidBodyExchange};
use vg_heat::{BodyCoupling, GasCoupling, HeatBody, Regulator, SolidCoupling, SolidHeat};

const DT: f32 = 1.0;

fn builder() -> WorldBuilder {
    WorldBuilder::new(WorldConfig {
        check_conservation: true,
        ..WorldConfig::default()
    })
}

#[test]
fn a_body_relaxes_toward_a_solid_cell_and_conserves_heat_energy() {
    let mut b = builder();
    let grid = b.add_grid(GridDims::new(2, 1, 1).unwrap());
    let field = b.add_field::<SolidHeat>(FieldConfig { dt: DT, max_substeps: 16 });
    let _body = b.add_component::<HeatBody>();
    let coupling = b.add_component::<SolidCoupling>();
    b.conserve("heat_energy", Tolerance::default());
    let _ = b.add_law::<SolidBodyExchange>();
    let mut world = b.build().expect("builds");
    let _ = grid;

    // Cell 0: an ordinary solid turf at 400 K, capacity 10,000 J/K.
    world
        .sim_mut()
        .port(field.geometry)
        .put(
            0,
            Geom {
                capacity: 10_000.0,
                blocked: vg_core::grid::Dir::NONE,
                reservoir: false,
            },
        )
        .unwrap();
    world
        .sim_mut()
        .port(field.cells)
        .put(0, vg_heat::SolidCell::at(10_000.0, 400.0, 0.05, 0.9, 0))
        .unwrap();

    let body_e = world
        .bind_value(
            None,
            HeatBody {
                capacity: 10.0,
                energy: 10.0 * 300.0,
                ..Default::default()
            },
        )
        .unwrap();
    let _ = world
        .bind_value(
            None,
            SolidCoupling {
                body: body_e.index(),
                cell: 0,
                conductance: 5.0,
                slot: 0,
            },
        )
        .unwrap();
    let _ = coupling;

    for _ in 0..2_000 {
        world.step_blocking();
    }

    let body: HeatBody = world.read(body_e).unwrap();
    assert!((body.temperature() - 400.0).abs() < 1.0, "body settled near the cell: {}", body.temperature());
    let cell = world.sim_mut().port(field.cells).read(0).unwrap();
    let cell_t = f64::from(cell.energy) / 10_000.0;
    assert!((cell_t - 400.0).abs() < 1.0, "the much larger cell barely moved: {cell_t}");

    let violations = world.violations();
    assert!(violations.is_empty(), "heat_energy conserved across the body/solid exchange: {violations:?}");
}

#[test]
fn two_bodies_exchange_and_conserve_energy() {
    let mut b = builder();
    let a = b.add_component::<HeatBody>();
    let coupling = b.add_component::<BodyCoupling>();
    b.conserve("heat_energy", Tolerance::default());
    let _ = b.add_law::<BodyBodyExchange>();
    let mut world = b.build().expect("builds");
    let _ = (a, coupling);

    let a_e = world
        .bind_value(
            None,
            HeatBody {
                capacity: 10.0,
                energy: 10.0 * 400.0,
                ..Default::default()
            },
        )
        .unwrap();
    let b_e = world
        .bind_value(
            None,
            HeatBody {
                capacity: 20.0,
                energy: 20.0 * 300.0,
                ..Default::default()
            },
        )
        .unwrap();
    let _ = world
        .bind_value(
            None,
            BodyCoupling {
                body: a_e.index(),
                other: b_e.index(),
                conductance: 2.0,
                slot: 0,
            },
        )
        .unwrap();

    let before: f64 = {
        let a: HeatBody = world.read(a_e).unwrap();
        let b: HeatBody = world.read(b_e).unwrap();
        a.energy + b.energy
    };

    for _ in 0..500 {
        world.step_blocking();
    }

    let a_body: HeatBody = world.read(a_e).unwrap();
    let b_body: HeatBody = world.read(b_e).unwrap();
    assert!(a_body.temperature() < 400.0);
    assert!(b_body.temperature() > 300.0);
    assert!((a_body.temperature() - b_body.temperature()).abs() < 1.0, "settled near a common temperature");
    assert!(((a_body.energy + b_body.energy) - before).abs() < 1e-2, "total energy conserved");

    let violations = world.violations();
    assert!(violations.is_empty(), "heat_energy conserved across the body/body exchange: {violations:?}");
}

#[test]
fn a_regulator_heats_the_controlled_body_toward_its_target() {
    let mut b = builder();
    let controlled = b.add_component::<HeatBody>();
    let other = b.add_component::<Regulator>();
    let _ = b.add_law::<RegulatorHeatPump>();
    let mut world = b.build().expect("builds");
    let _ = (controlled, other);

    let cold_e = world
        .bind_value(
            None,
            HeatBody {
                capacity: 100.0,
                energy: 100.0 * 280.0,
                ..Default::default()
            },
        )
        .unwrap();
    let hot_e = world
        .bind_value(
            None,
            HeatBody {
                capacity: 1.0e6,
                energy: 1.0e6 * 293.15,
                ..Default::default()
            },
        )
        .unwrap();
    let _ = world
        .bind_value(
            None,
            Regulator {
                controlled: cold_e.index(),
                other: hot_e.index(),
                target: 293.15,
                max_power: 500.0,
                mode: 2,
                carnot_fraction: 0.5,
                max_cop: 10.0,
                resistive_heating: true,
                deadband: 0.05,
            },
        )
        .unwrap();

    for _ in 0..2_000 {
        world.step_blocking();
    }

    let controlled_body: HeatBody = world.read(cold_e).unwrap();
    assert!((controlled_body.temperature() - 293.15).abs() < 1.0, "driven to the target: {}", controlled_body.temperature());
}

#[test]
fn a_body_exchanges_with_gas_through_the_gas_handle() {
    use vg_heat::{GasExchange, GasProbe, GasRef};

    struct FixedGas(std::sync::Mutex<f32>);
    impl GasExchange for FixedGas {
        fn probe(&self, _gas: GasRef) -> Option<GasProbe> {
            None
        }
        fn exchange(&self, _gas: GasRef, f: &mut dyn FnMut(GasProbe) -> f32) -> Option<f32> {
            let mut t = self.0.lock().unwrap();
            let applied = f(GasProbe {
                temperature: *t,
                capacity: 1_000.0,
                reservoir: false,
            });
            *t += applied / 1_000.0;
            Some(applied)
        }
    }

    let mut b = builder();
    let body = b.add_component::<HeatBody>();
    let coupling = b.add_component::<GasCoupling>();
    b.add_global(vg_core::component::Ownership::Worker, GasHandle(Arc::new(FixedGas(std::sync::Mutex::new(280.0)))));
    let _ = b.add_law::<BodyGasExchange>();
    let mut world = b.build().expect("builds");
    let _ = (body, coupling);

    let body_e = world
        .bind_value(
            None,
            HeatBody {
                capacity: 10.0,
                energy: 10.0 * 400.0,
                ..Default::default()
            },
        )
        .unwrap();
    let _ = world
        .bind_value(
            None,
            GasCoupling {
                body: body_e.index(),
                kind: 0,
                target: 0,
                conductance: 2.0,
                slot: 0,
            },
        )
        .unwrap();

    for _ in 0..500 {
        world.step_blocking();
    }

    let body: HeatBody = world.read(body_e).unwrap();
    assert!(body.temperature() < 400.0, "the body cooled toward the gas: {}", body.temperature());
    let _ = NoGas;
}
