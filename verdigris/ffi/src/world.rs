//! The DLL's one [`World`] (`rust_architecture.md` §4.3, §5) and the generic
//! component binds.
//!
//! There are no per-component binds. DM's generated wrappers
//! (`tools/build/lib/verdigris_bindings.ts`) call these few procs with the
//! kind code (`domain << 8 | kind`) and field ids `#[vg::component]`
//! assigned:
//!
//! | Bind | Does |
//! |---|---|
//! | `vg_component_bind(entity, code, init)` | attach a component (creating the entity when `entity` is 0), `init` = `[field, value, ...]`; returns the entity |
//! | `vg_component_detach(entity, code)` | detach one component |
//! | `vg_component_has(entity, code)` | whether it is attached |
//! | `vg_component_get(entity, code, field, index)` | one number |
//! | `vg_component_get_many(entity, code, fields)` | a list, one number per field id (query groups) |
//! | `vg_component_set(entity, code, field, index, value)` | a validated write (`index` < 0: whole field) |
//! | `vg_component_adjust(entity, code, field, index, delta)` | take reconciliation on a conserved field; returns the shortfall |
//! | `vg_frame(elapsed, budget)` | the one driver (see [`crate::frame`]) |
//! | `vg_world_violations()` | conservation violations since the last call, as text |
//! | `vg_world_laws()` | per-law activity statistics, as text |
//!
//! Watches on component rows go through the scheduler's generic watch binds
//! with the kind's registry id (`VG_WORLD_KIND_BASE | code`) and entity
//! handles as cells.
//!
//! **The registration list.** [`register`] is where every domain's
//! declarations are added to the builder. A domain crate exposes its
//! components, kinds and laws; this list is the only place that names them
//! all.

use std::cell::RefCell;

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::component::FieldId;
use vg_core::conservation::Tolerance;
use vg_core::entity::{ComponentRef, EntityId, WORLD_DOMAIN};
use vg_core::grid::GridDims;
use vg_core::outbox::{Lane, Subscriber, Wake, WatchId};
use vg_core::registry::{DomainRegistry, world_kind_domain};
use vg_core::units::Seconds;
use vg_core::watch::Cond;
use vg_core::world::{KindId, World, WorldBuilder, WorldConfig};

use crate::{entity, registry};

thread_local! {
    /// Set by [`shutdown`]: the world is gone until [`revive`] (the next `world/New()`).
    static SHUT_DOWN: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
    static WORLD: RefCell<Option<World>> = const { RefCell::new(None) };
    /// The grid size the next (re)build uses ([`configure_world`]).
    static PENDING_DIMS: std::cell::Cell<GridDims> = std::cell::Cell::new(GridDims::new(2, 2, 2).expect("2x2x2 fits"));
}

/// The grid dims to build with next.
fn pending_dims() -> GridDims {
    PENDING_DIMS.with(std::cell::Cell::get)
}

/// Rebuilds the world for a `max_x` x `max_y` x `max_z` map, as
/// [`configure_world`] does at boot (tests drive a boot without BYOND).
#[cfg(test)]
pub(crate) fn configure_for_test(max_x: u32, max_y: u32, max_z: u32) -> Result<()> {
    let dims = GridDims::new(max_x, max_y, z_capacity(max_z))
        .ok_or_else(|| eyre!("grid does not fit a u32 index"))?;
    PENDING_DIMS.with(|d| d.set(dims));
    reset()
}

/// Headroom for z-levels created at run time (expeditions): the grid is
/// sized once, and cells past it are ignored.
fn z_capacity(max_z: u32) -> u32 {
    max_z.saturating_mul(2).max(256).max(max_z + 1)
}

/// Every domain's declarations (see the module docs).
/// The field keys `register` hands back for the FFI modules to keep.
struct Fields {
    heat: vg_core::field::FieldKey<vg_heat::SolidHeat>,
    turf_gas: vg_core::field::FieldKey<vg_gas::cell::TurfGas>,
}

