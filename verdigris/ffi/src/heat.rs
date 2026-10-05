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
use vg_core::grid::Dir;
use vg_core::outbox::{Lane, Subscriber, Wake, WatchId};
use vg_core::watch::{Cond, SetEntry};
use vg_core::world::{KindId, WorldBuilder};
use vg_heat::components::gas_kind;
use vg_heat::laws::{BodyBodyExchange, RegulatorHeatPump, SolidBodyExchange};
use vg_heat::{
    BodyCoupling, GasCoupling, HeatBody, MobHeat, Regulator, SolidCell, SolidCoupling, SolidHeat,
};

use crate::entity;
use crate::world::{list, num, with_world};

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
/// The gas of the pipe region a pipe port (an entity handle) is in: a pipeline's persistent coupling, which follows the
/// region through merges and splits.
/// @dm-define HEAT_TARGET_PIPE_PORT
pub const HEAT_TARGET_PIPE_PORT: i32 = 5;

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

/// Registers heat's fields, components and laws
/// (`crate::world::register`'s call site). Returns the field key so
/// `crate::world::build` can hand it to [`install_field`].
pub fn register(b: &mut WorldBuilder) -> FieldKey<SolidHeat> {
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
    b.conserve("heat_energy", Tolerance::default());
    let _ = b.add_law::<SolidBodyExchange>();
    let _ = b.add_law::<BodyBodyExchange>();
    let _ = b.add_law::<RegulatorHeatPump>();
    let _ = b.add_law::<vg_heat::laws::BodyPower>();
    b.add_global(
        vg_core::component::Ownership::Worker,
        vg_heat::laws::MixtureProbes::default(),
    );
    let _ = b.add_law::<vg_heat::laws::BodyMixtureExchange>();
    let _ = b.add_law::<vg_heat::mob::MobHeatFlux>();
    field
}

/// Stashes the field key `register` returned, and the gas bridge, once the
/// world is built (`crate::world::build`'s call site).
pub fn install_field(field: FieldKey<SolidHeat>) {
    FIELD.with(|f| f.set(Some(field)));
}

pub(crate) fn field() -> Result<FieldKey<SolidHeat>> {
    FIELD
        .with(Cell::get)
        .ok_or_else(|| eyre!("heat field not installed"))
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

pub(crate) fn set_turf(
    field: FieldKey<SolidHeat>,
    cell: u32,
    kind: i32,
    capacity: f32,
    conductivity: f32,
    emissivity: f32,
    temperature: f32,
    air: bool,
) -> Result<bool> {
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
        let old = w
            .sim_mut()
            .port(field.geometry)
            .read(cell)
            .unwrap_or_default();
        let geom = Geom {
            capacity,
            // A solid deck separates z-levels: cross-z heat needs an
            // explicit conductor (unchanged from the pre-port field).
            blocked: Dir::NONE
                .with(vg_core::grid::Face::Up)
                .with(vg_core::grid::Face::Down),
            reservoir,
        };
        if old != geom
            && let Some(geom) = bulk_push(|b| b.geometry.push(cell, geom), geom)
        {
            let _ = w.sim_mut().port(field.geometry).put(cell, geom);
        }
        if old.is_node() && !old.reservoir && !reservoir {
            let current = w.sim_mut().port(field.cells).read(cell).unwrap_or_default();
            if current.conductivity != conductivity
                || current.emissivity != emissivity
                || current.flags != f
            {
                let _ = w.sim_mut().port(field.cells).submit(
                    cell,
                    vg_heat::SolidCmd::Props {
                        conductivity,
                        emissivity,
                        flags: f,
                    },
                );
            }
            if (old.capacity - capacity).abs() > 0.0 {
                let _ = w.sim_mut().port(field.cells).submit(
                    cell,
                    vg_heat::SolidCmd::Rescale {
                        from: old.capacity,
                        to: capacity,
                    },
                );
            }
        } else {
            let t = if kind == HEAT_CELL_SPACE {
                vg_heat::consts::TCMB
            } else {
                temperature.max(vg_heat::consts::TCMB)
            };
            let value = SolidCell::at(capacity, t, conductivity.max(0.0), emissivity, f);
            if let Some(value) = bulk_push(|b| b.cells.push(cell, value), value) {
                let _ = w.sim_mut().port(field.cells).put(cell, value);
            }
        }
        wake_cell_couplings(w, cell);
        Ok(true)
    })
}

fn clear_turf(w: &mut vg_core::world::World, field: FieldKey<SolidHeat>, cell: u32) {
    let old = w
        .sim_mut()
        .port(field.geometry)
        .read(cell)
        .unwrap_or_default();
    if old != Geom::default() {
        let _ = w.sim_mut().port(field.geometry).put(cell, Geom::default());
        let _ = w
            .sim_mut()
            .port(field.cells)
            .put(cell, SolidCell::default());
    }
    wake_cell_couplings(w, cell);
}

#[auxmacros::bind("/turf/proc/heat_set_turf")]
fn heat_set_turf(
    turf: ByondValue,
    kind: ByondValue,
    capacity: ByondValue,
    conductivity: ByondValue,
    emissivity: ByondValue,
    temperature: ByondValue,
    air: ByondValue,
) -> Result<ByondValue> {
    let cell = turf.get_ref()?;
    let field = field()?;
    #[allow(clippy::cast_possible_truncation)]
    let ok = set_turf(
        field,
        cell,
        num(&kind)? as i32,
        num(&capacity)?,
        num(&conductivity)?,
        num(&emissivity)?,
        num(&temperature)?,
        air.is_true(),
    )?;
    Ok(ok.into())
}

/// Heat rows buffered by a bulk bind ([`with_bulk`]).
struct Bulk {
    cells: crate::bulk::Direct<SolidHeat>,
    geometry: crate::bulk::Direct<vg_core::field::Geometry<SolidHeat>>,
}

thread_local! {
    static BULK: RefCell<Option<Bulk>> = const { RefCell::new(None) };
}

/// Inside a bulk bind, hands the row to `push` and returns `None`; outside
/// one, returns `value` for the caller to put through the port.
fn bulk_push<T>(push: impl FnOnce(&mut Bulk), value: T) -> Option<T> {
    BULK.with_borrow_mut(|b| match b.as_mut() {
        Some(bulk) => {
            push(bulk);
            None
        }
        None => Some(value),
    })
}

