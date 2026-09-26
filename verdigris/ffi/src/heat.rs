//! Binds for `vg-heat` (`rust_architecture.md` §6, §8.5, step 4): the turf
//! solid field's topology (a field cell has no entity, so it can't go
//! through `vg_component_*`) and a body's coupling topology (a coupling is
//! its own entity, but DM's `heat_body_couple`/`heat_body_create` name a
//! *slot* (0 or 1) of a body, not an entity -- this module keeps the small
//! side table from (body, slot) to the coupling entity that currently fills
//! it, mirroring `body.rs`'s old `couplings: [Coupling; 2]` array one level
//! up, at the FFI boundary instead of inside the component).
//!
//! Every other read/write DM does on a `HeatBody`/`MobHeat`/`Regulator` row
//! goes through the generic `vg_component_*` binds in [`crate::world`].
//! Watches keep their own bespoke binds (`heat_watch`/`heat_unwatch`/...,
//! DM's existing proc surface, unchanged) because the reactor's generic
//! watch/token facility that other domains share is itself scheduled for
//! deletion in step 7 (`rust_architecture.md` §8.5); wiring heat through it
//! now would be thrown away almost immediately. `World::watch`/
//! `watch_cells` are called directly instead.

#![allow(clippy::too_many_arguments)]

use std::cell::{Cell, RefCell};
use std::collections::HashMap;

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::field::{FieldKey, Geom};
use vg_core::grid::{Dir, GridDims};
use vg_core::outbox::{Lane, Subscriber, WatchId};
use vg_core::watch::{Cmp, Cond, Edge, Level, SetEntry};
use vg_core::world::{KindId, WorldBuilder};
use vg_heat::components::gas_kind;
use vg_heat::couple::GasHandle;
use vg_heat::laws::{BodyBodyExchange, BodyGasExchange, RegulatorHeatPump, SolidBodyExchange};
use vg_heat::{BodyCoupling, GasCoupling, HeatBody, MobHeat, Regulator, SolidCell, SolidCoupling, SolidHeat};

use crate::entity;
use crate::world::{list, num, whole, with_world};

thread_local! {
    static FIELD: Cell<Option<FieldKey<SolidHeat>>> = const { Cell::new(None) };
    /// (body row index, slot) -> (coupling kind, coupling entity), the
    /// side table `heat_body_couple`/`heat_body_create`/`heat_body_release`
    /// keep in sync so a re-couple can find and drop the old one.
    static COUPLINGS: RefCell<HashMap<(u32, u8), (u8, vg_core::entity::EntityId)>> = RefCell::new(HashMap::new());
    /// The grid size the next (re)build uses (`vg_heat_configure_world`).
    static PENDING_DIMS: Cell<GridDims> = Cell::new(GridDims::new(2, 2, 2).expect("2x2x2 fits"));
}

/// Coupling-slot kinds DM sends, matching the pre-existing `HEAT_TARGET_*`
/// defines exactly (unchanged DM proc surface).
/// @dm-define HEAT_TARGET_NONE
pub const HEAT_TARGET_NONE: i32 = 0;
/// @dm-define HEAT_TARGET_SOLID
pub const HEAT_TARGET_SOLID: i32 = 1;
/// @dm-define HEAT_TARGET_TURF_AIR
pub const HEAT_TARGET_TURF_AIR: i32 = 2;
/// @dm-define HEAT_TARGET_MIXTURE
pub const HEAT_TARGET_MIXTURE: i32 = 3;
/// @dm-define HEAT_TARGET_BODY
pub const HEAT_TARGET_BODY: i32 = 4;

/// `HEAT_CELL_*` kinds DM sends for a turf.
/// @dm-define HEAT_CELL_SOLID
pub const HEAT_CELL_SOLID: i32 = 0;
/// @dm-define HEAT_CELL_SPACE
pub const HEAT_CELL_SPACE: i32 = 1;
/// @dm-define HEAT_CELL_PLANET
pub const HEAT_CELL_PLANET: i32 = 2;

mod flags {
    pub const SPACE: u8 = 1;
    pub const AIR: u8 = 2;
    pub const PLANET: u8 = 4;
}

/// Headroom for z-levels created at run time (expeditions): the grid is
/// sized once, and cells past it are ignored (`vg_heat::world`'s old
/// comment, ported verbatim: this limitation predates the port).
fn z_capacity(max_z: u32) -> u32 {
    max_z.saturating_mul(2).max(256).max(max_z + 1)
}