fn register(b: &mut WorldBuilder) -> Fields {
    b.add_global(
        vg_core::component::Ownership::Main,
        crate::propagate::RadiationLayer::default(),
    );
    b.add_component::<crate::sched::Probe>();
    b.add_component::<vg_gas::kind::pump::Pump>();
    b.conserve("gas_moles", Tolerance::default());
    // Pipe device flows/valves (the coordinator-approved redesign
    // alongside the gas cutover, `rust_architecture.md` §8.5 step 6):
    // declarative rows replacing DeviceParams's packed `kind, p0..p3` wire
    // form. Registered here (additive; nothing reads or writes them yet --
    // that's `ffi/src/pipes.rs`'s own device stepping, still on the old
    // encoding pending the DM-side device file rewrite).
    b.add_component::<vg_gas::kind::device::DeviceFlow>();
    b.add_component::<vg_gas::kind::device::DeviceValve>();

    // Heat (`rust_architecture.md` §6, §8.5, step 4): the turf solid field
    // plus HeatBody/its coupling components and laws. `crate::heat` is the
    // only heat FFI besides the generic `vg_component_*`/`vg_world_*` ones
    // (turf topology, and watches -- see that module's docs).
    let _grid = b.add_grid(pending_dims());
    let heat_field = crate::heat::register(b);
    let turf_gas = crate::gas::register(b);
    // Heat against turf gas: couplings across the two domains' fields.
    let _ = b.add_law::<vg_heat::laws::SolidGasExchange<vg_gas::cell::TurfGas>>();
    let _ = b.add_law::<vg_heat::laws::BodyGasExchange<vg_gas::cell::TurfGas>>();

    // Power (`rust_architecture.md` §6, §8.5): `Cables`, its components and
    // laws. A SMES's output/input terminals are their own entities, each on
    // its own region; `crate::power`'s topology binds are the only power
    // FFI besides the generic `vg_component_*`/`vg_world_*` ones.
    use vg_core::component::Ownership;
    use vg_power::components::{Apc, Producer, Smes, SmesInputTerminal};
    use vg_power::kind::Cables;
    use vg_power::laws::{
        ApcTick, PowerReset, PowerSettle, ProducerCredit, SmesFlowReset, SmesInputApply, SmesInputPlan,
        SmesOutputApply, SmesOutputPlan,
    };
    b.add_component::<Producer>();
    b.add_component::<Apc>();
    b.add_component::<Smes>();
    b.add_component::<SmesInputTerminal>();
    b.add_network::<Cables>(Ownership::Main);
    b.conserve("power_apc_charge", Tolerance::default());
    b.conserve("power_smes_charge", Tolerance::default());
    let _ = b.add_law::<PowerReset>();
    let _ = b.add_law::<ProducerCredit>().after::<PowerReset>();
    let _ = b.add_law::<SmesOutputPlan>().after::<PowerReset>();
    let _ = b.add_law::<SmesInputPlan>().after::<PowerReset>();
    let _ = b
        .add_law::<ApcTick>()
        .after::<ProducerCredit>()
        .after::<SmesOutputPlan>();
    let _ = b.add_law::<PowerSettle>().after::<ApcTick>();
    let _ = b.add_law::<SmesFlowReset>().after::<PowerReset>();
    let _ = b.add_law::<SmesOutputApply>().after::<PowerSettle>().after::<SmesFlowReset>();
    let _ = b.add_law::<SmesInputApply>().after::<PowerSettle>().after::<SmesFlowReset>();

    // Pipes (`rust_architecture.md` §6, §8.5, step 5): a main-owned network,
    // its region payloads pooled gas (`vg_gas::pipes::PipeGas`). The devices
    // are one law, `PipeDeviceStep`, on the pacer's period (0.5 s): their jobs
    // are staged before each step and written back after it
    // (`crate::pipes::stage_devices` / `apply_devices`).
    b.add_network::<vg_gas::pipes::Pipes>(Ownership::Main);
    b.add_global(Ownership::Main, vg_gas::laws::DeviceJobs::default());
    let _ = b.add_law::<vg_gas::laws::PipeDeviceStep>();
    b.conserve_network::<vg_gas::pipes::Pipes>();
    b.conserve("pipe_moles", Tolerance::default());
    b.conserve("pipe_energy", Tolerance::default());

    Fields {
        heat: heat_field,
        turf_gas,
    }
}

