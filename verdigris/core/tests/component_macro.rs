//! End-to-end test of `#[vg::component]`, `#[vg::query]` and `#[vg::events]`
//! (`doc/rewrite/rust_bindings.md` §2, §3), using a small stand-in component
//! shaped like the pump (§14). This is the host-buildable half of the
//! generated code: everything here is `byondapi`-free, so it runs in a
//! normal `cargo test` without the i686 toolchain the FFI glue needs.

use vg_core::component::QueryValue;
use vg_core::cow::ChunkLayout;
use vg_core::entity::{CellAllocator, ComponentRef, EntityTable};
use vg_core::owner::Domain;
use vg_core::sim::{SimBuilder, SimConfig};
use vg_core::vg;

#[vg::component(domain = test_domain, kind = 1, dm = "/obj/machinery/atmospherics/binary/pump")]
pub struct Widget {
    #[vg(config, unit = "kPa", range = 0.0..=100.0, default = 20.0, on_invalid = clamp)]
    target_pressure: f32,
    #[vg(config, unit = "W", range = 0.0..=500.0, default = 30.0, on_invalid = reject)]
    power_rating: f32,
    #[vg(config, default = false)]
    on: bool,
    #[vg(input, from = [construction, integrity])]
    operable: bool,
    #[vg(state, unit = "mol/s")]
    flow_rate: f32,
}

#[vg::query(Widget, ui = [target_pressure, power_rating, on, flow_rate])]
#[allow(dead_code)]
struct WidgetQuery;

#[vg::events(Widget)]
pub enum WidgetEvent {
    TargetReached,
    Starved,
}

#[test]
fn defaults_and_clamp_validation() {
    let w = Widget::default();
    assert_eq!(w.target_pressure, 20.0);
    assert_eq!(w.power_rating, 30.0);
    assert!(!w.on);
    assert!(!w.operable);
    assert_eq!(w.flow_rate, 0.0);

    assert_eq!(Widget::validate_target_pressure(150.0), Ok(100.0), "clamp");
    assert_eq!(Widget::validate_target_pressure(-5.0), Ok(0.0), "clamp");
    assert!(Widget::validate_power_rating(600.0).is_err(), "reject out of range");
    assert_eq!(Widget::validate_power_rating(400.0), Ok(400.0));
    assert_eq!(Widget::validate_on(true), Ok(true));
}

#[test]
fn schema_lists_every_field_with_its_role_and_unit() {
    let schema = Widget::schema();
    assert_eq!(schema.domain, "test_domain");
    assert_eq!(schema.kind, 1);
    assert_eq!(schema.dm_type, "/obj/machinery/atmospherics/binary/pump");
    let names: Vec<&str> = schema.fields.iter().map(|f| f.name).collect();
    assert_eq!(names, ["target_pressure", "power_rating", "on", "operable", "flow_rate"]);
    assert_eq!(schema.fields[0].unit, Some("kPa"));
    assert_eq!(schema.fields[2].unit, None);
}

#[test]
fn query_group_returns_every_listed_field_in_order() {
    let w = Widget {
        target_pressure: 55.0,
        power_rating: 12.0,
        on: true,
        operable: false,
        flow_rate: 3.5,
    };
    let q = w.query_ui();
    assert_eq!(
        q,
        [
            QueryValue::F32(55.0),
            QueryValue::F32(12.0),
            QueryValue::Bool(true),
            QueryValue::F32(3.5),
        ]
    );
    assert_eq!(Widget::QUERY_UI_FIELDS, ["target_pressure", "power_rating", "on", "flow_rate"]);
}

#[test]
fn events_get_stable_ids_and_snake_case_names() {
    assert_eq!(WidgetEvent::TargetReached.id(), 0);
    assert_eq!(WidgetEvent::TargetReached.name(), "target_reached");
    assert_eq!(WidgetEvent::Starved.id(), 1);
    assert_eq!(WidgetEvent::Starved.name(), "starved");
    assert_eq!(WidgetEvent::from_id(1), Some(WidgetEvent::Starved));
    assert_eq!(WidgetEvent::from_id(2), None);
}

/// Commands round-trip through `Domain::apply`, exactly as the generated
/// `set_*`/`push_*` FFI glue will use them (§5).
#[test]
fn commands_apply_config_and_input_fields() {
    let mut w = Widget::default();
    WidgetKind::apply(&mut w, &WidgetCommand::TargetPressure(42.0));
    WidgetKind::apply(&mut w, &WidgetCommand::On(true));
    WidgetKind::apply(&mut w, &WidgetCommand::Operable(true));
    assert_eq!(w.target_pressure, 42.0);
    assert!(w.on);
    assert!(w.operable);
    // `flow_rate` (state) intentionally has no command variant: `WidgetCommand`
    // only has TargetPressure/PowerRating/On/Operable.
}

/// The whole storage path a generated component uses: entity table resolves
/// a handle to a `ComponentRef`, whose `cell` addresses the kind's own
/// `MainPort` (`rust_bindings.md` §1, §4, §5, §9) — proving read-your-writes
/// end to end without any FFI involved.
#[test]
fn entity_and_main_port_give_read_your_writes() {
    const DOMAIN: usize = 0;

    let mut entities = EntityTable::new();
    let mut cells = CellAllocator::new();
    let mut builder = SimBuilder::new(SimConfig {
        threads: 1,
        ..SimConfig::default()
    });
    let key = builder.add_domain::<WidgetKind>(ChunkLayout::linear(1 << 10));
    let mut sim = builder.build().expect("static config always builds");

    let entity = entities.bind().unwrap();
    let cell = cells.alloc();
    sim.port(key).put(cell, Widget::default()).unwrap();
    entities.attach(entity, DOMAIN, ComponentRef::new(Widget::KIND, cell)).unwrap();

    let comp = entities.component(entity, DOMAIN, Widget::KIND).unwrap();
    assert_eq!(comp.cell, cell);

    let validated = Widget::validate_target_pressure(9000.0).unwrap();
    sim.port(key)
        .submit(comp.cell, WidgetCommand::TargetPressure(validated))
        .unwrap();
    let seen = sim.port(key).read(comp.cell).unwrap();
    assert_eq!(seen.target_pressure, 100.0, "read reflects the write immediately");

    // Unbind: detach then free, mirroring `vg_entity_unbind` (§4).
    let _ = sim.port(key).take(comp.cell).unwrap();
    cells.free_cell(comp.cell);
    entities.detach(entity, DOMAIN).unwrap();
    entities.unbind(entity).unwrap();
    assert!(!entities.contains(entity));
}