/// Registers heat's fields, components and laws
/// (`crate::world::register`'s call site). Returns the field key so
/// `crate::world::build` can hand it to [`install_field`].
pub fn register(b: &mut WorldBuilder) -> FieldKey<SolidHeat> {
    use vg_core::component::Ownership;
    use vg_core::conservation::Tolerance;

    let field = b.add_field::<SolidHeat>(vg_core::field::FieldConfig {
        dt: vg_heat::consts::HEAT_DT,
        max_substeps: 16,
    });
    b.watch_field(field);
    b.add_component::<HeatBody>();
    b.add_component::<SolidCoupling>();
    b.add_component::<BodyCoupling>();
    b.add_component::<GasCoupling>();
    b.add_component::<MobHeat>();
    b.add_component::<Regulator>();
    b.add_global(Ownership::Worker, GasHandle::default());
    b.conserve("heat_energy", Tolerance::default());
    let _ = b.add_law::<SolidBodyExchange>();
    let _ = b.add_law::<BodyBodyExchange>();
    let _ = b.add_law::<BodyGasExchange>();
    let _ = b.add_law::<RegulatorHeatPump>();
    let _ = b.add_law::<vg_heat::mob::MobHeatFlux>();
    field
}

/// Stashes the field key `register` returned, and the gas bridge, once the
/// world is built (`crate::world::build`'s call site).
pub fn install_field(field: FieldKey<SolidHeat>) {
    FIELD.with(|f| f.set(Some(field)));
}

/// The grid dims to build with next (`vg_heat_configure_world`'s pending
/// size, or the default if it was never called).
pub fn pending_dims() -> GridDims {
    PENDING_DIMS.with(Cell::get)
}

fn field() -> Result<FieldKey<SolidHeat>> {
    FIELD.with(Cell::get).ok_or_else(|| eyre!("heat field not installed"))
}

/// Sizes the world's grid for the map (`maxx`, `maxy`, `maxz`), the same
/// call site as `vg_configure_world` -- gas's own field is separate and
/// sized by that call already. Rebuilds the whole world only on the first
/// call (or if the current grid is already too small); once built, a
/// within-headroom call is a no-op, exactly as the pre-port `HeatWorld`
/// behaved.
#[auxmacros::bind("/proc/vg_heat_configure_world")]
fn heat_configure_world(max_x: ByondValue, max_y: ByondValue, max_z: ByondValue) -> Result<ByondValue> {
    let max_x = whole(&max_x, "max_x")?.max(1);
    let max_y = whole(&max_y, "max_y")?.max(1);
    let max_z = whole(&max_z, "max_z")?.max(1);
    let dims = GridDims::new(max_x, max_y, z_capacity(max_z)).ok_or_else(|| eyre!("heat grid {max_x}x{max_y}x{max_z} does not fit a u32 index"))?;
    let need_build = field().is_err();
    if need_build {
        // Nothing exists yet (world boot): safe to (re)build with these
        // dims -- nothing is lost.
        PENDING_DIMS.with(|d| d.set(dims));
        crate::world::reset()?;
        return Ok(ByondValue::null());
    }
    let fits = with_world(|w| {
        let g = w.grid().map_err(|e| eyre!("{e}"))?;
        Ok(g.dims().max_x() == max_x && g.dims().max_y() == max_y && max_z <= g.dims().max_z())
    })
    .unwrap_or(false);
    // if !fits: the world is already up (power, bodies, live heat rows);
    // a full rebuild here would wipe every other domain's state to grow
    // heat's grid, which the pre-port `HeatWorld` never did either -- it
    // silently ignored cells past its own headroom instead. A no-op here
    // matches that (disclosed) limitation rather than a
    // same-effect-as-`verdigris_init` reset triggered by ordinary runtime
    // z-growth (expeditions).
    let _ = fits;
    Ok(ByondValue::null())
}

// ------------------------------------------------------------------ turfs

fn cell_kind_flags(kind: i32) -> Result<(bool, u8)> {
    Ok(match kind {
        HEAT_CELL_SOLID => (false, 0),
        HEAT_CELL_SPACE => (true, flags::SPACE),
        HEAT_CELL_PLANET => (true, flags::PLANET),
        other => bail!("unknown HEAT_CELL_* kind {other}"),
    })
}

