//! Binds for the mob heat-body component (H2, `verdigris/domains/heat/src/mob.rs`):
//! the first heat FFI to land outside `domains/gas/src/heat.rs`, and the
//! first heat identity on the R10 entity table instead of a hand-rolled
//! packed handle DM sees directly (`rust_core.md` §15's "heat's hand-rolled
//! body and watch handles" row, for this component; turf/object heat bodies
//! still use their own [`vg_heat::world::HeatWorld`] handles -- see this
//! module's doc for why that migration is scoped separately).
//!
//! Structured like `domains/gas/src/kind/pump.rs` (§14's reference
//! component): a thread-local [`vg_heat::mob::MobHeatWorld`] shared between
//! this module's binds and the boxed [`EntityDomain`] the entity table
//! drives, so `entity_unbind`/a future `vg_entity_tick_all` act on the exact
//! storage the accessors below read and write. Unlike pump, this
//! component's config surface (an `Option`-free multi-source flux
//! accumulator, plus `core::watch` comfort bands) doesn't fit the
//! `#[vg::component]` macro's one-setter-per-scalar-field model, so its
//! binds are written by hand -- the entity *identity* half (bind, attach,
//! resolve, detach) is the part `rust_core.md` §15 actually asks every
//! domain to share, and that half is used here exactly as pump uses it.

// heat_mob_bind's argument count is inherent to its DM call convention (one
// Rust parameter per config field, matching pump_bind's shape) -- an
// item-level #[allow] on the fn doesn't reach the warning, which is emitted
// inside ::byondapi::bind's own macro expansion (see ffi/src/reactor.rs's
// file-level allow and its comment for the same reason).
#![allow(clippy::too_many_arguments)]

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::entity::ComponentRef;
use vg_heat::mob::{MOB_EXTERNAL_SOURCES, MobHeatConfig, MobHeatWorld};

use crate::entity;
use crate::registry;
use vg_core::registry::DomainRegistry;

/// This host's entity slot and registry id. It must differ from every
/// other host's: power holds 1 and the gas turf watch port 2 (this used to
/// be 1 as well, so whichever registered last replaced the other).
/// @dm-define VG_DOMAIN_HEAT_MOB
pub const DOMAIN: usize = 3;

/// This component's kind id within its domain (only one kind lives in this
/// domain so far).
/// @dm-define VG_HEAT_MOB_KIND
pub const KIND: u16 = 1;

/// Simulated seconds per mob-heat frame. Mob thermal drift is slow (minutes,
/// not the sub-second responsiveness turf/gas needs), so a coarser step than
/// [`vg_heat::consts::HEAT_DT`] is fine and cheaper; matching it exactly
/// isn't required for correctness since the model is an explicit-Euler
/// integrator stable at this step.
const MOB_HEAT_DT: f32 = 1.0;

struct Shared(Rc<RefCell<MobHeatWorld>>);

impl DomainRegistry for Shared {
    fn detach(&mut self, comp: ComponentRef) {
        if comp.kind != KIND {
            return;
        }
        let mut w = self.0.borrow_mut();
        if let Some(h) = w.handle_at(comp.cell) {
            let _ = w.release(h);
        }
    }

    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
        if comp.kind != KIND {
            return Vec::new();
        }
        let w = self.0.borrow();
        let Some(h) = w.handle_at(comp.cell) else {
            return Vec::new();
        };
        // `temperature` needs `&mut` (it reads through the pinned port);
        // everything else about a mob body is config DM already has, so
        // there is nothing else worth describing here.
        drop(w);
        let mut w = self.0.borrow_mut();
        let t = w.temperature(h).unwrap_or(f32::NAN);
        vec![("temperature".into(), format!("{t} K"))]
    }

    fn tick(&mut self) {
        // The generic per-sweep tick (SSvg, §7) has no elapsed-time
        // argument; real pacing against game time happens through
        // `heat_mob_tick` below (SSheat or SSmobs calls it, matching
        // `vg_heat_tick(seconds)`'s existing pattern). One MOB_HEAT_DT
        // step here keeps a mob body from silently never advancing if
        // nothing calls the paced tick.
        let _ = self.0.borrow_mut().tick(MOB_HEAT_DT);
    }

    fn reset(&mut self) {
        *self.0.borrow_mut() = MobHeatWorld::new(MOB_HEAT_DT)
            .unwrap_or_else(|e| unreachable!("static mob-heat config always builds: {e}"));
    }
}

