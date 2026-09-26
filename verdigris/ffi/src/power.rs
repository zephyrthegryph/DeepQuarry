//! Binds for `vg-power` (`rust_architecture.md` §6, §8.5): topology only.
//! Every field read/write DM does on a `Producer`/`Apc`/`Smes`/
//! `SmesInputTerminal` row (or `Smes`/`Apc`/`Producer` directly) goes through the generic
//! `vg_component_*` binds in [`crate::world`] -- there is no
//! `PowerHost`, no key table, no hand-encoded event stream. What remains
//! here is what only power's own topology (a cable's shape, a machine
//! node's cell) can't express generically: binding a
//! [`vg_power::kind::Cables`] node, and reading a region's ledger (region
//! payloads are network state, not a component, so
//! [`crate::world::component_get`] can't reach them).
//!
//! DM still names a turf by `(x, y, z)`; [`vg_power::geom::pos`] packs it
//! into the `CellId` `Cables` uses (power does not register a
//! [`vg_core::grid::Grid`], so this is its own address space, not the
//! shared grid's).

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::network::RegionId;
use vg_core::slot::RawHandle;
use vg_power::geom::pos;
use vg_power::kind::{Cables, PowerNode};
use vg_power::{Cable, PowerLedger};

use crate::entity;
use crate::world::{list, num, whole, with_world};

/// Node kinds in the graph (an opaque tag `NetworkHost` stores per node;
/// power does not read it back, only DM's own bookkeeping might).
/// @dm-define POWER_NODE_CABLE
pub const NODE_CABLE: u16 = 0;
/// @dm-define POWER_NODE_MACHINE
pub const NODE_MACHINE: u16 = 1;

fn cell(x: &ByondValue, y: &ByondValue, z: &ByondValue) -> Result<u32> {
    Ok(pos(whole(x, "x")?, whole(y, "y")?, whole(z, "z")?))
}

/// Binds (or rebinds) `entity`'s node as a cable piece: `shape` is
/// `[x, y, z, d1, d2, up, down, link]`. `entity` `0`: mints a new one (a
/// cable has no component of its own). Returns the entity handle.
#[auxmacros::bind("/proc/vg_power_bind_cable")]
fn power_bind_cable(entity: ByondValue, shape: ByondValue) -> Result<ByondValue> {
    let v = shape.get_list_values()?;
    let [x, y, z, d1, d2, up, down, link] = v.as_slice() else {
        bail!("shape must be [x, y, z, d1, d2, up, down, link]");
    };
    let e = entity::bind_or_reuse(num(&entity)?)?;
    let p = cell(x, y, z)?;
    let data = Cable {
        d1: whole(d1, "d1")? as u8,
        d2: whole(d2, "d2")? as u8,
        up: whole(up, "up")?,
        down: whole(down, "down")?,
        link: whole(link, "link")?,
    };
    with_world(|w| {
        w.edit_network::<Cables>(move |host| {
            let _ = host.bind_node(e, p, NODE_CABLE, PowerNode::Cable(data));
        })
        .map_err(|err| eyre!("{err}"))
    })?;
    Ok(ByondValue::from(entity::entity_value(e)))
}

/// Binds (or rebinds) `entity`'s node as a plain machine terminal at
/// `(x, y, z)`: a producer, an APC's own area terminal, or one of a SMES's
/// two terminals. `entity` must already exist (a `vg_component_bind` on
/// the matching component) -- unlike a cable, a machine terminal is never
/// topology-only.
#[auxmacros::bind("/proc/vg_power_bind_machine")]
fn power_bind_machine(entity: ByondValue, x: ByondValue, y: ByondValue, z: ByondValue) -> Result<ByondValue> {
    let e = entity::decode(num(&entity)?)?;
    let p = cell(&x, &y, &z)?;
    with_world(|w| {
        w.edit_network::<Cables>(move |host| {
            let _ = host.bind_node(e, p, NODE_MACHINE, PowerNode::Machine);
        })
        .map_err(|err| eyre!("{err}"))
    })?;
    Ok(entity)
}