/// Runs `f` with [`set_turf`] buffering its new cells, then writes them into
/// the live stores in one pass (Phase 4b, `crate::bulk`).
pub(crate) fn with_bulk<T>(field: FieldKey<SolidHeat>, f: impl FnOnce() -> Result<T>) -> Result<T> {
    BULK.with_borrow_mut(|b| {
        *b = Some(Bulk {
            cells: crate::bulk::Direct::new(field.cells),
            geometry: crate::bulk::Direct::new(field.geometry),
        });
    });
    let result = f();
    if let Some(bulk) = BULK.with_borrow_mut(Option::take) {
        with_world(|w| {
            bulk.geometry.flush(w);
            bulk.cells.flush(w);
            Ok(())
        })?;
    }
    result
}

#[auxmacros::bind("/proc/heat_set_turfs_bulk")]
fn heat_set_turfs_bulk(records: ByondValue) -> Result<ByondValue> {
    let values = records.get_list_values()?;
    let field = field()?;
    with_bulk(field, || set_turfs(field, &values)).map(|set| ByondValue::from(set as f32))
}

fn set_turfs(field: FieldKey<SolidHeat>, values: &[ByondValue]) -> Result<u32> {
    let mut set = 0u32;
    for r in values.chunks_exact(7) {
        let Ok(cell) = r[0].get_ref() else { continue };
        #[allow(clippy::cast_possible_truncation)]
        let kind = num(&r[1])? as i32;
        if set_turf(
            field,
            cell,
            kind,
            num(&r[2])?,
            num(&r[3])?,
            num(&r[4])?,
            num(&r[5])?,
            r[6].is_true(),
        )? {
            set += 1;
        }
    }
    Ok(set)
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
        Ok(Some(if g.reservoir {
            c.temperature
        } else {
            c.temperature_in(g.capacity)
        }))
    })?;
    Ok(t.filter(|t| t.is_finite())
        .map_or_else(ByondValue::null, ByondValue::from))
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
        let ok = w
            .sim_mut()
            .port(field.cells)
            .submit(cell, vg_heat::SolidCmd::Add(joules))
            .is_ok();
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
        let ok = w
            .sim_mut()
            .port(field.cells)
            .submit(
                cell,
                vg_heat::SolidCmd::Set {
                    temperature: t,
                    capacity: g.capacity,
                },
            )
            .is_ok();
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
        Ok(g.is_node()
            .then_some((g.capacity, c.conductivity, c.emissivity)))
    })?;
    let Some((c, k, e)) = props else {
        return Ok(ByondValue::null());
    };
    list([c, k, e])
}

// ----------------------------------------------------------------- bodies

