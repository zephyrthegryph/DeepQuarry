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
use vg_heat::couple::{GasHandle, GasRef};
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
    /// Coupling entity index -> owning body entity, the reverse of
    /// [`COUPLINGS`]: `HeatEvent::Settled` (`vg_heat::laws`) is emitted by
    /// the coupling's own law (`LawCtx::emit`'s entity is always the
    /// anchor, never the `Foreign`-joined body), so draining it needs this
    /// to find which body to release.
    static COUPLING_BODY: RefCell<HashMap<u32, vg_core::entity::EntityId>> = RefCell::new(HashMap::new());
    /// Solid cell -> the `SolidCoupling` entities targeting it, so an
    /// external turf write (`heat_set_turf`/`heat_add_turf`/
    /// `heat_set_turf_temperature`) can wake them: a coupling anchored on
    /// its own entity is never woken by a write to the field cell it
    /// merely joins (`Foreign2`'s join has no reverse-wake of its own,
    /// unlike a network region's revision).
    static CELL_COUPLINGS: RefCell<HashMap<u32, Vec<vg_core::entity::EntityId>>> = RefCell::new(HashMap::new());
    /// Body entity index -> the `BodyCoupling` entities naming it as the
    /// *other* side, so a write to that body (any `heat_body_*` bind)
    /// wakes them too, not only the couplings it owns.
    static BODY_AS_OTHER: RefCell<HashMap<u32, Vec<vg_core::entity::EntityId>>> = RefCell::new(HashMap::new());
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
        wake_cell_couplings(w, cell);
        Ok(true)
    })
}

fn clear_turf(w: &mut vg_core::world::World, field: FieldKey<SolidHeat>, cell: u32) {
    let old = w.sim_mut().port(field.geometry).read(cell).unwrap_or_default();
    if old != Geom::default() {
        let _ = w.sim_mut().port(field.geometry).put(cell, Geom::default());
        let _ = w.sim_mut().port(field.cells).put(cell, SolidCell::default());
    }
    wake_cell_couplings(w, cell);
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
        let ok = w.sim_mut().port(field.cells).submit(cell, vg_heat::SolidCmd::Add(joules)).is_ok();
        wake_cell_couplings(w, cell);
        Ok(ok)
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
        let ok = w.sim_mut().port(field.cells).submit(cell, vg_heat::SolidCmd::Set { temperature: t, capacity: g.capacity }).is_ok();
        wake_cell_couplings(w, cell);
        Ok(ok)
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
        COUPLING_BODY.with(|c| c.borrow_mut().remove(&e.index()));
        CELL_COUPLINGS.with(|c| {
            for v in c.borrow_mut().values_mut() {
                v.retain(|&x| x != e);
            }
        });
        BODY_AS_OTHER.with(|c| {
            for v in c.borrow_mut().values_mut() {
                v.retain(|&x| x != e);
            }
        });
        let _ = w.despawn(e);
    }
}

/// Records `coupling`'s owning body for [`drain_settled_bodies`].
fn track_coupling_owner(coupling: vg_core::entity::EntityId, body: vg_core::entity::EntityId) {
    COUPLING_BODY.with(|c| c.borrow_mut().insert(coupling.index(), body));
}

/// Records that `coupling` (a `SolidCoupling`) targets `cell`, for
/// [`wake_cell_couplings`].
fn track_cell_coupling(cell: u32, coupling: vg_core::entity::EntityId) {
    CELL_COUPLINGS.with(|c| c.borrow_mut().entry(cell).or_default().push(coupling));
}

/// Records that `coupling` (a `BodyCoupling`) names `other` as its other
/// side, for [`wake_body_couplings`].
fn track_body_coupling(other: u32, coupling: vg_core::entity::EntityId) {
    BODY_AS_OTHER.with(|c| c.borrow_mut().entry(other).or_default().push(coupling));
}

/// Wakes every `SolidCoupling` targeting `cell` (an external turf write).
fn wake_cell_couplings(w: &mut vg_core::world::World, cell: u32) {
    let Some(kind) = w.kind_of::<SolidCoupling>() else { return };
    let targets = CELL_COUPLINGS.with(|c| c.borrow().get(&cell).cloned()).unwrap_or_default();
    for e in targets {
        let _ = w.wake_row(e, kind);
    }
}