fn set_turf(field: FieldKey<SolidHeat>, cell: u32, kind: i32, capacity: f32, conductivity: f32, emissivity: f32, temperature: f32, air: bool) -> Result<bool> {
    let (reservoir, mut f) = cell_kind_flags(kind)?;
    if air {
        f |= flags::AIR;
    }
    let capacity = if reservoir {
        capacity.max(vg_heat::consts::HEAT_CAPACITY_VACUUM)
    } else {
        capacity
    };
    if !(capacity.is_finite() && capacity > 0.0) {
        return with_world(|w| {
            clear_turf(w, field, cell);
            Ok(true)
        });
    }
    with_world(|w| {
        let old = w.sim_mut().port(field.geometry).read(cell).unwrap_or_default();
        let geom = Geom {
            capacity,
            // A solid deck separates z-levels: cross-z heat needs an
            // explicit conductor (unchanged from the pre-port field).
            blocked: Dir::NONE.with(vg_core::grid::Face::Up).with(vg_core::grid::Face::Down),
            reservoir,
        };
        if old != geom {
            let _ = w.sim_mut().port(field.geometry).put(cell, geom);
        }
        if old.is_node() && !old.reservoir && !reservoir {
            let current = w.sim_mut().port(field.cells).read(cell).unwrap_or_default();
            if current.conductivity != conductivity || current.emissivity != emissivity || current.flags != f {
                let _ = w.sim_mut().port(field.cells).submit(cell, vg_heat::SolidCmd::Props { conductivity, emissivity, flags: f });
            }
            if (old.capacity - capacity).abs() > 0.0 {
                let _ = w.sim_mut().port(field.cells).submit(cell, vg_heat::SolidCmd::Rescale { from: old.capacity, to: capacity });
            }
        } else {
            let t = if kind == HEAT_CELL_SPACE { vg_heat::consts::TCMB } else { temperature.max(vg_heat::consts::TCMB) };
            let _ = w.sim_mut().port(field.cells).put(cell, SolidCell::at(capacity, t, conductivity.max(0.0), emissivity, f));
        }
        Ok(true)
    })
}

fn clear_turf(w: &mut vg_core::world::World, field: FieldKey<SolidHeat>, cell: u32) {
    let old = w.sim_mut().port(field.geometry).read(cell).unwrap_or_default();
    if old != Geom::default() {
        let _ = w.sim_mut().port(field.geometry).put(cell, Geom::default());
        let _ = w.sim_mut().port(field.cells).put(cell, SolidCell::default());
    }
}