thread_local! {
    static WORLD: Rc<RefCell<MobHeatWorld>> = Rc::new(RefCell::new(
        MobHeatWorld::new(MOB_HEAT_DT).unwrap_or_else(|e| unreachable!("static mob-heat config always builds: {e}")),
    ));
    static REGISTERED: Cell<bool> = const { Cell::new(false) };
}

fn with<T>(f: impl FnOnce(&mut MobHeatWorld) -> T) -> T {
    REGISTERED.with(|done| {
        if !done.get() {
            #[allow(clippy::cast_possible_truncation)]
            WORLD.with(|w| registry::register_domain(DOMAIN as u32, Box::new(Shared(Rc::clone(w)))));
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

/// Resolves `entity` to this component's slot in [`MobHeatWorld`]'s own
/// table (its `ComponentRef::cell`, not a [`vg_heat::mob::MobHandle`] --
/// see [`vg_heat::mob::MobHeatWorld::handle_at`]'s doc comment for why
/// reconstructing the handle from an already-entity-checked slot is exact).
fn handle_of(w: &MobHeatWorld, entity: &ByondValue) -> Result<vg_heat::mob::MobHandle> {
    let comp = entity::resolve(num(entity)?, DOMAIN, KIND)?;
    w.handle_at(comp.cell)
        .ok_or_else(|| eyre!("heat-mob cell {} is stale", comp.cell))
}

// --- Lifecycle -------------------------------------------------------------

/// Creates the entity (if `entity` is 0) or reuses it, attaches a mob
/// heat-body component seeded from the `init_*` values, and returns the
/// entity handle. DM's base `on_materialize()` calls this once per
/// component the type declares (§4).
#[auxmacros::bind("/proc/heat_mob_bind")]
fn heat_mob_bind(
    entity: ByondValue,
    init_capacity: ByondValue,
    init_temperature: ByondValue,
    init_metabolic_watts: ByondValue,
    init_coolant: ByondValue,
    init_insulation: ByondValue,
    init_ambient: ByondValue,
    init_setpoint: ByondValue,
    init_sweat_capacity_w: ByondValue,
    init_shiver_capacity_w: ByondValue,
    init_time_scale: ByondValue,
) -> Result<ByondValue> {
    let config = MobHeatConfig {
        capacity: num(&init_capacity)?,
        temperature: num(&init_temperature)?,
        metabolic_watts: num(&init_metabolic_watts)?,
        coolant: truthy(&init_coolant)?,
        insulation: num(&init_insulation)?,
        ambient: num(&init_ambient)?,
        setpoint: num(&init_setpoint)?,
        sweat_capacity_w: num(&init_sweat_capacity_w)?,
        shiver_capacity_w: num(&init_shiver_capacity_w)?,
        time_scale: num(&init_time_scale)?,
    };
    let h = entity::bind_or_reuse(num(&entity)?)?;
    let mob = with(|w| w.create_body(config)).map_err(|e| eyre!("heat_mob_bind: {e}"))?;
    let slot = vg_heat::mob::slot_of(mob);
    entity::attach(h, DOMAIN, ComponentRef::new(KIND, slot)).map_err(|e| eyre!("{e}"))?;
    Ok(ByondValue::from(entity::entity_value(h)))
}

// --- Config: set only (state is read back through get_temperature) --------

macro_rules! setter {
    ($fn_name:ident, $bind:literal, $set:ident) => {
        #[auxmacros::bind($bind)]
        fn $fn_name(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
            let v = num(&value)?;
            with(|w| {
                let h = handle_of(w, &entity)?;
                w.$set(h, v).map_err(|e| eyre!("{e}"))
            })?;
            Ok(ByondValue::from(v))
        }
    };
}

setter!(
    heat_mob_set_insulation,
    "/mob/proc/heat_mob_set_insulation",
    set_insulation
);
setter!(
    heat_mob_set_ambient,
    "/mob/proc/heat_mob_set_ambient",
    set_ambient
);
setter!(
    heat_mob_set_setpoint,
    "/mob/proc/heat_mob_set_setpoint",
    set_setpoint
);
setter!(
    heat_mob_set_sweat_capacity,
    "/mob/proc/heat_mob_set_sweat_capacity",
    set_sweat_capacity
);
setter!(
    heat_mob_set_shiver_capacity,
    "/mob/proc/heat_mob_set_shiver_capacity",
    set_shiver_capacity
);
setter!(
    heat_mob_set_time_scale,
    "/mob/proc/heat_mob_set_time_scale",
    set_time_scale
);
setter!(
    heat_mob_set_metabolic_watts,
    "/mob/proc/heat_mob_set_metabolic_watts",
    set_metabolic_watts
);

#[auxmacros::bind("/mob/proc/heat_mob_set_coolant")]
fn heat_mob_set_coolant(entity: ByondValue, value: ByondValue) -> Result<ByondValue> {
    let v = truthy(&value)?;
    with(|w| {
        let h = handle_of(w, &entity)?;
        w.set_coolant(h, v).map_err(|e| eyre!("{e}"))
    })?;
    Ok(bool_value(v))
}

/// `body_heat_add(watts, source)`: one external flux source's current rate
/// (reagents, cryo, bellies, items, afflictions, ... DQ Medical's own small
/// `source` enum, `< MOB_EXTERNAL_SOURCES`), set to 0 to clear it. Persists
/// like a rate, not a one-shot amount, until the source updates it again.
#[auxmacros::bind("/mob/proc/heat_mob_body_heat_add")]
fn heat_mob_body_heat_add(
    entity: ByondValue,
    watts: ByondValue,
    source: ByondValue,
) -> Result<ByondValue> {
    let watts = num(&watts)?;
    let source = num(&source)?;
    if !(0.0..MOB_EXTERNAL_SOURCES as f32).contains(&source) {
        bail!("heat body_heat_add: source {source} out of range (0..{MOB_EXTERNAL_SOURCES})");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let source = source as u8;
    with(|w| {
        let h = handle_of(w, &entity)?;
        w.body_heat_add(h, source, watts).map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::from(watts))
}

// --- State: read-only --------------------------------------------------------

#[auxmacros::bind("/mob/proc/heat_mob_get_temperature")]
fn heat_mob_get_temperature(entity: ByondValue) -> Result<ByondValue> {
    let t = with(|w| {
        let h = handle_of(w, &entity)?;
        Ok(w.temperature(h))
    })
    .map_err(|e: eyre::Report| e)?;
    Ok(t.map_or_else(ByondValue::null, ByondValue::from))
}

// --- Comfort bands: core::watch, ascending thresholds -----------------------

/// Registers (replacing any previous one) this body's comfort bands.
/// `levels` is a DM list of ascending temperatures; `subscriber` is who
/// gets woken (`vg_wakes()`, matching turf/object heat watches) on the
/// starting band and every crossing.
#[auxmacros::bind("/mob/proc/heat_mob_set_bands")]
fn heat_mob_set_bands(
    entity: ByondValue,
    subscriber: ByondValue,
    lane: ByondValue,
    levels: ByondValue,
) -> Result<ByondValue> {
    let subscriber = num(&subscriber)?;
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let subscriber = subscriber.max(0.0) as u32;
    let lane = if num(&lane)? >= 1.0 {
        vg_core::outbox::Lane::Urgent
    } else {
        vg_core::outbox::Lane::Normal
    };
    let values = levels.get_list_values()?;
    let mut parsed = Vec::with_capacity(values.len());
    for v in &values {
        parsed.push(num(v)?);
    }
    with(|w| {
        let h = handle_of(w, &entity)?;
        w.set_bands(h, subscriber, lane, &parsed)
            .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::null())
}

// --- Tick and wakes ----------------------------------------------------------

/// SSheat/SSmobs' per-cycle pump: paces frames against `elapsed` seconds of
/// game time (`vg_heat_tick`'s pattern), and appends this cycle's wakes to
/// the shared wake buffer `heat_mob_drain_wakes` empties.
#[auxmacros::bind("/proc/heat_mob_tick")]
fn heat_mob_tick(elapsed: ByondValue) -> Result<ByondValue> {
    let elapsed = num(&elapsed)?;
    let ran = with(|w| w.tick(elapsed));
    Ok(bool_value(ran))
}

/// Drains and returns this cycle's wakes as a flat `[subscriber, watch,
/// reason, source]`-quad list (matching `vg_heat`'s `heat_take_wakes`
/// convention exactly) -- a comfort-band crossing shows up here; DM
/// re-reads the temperature/band with `heat_mob_get_temperature`.
#[auxmacros::bind("/proc/heat_mob_drain_wakes")]
fn heat_mob_drain_wakes() -> Result<ByondValue> {
    let flat = with(|w| {
        let mut out = Vec::new();
        w.take_wakes(&mut out);
        out
    });
    let list = ByondValue::new_list()?;
    let values: Vec<ByondValue> = flat.into_iter().map(ByondValue::from).collect();
    list.write_list(&values)?;
    Ok(list)
}