fn build() -> Result<World> {
    // dt matches `SSvg`'s own `wait` (`code/controllers/subsystems/vg.dm`):
    // gas needs the whole shared World paced at its own real-time cadence
    // (turf venting/decompression), and `vg_world_tick()` is the only
    // driver -- rather than add a second, gas-only tick caller, `SSvg`'s
    // `wait` moved from 10 seconds to 0.5, and this `dt` moved with it
    // (`rust_architecture.md` §8.5 step 6).
    let mut b = WorldBuilder::new(WorldConfig {
        dt: vg_core::units::Seconds(f64::from(crate::frame::PIPE_DEVICE_PERIOD)),
        ..WorldConfig::default()
    });
    let fields = register(&mut b);
    let world = b.build().map_err(|e| eyre!("world build: {e}"))?;
    crate::heat::install_field(fields.heat);
    crate::gas::install(fields.turf_gas);
    registry::register_domain(
        u32::try_from(WORLD_DOMAIN).unwrap_or(7),
        Box::new(WorldEntities),
    );
    for (kind, schema) in world.schemas() {
        let code =
            vg_core::world::kind_code(vg_core::component::domain_id(schema.domain), schema.kind);
        registry::register_domain(world_kind_domain(code), Box::new(WorldKind { kind }));
    }
    // The turf solid's cells as a watch port (heat watches use the same
    // generic watch binds as every other watchable).
    registry::register_domain(
        world_kind_domain(crate::heat::HEAT_CELLS),
        Box::new(crate::heat::HeatCells),
    );
    // Gas handles (turf cells, main and pipe mixtures) as a watch port.
    registry::register_domain(
        world_kind_domain(crate::sched::GAS_HANDLES),
        Box::new(crate::gas::GasDomain),
    );
    Ok(world)
}

/// Rebuilds the world from scratch (`verdigris_init`/`verdigris_cleanup`):
/// no entity, row or watch survives.
///
/// # Errors
/// If a registered law is inconsistent (a build error is a code bug).
pub fn reset() -> Result<()> {
    let world = build()?;
    WORLD.with_borrow_mut(|w| *w = Some(world));
    Ok(())
}

/// Runs `f` on the world, building it on first use.
///
/// # Errors
/// Whatever `f` returns, or a world build failure.
pub fn with_world<T>(f: impl FnOnce(&mut World) -> Result<T>) -> Result<T> {
    if SHUT_DOWN.with(std::cell::Cell::get) {
        bail!("verdigris is shut down");
    }
    let missing = WORLD.with_borrow(Option::is_none);
    if missing {
        reset()?;
    }
    WORLD.with_borrow_mut(|w| f(w.as_mut().expect("built above")))
}

/// Entity lifecycle for world components, under [`WORLD_DOMAIN`]: the
/// generic `entity_unbind` reaches the world through this slot.
struct WorldEntities;

fn slot_entity(comp: ComponentRef) -> Option<EntityId> {
    EntityId::from_bits(comp.cell)
}

impl DomainRegistry for WorldEntities {
    fn detach(&mut self, comp: ComponentRef) {
        if let Some(e) = slot_entity(comp) {
            let _ = with_world(|w| Ok(w.detach_all(e)));
        }
    }

    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
        let Some(e) = slot_entity(comp) else {
            return Vec::new();
        };
        with_world(|w| {
            Ok(w.describe(e)
                .into_iter()
                .flat_map(|(kind, fields)| {
                    fields
                        .into_iter()
                        .map(move |(f, v)| (format!("{kind}.{f}"), v))
                })
                .collect())
        })
        .unwrap_or_default()
    }
}

/// One world component kind as a reactor watch port: cells are entity
/// handles (`vg_entity` values).
struct WorldKind {
    kind: KindId,
}