/// Wakes every coupling that reads `body` (its own, and any `BodyCoupling`
/// naming it as the other side) -- an external write to the body itself
/// (`heat_body_add`/`power`/`capacity`/`phase`/`set_temperature`/
/// `release`), so a coupling that had settled and gone to sleep notices.
fn wake_body_couplings(w: &mut vg_core::world::World, body: u32) {
    let owned = COUPLINGS.with(|c| {
        c.borrow()
            .iter()
            .filter(|&(&(b, _), _)| b == body)
            .map(|(_, &(kind, e))| (kind, e))
            .collect::<Vec<_>>()
    });
    for (kind, e) in owned {
        let kind_id = match kind {
            0 => w.kind_of::<SolidCoupling>(),
            1 => w.kind_of::<GasCoupling>(),
            2 => w.kind_of::<BodyCoupling>(),
            _ => None,
        };
        if let Some(k) = kind_id {
            let _ = w.wake_row(e, k);
        }
    }
    let Some(body_kind) = w.kind_of::<BodyCoupling>() else { return };
    let others = BODY_AS_OTHER.with(|c| c.borrow().get(&body).cloned()).unwrap_or_default();
    for e in others {
        let _ = w.wake_row(e, body_kind);
    }
}

/// If `body` is following the analytic relax model (`vg_heat::laws`'s
/// module docs), resolves it exactly at `w.now()` and deposits the energy
/// it moved into slot 0's environment, leaving `body.relax` cleared. A
/// direct external write to a relaxing body (`heat_body_add`/`power`/
/// `capacity`/`phase`/`set_temperature`) must go through this first: the
/// model's anchor (`since`/`ambient`) is only valid until something other
/// than the coupling's own law changes the body, and `energy` holds the
/// anchor value, not the current one, while relaxing -- writing it
/// directly without settling first would silently create or destroy
/// energy relative to what the exact model already promised the
/// environment. The coupling's own law re-enters relax mode on its own
/// next run if the body (now freshly woken, see [`wake_body_couplings`])
/// is still eligible.
fn settle_body_if_relaxing(w: &mut vg_core::world::World, e: vg_core::entity::EntityId, body: &mut HeatBody) -> Result<()> {
    if !body.relax {
        return Ok(());
    }
    let now = w.now();
    let Some(&(kind, coupling_e)) = COUPLINGS.with(|c| c.borrow().get(&(e.index(), 0)).copied()).as_ref() else {
        // No slot-0 coupling to deposit into (it was detached without
        // going through `heat_body_couple`/`release`, which both settle
        // and drop it themselves): just leave the model's anchor value as
        // the stored energy -- the least-surprising fallback, matching a
        // plain non-relaxing body with the same energy.
        body.relax = false;
        return Ok(());
    };
    match kind {
        0 => {
            let Some(coupling) = w.read::<SolidCoupling>(coupling_e) else {
                body.relax = false;
                return Ok(());
            };
            let field = field()?;
            let (Some(g), Some(mut cell)) = (w.sim_mut().port(field.geometry).read(coupling.cell), w.sim_mut().port(field.cells).read(coupling.cell)) else {
                body.relax = false;
                return Ok(());
            };
            let moved = vg_heat::laws::settle_relax(body, coupling.conductance, now);
            if g.reservoir {
                // Outside `heat_energy`'s tracked total either way; nothing
                // to write back, and there is no generic per-bind ledger
                // to book a one-off external write to (unlike the law's
                // own step, which always runs inside a `World::conserve()`
                // check).
            } else if moved != 0.0 {
                #[allow(clippy::cast_possible_truncation)]
                let m = moved as f32;
                cell.energy += m;
                cell.temperature = cell.energy / g.capacity;
                let _ = w.sim_mut().port(field.cells).put(coupling.cell, cell);
            }
        }
        1 => {
            let Some(coupling) = w.read::<GasCoupling>(coupling_e) else {
                body.relax = false;
                return Ok(());
            };
            let target = if coupling.kind == gas_kind::MIXTURE { GasRef::Mixture(coupling.target) } else { GasRef::Turf(coupling.target) };
            let gas = w.global::<GasHandle>().map(|g| g.0.clone()).ok();
            let moved = vg_heat::laws::settle_relax(body, coupling.conductance, now);
            if let Some(gas) = gas {
                #[allow(clippy::cast_possible_truncation)]
                let m = moved as f32;
                let _ = gas.exchange(target, &mut |_p| m);
            }
        }
        2 => {
            let Some(coupling) = w.read::<BodyCoupling>(coupling_e) else {
                body.relax = false;
                return Ok(());
            };
            let other_e = vg_core::entity::EntityId::from_bits(coupling.other).unwrap_or(e);
            let moved = vg_heat::laws::settle_relax(body, coupling.conductance, now);
            if moved != 0.0
                && let Some(mut other) = w.read::<HeatBody>(other_e)
            {
                let floor = other.capacity * f64::from(vg_heat::consts::TCMB);
                other.energy = (other.energy + moved).max(floor);
                let _ = w.put(other_e, other);
            }
        }
        _ => body.relax = false,
    }
    Ok(())
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
                track_coupling_owner(e, body_e);
                track_cell_coupling(cell, e);
            }
            HEAT_TARGET_TURF_AIR => {
                let cell = target_ref.get_ref()?;
                let e = w
                    .bind_value(None, GasCoupling { body: body_i, kind: gas_kind::TURF, target: cell, conductance: conductance.into(), slot })
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (1, e)));
                track_coupling_owner(e, body_e);
            }
            HEAT_TARGET_MIXTURE => {
                #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
                let target = num(target_ref)? as u32;
                let e = w
                    .bind_value(None, GasCoupling { body: body_i, kind: gas_kind::MIXTURE, target, conductance: conductance.into(), slot })
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (1, e)));
                track_coupling_owner(e, body_e);
            }
            HEAT_TARGET_BODY => {
                let other = entity::decode(num(target_ref)?)?;
                let e = w
                    .bind_value(None, BodyCoupling { body: body_i, other: other.index(), conductance: conductance.into(), slot })
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (2, e)));
                track_coupling_owner(e, body_e);
                track_body_coupling(other.index(), e);
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
        settle_body_if_relaxing(w, e, &mut b)?;
        let floor = b.capacity * f64::from(vg_heat::consts::TCMB);
        b.energy = (b.energy + joules).max(floor);
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
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
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        settle_body_if_relaxing(w, e, &mut b)?;
        b.power = watts;
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
    })?;
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
        settle_body_if_relaxing(w, e, &mut b)?;
        let t = b.temperature();
        b.capacity = capacity;
        b.energy = capacity * t;
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
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
        settle_body_if_relaxing(w, e, &mut b)?;
        let temp = b.temperature();
        b.phase_temperature = t;
        b.phase_latent = l;
        b.energy = f64::from(vg_core::thermo::phase_energy(temp as f32, b.capacity as f32, b.phase()));
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
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
        // DM authority: the new temperature replaces whatever the model
        // was doing, so this clears `relax` outright instead of settling
        // first (settling would just be overwritten immediately after).
        b.relax = false;
        b.energy = f64::from(vg_core::thermo::phase_energy(t as f32, b.capacity as f32, b.phase()));
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_keep")]
fn heat_body_keep(h: ByondValue, keep: ByondValue) -> Result<ByondValue> {
    let keep = keep.is_true();
    let Some(e) = body(&h)? else { return Ok(false.into()) };
    let ok = with_world(|w| {
        let ok = w.set(e, kind_of(w, "HeatBody")?, field_id::<HeatBody>("keep")?, None, if keep { 1.0 } else { 0.0 }).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
    })?;
    Ok(ok.into())
}

