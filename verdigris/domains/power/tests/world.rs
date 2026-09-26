//! End-to-end test of `vg-power`'s laws over `vg_core::world::World`
//! (`rust_architecture.md` §8.5, step 3): two regions -- a producer, an APC
//! and a SMES's own (output) node in one, its separate input terminal
//! entity in the other (`vg_core::query::Foreign` joins the input terminal
//! back to the shared `Smes` row). Everything here is `byondapi`-free, and
//! every write below goes through the same generic, field-id path DM's
//! `vg_component_bind`/`vg_component_get` binds use -- not the private
//! struct fields.

use vg_core::component::{Component, Ownership};
use vg_core::conservation::Tolerance;
use vg_core::entity::EntityId;
use vg_core::world::{WorldBuilder, WorldConfig};
use vg_power::components::{Apc, Producer, Smes, SmesInputTerminal};
use vg_power::kind::{Cables, PowerNode};
use vg_power::laws::{ApcTick, PowerReset, PowerSettle, ProducerCredit, SmesInputApply, SmesInputPlan, SmesOutputApply, SmesOutputPlan};

const NODE_MACHINE: u16 = 1;

fn knot(d1: u8) -> vg_power::Cable {
    vg_power::Cable { d1, d2: 0, up: 0, down: 0, link: 0 }
}

fn field<C: Component>(name: &str) -> u16 {
    C::field_id(name).unwrap_or_else(|| panic!("no field {name} on {}", C::NAME))
}

#[test]
fn a_smes_shares_storage_per_terminal_across_two_regions() {
    let mut b = WorldBuilder::new(WorldConfig {
        check_conservation: true,
        ..WorldConfig::default()
    });
    let apc = b.add_component::<Apc>();
    let producer = b.add_component::<Producer>();
    let smes = b.add_component::<Smes>();
    let smes_in = b.add_component::<SmesInputTerminal>();
    b.add_network::<Cables>(Ownership::Main);
    b.conserve("power_apc_charge", Tolerance::default());
    b.conserve("power_smes_charge", Tolerance::default());
    let _ = b.add_law::<PowerReset>();
    let _ = b.add_law::<ProducerCredit>().after::<PowerReset>();
    let _ = b.add_law::<SmesOutputPlan>().after::<PowerReset>();
    let _ = b.add_law::<SmesInputPlan>().after::<PowerReset>();
    let _ = b.add_law::<ApcTick>().after::<ProducerCredit>().after::<SmesOutputPlan>();
    let _ = b.add_law::<PowerSettle>().after::<ApcTick>();
    let _ = b.add_law::<SmesOutputApply>().after::<PowerSettle>();
    let _ = b.add_law::<SmesInputApply>().after::<PowerSettle>();
    let mut world = b.build().expect("builds");

    // Region A: a producer (50 W), an APC demanding more than that alone
    // (100 W), and the SMES's output terminal.
    let producer_e = world.bind(None, producer, &[(field::<Producer>("supply"), None, 50.0)]).unwrap();
    let cable_a = world.entities_mut().bind().unwrap();
    world
        .edit_network::<Cables>(move |host| {
            host.bind_node(producer_e, 1, NODE_MACHINE, PowerNode::Machine).unwrap();
            host.bind_node(cable_a, 1, 0, PowerNode::Cable(knot(0))).unwrap();
        })
        .unwrap();

    let apc_e = world
        .bind(None, apc, &[(field::<Apc>("static_load"), Some(0), 100.0), (field::<Apc>("capacity"), None, 1_000_000.0)])
        .unwrap();
    world.adjust(apc_e, apc, field::<Apc>("charge"), 0, 1_000_000.0).unwrap();
    world
        .edit_network::<Cables>(move |host| {
            host.bind_node(apc_e, 1, NODE_MACHINE, PowerNode::Machine).unwrap();
        })
        .unwrap();

    let unit_e = world
        .bind(
            None,
            smes,
            &[
                (field::<Smes>("output_level"), None, 1000.0),
                (field::<Smes>("input_level"), None, 500.0),
                (field::<Smes>("capacity"), None, 1_000_000.0),
            ],
        )
        .unwrap();
    world.set(unit_e, smes, field::<Smes>("output_enabled"), None, 1.0).unwrap();
    world.set(unit_e, smes, field::<Smes>("input_enabled"), None, 1.0).unwrap();
    world.adjust(unit_e, smes, field::<Smes>("charge"), 0, 1_000_000.0).unwrap();

    world
        .edit_network::<Cables>(move |host| {
            host.bind_node(unit_e, 1, NODE_MACHINE, PowerNode::Machine).unwrap();
        })
        .unwrap();

    // Region B: only the SMES's input terminal, on its own cell (its own
    // region -- no cable joins it to region A).
    let in_e = world.bind(None, smes_in, &[(field::<SmesInputTerminal>("unit"), None, f64::from(unit_e.index()))]).unwrap();
    world
        .edit_network::<Cables>(move |host| {
            host.bind_node(in_e, 2, NODE_MACHINE, PowerNode::Machine).unwrap();
        })
        .unwrap();

    world.commit_network::<Cables>();
    world.step_blocking();
    world.step_blocking();

    // The APC's 100 W demand is covered by the 50 W producer plus the
    // SMES's offer (a full 1000 W, all it can output): 50 W non-storage,
    // so 50 W of the APC's load is storage-financed and the SMES's full
    // offer covers it (only output terminal in the region), landing the
    // whole 50 W share on the SMES.
    let apc_charge = world.get(apc_e, apc, field::<Apc>("charge"), 0).unwrap();
    assert!(apc_charge >= 999_999.0, "the grid covered the APC; its cell was not drawn on: {apc_charge}");

    let smes_charge = world.get(unit_e, smes, field::<Smes>("charge"), 0).unwrap();
    assert!(smes_charge < 1_000_000.0, "the output terminal's region asked for storage help: {smes_charge}");
    let discharged = 1_000_000.0 - smes_charge;
    // 50 W of storage-financed load, two ticks (`step_blocking` ran
    // twice), at SMESRATE charge units per watt-tick.
    let expected = 2.0 * 50.0 * vg_power::components::SMESRATE;
    assert!((discharged - expected).abs() < 1e-6, "discharged {discharged}, expected {expected}");

    let violations = world.violations();
    assert!(
        violations.is_empty(),
        "power_apc_charge/power_smes_charge conservation held across the two-region SMES split: {violations:?}"
    );

    // The producer and APC entities stay in region A; the two SMES
    // terminals never share a region with each other or with region A.
    let region_of = |e: EntityId| world.network::<Cables>().unwrap().region_of(e);
    assert_eq!(region_of(producer_e), region_of(apc_e));
    assert_eq!(region_of(producer_e), region_of(unit_e));
    assert_ne!(region_of(producer_e), region_of(in_e));
}
