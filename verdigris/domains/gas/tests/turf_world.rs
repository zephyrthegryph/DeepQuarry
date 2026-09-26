//! End-to-end test of `vg-gas`'s turf field's new `Cell<TurfGas>`-anchored
//! laws (`rust_architecture.md` §8.5, step 6) against a real
//! `vg_core::world::World`: `WorldBuilder::add_field::<TurfGas>` plus
//! `CellVisualChangeLaw`/`SpacewindLaw` registered as ordinary laws, driven
//! by `World::tick`/`step_blocking`, exactly the shape the real cutover
//! (replacing gas's private `Sim` in `domains/gas/src/world.rs`) will use.
//! This is deliberately independent of that cutover: nothing here is
//! reachable from DM yet (`vg-ffi` still registers the old private
//! `Field`), so it carries no risk to the live game while proving the new
//! laws work against the real field simulation, not just in isolation
//! (`domains/gas/src/laws.rs`'s own unit tests already cover that).
//!
//! Both cells here are face neighbours (a `2x1x1` grid): a `Cell<K>`-
//! anchored law only ever visits cells with at least one live edge (the
//! field's own wake/settle bookkeeping is edge-driven, `field/mod.rs`'s own
//! docs) -- true of every real turf but not of an edgeless single-cell
//! grid, which this discovered while first writing these tests.

use vg_core::field::FieldConfig;
use vg_core::grid::{Dir, GridDims};
use vg_core::world::{WorldBuilder, WorldConfig};
use vg_gas::cell::{GasCell, N, TurfGas};
use vg_gas::gas::ids::GAS_OXYGEN;
use vg_gas::laws::{CellVisualChangeLaw, GasEvent, SpacewindLaw};

const DT: f32 = 0.5;

fn builder() -> WorldBuilder {
    WorldBuilder::new(WorldConfig {
        check_conservation: true,
        ..WorldConfig::default()
    })
}

fn geom(capacity: f32) -> vg_core::field::Geom {
    vg_core::field::Geom {
        capacity,
        blocked: Dir::NONE,
        reservoir: false,
    }
}

#[test]
fn a_pressure_gradient_between_two_open_cells_emits_a_pressure_jump() {
    let mut b = builder();
    let _grid = b.add_grid(GridDims::new(2, 1, 1).unwrap());
    let field = b.add_field::<TurfGas>(FieldConfig { dt: DT, max_substeps: 16 });
    let _ = b.add_law::<SpacewindLaw>();
    let mut world = b.build().expect("builds");

    // A huge molar gap at a real temperature: comfortably past
    // `PRESSURE_EVENT`'s 5 kPa (already scaled by `PRESSURE_EVENT_SCALE`)
    // even before the field's first flux pass narrows it.
    let mut hi = GasCell::new([0.0; N], 293.0);
    hi.moles[GAS_OXYGEN] = 100_000.0;
    hi.refresh_in(2500.0);
    let lo = GasCell::new([0.0; N], 293.0); // empty: a large pressure gap to cell 0

    world.sim_mut().port(field.geometry).put(0, geom(2500.0)).unwrap();
    world.sim_mut().port(field.geometry).put(1, geom(2500.0)).unwrap();
    world.sim_mut().port(field.cells).put(0, hi).unwrap();
    world.sim_mut().port(field.cells).put(1, lo).unwrap();

    // The spacewind law runs on the very first step the newly-put cells
    // are active (their chunk allocation just changed, so both wake
    // immediately) -- one step is enough to see the gradient.
    world.step_blocking();

    let events: Vec<_> = world.drain_events().decoded::<GasEvent>().map(|(_, e)| e).collect();
    assert!(
        events.iter().any(|e| matches!(e, GasEvent::PressureJump { cell: 0, neighbor: 1, .. })),
        "expected a PressureJump from the high side: {events:?}"
    );

    let violations = world.violations();
    assert!(violations.is_empty(), "the field itself still conserves gas: {violations:?}");
}

#[test]
fn a_cell_with_visible_gas_emits_exactly_one_visual_change_until_it_changes_again() {
    // `GasCell::refresh_in` derives `vis` from the process-wide gate table
    // (`gate::install`/`gate::current()`): install one that makes oxygen
    // visible above a trivial threshold. Safe here (unlike
    // `laws.rs`'s own tests of the same global): this file is its own test
    // binary/process, and it is the only test in it that touches the gate.
    let mut gate = vg_gas::gate::Gate::default();
    gate.visible[GAS_OXYGEN] = Some(1.0);
    vg_gas::gate::install(gate);

    let mut b = builder();
    let _grid = b.add_grid(GridDims::new(2, 1, 1).unwrap());
    let field = b.add_field::<TurfGas>(FieldConfig { dt: DT, max_substeps: 16 });
    let _ = b.add_law::<CellVisualChangeLaw>();
    let mut world = b.build().expect("builds");

    let mut cell = GasCell::new([0.0; N], 293.0);
    cell.moles[GAS_OXYGEN] = 500.0;
    cell.refresh_in(2500.0);
    assert_ne!(cell.vis, 0, "oxygen above the installed visibility threshold");
    let empty = GasCell::new([0.0; N], 293.0);

    world.sim_mut().port(field.geometry).put(0, geom(2500.0)).unwrap();
    world.sim_mut().port(field.geometry).put(1, geom(2500.0)).unwrap();
    world.sim_mut().port(field.cells).put(0, cell).unwrap();
    world.sim_mut().port(field.cells).put(1, empty).unwrap();

    world.step_blocking();
    let first: Vec<_> = world.drain_events().decoded::<GasEvent>().map(|(_, e)| e).collect();
    assert!(
        first.iter().any(|e| matches!(e, GasEvent::CellVisualChange { cell: 0, vis } if *vis == cell.vis)),
        "expected cell 0's visual change: {first:?}"
    );

    // Running to equilibrium and re-checking a settled cell that hasn't
    // crossed the threshold again should emit nothing further for it.
    for _ in 0..50 {
        world.step_blocking();
    }
    let _ = world.drain_events(); // drop whatever the diffusing neighbour emitted meanwhile
    world.step_blocking();
    let steady: Vec<_> = world.drain_events().decoded::<GasEvent>().map(|(_, e)| e).collect();
    assert!(
        !steady.iter().any(|e| matches!(e, GasEvent::CellVisualChange { cell: 0, .. })),
        "settled: no further visual change for cell 0: {steady:?}"
    );
}
