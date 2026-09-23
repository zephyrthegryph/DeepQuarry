//! The pump component (`doc/rewrite/rust_bindings.md` §2, §14 — the
//! reference component for the whole binding layer).
//!
//! `Pump`'s config and state live in its own `MainPort<PumpKind>` (R4), one
//! cell per bound pump; the entity table (`vg_ffi::entity`) is what lets a
//! DM `vg_entity` handle find that cell, checked for staleness and for
//! holding a pump at all (§5, §9). The flow law itself (M2) reads and writes
//! this same store from its own frame task once it lands; nothing here
//! assumes it has.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use byondapi::prelude::*;
use eyre::{Result, eyre};
use vg_core::component::QueryValue;
use vg_core::cow::ChunkLayout;
use vg_core::entity::{CellAllocator, ComponentRef};
use vg_core::owner::DomainKey;
use vg_core::sim::{Sim, SimBuilder, SimConfig};
use vg_core::vg;
use vg_ffi::entity::{self, EntityDomain};

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

// `VG_GAS_PUMP` is generated from the `#[vg::component(kind = 1, ...)]`
// attribute above (component scan), not from an `@dm-define` line: the two
// generators must never disagree on a kind's numeric id.
pub const KIND: u16 = Pump::KIND;

struct World {
    sim: Sim,
    key: DomainKey<PumpKind>,
    cells: CellAllocator,
}

impl World {
    fn new() -> Self {
        let mut builder = SimBuilder::new(SimConfig {
            // A component kind's own store needs no worker parallelism
            // today (the flow law is a separate frame task M2 adds later);
            // one thread keeps the pool footprint minimal.
            threads: 1,
            ..SimConfig::default()
        });
        let key = builder.add_domain::<PumpKind>(ChunkLayout::linear(1 << 16));
        let sim = builder
            .build()
            .unwrap_or_else(|e| unreachable!("static pump domain config always builds: {e}"));
        Self {
            sim,
            key,
            cells: CellAllocator::new(),
        }
    }

    fn detach_component(&mut self, comp: ComponentRef) {
        if comp.kind != KIND {
            return;
        }
        let _ = self.sim.port(self.key).take(comp.cell);
        self.cells.free_cell(comp.cell);
    }

