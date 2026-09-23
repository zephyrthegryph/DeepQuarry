//! The pump component (`doc/rewrite/rust_architecture.md` §5, §6 — the
//! reference component for the whole binding layer).
//!
//! `Pump`'s config and state live in one [`vg_core::store::KindStore`] (R4's
//! `MainPort`, generalized off gas), one row per bound pump; the entity
//! table (`vg_ffi::entity`) is what lets a DM `vg_entity` handle find that
//! row, checked for staleness and for holding a pump at all (§5, §9). The
//! flow law itself (M2) reads and writes this same store from its own frame
//! task once it lands; nothing here assumes it has.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use byondapi::prelude::*;
use eyre::{Result, eyre};
use vg_core::component::QueryValue;
use vg_core::entity::ComponentRef;
use vg_core::store::KindStore;
use vg_core::vg;
use vg_ffi::entity;
use vg_ffi::registry::{self, DomainRegistry};

/// This component's domain index in the entity table (§1). Gas is domain 0;
/// later domains (power, heat, ...) take 1, 2, ... as they land.
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

/// `@dm-define VG_GAS_PUMP`
pub const KIND: u16 = Pump::KIND;

/// Shares one store between this module's `thread_local` (used by every
/// bind below) and the boxed [`DomainRegistry`] the entity table drives, so
/// `vg_entity_unbind`/`vg_entity_tick_all`/reset act on the exact same
/// storage the get/set binds read and write.
struct Shared(Rc<RefCell<KindStore<PumpKind>>>);

impl DomainRegistry for Shared {
    fn detach(&mut self, comp: ComponentRef) {
        if comp.kind != KIND {
            return;
        }
        self.0.borrow_mut().detach(comp.cell);
    }
    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
        if comp.kind != KIND {
            return Vec::new();
        }
        let Some(p) = self.0.borrow().read(comp.cell) else {
            return Vec::new();
        };
        vec![
            ("target_pressure".into(), format!("{} kPa", p.target_pressure)),
            ("power_rating".into(), format!("{} W", p.power_rating)),
            ("on".into(), p.on.to_string()),
            ("operable".into(), p.operable.to_string()),
            ("flow_rate".into(), format!("{} mol/s", p.flow_rate)),
        ]
    }
    fn tick(&mut self) {
        self.0.borrow_mut().tick();
    }
    fn reset(&mut self) {
        *self.0.borrow_mut() = KindStore::new();
    }
    fn drain_events(&mut self, out: &mut Vec<(u16, f32, u8)>) {
        let mut raw = Vec::new();
        self.0.borrow_mut().drain_events(&mut raw);
        out.extend(raw.into_iter().map(|(entity, id)| (KIND, entity, id)));
    }
}

thread_local! {
    static STORE: Rc<RefCell<KindStore<PumpKind>>> = Rc::new(RefCell::new(KindStore::new()));
    static REGISTERED: Cell<bool> = const { Cell::new(false) };
}

fn with<T>(f: impl FnOnce(&mut KindStore<PumpKind>) -> Result<T>) -> Result<T> {
    REGISTERED.with(|done| {
        if !done.get() {
            #[allow(clippy::cast_possible_truncation)]
            STORE.with(|s| registry::register_domain(DOMAIN as u32, Box::new(Shared(Rc::clone(s)))));
            done.set(true);
        }
    });
    STORE.with(|s| f(&mut s.borrow_mut()))
}

fn num(v: &ByondValue) -> Result<f32> {
    Ok(v.get_number()?)
}

fn truthy(v: &ByondValue) -> Result<bool> {
    Ok(num(v)? != 0.0)
}

fn bool_value(b: bool) -> ByondValue {
    ByondValue::from(if b { 1.0f32 } else { 0.0f32 })
}

/// Resolves `entity` to this pump's row.
fn cell_of(entity: &ByondValue) -> Result<u32> {
    let comp = entity::resolve(num(entity)?, DOMAIN, KIND)?;
    Ok(comp.cell)
}

fn read(cell: u32) -> Result<Pump> {
    with(|w| w.read(cell).ok_or_else(|| eyre!("pump row {cell} out of range")))
}

// --- Lifecycle: bind and query-string of the entity table --------------

/// Creates the entity (if `entity` is 0) or reuses it, attaches a pump
/// component seeded from the `init_*` values and the current input, and
/// returns the entity handle (§4, §5). DM's base `on_materialize()` calls
/// this once per component the type declares.
#[auxmacros::bind("/proc/pump_bind")]
fn pump_bind(
    entity: ByondValue,
    init_target_pressure: ByondValue,
    init_power_rating: ByondValue,
    init_on: ByondValue,
    operable: ByondValue,
) -> Result<ByondValue> {
    let target_pressure = Pump::validate_target_pressure(num(&init_target_pressure)?)
        .map_err(|e| eyre!("field `target_pressure`: {e}"))?;
    let power_rating = Pump::validate_power_rating(num(&init_power_rating)?)
        .map_err(|e| eyre!("field `power_rating`: {e}"))?;
    let value = Pump {
        target_pressure,
        power_rating,
        on: truthy(&init_on)?,
        operable: truthy(&operable)?,
        flow_rate: 0.0,
    };
    let id = entity::bind_or_reuse(num(&entity)?)?;
    let entity_v = entity::entity_value(id);
    let cell = with(|w| w.bind(entity_v, value).map_err(|e| eyre!("pump bind: {e}")))?;
    entity::attach(id, DOMAIN, ComponentRef::new(KIND, cell)).map_err(|e| eyre!("{e}"))?;
    Ok(ByondValue::from(entity_v))
}