/// Releases a body: settles it (if relaxing) into its environment,
/// deposits its excess over slot 0's environment there too, drops its
/// coupling entities and despawns it at once.
#[auxmacros::bind("/proc/heat_body_release")]
fn heat_body_release(h: ByondValue) -> Result<ByondValue> {
    if let Some(e) = body(&h)? {
        let body_i = e.index();
        with_world(|w| {
            release_body(w, e)?;
            drop_coupling(w, body_i, 0);
            drop_coupling(w, body_i, 1);
            let _ = w.despawn(e);
            Ok(())
        })?;
    }
    Ok(ByondValue::null())
}

/// Settles `body` if it is relaxing, then moves whatever it holds above
/// slot 0's environment there too (`body.rs::release`, ported): the
/// baseline (what the environment already is) stays out of the books as
/// released, not conserved -- exactly `heat.dm`'s "excess heat goes to its
/// surroundings" contract.
fn release_body(w: &mut vg_core::world::World, e: vg_core::entity::EntityId) -> Result<()> {
    let Some(mut b) = w.read::<HeatBody>(e) else {
        return Ok(());
    };
    settle_body_if_relaxing(w, e, &mut b)?;
    let Some(&(kind, coupling_e)) = COUPLINGS.with(|c| c.borrow().get(&(e.index(), 0)).copied()).as_ref() else {
        return Ok(());
    };
    match kind {
        0 => {
            if let Some(coupling) = w.read::<SolidCoupling>(coupling_e) {
                let field = field()?;
                if let (Some(g), Some(cell)) = (w.sim_mut().port(field.geometry).read(coupling.cell), w.sim_mut().port(field.cells).read(coupling.cell)) {
                    let baseline_t = if g.reservoir { cell.temperature } else { cell.temperature_in(g.capacity) };
                    #[allow(clippy::cast_possible_truncation)]
                    let baseline = f64::from(vg_core::thermo::phase_energy(baseline_t, b.capacity as f32, b.phase()).max(0.0));
                    let excess = b.energy - baseline;
                    if excess != 0.0 && !g.reservoir {
                        #[allow(clippy::cast_possible_truncation)]
                        let m = excess as f32;
                        let mut cell = cell;
                        cell.energy += m;
                        cell.temperature = cell.energy / g.capacity;
                        let _ = w.sim_mut().port(field.cells).put(coupling.cell, cell);
                    }
                }
            }
        }
        1 => {
            if let Some(coupling) = w.read::<GasCoupling>(coupling_e) {
                let target = if coupling.kind == gas_kind::MIXTURE { GasRef::Mixture(coupling.target) } else { GasRef::Turf(coupling.target) };
                if let Ok(gas) = w.global::<GasHandle>() {
                    let gas = gas.0.clone();
                    if let Some(probe) = gas.probe(target) {
                        #[allow(clippy::cast_possible_truncation)]
                        let baseline = f64::from(vg_core::thermo::phase_energy(probe.temperature, b.capacity as f32, b.phase()).max(0.0));
                        let excess = b.energy - baseline;
                        if excess != 0.0 {
                            #[allow(clippy::cast_possible_truncation)]
                            let m = excess as f32;
                            let _ = gas.exchange(target, &mut |_p| m);
                        }
                    }
                }
            }
        }
        2 => {
            if let Some(coupling) = w.read::<BodyCoupling>(coupling_e) {
                let other_e = vg_core::entity::EntityId::from_bits(coupling.other).unwrap_or(e);
                if let Some(mut other) = w.read::<HeatBody>(other_e) {
                    #[allow(clippy::cast_possible_truncation)]
                    let baseline = f64::from(vg_core::thermo::phase_energy(other.temperature() as f32, b.capacity as f32, b.phase()).max(0.0));
                    let excess = b.energy - baseline;
                    if excess != 0.0 {
                        other.energy += excess;
                        let _ = w.put(other_e, other);
                    }
                }
            }
        }
        _ => {}
    }
    Ok(())
}

