//! The pump component (`doc/rewrite/rust_architecture.md` §5 — the
//! reference component for the whole binding layer). Everything below the
//! declarations is generated: the store, `get_*`/`set_*`/`push_*`, `bind`,
//! `describe` and the query proc all come from `#[vg::component]`/
//! `#[vg::query]`/`#[vg::events]` (`verdigris/ffi/macros/src/component.rs`).

use vg_core::vg;

/// This component's domain index in the entity table (§4.1). Gas is domain
/// 0; later domains (power, heat, ...) take 1, 2, ... as they land. Expected
/// in scope by the generated glue (`DOMAIN` is a fixed name, not passed
/// through the macro, since several kinds share one domain's number).
/// @dm-define VG_DOMAIN_GAS
pub const DOMAIN: usize = 0;

#[vg::component(domain = gas, kind = 1, dm = "/obj/machinery/atmospherics/binary/pump")]
pub struct Pump {
    #[vg(config, unit = "kPa", range = 0.0..=15000.0, default = 101.325, on_invalid = clamp)]
    target_pressure: f32,
    #[vg(config, unit = "W", range = 0.0..=60000.0, default = 7500.0, on_invalid = clamp)]
    power_rating: f32,
    #[vg(config, default = false)]
    on: bool,
    #[vg(input, from = [construction, integrity])]
    operable: bool,
    #[vg(state, unit = "mol/s")]
    flow_rate: f32,
}

#[vg::query(Pump, ui = [target_pressure, power_rating, on, flow_rate])]
#[allow(dead_code)]
struct PumpQuery;

#[vg::events(Pump)]
pub enum PumpEvent {
    TargetReached,
    Starved,
}

#[cfg(test)]
mod tests {
    use super::*;
    use vg_core::store::KindStore;

    /// The generated store binds, reads, writes and detaches a row
    /// correctly, without going through byondapi at all (the generated FFI
    /// wrappers are thin; this exercises the storage and validation they
    /// call into).
    #[test]
    fn store_binds_reads_writes_and_detaches() {
        let mut store = KindStore::<PumpKind>::new();
        let seeded = Pump {
            target_pressure: 101.325,
            power_rating: 7500.0,
            on: false,
            operable: true,
            flow_rate: 0.0,
        };
        let cell = store.bind(1.0, seeded.clone()).unwrap();
        assert_eq!(store.read(cell), Some(seeded));

        let clamped = Pump::validate_target_pressure(999_999.0).unwrap();
        store.submit(cell, PumpCommand::TargetPressure(clamped)).unwrap();
        assert_eq!(store.read(cell).unwrap().target_pressure, 15000.0);

        store.detach(cell);
        assert_eq!(store.read(cell), Some(Pump::default()), "detach resets the row to Value::default()");
    }

    /// Events raised against a row are attributed to the entity bound there,
    /// and vanish once that entity detaches (§4.8): the whole path a future
    /// law's `push_event` will exercise, tested independent of one.
    #[test]
    fn events_are_attributed_to_the_bound_entity_and_drain_once() {
        let mut store = KindStore::<PumpKind>::new();
        let cell = store.bind(42.0, Pump::default()).unwrap();

        store.push_event(cell + 1, PumpEvent::Starved.id());
        let mut out = Vec::new();
        store.drain_events(&mut out);
        assert!(out.is_empty(), "an event on an unbound row must not be attributed to anything");

        store.push_event(cell, PumpEvent::TargetReached.id());
        store.push_event(cell, PumpEvent::Starved.id());
        let mut out = Vec::new();
        store.drain_events(&mut out);
        assert_eq!(out, vec![(42.0, PumpEvent::TargetReached.id()), (42.0, PumpEvent::Starved.id())]);

        let mut out2 = Vec::new();
        store.drain_events(&mut out2);
        assert!(out2.is_empty(), "drained once");

        store.detach(cell);
        store.push_event(cell, PumpEvent::TargetReached.id());
        let mut out3 = Vec::new();
        store.drain_events(&mut out3);
        assert!(out3.is_empty(), "a detached row's event must not resurrect the old entity");
    }
}