// --- Config: get/set -----------------------------------------------------

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_target_pressure")]
fn pump_get_target_pressure(entity: ByondValue) -> Result<ByondValue> {
    Ok(ByondValue::from(read(cell_of(&entity)?)?.target_pressure))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/set_target_pressure")]
fn pump_set_target_pressure(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v =
        Pump::validate_target_pressure(num(&value)?).map_err(|e| eyre!("field `target_pressure`: {e}"))?;
    with(|w| w.submit(cell, PumpCommand::TargetPressure(v)).map_err(|e| eyre!("{e}")))?;
    Ok(ByondValue::from(v))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_power_rating")]
fn pump_get_power_rating(entity: ByondValue) -> Result<ByondValue> {
    Ok(ByondValue::from(read(cell_of(&entity)?)?.power_rating))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/set_power_rating")]
fn pump_set_power_rating(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v = Pump::validate_power_rating(num(&value)?).map_err(|e| eyre!("field `power_rating`: {e}"))?;
    with(|w| w.submit(cell, PumpCommand::PowerRating(v)).map_err(|e| eyre!("{e}")))?;
    Ok(ByondValue::from(v))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_on")]
fn pump_get_on(entity: ByondValue) -> Result<ByondValue> {
    Ok(bool_value(read(cell_of(&entity)?)?.on))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/set_on")]
fn pump_set_on(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v = truthy(&value)?;
    with(|w| w.submit(cell, PumpCommand::On(v)).map_err(|e| eyre!("{e}")))?;
    Ok(bool_value(v))
}

// --- State: read-only ------------------------------------------------------

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_flow_rate")]
fn pump_get_flow_rate(entity: ByondValue) -> Result<ByondValue> {
    Ok(ByondValue::from(read(cell_of(&entity)?)?.flow_rate))
}

// --- Input: read-only get (reconciler, §7), pushed by generated wiring ----

/// Rust's currently stored `operable`, for the reconciler (§7): it compares
/// this against what `pump_input_operable()` recomputes on the DM side.
#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_operable")]
fn pump_get_operable(entity: ByondValue) -> Result<ByondValue> {
    Ok(bool_value(read(cell_of(&entity)?)?.operable))
}

/// Pushes a recomputed `operable` (class 3/4 sources: construction,
/// integrity). Never validated (booleans have no range): §2's `identity`
/// path.
#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/push_operable")]
fn pump_push_operable(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v = truthy(&value)?;
    with(|w| w.submit(cell, PumpCommand::Operable(v)).map_err(|e| eyre!("{e}")))?;
    Ok(bool_value(v))
}

// --- Query group -----------------------------------------------------------

/// `pump_query_ui()` (§3, §6): every UI field in one call. Rust fn name
/// intentionally matches the generated global proc the generator points
/// `pump_query_ui()`'s DM wrapper at (`vg_<fn name>`, no `_ffi` suffix): see
/// `tools/build/lib/verdigris_bindings.ts`'s component-binding convention.
#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/pump_query_ui")]
fn pump_query_ui(entity: ByondValue) -> Result<ByondValue> {
    let p = read(cell_of(&entity)?)?;
    let values: Vec<ByondValue> = p
        .query_ui()
        .into_iter()
        .map(|v| match v {
            QueryValue::F32(f) => ByondValue::from(f),
            QueryValue::Bool(b) => bool_value(b),
        })
        .collect();
    let mut list = ByondValue::new_list()?;
    for (name, value) in Pump::QUERY_UI_FIELDS.iter().zip(values) {
        list.write_list_index(*name, value)?;
    }
    Ok(list)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The store binds, reads, writes and detaches a row correctly, without
    /// going through byondapi at all (the FFI wrappers above are thin; this
    /// exercises the storage and validation they call into).
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
    /// and vanish once that entity detaches (§8): the whole path a future
    /// law's `push_event` will exercise, tested independent of one.
    #[test]
    fn events_are_attributed_to_the_bound_entity_and_drain_once() {
        let mut store = KindStore::<PumpKind>::new();
        let cell = store.bind(42.0, Pump::default()).unwrap();

        // No bound entity yet at a different row: nothing to attribute to.
        store.push_event(cell + 1, PumpEvent::Starved.id());
        let mut out = Vec::new();
        store.drain_events(&mut out);
        assert!(out.is_empty(), "an event on an unbound row must not be attributed to anything");

        store.push_event(cell, PumpEvent::TargetReached.id());
        store.push_event(cell, PumpEvent::Starved.id());
        let mut out = Vec::new();
        store.drain_events(&mut out);
        assert_eq!(out, vec![(42.0, PumpEvent::TargetReached.id()), (42.0, PumpEvent::Starved.id())]);

        // Drained once: nothing left the second time.
        let mut out2 = Vec::new();
        store.drain_events(&mut out2);
        assert!(out2.is_empty());

        // Detaching clears the attribution: a later event on the same
        // (reused) row is never mistaken for the old entity's.
        store.detach(cell);
        store.push_event(cell, PumpEvent::TargetReached.id());
        let mut out3 = Vec::new();
        store.drain_events(&mut out3);
        assert!(out3.is_empty(), "a detached row's event must not resurrect the old entity");
    }
}