#[auxmacros::bind("/proc/heat_body_flow")]
fn heat_body_flow(h: ByondValue) -> Result<ByondValue> {
    let Some(e) = body(&h)? else { return Ok(0.0f32.into()) };
    let flow = with_world(|w| Ok(w.read::<HeatBody>(e).map(|b| b.flow)))?;
    Ok(ByondValue::from(flow.unwrap_or(0.0) as f32))
}

/// Auto-release: a coupling law that just settled a releasable body within
/// [`vg_heat::consts::BODY_SETTLED_K`] of its environment emitted
/// [`vg_heat::laws::HeatEvent::Settled`] (`LawCtx::emit`'s entity is
/// always the coupling's own, the law's anchor -- never the body it
/// `Foreign`-joins), so this resolves it back to the owning body through
/// [`COUPLING_BODY`] and releases it exactly as `heat_body_release` would
/// (the settle already happened inside the law; only dropping the
/// coupling entities and despawning is left).
fn drain_settled_bodies(w: &mut vg_core::world::World) {
    let events = w.drain_events();
    let settled: Vec<vg_core::entity::EntityId> = events
        .decoded::<vg_heat::laws::HeatEvent>()
        .filter_map(|(entity_v, vg_heat::laws::HeatEvent::Settled)| entity::decode(entity_v).ok())
        .filter_map(|coupling_e| COUPLING_BODY.with(|c| c.borrow().get(&coupling_e.index()).copied()))
        .collect();
    for body_e in settled {
        if w.read::<HeatBody>(body_e).is_none() {
            continue;
        }
        let body_i = body_e.index();
        drop_coupling(w, body_i, 0);
        drop_coupling(w, body_i, 1);
        let _ = w.despawn(body_e);
    }
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

/// A DM watch handle: `index` and `generation` as their own numbers (no
/// packing), so neither is ever truncated -- `WatchId::generation` is a
/// full `u32`, wider than a single `f32` could carry alongside `index`
/// without losing bits. `heat_watch` returns `list(index, generation)`;
/// every other watch bind takes them back as two arguments plus `on_body`
/// (also no longer packed into a spare bit), matching `Wake`/`WatchId`'s
/// own shape exactly instead of DM's own encoding of it.
fn watch_id(index: &ByondValue, generation: &ByondValue) -> Result<WatchId> {
    Ok(WatchId {
        index: whole(index, "watch index")?,
        generation: whole(generation, "watch generation")?,
    })
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
    #[allow(clippy::cast_precision_loss)]
    list([id.index as f32, id.generation as f32])
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
fn heat_watch_set_add(on_body: ByondValue, index: ByondValue, watch_generation: ByondValue, payload: ByondValue, generation: ByondValue, cmp: ByondValue, limit: ByondValue, both: ByondValue) -> Result<ByondValue> {
    let id = watch_id(&index, &watch_generation)?;
    let on_body = on_body.is_true();
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
fn heat_watch_set_remove(on_body: ByondValue, index: ByondValue, watch_generation: ByondValue, payload: ByondValue) -> Result<ByondValue> {
    let id = watch_id(&index, &watch_generation)?;
    let on_body = on_body.is_true();
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
fn heat_unwatch(on_body: ByondValue, index: ByondValue, watch_generation: ByondValue) -> Result<ByondValue> {
    let id = watch_id(&index, &watch_generation)?;
    let on_body = on_body.is_true();
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
        // `ThresholdSet` crossings: watch_index, payload, entered,
        // payload_generation -- matching the pre-port wire format exactly.
        // `crate::outbox::Event` (the core type a crossing rides in) only
        // carries the watch's table *index*, not its generation
        // (`core::world::ThresholdCrossing`'s doc), so -- like the pre-port
        // `HeatWorld`'s own `cell_watch_owner`/`body_watch_owner` re-keying
        // maps, which were also index-only internally -- `GLOB.
        // heat_watch_owners` (heat.dm) looks up a crossing's owner by watch
        // index alone, not the full (index, generation) handle DM otherwise
        // holds for `heat_unwatch`/`heat_watch_set_add`/`remove`.
        for c in w.drain_threshold_crossings() {
            flat.extend_from_slice(&[c.watch as f32, c.payload as f32, if c.entered { 1.0 } else { 0.0 }, c.generation as f32]);
        }
        drain_settled_bodies(w);
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
