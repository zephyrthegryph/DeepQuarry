//! End-to-end test of `#[vg::component]`, `#[vg::query]`, `#[vg::events]`
//! and the driver (`doc/rewrite/rust_architecture.md` §4–§5), with small
//! stand-in components: a worker-owned pump-like `Widget` and a main-owned,
//! conserved `Tank`. Everything here is `byondapi`-free.

use vg_core::component::{Component, ComponentError, FieldRole, Ownership, QueryValue};
use vg_core::conservation::Tolerance;
use vg_core::event::Event;
use vg_core::law::{Law, LawCtx, Settle};
use vg_core::owner::Domain;
use vg_core::units::Seconds;
use vg_core::vg;
use vg_core::world::{WorldBuilder, WorldConfig};

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
    /// A fixed-size, enum-keyed field (`rust_bindings.md` §2).
    #[vg(config, unit = "W", range = 0.0..=1000.0, default = [0.0, 0.0, 0.0], on_invalid = clamp)]
    channels: [f64; 3],
}

#[vg::query(Widget, ui = [target_pressure, power_rating, on, flow_rate])]
#[allow(dead_code)]
struct WidgetQuery;

#[vg::events(Widget)]
pub enum WidgetEvent {
    TargetReached,
    Starved { deficit: f32 },
}

#[vg::component(domain = test_domain, kind = 2, dm = "/obj/item/tank", owner = main, computed = [doubled])]
pub struct Tank {
    #[vg(state, unit = "mol", conserve = "moles")]
    moles: f64,
    #[vg(config, unit = "K", range = 2.7..=10000.0, default = 293.15)]
    temperature: f32,
}

impl Tank {
    fn doubled(&self) -> f64 {
        self.moles * 2.0
    }
}

#[test]
fn defaults_validation_and_schema() {
    let w = Widget::default();
    assert_eq!(w.target_pressure, 20.0);
    assert_eq!(w.power_rating, 30.0);
    assert_eq!(Widget::validate_target_pressure(150.0), Ok(100.0), "clamp");
    assert!(Widget::validate_power_rating(600.0).is_err(), "reject out of range");

    assert_eq!(Widget::DOMAIN, "test_domain");
    assert_eq!(Widget::KIND, 1);
    assert_eq!(<Widget as Component>::OWNER, Ownership::Worker);
    assert_eq!(<Tank as Component>::OWNER, Ownership::Main);
    let names: Vec<&str> = Widget::FIELDS.iter().map(|f| f.name).collect();
    assert_eq!(names, ["target_pressure", "power_rating", "on", "operable", "flow_rate", "channels"]);
    assert_eq!(Widget::FIELDS[5].len, 3);
    assert_eq!(Tank::FIELDS[2].role, FieldRole::Computed);
    assert_eq!(Tank::FIELDS[0].conserve, Some("moles"));
}

#[test]
fn generic_field_access_by_id() {
    let mut w = Widget::default();
    let tp = Widget::field_id("target_pressure").unwrap();
    assert_eq!(w.get_field(tp, 0), Some(20.0));
    let cmd = Widget::set_command(tp, None, 500.0).unwrap();
    WidgetKind::apply(&mut w, &cmd);
    assert_eq!(w.target_pressure, 100.0, "clamped through the generic path");
    let flow = Widget::field_id("flow_rate").unwrap();
    assert!(matches!(Widget::set_command(flow, None, 1.0), Err(ComponentError::ReadOnly { .. })));
    let ch = Widget::field_id("channels").unwrap();
    WidgetKind::apply(&mut w, &Widget::set_command(ch, Some(1), 5000.0).unwrap());
    assert_eq!(w.channels, [0.0, 1000.0, 0.0]);

    let mut t = Tank { moles: 10.0, temperature: 300.0 };
    assert_eq!(t.get_field(2, 0), Some(20.0), "computed readout");
    let adj = Tank::adjust_command(0, 0, -15.0).unwrap();
    let applied = TankKind::apply(&mut t, &adj);
    assert_eq!(t.moles, 0.0);
    assert_eq!(applied.shortfall, 5.0);
    assert!(Tank::adjust_command(1, 0, 1.0).is_err(), "temperature is not conserved");
}

#[test]
fn queries_and_events() {
    let w = Widget {
        target_pressure: 55.0,
        power_rating: 12.0,
        on: true,
        ..Widget::default()
    };
    assert_eq!(w.query_ui()[0], QueryValue::F32(55.0));
    assert_eq!(Widget::query_ui_ids(), [0, 1, 2, 4]);
    assert_eq!(WidgetEvent::TargetReached.id(), 0);
    assert_eq!(WidgetEvent::Starved { deficit: 1.0 }.name(), "starved");
    assert_eq!(<WidgetEvent as Event>::VARIANTS[1].fields[0].name, "deficit");
}

/// Runs a worker law over `Widget` rows that reads an optional `Tank` on
/// the same entity.
struct Regulate;

impl Law for Regulate {
    type Reads = Option<Tank>;
    type Writes = Widget;
    const NAME: &'static str = "test_regulate";

    fn step(ctx: &mut LawCtx<'_, Option<Tank>, Widget>, _dt: Seconds) -> Settle {
        let supply = ctx.reads.as_ref().map_or(0.0, |t| t.moles);
        #[allow(clippy::cast_possible_truncation)]
        let flow = supply.min(f64::from(ctx.writes.power_rating)) as f32;
        ctx.writes.flow_rate = flow;
        if flow <= 0.0 {
            ctx.emit(WidgetEvent::Starved { deficit: ctx.writes.power_rating });
        }
        Settle::Sleep
    }
}

#[test]
fn a_world_runs_laws_over_component_rows() {
    let mut b = WorldBuilder::new(WorldConfig {
        check_conservation: true,
        ..WorldConfig::default()
    });
    let widget = b.add_component::<Widget>();
    let tank = b.add_component::<Tank>();
    b.conserve("moles", Tolerance::default());
    let _ = b.add_law::<Regulate>();
    let mut world = b.build().expect("builds");

    let e = world.bind(None, widget, &[(1, None, 7.0)]).unwrap();
    world.bind(Some(e), tank, &[]).unwrap();
    world.adjust(e, tank, 0, 0, 3.0).unwrap();
    let starved = world.bind(None, widget, &[]).unwrap();

    world.step_blocking();
    world.step_blocking();
    assert_eq!(world.read::<Widget>(e).unwrap().flow_rate, 3.0);
    assert_eq!(world.get(e, tank, 2, 0).unwrap(), 6.0);
    let events = world.drain_events();
    let starved_events: Vec<_> = events.decoded::<WidgetEvent>().collect();
    assert_eq!(starved_events.len(), 1);
    assert_eq!(starved_events[0].0, starved.to_f32() + 1.0);
    assert!(world.violations().is_empty(), "DM's adjust is a crossing, not a leak");

    world.despawn(e).unwrap();
    assert!(!world.has(e, widget));
}
