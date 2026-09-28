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
//! DM still names a turf by `(x, y, z)`; [`pos`] packs it into the
//! `CellId` `Cables` uses, and a cable's reach (the cells its directions
//! lead to, following DM's explicit z links) is computed here at bind.

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::grid::Dir;
use vg_core::network::RegionId;
use vg_core::slot::RawHandle;
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

const XY_BITS: u32 = 10;
const XY_MASK: u32 = (1 << XY_BITS) - 1;

/// A turf, packed `z << 20 | y << 10 | x` (x, y below 1024).
const fn pos(x: u32, y: u32, z: u32) -> u32 {
    (z << (2 * XY_BITS)) | ((y & XY_MASK) << XY_BITS) | (x & XY_MASK)
}

/// `get_zstep(p, dir)`: `up`/`down` are the z-levels above and below `p`'s
/// z (0: none), as DM's `GetAbove`/`GetBelow` report them.
fn step(p: u32, dir: u8, up: u32, down: u32) -> Option<u32> {
    let d = Dir(dir);
    let (x, y, mut z) = (
        i64::from(p & XY_MASK),
        i64::from((p >> XY_BITS) & XY_MASK),
        p >> (2 * XY_BITS),
    );
    let x = x + i64::from(d.contains(vg_core::grid::Face::East))
        - i64::from(d.contains(vg_core::grid::Face::West));
    let y = y + i64::from(d.contains(vg_core::grid::Face::North))
        - i64::from(d.contains(vg_core::grid::Face::South));
    for (face, to) in [
        (vg_core::grid::Face::Up, up),
        (vg_core::grid::Face::Down, down),
    ] {
        if d.contains(face) {
            if to == 0 {
                return None;
            }
            z = to;
        }
    }
    let max = i64::from(XY_MASK);
    if !(1..=max).contains(&x) || !(1..=max).contains(&y) || z == 0 {
        return None;
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    Some(pos(x as u32, y as u32, z))
}

/// The cells a cable at `p` reaches, each with the direction a cable there
/// must have to connect back (a diagonal also reaches its two orthogonal
/// neighbours on the same level).
fn reach(p: u32, d1: u8, d2: u8, up: u32, down: u32) -> Vec<(u32, u8)> {
    let mut out = Vec::with_capacity(4);
    for dir in [d1, d2].into_iter().filter(|&d| d != 0) {
        if let Some(t) = step(p, dir, up, down) {
            out.push((t, Dir(dir).reverse().0));
        }
        if Dir(dir).is_diagonal() {
            for pair in [Dir::NORTH.union(Dir::SOUTH), Dir::EAST.union(Dir::WEST)] {
                if let Some(t) = step(p, dir & pair.0, 0, 0) {
                    out.push((t, dir ^ pair.0));
                }
            }
        }
    }
    out
}

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
    let (d1, d2) = (whole(d1, "d1")? as u8, whole(d2, "d2")? as u8);
    let data = Cable {
        d1,
        d2,
        link: whole(link, "link")?,
        reach: reach(p, d1, d2, whole(up, "up")?, whole(down, "down")?),
    };
    with_world(|w| {
        w.edit_network::<Cables>(move |host| {
            let _ = host.bind_node(e, p, NODE_CABLE, PowerNode::Cable(data));
        })
        .map_err(|err| eyre!("{err}"))
    })?;
    Ok(ByondValue::from(entity::entity_value(e)))
}

/// A map-load chunk's cables in one call (`doc/rewrite/init_and_turfs.md`
/// §3.3 step 4): [`power_bind_cable`] for each piece, in one topology edit.
/// `entities` holds each piece's current handle (`0`: mint one) and `shapes`
/// its `x, y, z, d1, d2, up, down, link`, flattened. Returns the handles in
/// order.
#[auxmacros::bind("/proc/vg_power_bind_cable_list")]
fn power_bind_cable_list(entities: ByondValue, shapes: ByondValue) -> Result<ByondValue> {
    let entities = entities.get_list_values()?;
    let shapes = shapes.get_list_values()?;
    if shapes.len() != entities.len() * 8 {
        bail!("shapes must hold 8 values per entity");
    }
    let mut nodes = Vec::with_capacity(entities.len());
    let mut handles = Vec::with_capacity(entities.len());
    for (entity, shape) in entities.iter().zip(shapes.chunks_exact(8)) {
        let [x, y, z, d1, d2, up, down, link] = shape else {
            unreachable!("chunks_exact(8)");
        };
        let e = entity::bind_or_reuse(num(entity)?)?;
        let p = cell(x, y, z)?;
        let (d1, d2) = (whole(d1, "d1")? as u8, whole(d2, "d2")? as u8);
        let data = Cable {
            d1,
            d2,
            link: whole(link, "link")?,
            reach: reach(p, d1, d2, whole(up, "up")?, whole(down, "down")?),
        };
        nodes.push((e, p, data));
        handles.push(ByondValue::from(entity::entity_value(e)));
    }
    with_world(|w| {
        w.edit_network::<Cables>(move |host| {
            for (e, p, data) in nodes {
                let _ = host.bind_node(e, p, NODE_CABLE, PowerNode::Cable(data));
            }
        })
        .map_err(|err| eyre!("{err}"))
    })?;
    let list = ByondValue::new_list()?;
    list.write_list(&handles)?;
    Ok(list)
}