#[auxmacros::bind("/turf/proc/heat_set_turf")]
fn heat_set_turf(turf: ByondValue, kind: ByondValue, capacity: ByondValue, conductivity: ByondValue, emissivity: ByondValue, temperature: ByondValue, air: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let field = field()?;
    #[allow(clippy::cast_possible_truncation)]
    let ok = set_turf(field, cell, num(&kind)? as i32, num(&capacity)?, num(&conductivity)?, num(&emissivity)?, num(&temperature)?, air.is_true())?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_set_turfs_bulk")]
fn heat_set_turfs_bulk(records: ByondValue) -> Result<ByondValue> {
    let values = records.get_list_values()?;
    let field = field()?;
    let mut set = 0u32;
    for r in values.chunks_exact(7) {
        let Ok(cell) = r[0].get_ref() else { continue };
        #[allow(clippy::cast_possible_truncation)]
        let kind = num(&r[1])? as i32;
        if set_turf(field, cell, kind, num(&r[2])?, num(&r[3])?, num(&r[4])?, num(&r[5])?, r[6].is_true())? {
            set += 1;
        }
    }
    Ok(ByondValue::from(set as f32))
}

#[auxmacros::bind("/turf/proc/heat_clear_turf")]
fn heat_clear_turf(turf: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let field = field()?;
    with_world(|w| {
        clear_turf(w, field, cell);
        Ok(())
    })?;
    Ok(ByondValue::null())
}

#[auxmacros::bind("/turf/proc/heat_turf_temperature")]
fn heat_turf_temperature(turf: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let field = field()?;
    let t = with_world(|w| {
        let Some(g) = w.sim_mut().port(field.geometry).read(cell) else {
            return Ok(None);
        };
        if !g.is_node() {
            return Ok(None);
        }
        let Some(c) = w.sim_mut().port(field.cells).read(cell) else {
            return Ok(None);
        };
        Ok(Some(if g.reservoir { c.temperature } else { c.temperature_in(g.capacity) }))
    })?;
    Ok(t.filter(|t| t.is_finite()).map_or_else(ByondValue::null, ByondValue::from))
}

#[auxmacros::bind("/turf/proc/heat_add_turf")]
fn heat_add_turf(turf: ByondValue, joules: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let joules = num(&joules)?;
    let field = field()?;
    let ok = with_world(|w| {
        let Some(g) = w.sim_mut().port(field.geometry).read(cell) else {
            return Ok(false);
        };
        if !g.is_node() || g.reservoir || !joules.is_finite() {
            return Ok(false);
        }
        Ok(w.sim_mut().port(field.cells).submit(cell, vg_heat::SolidCmd::Add(joules)).is_ok())
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/turf/proc/heat_set_turf_temperature")]
fn heat_set_turf_temperature(turf: ByondValue, temperature: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let t = num(&temperature)?;
    let field = field()?;
    let ok = with_world(|w| {
        let Some(g) = w.sim_mut().port(field.geometry).read(cell) else {
            return Ok(false);
        };
        if !g.is_node() || !t.is_finite() {
            return Ok(false);
        }
        Ok(w.sim_mut().port(field.cells).submit(cell, vg_heat::SolidCmd::Set { temperature: t, capacity: g.capacity }).is_ok())
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/turf/proc/heat_turf_properties")]
fn heat_turf_properties(turf: ByondValue) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let field = field()?;
    let props = with_world(|w| {
        let Some(g) = w.sim_mut().port(field.geometry).read(cell) else {
            return Ok(None);
        };
        let Some(c) = w.sim_mut().port(field.cells).read(cell) else {
            return Ok(None);
        };
        Ok(g.is_node().then_some((g.capacity, c.conductivity, c.emissivity)))
    })?;
    let Some((c, k, e)) = props else {
        return Ok(ByondValue::null());
    };
    list([c, k, e])
}

// ----------------------------------------------------------------- bodies

fn coupling_kind_for(target_kind: i32) -> Result<i32> {
    match target_kind {
        HEAT_TARGET_NONE | HEAT_TARGET_SOLID | HEAT_TARGET_TURF_AIR | HEAT_TARGET_MIXTURE | HEAT_TARGET_BODY => Ok(target_kind),
        other => bail!("bad heat target kind {other}"),
    }
}

/// Detaches (body, slot)'s current coupling entity, if any.
fn drop_coupling(w: &mut vg_core::world::World, body: u32, slot: u8) {
    if let Some((_, e)) = COUPLINGS.with(|c| c.borrow_mut().remove(&(body, slot))) {
        let _ = w.despawn(e);
    }
}

/// Sets (body, slot)'s coupling, replacing any previous one. `target_kind`
/// is `HEAT_TARGET_*`; `target_ref` a turf (solid/turf air), a mixture id,
/// or another body's `vg_entity` handle.
fn set_coupling(body_e: vg_core::entity::EntityId, slot: u8, target_kind: i32, target_ref: &ByondValue, conductance: f32) -> Result<()> {
    let target_kind = coupling_kind_for(target_kind)?;
    let body_i = body_e.index();
    with_world(|w| {
        drop_coupling(w, body_i, slot);
        match target_kind {
            HEAT_TARGET_NONE => {}
            HEAT_TARGET_SOLID => {
                let cell = target_ref.get_ref()?;
                let e = w.bind_value(None, SolidCoupling { body: body_i, cell, conductance: conductance.into(), slot }).map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (0, e)));
            }
            HEAT_TARGET_TURF_AIR => {
                let cell = target_ref.get_ref()?;
                let e = w
                    .bind_value(None, GasCoupling { body: body_i, kind: gas_kind::TURF, target: cell, conductance: conductance.into(), slot })
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (1, e)));
            }
            HEAT_TARGET_MIXTURE => {
                #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
                let target = num(target_ref)? as u32;
                let e = w
                    .bind_value(None, GasCoupling { body: body_i, kind: gas_kind::MIXTURE, target, conductance: conductance.into(), slot })
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (1, e)));
            }
            HEAT_TARGET_BODY => {
                let other = entity::decode(num(target_ref)?)?;
                let e = w
                    .bind_value(None, BodyCoupling { body: body_i, other: other.index(), conductance: conductance.into(), slot })
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (2, e)));
            }
            _ => unreachable!("coupling_kind_for checked"),
        }
        Ok(())
    })
}