fn coupling_kind_for(target_kind: i32) -> Result<i32> {
    match target_kind {
        HEAT_TARGET_NONE | HEAT_TARGET_SOLID | HEAT_TARGET_TURF_AIR | HEAT_TARGET_MIXTURE
        | HEAT_TARGET_BODY | HEAT_TARGET_PIPE_PORT => Ok(target_kind),
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
pub(crate) fn wake_cell_couplings(w: &mut vg_core::world::World, cell: u32) {
    let Some(kind) = w.kind_of::<SolidCoupling>() else {
        return;
    };
    let targets = CELL_COUPLINGS
        .with(|c| c.borrow().get(&cell).cloned())
        .unwrap_or_default();
    for e in targets {
        let _ = w.wake_row(e, kind);
    }
}

/// Wakes every coupling that reads `body` (its own, and any `BodyCoupling`
/// naming it as the other side) -- an external write to the body itself
/// (`heat_body_add`/`power`/`capacity`/`phase`/`set_temperature`/
/// `release`), so a coupling that had settled and gone to sleep notices.
pub(crate) fn wake_body_couplings(w: &mut vg_core::world::World, body: u32) {
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
    let Some(body_kind) = w.kind_of::<BodyCoupling>() else {
        return;
    };
    let others = BODY_AS_OTHER
        .with(|c| c.borrow().get(&body).cloned())
        .unwrap_or_default();
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
pub(crate) fn settle_body_if_relaxing(
    w: &mut vg_core::world::World,
    e: vg_core::entity::EntityId,
    body: &mut HeatBody,
) -> Result<()> {
    if !body.relax {
        return Ok(());
    }
    let now = w.now();
    let Some(&(kind, coupling_e)) = COUPLINGS
        .with(|c| c.borrow().get(&(e.index(), 0)).copied())
        .as_ref()
    else {
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
            let (Some(g), Some(mut cell)) = (
                w.sim_mut().port(field.geometry).read(coupling.cell),
                w.sim_mut().port(field.cells).read(coupling.cell),
            ) else {
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
            let moved = vg_heat::laws::settle_relax(body, coupling.conductance, now);
            if coupling.kind == gas_kind::TURF {
                turf_gas_heat(w, coupling.target, moved);
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
fn set_coupling(
    body_e: vg_core::entity::EntityId,
    slot: u8,
    target_kind: i32,
    target_ref: &ByondValue,
    conductance: f32,
) -> Result<()> {
    let target_kind = coupling_kind_for(target_kind)?;
    let body_i = body_e.index();
    with_world(|w| {
        drop_coupling(w, body_i, slot);
        match target_kind {
            HEAT_TARGET_NONE => {}
            HEAT_TARGET_SOLID => {
                let cell = target_ref.get_ref()?;
                let e = w
                    .bind_value(
                        None,
                        SolidCoupling {
                            body: body_i,
                            cell,
                            conductance: conductance.into(),
                            slot,
                        },
                    )
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (0, e)));
                track_coupling_owner(e, body_e);
                track_cell_coupling(cell, e);
            }
            HEAT_TARGET_TURF_AIR => {
                let cell = target_ref.get_ref()?;
                let e = w
                    .bind_value(
                        None,
                        GasCoupling {
                            body: body_i,
                            kind: gas_kind::TURF,
                            target: cell,
                            conductance: conductance.into(),
                            slot,
                        },
                    )
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (1, e)));
                track_coupling_owner(e, body_e);
            }
            HEAT_TARGET_MIXTURE => {
                #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
                let target = num(target_ref)? as u32;
                let e = w
                    .bind_value(
                        None,
                        GasCoupling {
                            body: body_i,
                            kind: gas_kind::MIXTURE,
                            target,
                            conductance: conductance.into(),
                            slot,
                        },
                    )
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (1, e)));
                track_coupling_owner(e, body_e);
            }
            HEAT_TARGET_PIPE_PORT => {
                let port = entity::decode(num(target_ref)?)?;
                let e = w
                    .bind_value(
                        None,
                        GasCoupling {
                            body: body_i,
                            kind: gas_kind::PIPE_PORT,
                            target: port.bits(),
                            conductance: conductance.into(),
                            slot,
                        },
                    )
                    .map_err(|e| eyre!("{e}"))?;
                COUPLINGS.with(|c| c.borrow_mut().insert((body_i, slot), (1, e)));
                track_coupling_owner(e, body_e);
            }
            HEAT_TARGET_BODY => {
                let other = entity::decode(num(target_ref)?)?;
                let e = w
                    .bind_value(
                        None,
                        BodyCoupling {
                            body: body_i,
                            other: other.index(),
                            conductance: conductance.into(),
                            slot,
                        },
                    )
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
fn heat_body_create(
    capacity: ByondValue,
    temperature: ByondValue,
    target_kind: ByondValue,
    target_ref: ByondValue,
    conductance: ByondValue,
    keep: ByondValue,
) -> Result<ByondValue> {
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

// ---------------------------------------------------------- bulk binds

/// What happened to a reserved body between [`heat_body_reserve`] and its
/// [`heat_body_configure_list`] entry. Configure never overwrites an explicit
/// write made in between: a handle is usable the moment it is reserved.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Reserved {
    /// `heat_body_set_temperature` ran: keep the temperature it set.
    pub temperature_set: bool,
    /// `heat_body_couple` on slot 0 ran: keep that coupling.
    pub slot0_set: bool,
    /// `heat_body_keep` ran: keep that flag.
    pub keep_set: bool,
    /// Joules `heat_body_add` put in; re-added on top of the configured
    /// temperature.
    pub added: f64,
}

thread_local! {
    /// Body entity index -> [`Reserved`], for bodies handed out by
    /// [`heat_body_reserve`] and not yet configured.
    static RESERVED: RefCell<HashMap<u32, Reserved>> = RefCell::new(HashMap::new());
}

/// A reserved body's placeholder: kept (so it never relaxes away), uncoupled,
/// unpowered, at TCMB with capacity 1. It takes no part in any exchange until
/// it is configured or coupled.
fn reserved_placeholder() -> HeatBody {
    HeatBody {
        capacity: 1.0,
        energy: f64::from(vg_heat::consts::TCMB),
        keep: true,
        ..Default::default()
    }
}

/// Spawns `n` placeholder bodies and records them as reserved.
pub(crate) fn reserve_bodies(
    w: &mut vg_core::world::World,
    n: usize,
) -> Result<Vec<vg_core::entity::EntityId>> {
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let e = w
            .bind_value(None, reserved_placeholder())
            .map_err(|e| eyre!("{e}"))?;
        RESERVED.with_borrow_mut(|r| r.insert(e.index(), Reserved::default()));
        out.push(e);
    }
    Ok(out)
}

/// Records a write on `e` if it is still reserved (a no-op otherwise).
pub(crate) fn note_reserved(e: vg_core::entity::EntityId, f: impl FnOnce(&mut Reserved)) {
    RESERVED.with_borrow_mut(|r| {
        if let Some(flags) = r.get_mut(&e.index()) {
            f(flags);
        }
    });
}

/// Whether `e` is reserved and not yet configured.
#[cfg(test)]
pub(crate) fn is_reserved(e: vg_core::entity::EntityId) -> bool {
    RESERVED.with_borrow(|r| r.contains_key(&e.index()))
}

/// One reserved body's configuration.
#[derive(Clone, Copy, Debug)]
pub(crate) struct BodySpec {
    pub e: vg_core::entity::EntityId,
    pub capacity: f64,
    pub temperature: f64,
    pub keep: bool,
}

/// Configures reserved bodies in one pass. Per spec: `None` when the handle
/// is not a live reserved body (never reserved, released, or already
/// configured -- left untouched), else `Some(couple_slot0)`, false when slot
/// 0 was coupled explicitly after the reserve and must be kept.
pub(crate) fn configure_bodies(
    w: &mut vg_core::world::World,
    specs: &[BodySpec],
) -> Vec<Option<bool>> {
    specs
        .iter()
        .map(|spec| {
            if !(spec.capacity.is_finite() && spec.capacity > 0.0) {
                return None;
            }
            let flags = RESERVED.with_borrow_mut(|r| r.remove(&spec.e.index()))?;
            let mut b = w.read::<HeatBody>(spec.e)?;
            let temperature = if flags.temperature_set {
                b.energy / b.capacity.max(f64::MIN_POSITIVE)
            } else {
                spec.temperature.max(f64::from(vg_heat::consts::TCMB)) + flags.added / spec.capacity
            };
            b.capacity = spec.capacity;
            b.energy = spec.capacity * temperature;
            if !flags.keep_set {
                b.keep = spec.keep;
            }
            w.put(spec.e, b).ok()?;
            wake_body_couplings(w, spec.e.index());
            Some(!flags.slot0_set)
        })
        .collect()
}

/// Bulk bind, step 1 (`doc/rewrite/init_and_turfs.md` sec 4.6): `n`
/// heat-body handles in one call. Each is a live, kept, inert body at once,
/// so DM may use it immediately (keep, power, couple, set temperature all
/// work); [`heat_body_configure_list`] gives it its real capacity,
/// temperature, environment and keep flag later without undoing those
/// writes. Reads before the configure see the placeholder: DM configures a
/// pending body before reading it (`/atom/proc/resolve_heat_body()`).
#[auxmacros::bind("/proc/heat_body_reserve")]
fn heat_body_reserve(n: ByondValue) -> Result<ByondValue> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let n = num(&n)?.clamp(0.0, 65_536.0) as usize;
    let bodies = with_world(|w| reserve_bodies(w, n))?;
    let handles: Vec<ByondValue> = bodies
        .into_iter()
        .map(|e| ByondValue::from(entity::entity_value(e)))
        .collect();
    let list = ByondValue::new_list()?;
    list.write_list(&handles)?;
    Ok(list)
}

/// Bulk bind, step 2: configures reserved bodies from `args`, flattened 7 per
/// body: `handle, capacity, temperature, HEAT_TARGET_*, target, conductance,
/// keep` (as `heat_body_create` takes them). Entries whose handle is not a
/// reserved body are skipped. Returns how many were configured.
#[auxmacros::bind("/proc/heat_body_configure_list")]
fn heat_body_configure_list(args: ByondValue) -> Result<ByondValue> {
    let args = args.get_list_values()?;
    if args.len() % 7 != 0 {
        bail!("args must hold 7 values per body");
    }
    let mut specs = Vec::with_capacity(args.len() / 7);
    let mut couplings = Vec::with_capacity(args.len() / 7);
    for chunk in args.chunks_exact(7) {
        let [h, capacity, temperature, kind, target, conductance, keep] = chunk else {
            unreachable!("chunks_exact(7)");
        };
        let Ok(e) = num(h).and_then(entity::decode) else {
            continue;
        };
        specs.push(BodySpec {
            e,
            capacity: f64::from(num(capacity)?),
            temperature: f64::from(num(temperature)?),
            keep: keep.is_true(),
        });
        #[allow(clippy::cast_possible_truncation)]
        couplings.push((num(kind)? as i32, target.clone(), num(conductance)?));
    }
    let done = with_world(|w| Ok(configure_bodies(w, &specs)))?;
    let mut configured = 0u32;
    for ((spec, (kind, target, conductance)), outcome) in specs.iter().zip(couplings).zip(done) {
        let Some(couple) = outcome else { continue };
        configured += 1;
        if couple {
            set_coupling(spec.e, 0, kind, &target, conductance)?;
        }
    }
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(configured as f32))
}

fn body(h: &ByondValue) -> Result<Option<vg_core::entity::EntityId>> {
    let v = num(h)?;
    if v == 0.0 {
        return Ok(None);
    }
    Ok(entity::decode(v)
        .ok()
        .filter(|&e| with_world(|w| Ok(w.read::<HeatBody>(e).is_some())).unwrap_or(false)))
}

#[auxmacros::bind("/proc/heat_body_temperature")]
fn heat_body_temperature(h: ByondValue) -> Result<ByondValue> {
    let Some(e) = body(&h)? else {
        return Ok(ByondValue::null());
    };
    let t = with_world(|w| Ok(w.read::<HeatBody>(e).map(|b| body_temperature_now(w, e, &b))))?;
    Ok(t.map_or_else(ByondValue::null, |t| ByondValue::from(t as f32)))
}

/// A body's temperature now. A relaxing body's stored energy is its analytic
/// model's anchor (the coupling law sleeps until the model is due, up to
/// `RELAX_MAX_INTERVAL` later), so its temperature is the model's value at
/// the world's time, read without settling it.
fn body_temperature_now(w: &vg_core::world::World, e: vg_core::entity::EntityId, body: &HeatBody) -> f64 {
    if !body.relax {
        return body.temperature();
    }
    let Some((kind, coupling_e)) = COUPLINGS.with(|c| c.borrow().get(&(e.index(), 0)).copied()) else {
        return body.temperature();
    };
    let conductance = match kind {
        0 => w.read::<SolidCoupling>(coupling_e).map(|c| c.conductance),
        1 => w.read::<GasCoupling>(coupling_e).map(|c| c.conductance),
        2 => w.read::<BodyCoupling>(coupling_e).map(|c| c.conductance),
        _ => None,
    };
    conductance.map_or_else(|| body.temperature(), |g| vg_heat::laws::relax_temperature_at(body, g, w.now()))
}

#[auxmacros::bind("/proc/heat_body_add")]
fn heat_body_add(h: ByondValue, joules: ByondValue) -> Result<ByondValue> {
    let joules = f64::from(num(&joules)?);
    let Some(e) = body(&h)? else {
        return Ok(false.into());
    };
    note_reserved(e, |r| r.added += joules);
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
fn heat_body_couple(
    h: ByondValue,
    slot: ByondValue,
    target_kind: ByondValue,
    target_ref: ByondValue,
    conductance: ByondValue,
) -> Result<ByondValue> {
    let Some(e) = body(&h)? else {
        return Ok(false.into());
    };
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let slot = num(&slot)?.clamp(0.0, 1.0) as u8;
    if slot == 0 {
        note_reserved(e, |r| r.slot0_set = true);
    }
    #[allow(clippy::cast_possible_truncation)]
    let target_kind = num(&target_kind)? as i32;
    set_coupling(e, slot, target_kind, &target_ref, num(&conductance)?)?;
    Ok(true.into())
}

#[auxmacros::bind("/proc/heat_body_power")]
fn heat_body_power(h: ByondValue, watts: ByondValue) -> Result<ByondValue> {
    let watts = f64::from(num(&watts)?);
    let Some(e) = body(&h)? else {
        return Ok(false.into());
    };
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        settle_body_if_relaxing(w, e, &mut b)?;
        b.power = watts;
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        if let Ok(k) = kind_of(w, "HeatBody") {
            let _ = w.wake_row(e, k);
        }
        Ok(ok)
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_capacity")]
fn heat_body_capacity(h: ByondValue, capacity: ByondValue) -> Result<ByondValue> {
    let capacity = f64::from(num(&capacity)?);
    let Some(e) = body(&h)? else {
        return Ok(false.into());
    };
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
fn heat_body_phase(
    h: ByondValue,
    temperature: ByondValue,
    latent: ByondValue,
) -> Result<ByondValue> {
    let (t, l) = (f64::from(num(&temperature)?), f64::from(num(&latent)?));
    let Some(e) = body(&h)? else {
        return Ok(false.into());
    };
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        settle_body_if_relaxing(w, e, &mut b)?;
        let temp = b.temperature();
        b.phase_temperature = t;
        b.phase_latent = l;
        b.energy = f64::from(vg_core::thermo::phase_energy(
            temp as f32,
            b.capacity as f32,
            b.phase(),
        ));
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_set_temperature")]
fn heat_body_set_temperature(h: ByondValue, temperature: ByondValue) -> Result<ByondValue> {
    let t = f64::from(num(&temperature)?.max(vg_heat::consts::TCMB));
    let Some(e) = body(&h)? else {
        return Ok(false.into());
    };
    note_reserved(e, |r| r.temperature_set = true);
    let ok = with_world(|w| {
        let Some(mut b) = w.read::<HeatBody>(e) else {
            return Ok(false);
        };
        // DM authority: the new temperature replaces whatever the model
        // was doing, so this clears `relax` outright instead of settling
        // first (settling would just be overwritten immediately after).
        b.relax = false;
        b.energy = f64::from(vg_core::thermo::phase_energy(
            t as f32,
            b.capacity as f32,
            b.phase(),
        ));
        let ok = w.put(e, b).is_ok();
        wake_body_couplings(w, e.index());
        Ok(ok)
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/heat_body_keep")]
fn heat_body_keep(h: ByondValue, keep: ByondValue) -> Result<ByondValue> {
    let keep = keep.is_true();
    let Some(e) = body(&h)? else {
        return Ok(false.into());
    };
    note_reserved(e, |r| r.keep_set = true);
    let ok = with_world(|w| {
        let ok = w
            .set(
                e,
                kind_of(w, "HeatBody")?,
                field_id::<HeatBody>("keep")?,
                None,
                if keep { 1.0 } else { 0.0 },
            )
            .is_ok();
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
        RESERVED.with_borrow_mut(|r| r.remove(&e.index()));
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

/// Batched destroy's one heat release (`doc/rewrite/init_and_turfs.md`
/// §4.4 step 4): [`heat_body_release`] for every handle in `bodies`.
/// Zero/null and already-released entries are skipped.
#[auxmacros::bind("/proc/heat_body_release_list")]
fn heat_body_release_list(bodies: ByondValue) -> Result<ByondValue> {
    for h in bodies.get_list_values()? {
        heat_body_release(h)?;
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
    let Some(&(kind, coupling_e)) = COUPLINGS
        .with(|c| c.borrow().get(&(e.index(), 0)).copied())
        .as_ref()
    else {
        return Ok(());
    };
    match kind {
        0 => {
            if let Some(coupling) = w.read::<SolidCoupling>(coupling_e) {
                let field = field()?;
                if let (Some(g), Some(cell)) = (
                    w.sim_mut().port(field.geometry).read(coupling.cell),
                    w.sim_mut().port(field.cells).read(coupling.cell),
                ) {
                    let baseline_t = if g.reservoir {
                        cell.temperature
                    } else {
                        cell.temperature_in(g.capacity)
                    };
                    #[allow(clippy::cast_possible_truncation)]
                    let baseline = f64::from(
                        vg_core::thermo::phase_energy(baseline_t, b.capacity as f32, b.phase())
                            .max(0.0),
                    );
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
                if let Some(t) = (coupling.kind == gas_kind::TURF)
                    .then(|| turf_gas_temperature(w, coupling.target))
                    .flatten()
                {
                    #[allow(clippy::cast_possible_truncation)]
                    let baseline = f64::from(
                        vg_core::thermo::phase_energy(t, b.capacity as f32, b.phase()).max(0.0),
                    );
                    turf_gas_heat(w, coupling.target, b.energy - baseline);
                }
            }
        }
        2 => {
            if let Some(coupling) = w.read::<BodyCoupling>(coupling_e) {
                let other_e = vg_core::entity::EntityId::from_bits(coupling.other).unwrap_or(e);
                if let Some(mut other) = w.read::<HeatBody>(other_e) {
                    #[allow(clippy::cast_possible_truncation)]
                    let baseline = f64::from(
                        vg_core::thermo::phase_energy(
                            other.temperature() as f32,
                            b.capacity as f32,
                            b.phase(),
                        )
                        .max(0.0),
                    );
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
    let Some(e) = body(&h)? else {
        return Ok(0.0f32.into());
    };
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
    // Peeked, not drained: the events are DM's (`vg_world_events`).
    let settled: Vec<vg_core::entity::EntityId> = w
        .events()
        .decoded::<vg_heat::laws::HeatEvent>()
        .filter_map(|(entity_v, e)| {
            matches!(e, vg_heat::laws::HeatEvent::Settled)
                .then(|| entity::decode(entity_v).ok())
                .flatten()
        })
        .filter_map(|coupling_e| {
            COUPLING_BODY.with(|c| c.borrow().get(&coupling_e.index()).copied())
        })
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
#[allow(dead_code)] // a DM define only
pub const HEAT_WATCH_ABOVE: i32 = 0;
/// @dm-define HEAT_WATCH_BELOW
#[allow(dead_code)] // a DM define only
pub const HEAT_WATCH_BELOW: i32 = 1;
/// @dm-define HEAT_WATCH_BAND
#[allow(dead_code)] // a DM define only
pub const HEAT_WATCH_BAND: i32 = 2;
/// @dm-define HEAT_WATCH_SET
#[allow(dead_code)] // a DM define only
pub const HEAT_WATCH_SET: i32 = 3;

/// The turf solid's cells as a watch port: code [`HEAT_CELLS`], every cell a
/// turf ref (a `get_ref()` number). Body watches use the ordinary world
/// kind port; both go through the generic `vg_world_watch_*` binds.
/// @dm-define VG_HEAT_CELLS
pub const HEAT_CELLS: u32 = 0x0FFE;

/// The solid field's watch port in the domain registry.
pub(crate) struct HeatCells;

impl vg_core::registry::DomainRegistry for HeatCells {
    fn channels(&self) -> Vec<vg_core::channel::ChannelInfo> {
        with_world(|w| w.cell_channels::<SolidHeat>().map_err(|e| eyre!("{e}"))).unwrap_or_default()
    }

    fn watch(&mut self, sub: Subscriber, lane: Lane, cond: &Cond) -> Result<(u8, WatchId), String> {
        with_world(|w| {
            w.watch_cells::<SolidHeat>(sub, lane, cond)
                .map_err(|e| eyre!("{e}"))
        })
        .map(|id| (0, id))
        .map_err(|e| e.to_string())
    }

    fn unwatch(&mut self, _port: u8, id: WatchId) {
        let _ = with_world(|w| Ok(w.unwatch_cells::<SolidHeat>(id)));
    }

    fn add_entry(&mut self, _port: u8, id: WatchId, entry: SetEntry) -> Result<(), String> {
        with_world(|w| {
            w.add_field_watch_entry::<SolidHeat>(id, entry)
                .map_err(|e| eyre!("{e}"))
        })
        .map_err(|e| e.to_string())
    }

    fn remove_entry(&mut self, _port: u8, id: WatchId, payload: u32) {
        let _ = with_world(|w| Ok(w.remove_field_watch_entry::<SolidHeat>(id, payload)));
    }

    /// Cell watch wakes, the source the cell's ref (low 24 bits).
    fn take_wakes(&mut self, out: &mut Vec<Wake>) {
        let _ = with_world(|w| {
            let mut wakes = Vec::new();
            w.drain_field_wakes::<SolidHeat>(&mut wakes);
            out.extend(wakes.into_iter().map(|wk| Wake {
                source: wk.source & 0x00ff_ffff,
                ..wk
            }));
            Ok(())
        });
    }
}

/// Takes every `ThresholdSet` crossing since the last call as
/// `(subscriber, payload, entered, generation)`, then retires the bodies
/// whose couplings settled. `owners` maps a watch table index to its
/// subscriber (from the wakes drained in the same frame: every crossing also
/// wakes its watch). The frame calls this before it takes the world's events
/// (settling is read off them).
pub(crate) fn take_crossings(
    owners: &HashMap<u32, Subscriber>,
) -> Result<Vec<(Subscriber, u32, bool, u32)>> {
    with_world(|w| {
        let mut out = Vec::new();
        for c in w.drain_threshold_crossings() {
            let Some(&sub) = owners.get(&c.watch) else {
                continue;
            };
            out.push((sub, c.payload, c.entered, c.generation));
        }
        drain_settled_bodies(w);
        Ok(out)
    })
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
    crate::heat_net::reset();
    Ok(ByondValue::null())
}

/// A turf's gas temperature (turf-air couplings), if it has gas.
fn turf_gas_temperature(w: &vg_core::world::World, cell: u32) -> Option<f32> {
    use vg_core::thermo::Thermal;
    let key = crate::gas::turf_key().ok()?;
    let (gas, geom) = crate::gas::turf_read(w, key, cell)?;
    geom.is_node().then(|| gas.thermal(geom.capacity).0)
}

/// Adds `joules` to a turf's gas (a released body's excess), as a command.
fn turf_gas_heat(w: &mut vg_core::world::World, cell: u32, joules: f64) {
    let Ok(key) = crate::gas::turf_key() else {
        return;
    };
    let mut d = [0.0f32; vg_gas::cell::Q];
    #[allow(clippy::cast_possible_truncation)]
    {
        d[vg_gas::cell::N] = joules as f32;
    }
    if joules != 0.0 {
        let _ = w.submit_cell(key, cell, vg_gas::cell::GasCmd::Delta(d));
    }
}

/// The mixture a [`GasCoupling::probe_key`] names: an arena mixture by id, or the pipe region a port (a packed entity id with
/// [`gas_kind::PORT_KEY`] set) is in now.
pub(crate) fn probe_mixture(w: &vg_core::world::World, key: u32) -> Option<crate::gas::mix::MixRef> {
    if key & gas_kind::PORT_KEY == 0 {
        return crate::gas::mix::MixRef::from_id(key);
    }
    crate::pipes::port_mixture(w, key & !gas_kind::PORT_KEY)
}

/// Every gas mixture a heat body couples to, as the exchange law reads it
/// (`vg_heat::laws::MixtureProbes`). Loads mixtures, so call it outside the
/// world borrow.
pub(crate) fn mixture_probes() -> vg_heat::laws::MixtureProbes {
    // A coupling's key resolves to its mixture here, so a pipeline's port coupling is read from the region the port is in
    // now (after any merge or split), not from where it once was.
    let targets: Vec<(u32, Option<crate::gas::mix::MixRef>)> = with_world(|w| {
        Ok(w.entities_with::<GasCoupling>()
            .into_iter()
            .filter_map(|e| w.read::<GasCoupling>(e))
            .filter(|c| c.kind != gas_kind::TURF)
            .map(|c| (c.probe_key(), probe_mixture(w, c.probe_key())))
            .collect())
    })
    .unwrap_or_default();
    let mut probes: Vec<(u32, f32, f32, bool)> = targets
        .into_iter()
        .filter_map(|(key, mixture)| {
            let m = crate::gas::mix::load(mixture?)?;
            Some((key, m.get_temperature(), m.heat_capacity(), m.is_immutable()))
        })
        .collect();
    probes.sort_unstable_by_key(|p| p.0);
    probes.dedup_by_key(|p| p.0);
    vg_heat::laws::MixtureProbes(probes)
}

/// Applies the heat bodies moved into gas mixtures (`HeatEvent::MixtureHeat`
/// in `events`). Call it outside the world borrow.
pub(crate) fn apply_mixture_heat(events: &vg_core::event::EventSink) {
    for (_, e) in events.decoded::<vg_heat::laws::HeatEvent>() {
        let (key, joules) = match e {
            vg_heat::laws::HeatEvent::MixtureHeat { target, joules } => (target, joules),
            vg_heat::laws::HeatEvent::PortHeat { port, joules } => (gas_kind::PORT_KEY | port, joules),
            vg_heat::laws::HeatEvent::Settled => continue,
        };
        if let Some(r) = with_world(|w| Ok(probe_mixture(w, key))).ok().flatten() {
            let mut d = [0.0f32; vg_gas::cell::Q];
            d[vg_gas::cell::N] = joules;
            crate::gas::mix::add_amounts(r, &d, 0.0);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gas::mix::{self, MixRef};
    use vg_core::watch::{Cmp, Edge};

    /// A pipeline's persistent coupling names a port, so the gas it heats is always that of the region the port is in now.
    #[test]
    fn a_pipeline_port_coupling_follows_its_region_through_merge_and_split() {
        use vg_gas::pipes::{PipeGas, Pipes};
        with_world(|_| Ok(())).unwrap();
        let (a, b, body) = with_world(|w| {
            // Burn some entity slots first: a port whose id is not tiny is what the event's f32 wire must carry exactly.
            for _ in 0..5_000 {
                let _ = w.entities_mut().bind().unwrap();
            }
            let a = w.entities_mut().bind().unwrap();
            let b = w.entities_mut().bind().unwrap();
            let mut gas = PipeGas::default();
            gas.moles[vg_gas::gas::ids::GAS_OXYGEN] = 50.0;
            gas.energy = 50.0 * 20.0 * 280.0;
            w.edit_network::<Pipes>(move |host| {
                let _ = host.bind_node(a, 0, 0, 100.0);
                let _ = host.bind_node(b, 0, 0, 100.0);
                let region = host.region_of(a).expect("bound");
                let _ = host.set_payload(region, gas);
            })
            .map_err(|e| eyre!("{e}"))?;
            w.commit_network::<Pipes>();
            let body = w
                .bind_value(
                    None,
                    HeatBody {
                        capacity: 1_000.0,
                        energy: 1_000.0 * 600.0,
                        ..Default::default()
                    },
                )
                .map_err(|e| eyre!("{e}"))?;
            w.bind_value(
                None,
                GasCoupling {
                    body: body.index(),
                    kind: gas_kind::PIPE_PORT,
                    target: a.bits(),
                    conductance: 5.0,
                    slot: 1,
                },
            )
            .map_err(|e| eyre!("{e}"))?;
            Ok((a, b, body))
        })
        .unwrap();
        let key = gas_kind::PORT_KEY | a.bits();
        let resolve = |e: vg_core::entity::EntityId| with_world(|w| Ok(probe_mixture(w, gas_kind::PORT_KEY | e.bits()))).unwrap();
        let apart = (resolve(a).expect("a is in a region"), resolve(b).expect("b is in a region"));
        assert_ne!(apart.0, apart.1, "two ports, two pipelines");

        // Merge: the coupling resolves to the one surviving region, the same as the other port's.
        with_world(|w| {
            w.edit_network::<Pipes>(move |host| host.connect_entities(a, b).unwrap())
                .map_err(|e| eyre!("{e}"))?;
            w.commit_network::<Pipes>();
            Ok(())
        })
        .unwrap();
        assert_eq!(resolve(a), resolve(b), "merged: the coupling follows the surviving region");
        assert!(mix::load(resolve(a).unwrap()).unwrap().total_moles() > 49.0, "and its gas is the merged pipeline's");

        // Split: the coupling stays with the port's side; the other port is alone again.
        with_world(|w| {
            w.edit_network::<Pipes>(move |host| host.disconnect_entities(a, b))
                .map_err(|e| eyre!("{e}"))?;
            w.commit_network::<Pipes>();
            Ok(())
        })
        .unwrap();
        assert_ne!(resolve(a), resolve(b), "split: two pipelines again");

        // The exchange heats the gas of the region the port is in now.
        let before = mix::load(resolve(a).unwrap()).unwrap().get_temperature();
        for _ in 0..10 {
            let probes = mixture_probes();
            assert!(probes.0.iter().any(|p| p.0 == key), "the port's coupling is probed under its key");
            let events = with_world(|w| {
                w.set_global(probes).map_err(|e| eyre!("{e}"))?;
                w.step_blocking();
                Ok(w.drain_events())
            })
            .unwrap();
            apply_mixture_heat(&events);
        }
        let after = mix::load(resolve(a).unwrap()).unwrap().get_temperature();
        assert!(after > before + 1.0, "the hot body warmed the pipeline: {before} -> {after}");
        let _ = body;
    }

    #[test]
    fn a_body_warms_a_tank() {
        with_world(|_| Ok(())).unwrap();
        let mut tank = vg_gas::gas::Mixture::from_vol(70.0);
        tank.set_moles(0, 10.0);
        tank.set_temperature(280.0);
        let r = MixRef::Main(mix::alloc(tank).unwrap());
        with_world(|w| {
            let body = w
                .bind_value(
                    None,
                    HeatBody {
                        capacity: 1_000.0,
                        energy: 1_000.0 * 400.0,
                        ..Default::default()
                    },
                )
                .map_err(|e| eyre!("{e}"))?;
            w.bind_value(
                None,
                GasCoupling {
                    body: body.index(),
                    kind: gas_kind::MIXTURE,
                    target: r.id(),
                    conductance: 5.0,
                    slot: 1,
                },
            )
            .map_err(|e| eyre!("{e}"))?;
            Ok(())
        })
        .unwrap();
        for _ in 0..10 {
            let probes = mixture_probes();
            let events = with_world(|w| {
                w.set_global(probes).map_err(|e| eyre!("{e}"))?;
                w.step_blocking();
                Ok(w.drain_events())
            })
            .unwrap();
            apply_mixture_heat(&events);
        }
        let t = mix::load(r).unwrap().get_temperature();
        assert!(t > 281.0, "the tank warmed: {t}");
    }

    fn body_at(w: &mut vg_core::world::World, t: f64, power: f64) -> vg_core::entity::EntityId {
        w.bind_value(
            None,
            HeatBody {
                capacity: 1_000.0,
                energy: 1_000.0 * t,
                power,
                keep: true,
                ..Default::default()
            },
        )
        .unwrap()
    }

    fn set_temp(w: &mut vg_core::world::World, e: vg_core::entity::EntityId, t: f64) {
        let mut b = w.read::<HeatBody>(e).unwrap();
        b.relax = false;
        b.energy = 1_000.0 * t;
        w.put(e, b).unwrap();
        wake_body_couplings(w, e.index());
    }

    fn channel_of(
        chans: &[vg_core::channel::ChannelInfo],
        name: &str,
    ) -> Result<vg_core::channel::ChannelId> {
        #[allow(clippy::cast_possible_truncation)]
        chans
            .iter()
            .position(|c| c.name == name)
            .map(|i| vg_core::channel::ChannelId(i as u8))
            .ok_or_else(|| eyre!("no {name} channel"))
    }

    #[test]
    fn a_body_watch_set_sees_a_dm_temperature_write() {
        let crossings = with_world(|w| {
            let e = body_at(w, 300.0, 0.0);
            let kind_id = kind_of(w, "HeatBody")?;
            let chans = w.channels(kind_id).map_err(|e| eyre!("{e}"))?;
            let ch = channel_of(&chans, "temperature")?;
            let id = w
                .watch(
                    kind_id,
                    7,
                    Lane::Normal,
                    &Cond::ThresholdSet {
                        cell: e.index(),
                        ch,
                    },
                )
                .map_err(|e| eyre!("{e}"))?;
            w.add_watch_entry(
                kind_id,
                id,
                SetEntry {
                    payload: 3,
                    generation: 1,
                    cmp: Cmp::Above,
                    limit: vg_core::channel::Quantity::new(320.0, vg_core::channel::Unit::Kelvin),
                    hysteresis: None,
                    edge: Edge::Enter,
                },
            )
            .map_err(|e| eyre!("{e}"))?;
            w.step_blocking();
            let _ = w.drain_threshold_crossings();
            set_temp(w, e, 330.0);
            w.step_blocking();
            Ok(w.drain_threshold_crossings())
        })
        .unwrap();
        assert_eq!(crossings.len(), 1, "{crossings:?}");
    }

    #[test]
    fn reserved_handles_are_live_distinct_and_usable_at_once() {
        let (bodies, reads) = with_world(|w| {
            let bodies = reserve_bodies(w, 4)?;
            let reads: Vec<_> = bodies.iter().map(|&e| w.read::<HeatBody>(e)).collect();
            Ok((bodies, reads))
        })
        .unwrap();
        let mut indices: Vec<_> = bodies.iter().map(|e| e.index()).collect();
        indices.sort_unstable();
        indices.dedup();
        assert_eq!(indices.len(), 4, "distinct: {bodies:?}");
        for (e, read) in bodies.iter().zip(reads) {
            let b = read.expect("a reserved handle is a live body");
            assert!(b.keep, "a reserved body is kept until configured");
            assert!(is_reserved(*e));
            // The handle round-trips through DM's number form.
            assert_eq!(entity::decode(entity::entity_value(*e)).unwrap(), *e);
        }
    }

    #[test]
    fn configure_applies_the_spec_but_keeps_writes_made_in_between() {
        let (plain_b, written_b, outcome, still_reserved) = with_world(|w| {
            let bodies = reserve_bodies(w, 2)?;
            let (plain, written) = (bodies[0], bodies[1]);
            // DM used `written` at once: kept it off, coupled slot 0, set 350 K.
            note_reserved(written, |r| {
                r.temperature_set = true;
                r.keep_set = true;
                r.slot0_set = true;
            });
            let mut b = w.read::<HeatBody>(written).unwrap();
            b.keep = false;
            b.energy = 350.0; // capacity 1: 350 K
            w.put(written, b).unwrap();
            let outcome = configure_bodies(
                w,
                &[
                    BodySpec {
                        e: plain,
                        capacity: 500.0,
                        temperature: 290.0,
                        keep: false,
                    },
                    BodySpec {
                        e: written,
                        capacity: 2_000.0,
                        temperature: 290.0,
                        keep: true,
                    },
                ],
            );
            let still_reserved = is_reserved(plain) || is_reserved(written);
            Ok((
                w.read::<HeatBody>(plain).unwrap(),
                w.read::<HeatBody>(written).unwrap(),
                outcome,
                still_reserved,
            ))
        })
        .unwrap();
        assert_eq!(outcome, vec![Some(true), Some(false)]);
        assert!((plain_b.capacity - 500.0).abs() < 1e-9);
        assert!((plain_b.energy / plain_b.capacity - 290.0).abs() < 1e-6);
        assert!(!plain_b.keep);
        assert!((written_b.capacity - 2_000.0).abs() < 1e-9);
        assert!(
            (written_b.energy / written_b.capacity - 350.0).abs() < 1e-6,
            "{written_b:?}"
        );
        assert!(!written_b.keep, "an explicit keep write survives configure");
        assert!(!still_reserved);
    }

    #[test]
    fn configure_skips_released_configured_and_foreign_handles() {
        let outcome = with_world(|w| {
            let bodies = reserve_bodies(w, 2)?;
            let foreign = body_at(w, 300.0, 0.0);
            // Released while pending: its handle stops resolving.
            RESERVED.with_borrow_mut(|r| r.remove(&bodies[1].index()));
            let _ = w.despawn(bodies[1]);
            assert!(
                w.read::<HeatBody>(bodies[1]).is_none(),
                "a released handle is dead"
            );
            let spec = |e| BodySpec {
                e,
                capacity: 10.0,
                temperature: 300.0,
                keep: false,
            };
            let first = configure_bodies(w, &[spec(bodies[0]), spec(bodies[1]), spec(foreign)]);
            // Configuring twice is a no-op the second time.
            let second = configure_bodies(w, &[spec(bodies[0])]);
            // A fresh reserve never hands back a handle equal to the dead one.
            let fresh = reserve_bodies(w, 1)?;
            assert_ne!(fresh[0], bodies[1], "a stale handle never names a new body");
            assert!(
                w.read::<HeatBody>(bodies[1]).is_none(),
                "the stale handle stays dead"
            );
            // The foreign body was not touched.
            let f = w.read::<HeatBody>(foreign).unwrap();
            assert!((f.capacity - 1_000.0).abs() < 1e-9);
            Ok((first, second))
        })
        .unwrap();
        assert_eq!(outcome.0, vec![Some(true), None, None]);
        assert_eq!(outcome.1, vec![None]);
    }

    #[test]
    fn added_heat_before_configure_is_kept_on_top() {
        let t = with_world(|w| {
            let e = reserve_bodies(w, 1)?[0];
            note_reserved(e, |r| r.added += 1_000.0);
            configure_bodies(
                w,
                &[BodySpec {
                    e,
                    capacity: 100.0,
                    temperature: 300.0,
                    keep: true,
                }],
            );
            let b = w.read::<HeatBody>(e).unwrap();
            Ok(b.energy / b.capacity)
        })
        .unwrap();
        assert!((t - 310.0).abs() < 1e-6, "{t}");
    }

    #[test]
    fn an_isolated_body_with_power_heats() {
        let (t0, t1) = with_world(|w| {
            let e = body_at(w, 300.0, 1_000.0);
            w.step_blocking();
            let t0 = w.read::<HeatBody>(e).unwrap().energy;
            for _ in 0..5 {
                w.step_blocking();
            }
            Ok((t0, w.read::<HeatBody>(e).unwrap().energy))
        })
        .unwrap();
        // Five 0.5 s steps of 1 kW.
        assert!((t1 - t0 - 2_500.0).abs() < 1.0, "{t0} -> {t1}");
    }
}