    fn describe_component(&self, comp: ComponentRef) -> Vec<(String, String)> {
        if comp.kind != KIND {
            return Vec::new();
        }
        let Some(p) = self.sim.port_ref(self.key).read(comp.cell) else {
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
}

/// Shares one `World` between this module's `thread_local` (used by every
/// bind below) and the boxed [`EntityDomain`] the entity table drives, so
/// `vg_entity_unbind`/`vg_entity_tick_all`/reset act on the exact same
/// storage the get/set binds read and write.
struct Shared(Rc<RefCell<World>>);

impl EntityDomain for Shared {
    fn detach(&mut self, comp: ComponentRef) {
        self.0.borrow_mut().detach_component(comp);
    }
    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
        self.0.borrow().describe_component(comp)
    }
    fn tick(&mut self) {
        let mut w = self.0.borrow_mut();
        w.sim.begin_tick();
        w.sim.dispatch_frame();
    }
    fn reset(&mut self) {
        *self.0.borrow_mut() = World::new();
    }
}

thread_local! {
    static WORLD: Rc<RefCell<World>> = Rc::new(RefCell::new(World::new()));
    static REGISTERED: Cell<bool> = const { Cell::new(false) };
}

fn with<T>(f: impl FnOnce(&mut World) -> Result<T>) -> Result<T> {
    REGISTERED.with(|done| {
        if !done.get() {
            WORLD.with(|w| entity::register_entity_domain(DOMAIN, Box::new(Shared(Rc::clone(w)))));
            done.set(true);
        }
    });
    WORLD.with(|w| f(&mut w.borrow_mut()))
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

/// Resolves `entity` to this pump's cell.
fn cell_of(entity: &ByondValue) -> Result<u32> {
    let comp = entity::resolve(num(entity)?, DOMAIN, KIND)?;
    Ok(comp.cell)
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
    let h = entity::bind_or_reuse(num(&entity)?)?;
    let cell = with(|w| {
        let cell = w.cells.alloc();
        w.sim
            .port(w.key)
            .put(cell, value.clone())
            .map_err(|e| eyre!("pump bind: {e}"))?;
        Ok(cell)
    })?;
    entity::attach(h, DOMAIN, ComponentRef::new(KIND, cell)).map_err(|e| eyre!("{e}"))?;
    Ok(ByondValue::from(entity::entity_value(h)))
}

// --- Config: get/set -----------------------------------------------------

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_target_pressure")]
fn pump_get_target_pressure(entity: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let p = with(|w| {
        w.sim
            .port(w.key)
            .read(cell)
            .ok_or_else(|| eyre!("pump cell {cell} out of range"))
    })?;
    Ok(ByondValue::from(p.target_pressure))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/set_target_pressure")]
fn pump_set_target_pressure(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v =
        Pump::validate_target_pressure(num(&value)?).map_err(|e| eyre!("field `target_pressure`: {e}"))?;
    with(|w| {
        w.sim
            .port(w.key)
            .submit(cell, PumpCommand::TargetPressure(v))
            .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::from(v))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_power_rating")]
fn pump_get_power_rating(entity: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let p = with(|w| {
        w.sim
            .port(w.key)
            .read(cell)
            .ok_or_else(|| eyre!("pump cell {cell} out of range"))
    })?;
    Ok(ByondValue::from(p.power_rating))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/set_power_rating")]
fn pump_set_power_rating(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v = Pump::validate_power_rating(num(&value)?).map_err(|e| eyre!("field `power_rating`: {e}"))?;
    with(|w| {
        w.sim
            .port(w.key)
            .submit(cell, PumpCommand::PowerRating(v))
            .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::from(v))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_on")]
fn pump_get_on(entity: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let p = with(|w| {
        w.sim
            .port(w.key)
            .read(cell)
            .ok_or_else(|| eyre!("pump cell {cell} out of range"))
    })?;
    Ok(bool_value(p.on))
}

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/set_on")]
fn pump_set_on(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v = truthy(&value)?;
    with(|w| {
        w.sim
            .port(w.key)
            .submit(cell, PumpCommand::On(v))
            .map_err(|e| eyre!("{e}"))
    })?;
    Ok(bool_value(v))
}

// --- State: read-only ------------------------------------------------------

#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_flow_rate")]
fn pump_get_flow_rate(entity: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let p = with(|w| {
        w.sim
            .port(w.key)
            .read(cell)
            .ok_or_else(|| eyre!("pump cell {cell} out of range"))
    })?;
    Ok(ByondValue::from(p.flow_rate))
}

// --- Input: read-only get (reconciler, §7), pushed by generated wiring ----

/// Rust's currently stored `operable`, for the reconciler (§7): it compares
/// this against what `pump_input_operable()` recomputes on the DM side.
#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/get_operable")]
fn pump_get_operable(entity: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let p = with(|w| {
        w.sim
            .port(w.key)
            .read(cell)
            .ok_or_else(|| eyre!("pump cell {cell} out of range"))
    })?;
    Ok(bool_value(p.operable))
}

/// Pushes a recomputed `operable` (class 3/4 sources: construction,
/// integrity). Never validated (booleans have no range): §2's `identity`
/// path.
#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/push_operable")]
fn pump_push_operable(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let v = truthy(&value)?;
    with(|w| {
        w.sim
            .port(w.key)
            .submit(cell, PumpCommand::Operable(v))
            .map_err(|e| eyre!("{e}"))
    })?;
    Ok(bool_value(v))
}

// --- Query group -----------------------------------------------------------

/// `pump_query_ui()` (§3, §6): every UI field in one call. Rust fn name
/// intentionally matches the generated global proc the generator points
/// `pump_query_ui()`'s DM wrapper at (`vg_<fn name>`, no `_ffi` suffix): see
/// `tools/build/lib/verdigris_bindings.ts`'s component-binding convention.
#[auxmacros::bind("/obj/machinery/atmospherics/binary/pump/proc/pump_query_ui")]
fn pump_query_ui(entity: ByondValue) -> Result<ByondValue> {
    let cell = cell_of(&entity)?;
    let p = with(|w| {
        w.sim
            .port(w.key)
            .read(cell)
            .ok_or_else(|| eyre!("pump cell {cell} out of range"))
    })?;
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

    /// The world builds and round-trips a bind/read/write/detach cycle
    /// without going through byondapi at all (the FFI wrappers above are
    /// thin; this exercises the storage and validation they call into).
    #[test]
    fn world_binds_reads_writes_and_detaches() {
        let mut world = World::new();
        let cell = world.cells.alloc();
        let seeded = Pump {
            target_pressure: 101.325,
            power_rating: 7500.0,
            on: false,
            operable: true,
            flow_rate: 0.0,
        };
        world.sim.port(world.key).put(cell, seeded.clone()).unwrap();
        assert_eq!(world.sim.port(world.key).read(cell), Some(seeded));

        let clamped = Pump::validate_target_pressure(999_999.0).unwrap();
        world
            .sim
            .port(world.key)
            .submit(cell, PumpCommand::TargetPressure(clamped))
            .unwrap();
        assert_eq!(world.sim.port(world.key).read(cell).unwrap().target_pressure, 15000.0);

        world.detach_component(ComponentRef::new(KIND, cell));
        assert_eq!(
            world.sim.port(world.key).read(cell),
            Some(Pump::default()),
            "take() resets the cell to Value::default()"
        );
    }
}