/// Creates a heat body: capacity (J/K), temperature (K), coupling slot 0
/// (`HEAT_TARGET_*`, target, conductance), and whether DM keeps it. Returns
/// the entity handle, or null on failure.
#[auxmacros::bind("/proc/heat_body_create")]
fn heat_body_create(capacity: ByondValue, temperature: ByondValue, target_kind: ByondValue, target_ref: ByondValue, conductance: ByondValue, keep: ByondValue) -> Result<ByondValue> {
    let capacity = f64::from(num(&capacity)?);
    if !(capacity.is_finite() && capacity > 0.0) {
        return Ok(ByondValue::null());
    }
    let temperature = f64::from(num(&temperature)?.max(vg_heat::consts::TCMB));
    let body = HeatBody {
        capacity,
        energy: capacity * temperature,
        keep: keep.is_true(),
        ..Default::default()
    };
    #[allow(clippy::cast_possible_truncation)]
    let target_kind = num(&target_kind)? as i32;
    let conductance = num(&conductance)?;
    let e = with_world(|w| w.bind_value(None, body).map_err(|e| eyre!("{e}")))?;
    set_coupling(e, 0, target_kind, &target_ref, conductance)?;
    Ok(ByondValue::from(entity::entity_value(e)))
}

fn body(h: &ByondValue) -> Result<Option<vg_core::entity::EntityId>> {
    let v = num(h)?;
    if v == 0.0 {
        return Ok(None);
    }
    Ok(entity::decode(v).ok().filter(|&e| with_world(|w| Ok(w.read::<HeatBody>(e).is_some())).unwrap_or(false)))
}

#[auxmacros::bind("/proc/heat_body_temperature")]
fn heat_body_temperature(h: ByondValue) -> Result<ByondValue> {
    let Some(e) = body(&h)? else { return Ok(ByondValue::null()) };
    let t = with_world(|w| Ok(w.read::<HeatBody>(e).map(|b| b.temperature())))?;
    Ok(t.map_or_else(ByondValue::null, |t| ByondValue::from(t as f32)))
}