/// Drops `entity`'s cable/machine node (the entity and any component it
/// holds are untouched; `entity_unbind`/`vg_component_detach` handle
/// those).
#[auxmacros::bind("/proc/vg_power_unbind_node")]
fn power_unbind_node(entity: ByondValue) -> Result<ByondValue> {
    let e = entity::decode(num(&entity)?)?;
    with_world(|w| {
        w.edit_network::<Cables>(move |host| host.unbind_node(e))
            .map_err(|err| eyre!("{err}"))
    })?;
    Ok(ByondValue::null())
}

/// Commits pending topology now, instead of at the next `vg_world_tick`
/// (an explosion or a construction burst wants its region split/merge
/// reflected before the next machinery tick reads it).
#[auxmacros::bind("/proc/vg_power_commit")]
fn power_commit() -> Result<ByondValue> {
    with_world(|w| {
        w.commit_network::<Cables>();
        Ok(())
    })?;
    Ok(ByondValue::null())
}

/// `entity`'s region, `0` if it has none (never a runtime): a raw handle
/// plus one (`0` is DM's null), stable until the node's region changes.
#[auxmacros::bind("/proc/vg_power_region_of")]
fn power_region_of(entity: ByondValue) -> Result<ByondValue> {
    let Ok(e) = entity::decode(num(&entity)?) else {
        return Ok(ByondValue::from(0.0f32));
    };
    #[allow(clippy::cast_precision_loss)]
    let id = with_world(|w| {
        let host = w.network::<Cables>().map_err(|err| eyre!("{err}"))?;
        Ok(host.region_of(e).map_or(0, |r| r.raw().bits() + 1))
    })? as f32;
    Ok(ByondValue::from(id))
}

fn region_id(raw: u32) -> Result<RegionId<Cables>> {
    if raw == 0 {
        bail!("region 0 is null");
    }
    RawHandle::from_bits(raw - 1)
        .map(RegionId::<Cables>::from_raw)
        .ok_or_else(|| eyre!("bad region {raw}"))
}

/// A region's ledger: `avail, load, brown` (W, W, 0/1). Everything else
/// (a region's producers, consumers, SMES terminals) DM already knows --
/// it bound them.
#[auxmacros::bind("/proc/vg_power_region_read")]
fn power_region_read(region: ByondValue) -> Result<ByondValue> {
    let r = region_id(whole(&region, "region")?)?;
    let ledger: PowerLedger = with_world(|w| {
        let host = w.network::<Cables>().map_err(|err| eyre!("{err}"))?;
        host.network().region(r).map(|reg| *reg.payload()).map_err(|err| eyre!("{err}"))
    })?;
    list([ledger.avail, ledger.load, f64::from(u8::from(ledger.brown))].map(|v: f64| v as f32))
}

/// Every entity with a node on `region` (the material power overlay's cable
/// enumeration, `powernet.dm`'s `rebuild_material_cache()`).
#[auxmacros::bind("/proc/vg_power_region_members")]
fn power_region_members(region: ByondValue) -> Result<ByondValue> {
    let r = region_id(whole(&region, "region")?)?;
    let members = with_world(|w| {
        let host = w.network::<Cables>().map_err(|err| eyre!("{err}"))?;
        Ok(host.members(r))
    })?;
    list(members.into_iter().map(entity::entity_value))
}

/// A mid-tick draw against `region`'s ledger, outside the normal
/// `ApcTick`/`PowerBalance` pass (the material power overlay paying its
/// resistive loss from the grid, `powernet.dm`'s `draw_power()`). Returns
/// what was delivered (never more than the region's remaining surplus).
#[auxmacros::bind("/proc/vg_power_region_draw")]
fn power_region_draw(region: ByondValue, watts: ByondValue) -> Result<ByondValue> {
    let r = region_id(whole(&region, "region")?)?;
    let amount = f64::from(num(&watts)?);
    let drawn = std::sync::Arc::new(std::sync::Mutex::new(0.0_f64));
    let out = drawn.clone();
    with_world(|w| {
        w.edit_network::<Cables>(move |host| {
            if let Ok(payload) = host.payload_mut(r) {
                let d = amount.min(payload.avail - payload.load).max(0.0);
                payload.load += d;
                *out.lock().expect("not poisoned") = d;
            }
        })
        .map_err(|err| eyre!("{err}"))
    })?;
    #[allow(clippy::cast_possible_truncation)]
    let d = *drawn.lock().expect("not poisoned") as f32;
    Ok(ByondValue::from(d))
}