/// `cond` with every cell rewritten by `f`.
pub(crate) fn map_cells(
    cond: &Cond,
    f: &dyn Fn(u32) -> Result<u32, String>,
) -> Result<Cond, String> {
    Ok(match cond {
        Cond::Changed { cell, mask } => Cond::Changed {
            cell: f(*cell)?,
            mask: *mask,
        },
        Cond::Threshold { cell, level } => Cond::Threshold {
            cell: f(*cell)?,
            level: *level,
        },
        Cond::Band {
            cell,
            ch,
            unit,
            levels,
            hysteresis,
        } => Cond::Band {
            cell: f(*cell)?,
            ch: *ch,
            unit: *unit,
            levels: levels.clone(),
            hysteresis: *hysteresis,
        },
        Cond::Difference { a, b, level, abs } => Cond::Difference {
            a: f(*a)?,
            b: f(*b)?,
            level: *level,
            abs: *abs,
        },
        Cond::ThresholdSet { cell, ch } => Cond::ThresholdSet {
            cell: f(*cell)?,
            ch: *ch,
        },
        Cond::Any(children) => Cond::Any(
            children
                .iter()
                .map(|c| map_cells(c, f))
                .collect::<Result<_, _>>()?,
        ),
        Cond::All(children) => Cond::All(
            children
                .iter()
                .map(|c| map_cells(c, f))
                .collect::<Result<_, _>>()?,
        ),
    })
}

/// A `vg_entity` value's slot index (the row the world's stores use).
#[allow(clippy::cast_precision_loss)]
fn entity_row(cell: u32) -> Result<u32, String> {
    entity::decode(cell as f32)
        .map(EntityId::index)
        .map_err(|e| e.to_string())
}

impl DomainRegistry for WorldKind {
    fn channels(&self) -> Vec<vg_core::channel::ChannelInfo> {
        with_world(|w| w.channels(self.kind).map_err(|e| eyre!("{e}"))).unwrap_or_default()
    }

    fn watch(&mut self, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<(u8, WatchId), String> {
        let rows = map_cells(cond, &entity_row)?;
        with_world(|w| {
            w.watch(self.kind, sub, lane, &rows)
                .map_err(|e| eyre!("{e}"))
        })
        .map(|id| (0, id))
        .map_err(|e| e.to_string())
    }

    fn unwatch(&mut self, _port: u8, id: WatchId) {
        let _ = with_world(|w| Ok(w.unwatch(self.kind, id)));
    }

    fn add_entry(
        &mut self,
        _port: u8,
        id: WatchId,
        entry: vg_core::watch::SetEntry,
    ) -> Result<(), String> {
        with_world(|w| {
            w.add_watch_entry(self.kind, id, entry)
                .map_err(|e| eyre!("{e}"))
        })
        .map_err(|e| e.to_string())
    }

    fn remove_entry(&mut self, _port: u8, id: WatchId, payload: u32) {
        let _ = with_world(|w| Ok(w.remove_watch_entry(self.kind, id, payload)));
    }

    /// This kind's watch wakes, with DM's `vg_entity` value as the source
    /// (the stores report the entity's slot).
    fn take_wakes(&mut self, out: &mut Vec<Wake>) {
        let _ = with_world(|w| {
            let mut wakes = Vec::new();
            w.drain_kind_wakes(self.kind, &mut wakes);
            #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            out.extend(wakes.into_iter().filter_map(|wk| {
                let e = w.entities().at(wk.source)?;
                Some(Wake {
                    source: entity::entity_value(e) as u32,
                    ..wk
                })
            }));
            Ok(())
        });
    }
}

// --- Binds -------------------------------------------------------------------------