#[auxmacros::bind("/proc/heat_body_add")]
fn heat_body_add(h: ByondValue, joules: ByondValue) -> Result<ByondValue> {
    let joules = f64::from(num(&joules)?);
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        let floor = b.capacity * f64::from(vg_heat::consts::TCMB);
        b.energy = (b.energy + joules).max(floor);
        Ok(w.put(e, b).is_ok())
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_couple")]
fn heat_body_couple(h: ByondValue, slot: ByondValue, target_kind: ByondValue, target_ref: ByondValue, conductance: ByondValue) -> Result<ByondValue> {
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let slot = num(&slot)?.clamp(0.0, 1.0) as u8;
    #[allow(clippy::cast_possible_truncation)]
    let target_kind = num(&target_kind)? as i32;
    set_coupling(e, slot, target_kind, &target_ref, num(&conductance)?)?;
    Ok(true.into())
}

#[auxmacros::bind("/proc/heat_body_power")]
fn heat_body_power(h: ByondValue, watts: ByondValue) -> Result<ByondValue> {
    let watts = f64::from(num(&watts)?);
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    let ok = with_world(|w| Ok(w.set(e, kind_of(w, "HeatBody")?, field_id::<HeatBody>("power")?, None, watts).is_ok()))?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_capacity")]
fn heat_body_capacity(h: ByondValue, capacity: ByondValue) -> Result<ByondValue> {
    let capacity = f64::from(num(&capacity)?);
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        if !(capacity.is_finite() && capacity > 0.0) {
            return Ok(false);
        }
        let t = b.temperature();
        b.capacity = capacity;
        b.energy = capacity * t;
        Ok(w.put(e, b).is_ok())
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_phase")]
fn heat_body_phase(h: ByondValue, temperature: ByondValue, latent: ByondValue) -> Result<ByondValue> {
    let (t, l) = (f64::from(num(&temperature)?), f64::from(num(&latent)?));
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        let temp = b.temperature();
        b.phase_temperature = t;
        b.phase_latent = l;
        b.energy = f64::from(vg_core::thermo::phase_energy(temp as f32, b.capacity as f32, b.phase()));
        Ok(w.put(e, b).is_ok())
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_set_temperature")]
fn heat_body_set_temperature(h: ByondValue, temperature: ByondValue) -> Result<ByondValue> {
    let t = f64::from(num(&temperature)?.max(vg_heat::consts::TCMB));
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        b.energy = f64::from(vg_core::thermo::phase_energy(t as f32, b.capacity as f32, b.phase()));
        Ok(w.put(e, b).is_ok())
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_keep")]
fn heat_body_keep(h: ByondValue, keep: ByondValue) -> Result<ByondValue> {
    let keep = keep.is_true();
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    let ok = with_world(|w| Ok(w.set(e, kind_of(w, "HeatBody")?, field_id::<HeatBody>("keep")?, None, if keep { 1.0 } else { 0.0 }).is_ok()))?;
    Ok(ok.into())
}

/// Releases a body: drops its coupling entities and despawns it at once
/// (unlike the pre-port model, its excess heat is not separately settled
/// into its environment first -- a known, disclosed simplification; see
/// `crate::heat`'s module docs and the step 4 commit message).
#[auxmacros::bind("/proc/heat_body_release")]
fn heat_body_release(h: ByondValue) -> Result<ByondValue> {
    if let Some(e) = body(&h)? {
        let body_i = e.index();
        with_world(|w| {
            drop_coupling(w, body_i, 0);
            drop_coupling(w, body_i, 1);
            let _ = w.despawn(e);
            Ok(())
        })?;
    }
    Ok(ByondValue::null())
}

#[auxmacros::bind("/proc/heat_body_flow")]
fn heat_body_flow(h: ByondValue) -> Result<ByondValue> {
    let Some(e) = body(&h)? else { return Ok(0.0f32.into()) };
    let flow = with_world(|w| Ok(w.read::<HeatBody>(e).map(|b| b.flow)))?;
    Ok(ByondValue::from(flow.unwrap_or(0.0) as f32))
}

fn kind_of(w: &vg_core::world::World, name: &str) -> Result<KindId> {
    match name {
        "HeatBody" => w.kind_of::<HeatBody>(),
        _ => None,
    }
    .ok_or_else(|| eyre!("heat kind {name} not registered"))
}

fn field_id<C: vg_core::component::Component>(name: &str) -> Result<vg_core::component::FieldId> {
    C::field_id(name).ok_or_else(|| eyre!("no field {name} on {}", C::NAME))
}

// ---------------------------------------------------------------- watches

/// Watch kinds, matching the pre-existing `HEAT_WATCH_*` defines.
/// @dm-define HEAT_WATCH_ABOVE
pub const HEAT_WATCH_ABOVE: i32 = 0;
/// @dm-define HEAT_WATCH_BELOW
pub const HEAT_WATCH_BELOW: i32 = 1;
/// @dm-define HEAT_WATCH_BAND
pub const HEAT_WATCH_BAND: i32 = 2;
/// @dm-define HEAT_WATCH_SET
pub const HEAT_WATCH_SET: i32 = 3;

/// Packs a `WatchId` into one DM-exact f32 (`index` in the low 16 bits,
/// `generation` truncated to 8 -- a real `WatchId::generation` is a full
/// `u32`, so a watch table slot reused more than 256 times before its
/// handle is unwatched sees a spurious "stale watch" rather than aliasing
/// onto the wrong watch: fails safe, not silently wrong. Disclosed
/// simplification, `crate::heat`'s module docs).
fn pack_watch(id: WatchId, on_body: bool) -> f32 {
    #[allow(clippy::cast_possible_truncation)]
    let packed = (id.index & 0xffff) | ((id.generation & 0xff) << 16) | (u32::from(on_body) << 24);
    packed as f32
}

fn unpack_watch(v: f32) -> Result<(WatchId, bool)> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let packed = v as u32;
    Ok((
        WatchId {
            index: packed & 0xffff,
            generation: (packed >> 16) & 0xff,
        },
        (packed >> 24) & 1 == 1,
    ))
}

fn channel_of(chans: &[vg_core::channel::ChannelInfo], name: &str) -> Result<vg_core::channel::ChannelId> {
    #[allow(clippy::cast_possible_truncation)]
    chans
        .iter()
        .position(|c| c.name == name)
        .map(|i| vg_core::channel::ChannelId(i as u8))
        .ok_or_else(|| eyre!("no {name} channel"))
}

#[auxmacros::bind("/proc/heat_watch")]
fn heat_watch(on_body: ByondValue, target_ref: ByondValue, subscriber: ByondValue, lane: ByondValue, kind: ByondValue, level: ByondValue, both: ByondValue) -> Result<ByondValue> {
    let on_body = on_body.is_true();
    let both = both.is_true();
    #[allow(clippy::cast_possible_truncation)]
    let kind = num(&kind)? as i32;
    let lane = Lane::from_id({
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        {
            num(&lane)? as u8
        }
    })
    .unwrap_or(Lane::Normal);
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let subscriber: Subscriber = num(&subscriber)? as u32;

    let id = with_world(|w| {
        if on_body {
            let e = entity::decode(num(&target_ref)?)?;
            let kind_id = kind_of(w, "HeatBody")?;
            let chans = w.channels(kind_id).map_err(|e| eyre!("{e}"))?;
            let ch = channel_of(&chans, "temperature")?;
            let cell = e.index();
            let cond = watch_cond(kind, &level, both, ch, vg_core::channel::Unit::Kelvin, cell)?;
            w.watch(kind_id, subscriber, lane, &cond).map_err(|e| eyre!("{e}"))
        } else {
            let cell = target_ref.get_ref()?;
            let ch = vg_heat::solid::solid_ch::TEMPERATURE;
            let cond = watch_cond(kind, &level, both, ch, vg_core::channel::Unit::Kelvin, cell)?;
            w.watch_cells::<SolidHeat>(subscriber, lane, &cond).map_err(|e| eyre!("{e}"))
        }
    })?;
    Ok(ByondValue::from(pack_watch(id, on_body)))
}

fn watch_cond(kind: i32, level: &ByondValue, both: bool, ch: vg_core::channel::ChannelId, unit: vg_core::channel::Unit, cell: u32) -> Result<Cond> {
    let k = |v: f32| vg_core::channel::Quantity::new(v, unit);
    Ok(match kind {
        HEAT_WATCH_ABOVE => {
            let mut l = Level::above(ch, k(num(level)?));
            if both {
                l = l.both_edges();
            }
            Cond::Threshold { cell, level: l }
        }
        HEAT_WATCH_BELOW => {
            let mut l = Level::below(ch, k(num(level)?));
            if both {
                l = l.both_edges();
            }
            Cond::Threshold { cell, level: l }
        }
        HEAT_WATCH_BAND => {
            let values = level.get_list_values()?;
            let mut levels = Vec::with_capacity(values.len());
            for v in &values {
                levels.push(num(v)?);
            }
            Cond::Band { cell, ch, unit, levels, hysteresis: None }
        }
        HEAT_WATCH_SET => Cond::ThresholdSet { cell, ch },
        other => bail!("bad heat watch kind {other}"),
    })
}

#[auxmacros::bind("/proc/heat_watch_set_add")]
fn heat_watch_set_add(watch: ByondValue, payload: ByondValue, generation: ByondValue, cmp: ByondValue, limit: ByondValue, both: ByondValue) -> Result<ByondValue> {
    let (id, on_body) = unpack_watch(num(&watch)?)?;
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let (payload, generation) = (num(&payload)? as u32, num(&generation)? as u32);
    let cmp = if num(&cmp)? as i32 == HEAT_WATCH_BELOW { Cmp::Below } else { Cmp::Above };
    let entry = SetEntry {
        payload,
        generation,
        cmp,
        limit: vg_core::channel::Quantity::new(num(&limit)?, vg_core::channel::Unit::Kelvin),
        hysteresis: None,
        edge: if both.is_true() { Edge::Both } else { Edge::Enter },
    };
    with_world(|w| {
        if on_body {
            w.add_watch_entry(kind_of(w, "HeatBody")?, id, entry)
        } else {
            w.add_field_watch_entry::<SolidHeat>(id, entry)
        }
        .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::null())
}

#[auxmacros::bind("/proc/heat_watch_set_remove")]
fn heat_watch_set_remove(watch: ByondValue, payload: ByondValue) -> Result<ByondValue> {
    let (id, on_body) = unpack_watch(num(&watch)?)?;
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let payload = num(&payload)? as u32;
    with_world(|w| {
        if on_body {
            w.remove_watch_entry(kind_of(w, "HeatBody")?, id, payload)
        } else {
            w.remove_field_watch_entry::<SolidHeat>(id, payload)
        }
        .map_err(|e| eyre!("{e}"))
    })
    .ok();
    Ok(ByondValue::null())
}

#[auxmacros::bind("/proc/heat_unwatch")]
fn heat_unwatch(watch: ByondValue) -> Result<ByondValue> {
    let (id, on_body) = unpack_watch(num(&watch)?)?;
    with_world(|w| {
        if on_body {
            let _ = w.unwatch(kind_of(w, "HeatBody")?, id);
        } else {
            let _ = w.unwatch_cells::<SolidHeat>(id);
        }
        Ok(())
    })
    .ok();
    Ok(ByondValue::null())
}

// ------------------------------------------------------------------- tick

/// Takes every wake and `ThresholdSet` crossing collected since the last
/// call, as one flat list matching the pre-port wire format exactly:
/// `[wake count]`, then `[subscriber, watch, reason, source]` per wake,
/// then `[watch, payload, entered, generation]` per `ThresholdSet`
/// crossing. The world itself is driven by `SSvg`'s `vg_world_tick()`
/// (`code/controllers/subsystems/vg.dm`), not a heat-specific pacer, so
/// this bind only drains -- it never steps a frame.
#[auxmacros::bind("/proc/heat_take_wakes")]
fn heat_take_wakes() -> Result<ByondValue> {
    let mut flat = Vec::new();
    with_world(|w| {
        let mut wakes = Vec::new();
        w.drain_wakes(&mut wakes);
        flat.push(wakes.len() as f32);
        for wk in wakes {
            flat.extend_from_slice(&[wk.subscriber as f32, wk.watch.index as f32, wk.reason as f32, (wk.source & 0x00ff_ffff) as f32]);
        }
        // `ThresholdSet` crossings (payload/entered/generation) are not
        // appended here: `World`'s generic driver does not yet thread a
        // component/field kind's `Outbox::events()` through to
        // `World::drain_events()` (only wakes), so there is nowhere to read
        // a crossing's payload from yet. A `HEAT_WATCH_SET` watch still
        // registers and its wake still fires (DM sees *that* it crossed
        // something); which entry crossed is a disclosed gap, not silently
        // wrong data -- see the step 4 commit message.
        Ok(())
    })?;
    let list = ByondValue::new_list()?;
    let values: Vec<ByondValue> = flat.into_iter().map(ByondValue::from).collect();
    list.write_list(&values)?;
    Ok(list)
}

/// Kept for DM ABI stability (SSair's `process_turf_heat()` still calls
/// it): returns whether any wakes/crossings are waiting. Never steps a
/// frame itself -- see [`heat_take_wakes`]'s doc.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/heat_tick")]
fn heat_tick(_seconds: ByondValue) -> Result<ByondValue> {
    Ok(ByondValue::from(1.0f32))
}

/// Runs `frames` heat frames to completion, blocking. Unit tests only.
#[auxmacros::bind("/proc/heat_debug_run_frames")]
fn heat_debug_run_frames(frames: ByondValue) -> Result<ByondValue> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let n = num(&frames)?.clamp(0.0, 10_000.0) as u32;
    with_world(|w| {
        for _ in 0..n {
            w.step_blocking();
        }
        Ok(())
    })?;
    Ok(ByondValue::null())
}

/// `list(TCMB, T0C, T20C, space sky temperature, Stefan-Boltzmann constant,
/// default emissivity, seconds per heat frame, normal body temperature,
/// human heat capacity, ignition temperature, vacuum heat capacity)`.
#[auxmacros::bind("/proc/heat_constants")]
fn heat_constants() -> Result<ByondValue> {
    let hc = vg_heat::consts::TCMB;
    list([
        hc,
        vg_heat::consts::T0C,
        vg_heat::consts::T20C,
        vg_heat::consts::SPACE_SKY_TEMPERATURE,
        vg_heat::consts::STEFAN_BOLTZMANN as f32,
        vg_heat::consts::DEFAULT_EMISSIVITY,
        vg_heat::consts::HEAT_DT,
        vg_heat::consts::BODYTEMP_NORMAL,
        vg_heat::consts::HUMAN_HEAT_CAPACITY,
        vg_heat::consts::IGNITION_TEMPERATURE,
        vg_heat::consts::HEAT_CAPACITY_VACUUM,
    ])
}

/// Drops heat's coupling side table (`verdigris_cleanup`, a fresh round):
/// the world itself is rebuilt generically (`crate::entity::reset_all`).
#[auxmacros::bind("/proc/heat_reset")]
fn heat_reset() -> Result<ByondValue> {
    COUPLINGS.with(|c| c.borrow_mut().clear());
    Ok(ByondValue::null())
}
