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
//! | `vg_world_tick(seconds)` | pacing: runs a step when one is owed |
//! | `vg_world_events()` | every typed event since the last call, in `vg_core::event` wire form |
//! | `vg_world_violations()` | conservation violations since the last call, as text |
//! | `vg_world_laws()` | per-law activity statistics, as text |
//!
//! Watches on component rows go through the reactor's generic watch binds
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
use vg_core::outbox::{Lane, Subscriber, Wake, WatchId};
use vg_core::registry::{DomainRegistry, world_kind_domain};
use vg_core::units::Seconds;
use vg_core::watch::Cond;
use vg_core::world::{KindId, World, WorldBuilder, WorldConfig};

use crate::{entity, registry};

thread_local! {
    static WORLD: RefCell<Option<World>> = const { RefCell::new(None) };
}

/// Every domain's declarations (see the module docs).
fn register(b: &mut WorldBuilder) -> vg_core::field::FieldKey<vg_heat::SolidHeat> {
    b.add_global(
        vg_core::component::Ownership::Main,
        crate::propagate::RadiationLayer::default(),
    );
    b.add_component::<vg_gas::kind::pump::Pump>();
    b.add_component::<vg_gas::kind::gas_mix::GasMix>();
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
    let _grid = b.add_grid(crate::heat::pending_dims());
    let heat_field = crate::heat::register(b);

    // Power (`rust_architecture.md` §6, §8.5): `Cables`, its components and
    // laws. A SMES's output/input terminals are their own entities, each on
    // its own region; `crate::power`'s topology binds are the only power
    // FFI besides the generic `vg_component_*`/`vg_world_*` ones.
    use vg_core::component::Ownership;
    use vg_power::components::{Apc, Producer, Smes, SmesInputTerminal};
    use vg_power::kind::Cables;
    use vg_power::laws::{ApcTick, PowerReset, PowerSettle, ProducerCredit, SmesInputApply, SmesInputPlan, SmesOutputApply, SmesOutputPlan};
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
    let _ = b.add_law::<ApcTick>().after::<ProducerCredit>().after::<SmesOutputPlan>();
    let _ = b.add_law::<PowerSettle>().after::<ApcTick>();
    let _ = b.add_law::<SmesOutputApply>().after::<PowerSettle>();
    let _ = b.add_law::<SmesInputApply>().after::<PowerSettle>();

    // Pipes (`rust_architecture.md` §6, §8.5, step 5): a main-owned network,
    // its region payloads pooled gas (`vg_gas::pipes::PipeGas`). Devices
    // step imperatively from `crate::pipes::pipe_step_devices` (DM's own
    // `wait`-scaled dt, not the World's fixed law cadence -- see that
    // module's docs), not a registered `Law`.
    b.add_network::<vg_gas::pipes::Pipes>(Ownership::Main);
    b.conserve_network::<vg_gas::pipes::Pipes>();
    b.conserve("pipe_moles", Tolerance::default());
    b.conserve("pipe_energy", Tolerance::default());

    heat_field
}

fn build() -> Result<World> {
    // dt matches `SSvg`'s own `wait` (`code/controllers/subsystems/vg.dm`):
    // gas needs the whole shared World paced at its own real-time cadence
    // (turf venting/decompression), and `vg_world_tick()` is the only
    // driver -- rather than add a second, gas-only tick caller, `SSvg`'s
    // `wait` moved from 10 seconds to 0.5, and this `dt` moved with it
    // (`rust_architecture.md` §8.5 step 6).
    let mut b = WorldBuilder::new(WorldConfig {
        dt: vg_core::units::Seconds(0.5),
        ..WorldConfig::default()
    });
    let heat_field = register(&mut b);
    let world = b.build().map_err(|e| eyre!("world build: {e}"))?;
    crate::heat::install_field(heat_field);
    vg_gas::world::install_pipe_access(Box::new(crate::pipes::FfiPipeAccess));
    registry::register_domain(
        u32::try_from(WORLD_DOMAIN).unwrap_or(7),
        Box::new(WorldEntities),
    );
    for (kind, schema) in world.schemas() {
        let code =
            vg_core::world::kind_code(vg_core::component::domain_id(schema.domain), schema.kind);
        registry::register_domain(world_kind_domain(code), Box::new(WorldKind { kind }));
    }
    // Gas's turf watch port: a host that is not on the world yet.
    registry::register_domain(
        crate::reactor::DOMAIN_GAS,
        Box::new(vg_gas::turf::GasDomain),
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

    fn take_wakes(&mut self, out: &mut Vec<Wake>) {
        let _ = with_world(|w| {
            w.drain_wakes(out);
            Ok(())
        });
    }
}

/// One world component kind as a reactor watch port: cells are entity
/// handles (`vg_entity` values).
struct WorldKind {
    kind: KindId,
}

/// Rewrites every cell of `cond` from a `vg_entity` value to the entity's
/// slot index (the row the world's stores use).
fn cells_to_rows(cond: &Cond) -> Result<Cond, String> {
    let row = |cell: u32| -> Result<u32, String> {
        #[allow(clippy::cast_precision_loss)]
        entity::decode(cell as f32)
            .map(EntityId::index)
            .map_err(|e| e.to_string())
    };
    Ok(match cond {
        Cond::Changed { cell, mask } => Cond::Changed {
            cell: row(*cell)?,
            mask: *mask,
        },
        Cond::Threshold { cell, level } => Cond::Threshold {
            cell: row(*cell)?,
            level: *level,
        },
        Cond::Band {
            cell,
            ch,
            unit,
            levels,
            hysteresis,
        } => Cond::Band {
            cell: row(*cell)?,
            ch: *ch,
            unit: *unit,
            levels: levels.clone(),
            hysteresis: *hysteresis,
        },
        Cond::Difference { a, b, level, abs } => Cond::Difference {
            a: row(*a)?,
            b: row(*b)?,
            level: *level,
            abs: *abs,
        },
        Cond::ThresholdSet { cell, ch } => Cond::ThresholdSet {
            cell: row(*cell)?,
            ch: *ch,
        },
        Cond::Any(children) => Cond::Any(
            children
                .iter()
                .map(cells_to_rows)
                .collect::<Result<_, _>>()?,
        ),
        Cond::All(children) => Cond::All(
            children
                .iter()
                .map(cells_to_rows)
                .collect::<Result<_, _>>()?,
        ),
    })
}

impl DomainRegistry for WorldKind {
    fn channels(&self) -> Vec<vg_core::channel::ChannelInfo> {
        with_world(|w| w.channels(self.kind).map_err(|e| eyre!("{e}"))).unwrap_or_default()
    }

    fn watch(&mut self, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<(u8, WatchId), String> {
        let rows = cells_to_rows(cond)?;
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
/// step when one is owed. Returns whether a step ran.
#[auxmacros::bind("/proc/vg_world_tick")]
fn world_tick(seconds: ByondValue) -> Result<ByondValue> {
    let s = f64::from(num(&seconds)?);
    let ran = with_world(|w| Ok(w.tick(Seconds(s))))?;
    Ok(ByondValue::from(if ran { 1.0f32 } else { 0.0 }))
}

/// Every typed event since the last call, as `vg_core::event`'s wire form
/// (`header, entity, len, payload...` per record). The generated DM
/// `vg_drain_events()` decodes it and dispatches each record.
#[auxmacros::bind("/proc/vg_world_events")]
fn world_events() -> Result<ByondValue> {
    let wire = with_world(|w| Ok(w.drain_events().take()))?;
    list(wire)
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