pub(crate) fn num(v: &ByondValue) -> Result<f32> {
    Ok(v.get_number()?)
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
pub(crate) fn whole(v: &ByondValue, what: &str) -> Result<u32> {
    let n = num(v)?;
    if !(n >= 0.0 && n.fract() == 0.0 && n < 16_777_216.0) {
        bail!("bad {what} {n}");
    }
    Ok(n as u32)
}

fn field(v: &ByondValue) -> Result<FieldId> {
    FieldId::try_from(whole(v, "field id")?).map_err(|_| eyre!("field id out of range"))
}

fn kind(w: &World, code: &ByondValue) -> Result<KindId> {
    let code = whole(code, "kind code")?;
    w.kind_by_code(code)
        .ok_or_else(|| eyre!("no component kind with code {code}"))
}

pub(crate) fn list(values: impl IntoIterator<Item = f32>) -> Result<ByondValue> {
    let items: Vec<ByondValue> = values.into_iter().map(ByondValue::from).collect();
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}

fn text_list(values: impl IntoIterator<Item = String>) -> Result<ByondValue> {
    let items = values
        .into_iter()
        .map(ByondValue::new_str)
        .collect::<Result<Vec<_>, _>>()?;
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}

/// Attaches component `code` to `entity` (0: a new entity), seeded from its
/// defaults with `init` (`[field, value, ...]`) applied as validated
/// writes. Returns the entity handle.
#[auxmacros::bind("/proc/vg_component_bind")]
fn component_bind(entity: ByondValue, code: ByondValue, init: ByondValue) -> Result<ByondValue> {
    let e = entity::bind_or_reuse(num(&entity)?)?;
    let pairs = if init.is_list() {
        init.get_list_values()?
    } else {
        Vec::new()
    };
    let mut values = Vec::with_capacity(pairs.len() / 2);
    for pair in pairs.chunks(2) {
        let [f, v] = pair else {
            bail!("init must be [field, value, ...]");
        };
        values.push((field(f)?, None, f64::from(num(v)?)));
    }
    with_world(|w| {
        let k = kind(w, &code)?;
        w.bind(Some(e), k, &values).map_err(|err| eyre!("{err}"))?;
        w.entities_mut()
            .attach(e, WORLD_DOMAIN, ComponentRef::new(0, e.bits()))
            .map_err(|err| eyre!("{err}"))?;
        Ok(())
    })?;
    Ok(ByondValue::from(entity::entity_value(e)))
}

/// [`component_bind`] for many entities in one call and one world lock.
/// `fields` is `[field id, ...]`; `rows` is flat, `stride = length(fields) + 1`
/// values per row: `[entity (0: a new entity), value for each field...]`.
/// Returns the list of entity handles, in row order. One bad row fails the
/// whole call (nothing is half-bound past the failing row).
#[auxmacros::bind("/proc/vg_component_bind_list")]
fn component_bind_list(
    code: ByondValue,
    fields: ByondValue,
    rows: ByondValue,
) -> Result<ByondValue> {
    let field_ids = fields
        .get_list_values()?
        .iter()
        .map(field)
        .collect::<Result<Vec<_>>>()?;
    if field_ids.is_empty() {
        bail!("fields must name at least one field");
    }
    let values = rows.get_list_values()?;
    let stride = field_ids.len() + 1;
    if values.len() % stride != 0 {
        bail!("rows must be flat entity, value... records of {stride} values");
    }
    // Entities are minted before the world is borrowed (as `component_bind` does).
    let entities = values
        .chunks_exact(stride)
        .map(|row| entity::bind_or_reuse(num(&row[0])?))
        .collect::<Result<Vec<_>>>()?;
    let mut handles = Vec::with_capacity(entities.len());
    with_world(|w| {
        let k = kind(w, &code)?;
        for (row, e) in values.chunks_exact(stride).zip(entities.iter().copied()) {
            let mut init = Vec::with_capacity(field_ids.len());
            for (f, v) in field_ids.iter().zip(&row[1..]) {
                init.push((*f, None, f64::from(num(v)?)));
            }
            w.bind(Some(e), k, &init).map_err(|err| eyre!("{err}"))?;
            w.entities_mut()
                .attach(e, WORLD_DOMAIN, ComponentRef::new(0, e.bits()))
                .map_err(|err| eyre!("{err}"))?;
            handles.push(entity::entity_value(e));
        }
        Ok(())
    })?;
    list(handles)
}

/// Detaches one component.
#[auxmacros::bind("/proc/vg_component_detach")]
fn component_detach(entity: ByondValue, code: ByondValue) -> Result<ByondValue> {
    let e = entity::decode(num(&entity)?)?;
    with_world(|w| {
        let k = kind(w, &code)?;
        w.detach(e, k).map_err(|err| eyre!("{err}"))
    })?;
    Ok(ByondValue::null())
}

/// Whether `entity` has component `code` (never a runtime).
#[auxmacros::bind("/proc/vg_component_has")]
fn component_has(entity: ByondValue, code: ByondValue) -> Result<ByondValue> {
    let Ok(e) = entity::decode(num(&entity)?) else {
        return Ok(ByondValue::from(0.0f32));
    };
    let has = with_world(|w| Ok(kind(w, &code).is_ok_and(|k| w.has(e, k))))?;
    Ok(ByondValue::from(if has { 1.0f32 } else { 0.0 }))
}

/// One field (element `index` of an array field; 0 otherwise).
#[auxmacros::bind("/proc/vg_component_get")]
fn component_get(
    entity: ByondValue,
    code: ByondValue,
    field_id: ByondValue,
    index: ByondValue,
) -> Result<ByondValue> {
    let e = entity::decode(num(&entity)?)?;
    let f = field(&field_id)?;
    let i = if index.is_null() {
        0
    } else {
        whole(&index, "index")? as usize
    };
    #[allow(clippy::cast_possible_truncation)]
    let v = with_world(|w| {
        let k = kind(w, &code)?;
        w.get(e, k, f, i).map_err(|err| eyre!("{err}"))
    })? as f32;
    Ok(ByondValue::from(v))
}

/// Several fields in one call (a query group): one number per field id.
#[auxmacros::bind("/proc/vg_component_get_many")]
fn component_get_many(
    entity: ByondValue,
    code: ByondValue,
    fields: ByondValue,
) -> Result<ByondValue> {
    let e = entity::decode(num(&entity)?)?;
    let ids = fields
        .get_list_values()?
        .iter()
        .map(field)
        .collect::<Result<Vec<_>>>()?;
    let values = with_world(|w| {
        let k = kind(w, &code)?;
        ids.iter()
            .map(|&f| {
                #[allow(clippy::cast_possible_truncation)]
                w.get(e, k, f, 0)
                    .map(|v| v as f32)
                    .map_err(|err| eyre!("{err}"))
            })
            .collect::<Result<Vec<f32>>>()
    })?;
    list(values)
}

/// A validated write (`index` < 0 or null: the whole field). Returns the
/// value DM now reads back.
#[auxmacros::bind("/proc/vg_component_set")]
fn component_set(
    entity: ByondValue,
    code: ByondValue,
    field_id: ByondValue,
    index: ByondValue,
    value: ByondValue,
) -> Result<ByondValue> {
    let e = entity::decode(num(&entity)?)?;
    let f = field(&field_id)?;
    let i = if index.is_null() || num(&index)? < 0.0 {
        None
    } else {
        Some(whole(&index, "index")? as usize)
    };
    let v = f64::from(num(&value)?);
    #[allow(clippy::cast_possible_truncation)]
    let stored = with_world(|w| {
        let k = kind(w, &code)?;
        w.set(e, k, f, i, v).map_err(|err| eyre!("{err}"))?;
        w.get(e, k, f, i.unwrap_or(0)).map_err(|err| eyre!("{err}"))
    })? as f32;
    Ok(ByondValue::from(stored))
}

/// Take reconciliation on a conserved field: adds `delta` to the owner's
/// current value. Returns the shortfall of a removal.
#[auxmacros::bind("/proc/vg_component_adjust")]
fn component_adjust(
    entity: ByondValue,
    code: ByondValue,
    field_id: ByondValue,
    index: ByondValue,
    delta: ByondValue,
) -> Result<ByondValue> {
    let e = entity::decode(num(&entity)?)?;
    let f = field(&field_id)?;
    let i = if index.is_null() {
        0
    } else {
        whole(&index, "index")? as usize
    };
    let d = f64::from(num(&delta)?);
    let shortfall = with_world(|w| {
        let k = kind(w, &code)?;
        w.adjust(e, k, f, i, d).map_err(|err| eyre!("{err}"))
    })?;
    Ok(ByondValue::from(shortfall))
}

/// Pacing: feeds `seconds` of game time to the world's pacer and runs a
/// step when one is owed. The pipe devices' jobs are staged only when a step is due and written back after it;
/// returns the report of the step (`device handle, moles, power_w, target_reached` per device that moved gas or
/// drew power). With `force`, a step runs now whatever the pacer owes (a deterministic step for a test that built
/// a device by hand). Driven by [`crate::frame`] only.
pub(crate) fn pace(seconds: f64, force: bool) -> Result<Vec<f32>> {
    // The heat exchange law reads the mixture probes only when a step runs: building them walks every gas coupling
    // and loads its mixture, so a frame that only advances the pacer (most of them: the step is PIPE_DEVICE_PERIOD,
    // the frame a tick) skips it.
    let due = force || with_world(|w| Ok(w.step_due(Seconds(seconds))))?;
    let mut lap = PaceLaps::start();
    let probes = due.then(crate::heat::mixture_probes);
    lap.lap("pace_probes");
    with_world(|w| {
        if let Some(probes) = probes {
            w.set_global(probes).map_err(|e| eyre!("{e}"))?;
        }
        if due {
            crate::pipes::stage_devices(w)?;
        }
        lap.lap("pace_stage");
        if force {
            w.step_blocking();
        } else {
            let _ = w.tick(Seconds(seconds));
        }
        lap.lap(if due { "pace_step" } else { "pace_tick" });
        let applied = if due {
            crate::pipes::apply_devices(w)
        } else {
            Vec::new()
        };
        lap.lap("pace_apply");
        Ok(applied)
    })
}

/// Cumulative wall time of the parts of [`pace`] (`frame.us.pace_*`): the world's tick bookkeeping on frames that
/// step nothing, the step itself, and the per-step staging around it.
struct PaceLaps(std::time::Instant);

impl PaceLaps {
    fn start() -> Self {
        Self(std::time::Instant::now())
    }

    fn lap(&mut self, part: &'static str) {
        let now = std::time::Instant::now();
        #[allow(clippy::cast_possible_truncation)]
        crate::metrics::registry()
            .counter(&format!("frame.us.{part}"))
            .add((now - self.0).as_micros() as u64);
        self.0 = now;
    }
}

/// Changes the world's step length (the gas publication cadence: a rupture asks
/// for a short step for a while, the last grant to expire restores the default).
/// Every law integrates the new `dt` from the next step on. Returns the step
/// length now in effect, in seconds; a non-finite or non-positive `seconds` is
/// refused and the current length is returned.
#[auxmacros::bind("/proc/vg_world_set_dt")]
fn world_set_dt(seconds: ByondValue) -> Result<ByondValue> {
    let s = f64::from(num(&seconds)?);
    let now = with_world(|w| {
        let _ = w.set_dt(Seconds(s));
        Ok(w.dt().0)
    })?;
    #[allow(clippy::cast_possible_truncation)]
    Ok(ByondValue::from(now as f32))
}

/// Every typed event since the last call, as `vg_core::event`'s wire form
/// (`header, entity, len, payload...` per record). Taken by
/// [`crate::frame`], which turns each into a NOTICE record.
pub(crate) fn take_events() -> Result<Vec<f32>> {
    let mut events = with_world(|w| Ok(w.drain_events()))?;
    crate::heat::apply_mixture_heat(&events);
    Ok(events.take())
}

/// Conservation violations since the last call, as text (empty: none).
#[auxmacros::bind("/proc/vg_world_violations")]
fn world_violations() -> Result<ByondValue> {
    let v = with_world(|w| Ok(w.violations()))?;
    text_list(v.into_iter().map(|v| v.to_string()))
}

/// Per-law statistics, as `name phase stepped awake` lines.
#[auxmacros::bind("/proc/vg_world_laws")]
fn world_laws() -> Result<ByondValue> {
    let stats = with_world(|w| Ok(w.law_stats()))?;
    text_list(stats.into_iter().map(|s| {
        format!(
            "{} {:?} stepped={} awake={}",
            s.name, s.phase, s.stepped, s.awake
        )
    }))
}

/// Sizes the world's one grid (every per-turf field: turf gas, solid heat)
/// for the map, `(maxx, maxy, maxz)`. Builds the world on the first call
/// (or while the grid is still the 2x2x2 placeholder); once the world holds
/// state, a later call is a no-op and cells past the z headroom are ignored
/// (rebuilding would wipe every other domain's state to grow the grid).
#[auxmacros::bind("/proc/auxmos_configure_world")]
fn configure_world(max_x: ByondValue, max_y: ByondValue, max_z: ByondValue) -> Result<ByondValue> {
    let max_x = whole(&max_x, "max_x")?.max(1);
    let max_y = whole(&max_y, "max_y")?.max(1);
    let max_z = whole(&max_z, "max_z")?.max(1);
    let dims = GridDims::new(max_x, max_y, z_capacity(max_z))
        .ok_or_else(|| eyre!("grid {max_x}x{max_y}x{max_z} does not fit a u32 index"))?;
    let placeholder = WORLD.with_borrow(|w| {
        w.as_ref().is_none_or(|w| {
            w.grid()
                .is_ok_and(|g| g.dims() == GridDims::new(2, 2, 2).expect("fits"))
        })
    });
    if placeholder {
        PENDING_DIMS.with(|d| d.set(dims));
        reset()?;
    }
    Ok(ByondValue::null())
}

/// Runs `steps` world steps now, each waiting for its worker frame
/// (deterministic, no pacing: tests and admin tools).
#[auxmacros::bind("/proc/world_run_steps")]
fn world_run_steps(steps: ByondValue) -> Result<ByondValue> {
    let n = whole(&steps, "steps")?.min(100_000);
    for _ in 0..n {
        let probes = crate::heat::mixture_probes();
        with_world(|w| {
            w.set_global(probes).map_err(|e| eyre!("{e}"))?;
            w.step_blocking();
            Ok(())
        })?;
    }
    Ok(ByondValue::null())
}

/// Host shutdown (`world/Del()`): waits for the running frame, drops the
/// world (joining the frame threads) and joins the job threads, so no
/// verdigris thread outlives the DLL. Every later world call fails.
pub fn shutdown() {
    if let Some(mut w) = WORLD.with_borrow_mut(Option::take) {
        w.shutdown();
        drop(w);
    }
    SHUT_DOWN.with(|s| s.set(true));
    crate::jobs::shutdown();
}

/// Undoes [`shutdown`] for a new `world/New()`. BYOND keeps the library
/// loaded across a soft reboot (`world.Reboot()`) but runs `world/Del()`, so
/// without this every world call after a reboot fails. The world itself is
/// rebuilt lazily on first use.
///
/// # Errors
/// If the job threads cannot be restarted.
pub fn revive() -> Result<()> {
    SHUT_DOWN.with(|s| s.set(false));
    crate::jobs::reset();
    crate::jobs::restart()
}

#[auxmacros::bind("/proc/vg_shutdown")]
fn world_shutdown() -> Result<ByondValue> {
    shutdown();
    Ok(ByondValue::null())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shutdown_joins_the_threads_and_refuses_later_calls() {
        with_world(|w| {
            w.step_blocking();
            Ok(())
        })
        .unwrap();
        shutdown();
        assert!(WORLD.with_borrow(Option::is_none));
        assert!(
            with_world(|_| Ok(())).is_err(),
            "the world was rebuilt after shutdown"
        );
        revive().unwrap();
        with_world(|w| {
            w.step_blocking();
            Ok(())
        })
        .expect("a revived world (soft reboot) runs again");
    }
}