/// Binds (or rebinds) `entity`'s node as a plain machine terminal at
/// `(x, y, z)`: a producer, an APC's own area terminal, or one of a SMES's
/// two terminals. `entity` must already exist (a `vg_component_bind` on
/// the matching component) -- unlike a cable, a machine terminal is never
/// topology-only.
#[auxmacros::bind("/proc/vg_power_bind_machine")]
fn power_bind_machine(
    entity: ByondValue,
    x: ByondValue,
    y: ByondValue,
    z: ByondValue,
) -> Result<ByondValue> {
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

/// Bulk bind (`doc/rewrite/init_and_turfs.md` sec 4.6): [`power_bind_machine`]
/// for every entity in `entities`, with `coords` its `x, y, z` flattened, in
/// one topology edit. The handles are the machines' existing `vg_entity`s,
/// so nothing is minted. Bad entries (unbound handle, bad cell) are skipped.
/// Returns how many nodes were bound.
#[auxmacros::bind("/proc/vg_power_bind_machine_list")]
fn power_bind_machine_list(entities: ByondValue, coords: ByondValue) -> Result<ByondValue> {
    let entities = entities.get_list_values()?;
    let coords = coords.get_list_values()?;
    if coords.len() != entities.len() * 3 {
        bail!("coords must hold 3 values per entity");
    }
    let mut nodes = Vec::with_capacity(entities.len());
    for (entity, xyz) in entities.iter().zip(coords.chunks_exact(3)) {
        let [x, y, z] = xyz else {
            unreachable!("chunks_exact(3)");
        };
        let (Ok(e), Ok(p)) = (num(entity).and_then(entity::decode), cell(x, y, z)) else {
            continue;
        };
        nodes.push((e, p));
    }
    let count = nodes.len();
    with_world(|w| {
        w.edit_network::<Cables>(move |host| {
            for (e, p) in nodes {
                let _ = host.bind_node(e, p, NODE_MACHINE, PowerNode::Machine);
            }
        })
        .map_err(|err| eyre!("{err}"))
    })?;
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(count as f32))
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

/// Batched destroy's one power release (`doc/rewrite/init_and_turfs.md`
/// §4.4 step 4): drops the node of every entity handle in `entities` in one
/// topology edit. Zero/null or bad entries are skipped.
#[auxmacros::bind("/proc/vg_power_unbind_node_list")]
fn power_unbind_node_list(entities: ByondValue) -> Result<ByondValue> {
    let mut doomed = Vec::new();
    for v in entities.get_list_values()? {
        // Zero/null or bad handles are skipped (the rest still go).
        if let Ok(e) = num(&v).and_then(entity::decode) {
            doomed.push(e);
        }
    }
    if doomed.is_empty() {
        return Ok(ByondValue::null());
    }
    with_world(|w| {
        w.edit_network::<Cables>(move |host| {
            for e in doomed {
                host.unbind_node(e);
            }
        })
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
///
/// `region` names a region as of DM's *last* poll of the node that gave it
/// that id (`vg_power_region_of`, `powernet.dm`'s `power_facade`); a split
/// or merge inside this very step's `vg_power_commit()` can retire that
/// exact region between polls (a merge's smaller side is gone, not
/// renamed -- there is no successor id to redirect to). That is a stale
/// handle, not an error: the caller (`/datum/powernet/refresh()`) already
/// treats "no info" as "nothing to update this step" and every live node
/// re-resolves its *current* region fresh next tick
/// (`power_refresh_network()`), so this returns `null` instead of
/// surfacing a runtime for the one tick the old id is dangling.
///
/// Only [`ArenaError::Stale`] (the slot was freed, maybe reused, since this
/// id was issued -- exactly a split/merge retiring it) is that legitimate
/// case. Every other [`ArenaError`] (`OutOfRange`: `region`'s raw bits never
/// named a region the arena ever allocated; `Full`: not even reachable from
/// a read) means a bad id reached here -- `region_id()` decoding garbage, or
/// a caller passing something that was never a `vg_power_region_of()`
/// result, not a split/merge timing race. Silently returning `null` for
/// that would mask exactly the bind-order bug this function's callers exist
/// to avoid, so it's asserted out in debug builds and still logged in
/// release (never surfaced as a DM runtime -- the caller's "no info this
/// step" handling is still the right recovery either way).
#[auxmacros::bind("/proc/vg_power_region_read")]
fn power_region_read(region: ByondValue) -> Result<ByondValue> {
    let r = region_id(whole(&region, "region")?)?;
    let ledger: Option<PowerLedger> = with_world(|w| {
        let host = w.network::<Cables>().map_err(|err| eyre!("{err}"))?;
        match host.network().region(r) {
            Ok(reg) => Ok(Some(*reg.payload())),
            Err(vg_core::network::NetError::Arena(vg_core::arena::ArenaError::Stale)) => Ok(None),
            Err(vg_core::network::NetError::Arena(bad)) => {
                let msg = format!(
                    "vg_power_region_read: region {r:?} ({bad}, raw handle {region:?}) -- \
                     not a split/merge race, a bad region id reached here"
                );
                debug_assert!(false, "{msg}");
                // Release: surfaced to DM's own runtime log (best-effort, the
                // same channel `ffi/src/gas.rs`'s duplicate-reaction-priority
                // warning uses) instead of silently returning null like the
                // legitimate `Stale` case above -- this is the one path this
                // function must not let go unnoticed.
                let sender = auxcallback::byond_callback_sender();
                drop(sender.try_send(Box::new(move || Err(eyre!("{msg}")))));
                Ok(None)
            }
            Err(err) => Err(eyre!("{err}")),
        }
    })?;
    let Some(ledger) = ledger else {
        return Ok(ByondValue::null());
    };
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
