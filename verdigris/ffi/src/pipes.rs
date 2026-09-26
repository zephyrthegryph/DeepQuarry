//! Binds for `vg-gas`'s pipe network (`rust_architecture.md` §6, §8.5,
//! step 5): pipe regions are a main-owned network on the shared
//! `vg_core::world::World` (`ffi/src/world.rs`'s `register`), not the old
//! hand-rolled `PipeNet` (`domains/gas/src/pipes.rs`, deleted). Topology
//! is one generic bind per operation (upsert/remove/connect/disconnect/
//! commit) instead of a semicolon-encoded batch string DM built up and a
//! bespoke Rust parser decoded; `NetworkHost::connect_entities`/
//! `disconnect_entities` (new in `vg_core`, step 5) replace `Network::
//! connect`/`disconnect`'s direct calls `PipeNet` used to make, since pipes
//! manage their own topology explicitly rather than through
//! `NetworkKind::connects`'s geometric search (cables' own rule).
//!
//! DM's own `code/ATMOSPHERICS/rust_pipenets.dm` keeps its existing proc
//! surface (port ids, device ids, the pending-operation queue, the
//! `pipe_network` compatibility wrappers) unchanged: only its three
//! FFI-facing procs (`rust_apply_pipe_topology`, `rust_commit_pending_
//! devices`, `rust_step_pipe_devices`) now loop over their own queued
//! records calling these per-operation binds instead of one batch call, so
//! none of the ~20 machinery files that call into `rust_pipenets.dm`
//! change at all.
//!
//! Ports and devices are DM's own small integer ids (`rust_pipe_port_ids`/
//! `rust_device_id`), kept as thread-local maps to the `World` entities
//! that actually hold them -- DM never sees a `vg_entity` value for a pipe
//! port or device. A region's DM-facing handle is a compacted slot (not
//! its raw arena bits, which can exceed `vg_gas::world::MixRef::Pipe`'s
//! 21-bit address budget), the one piece of bookkeeping this module keeps
//! that `PipeNet` also needed for the same reason -- not for revision or
//! idle-skip tracking, which `NetworkHost`/`World` already provide
//! generically.
//!
//! Turf<->pipe devices (a vent pump or scrubber) still bridge the pipe
//! network and `vg-gas`'s own turf field, each with its own storage
//! (`rust_architecture.md` step 6 is what turns the turf field into a real
//! `FieldKind` and this into a `RegionCell<Pipes, TurfGas>` device law);
//! for now [`pipe_step_devices`] calls `vg_gas::world::with_world` for the
//! turf side directly, the same cross-crate shape heat's `GasExchange`
//! already uses for the same reason (gas is not on the shared `World`
//! yet).

// vg_pipe_device_set/set_turf's argument count is inherent to the DM call
// convention (an id/two endpoints plus a flow law's four parameters,
// matching the pre-port `rust_device_operation` shape); see
// `ffi/src/reactor.rs`'s file-level allow and its comment for why an
// item-level one doesn't reach the warning (emitted inside
// `::byondapi::bind`'s own macro expansion).
#![allow(clippy::too_many_arguments)]

use std::cell::RefCell;
use std::collections::HashMap;

use byondapi::prelude::*;
use eyre::{Result, eyre};
use vg_core::entity::EntityId;
use vg_core::network::{Endpoint, RegionId, Side};
use vg_core::slot::RawHandle;
use vg_core::world::World;
use vg_gas::device::{self, DeviceParams};
use vg_gas::pipes::{PipeGas, Pipes};
use vg_gas::world::MixRef;

use crate::world::{list, num, whole, with_world};

thread_local! {
    static PORTS: RefCell<HashMap<u32, EntityId>> = RefCell::new(HashMap::new());
    static DEVICES: RefCell<HashMap<u32, EntityId>> = RefCell::new(HashMap::new());
    /// A removed port's gas goes here if DM named a target mixture
    /// (`RUST_PIPE_OP_REMOVE_TO_MIXTURE`'s replacement), read back when its
    /// `Released` event drains at [`pipe_commit`].
    static RELEASE_TARGETS: RefCell<HashMap<u32, MixRef>> = RefCell::new(HashMap::new());
    /// Region raw handle <-> DM-facing compact slot (`MixRef::Pipe`'s
    /// 21-bit budget; a region's raw arena bits can exceed it).
    static REGION_SLOTS: RefCell<SlotTable> = RefCell::new(SlotTable::default());
}

#[derive(Default)]
struct SlotTable {
    slot_of: HashMap<u32, u32>,
    raw_of: Vec<Option<u32>>,
    free: Vec<u32>,
}

impl SlotTable {
    fn slot_for(&mut self, raw: u32) -> u32 {
        if let Some(&s) = self.slot_of.get(&raw) {
            return s;
        }
        let s = self.free.pop().unwrap_or_else(|| {
            self.raw_of.push(None);
            u32::try_from(self.raw_of.len() - 1).unwrap_or(u32::MAX)
        });
        self.raw_of[s as usize] = Some(raw);
        self.slot_of.insert(raw, s);
        s
    }

    fn retire(&mut self, raw: u32) -> Option<u32> {
        let s = self.slot_of.remove(&raw)?;
        self.raw_of[s as usize] = None;
        self.free.push(s);
        Some(s)
    }

    fn raw_slot_of(&self, raw: u32) -> Option<u32> {
        self.slot_of.get(&raw).copied()
    }

    fn raw_of(&self, slot: u32) -> Option<u32> {
        self.raw_of.get(slot as usize).copied().flatten()
    }
}

fn region_of_slot(slot: u32) -> Option<RegionId<Pipes>> {
    let raw = REGION_SLOTS.with(|s| s.borrow().raw_of(slot))?;
    RawHandle::from_bits(raw).map(RegionId::from_raw)
}

/// The [`vg_gas::world::PipeAccess`] bridge (this module's own docs):
/// installed once (`crate::world::build`) so `vg-gas`'s generic
/// `MixRef::Pipe` accessors (`load`/`store`/`revision`, so every existing
/// `/datum/gas_mixture` proc keeps working on a pipe-bound mixture) reach
/// the pipe network this module owns on the shared `World`.
pub struct FfiPipeAccess;

impl vg_gas::world::PipeAccess for FfiPipeAccess {
    fn probe(&self, slot: u32) -> Option<(PipeGas, f64)> {
        let region = region_of_slot(slot)?;
        with_world(|w| -> Result<Option<(PipeGas, f64)>> {
            let Ok(host) = w.network::<Pipes>() else { return Ok(None) };
            let Ok(r) = host.network().region(region) else { return Ok(None) };
            Ok(Some((*r.payload(), *r.summary())))
        })
        .ok()
        .flatten()
    }

    fn apply(&self, slot: u32, gas: &PipeGas) {
        let Some(region) = region_of_slot(slot) else { return };
        let gas = *gas;
        let _ = with_world(|w| -> Result<()> {
            let _ = w.edit_network::<Pipes>(move |host| {
                let _ = host.set_payload(region, gas);
            });
            Ok(())
        });
    }

    fn revision(&self, slot: u32) -> u32 {
        let Some(region) = region_of_slot(slot) else { return 0 };
        #[allow(clippy::cast_possible_truncation)]
        with_world(|w| -> Result<u32> { Ok(w.network::<Pipes>().map(|h| h.region_revision(region) as u32).unwrap_or(0)) }).unwrap_or(0)
    }
}

fn port_entity(port_id: u32) -> Option<EntityId> {
    PORTS.with(|p| p.borrow().get(&port_id).copied())
}

/// Adds a port holding the gas from `mixture_handle` (a `datum/gas_mixture`
/// handle; `0`/invalid: empty), or changes its volume if it already exists.
/// Mints a fresh entity for a new port. Returns whether it succeeded.
#[auxmacros::bind("/proc/vg_pipe_upsert")]
fn pipe_upsert(port_id: ByondValue, mixture_handle: ByondValue, volume: ByondValue) -> Result<ByondValue> {
    let port_id = whole(&port_id, "port_id")?;
    let volume = num(&volume)?;
    let fresh = port_entity(port_id).is_none();
    let gas = if fresh {
        gas_from_handle(&mixture_handle)
    } else {
        PipeGas::default()
    };
    let ok = with_world(|w| {
        let e = if let Some(e) = port_entity(port_id) {
            e
        } else {
            let e = w.entities_mut().bind().map_err(|e| eyre!("{e}"))?;
            PORTS.with(|p| p.borrow_mut().insert(port_id, e));
            e
        };
        w.edit_network::<Pipes>(move |host| {
            if host.node_of(e).is_some() {
                let _ = host.set_node_data(e, volume);
            } else {
                let _ = host.bind_node(e, 0, 0, volume);
            }
        })
        .map_err(|e| eyre!("{e}"))?;
        let ok = true;
        if ok && fresh {
            w.edit_network::<Pipes>(move |host| {
                if let Some(region) = host.region_of(e)
                    && let Ok(payload) = host.payload_mut(region)
                {
                    *payload = gas;
                }
            })
            .map_err(|e| eyre!("{e}"))?;
        }
        Ok(ok)
    })?;
    Ok(ok.into())
}

fn gas_from_handle(handle: &ByondValue) -> PipeGas {
    let Some(mix_ref) = num(handle).ok().and_then(MixRef::from_f32) else {
        return PipeGas::default();
    };
    vg_gas::world::with_world(|gw| {
        let Some(mix) = gw.load(mix_ref) else {
            return PipeGas::default();
        };
        PipeGas::from_amounts(&vg_gas::world::amounts_of(&mix), mix.get_temperature())
    })
}

/// Removes a port; its gas share is released, to `mixture_handle` if given
/// (else discarded -- `RUST_PIPE_OP_REMOVE`/`REMOVE_TO_MIXTURE`).
#[auxmacros::bind("/proc/vg_pipe_remove")]
fn pipe_remove(port_id: ByondValue, mixture_handle: ByondValue) -> Result<ByondValue> {
    let port_id = whole(&port_id, "port_id")?;
    let Some(e) = PORTS.with(|p| p.borrow_mut().remove(&port_id)) else {
        return Ok(false.into());
    };
    if let Some(target) = num(&mixture_handle).ok().and_then(MixRef::from_f32) {
        RELEASE_TARGETS.with(|r| r.borrow_mut().insert(port_id, target));
    }
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| host.unbind_node(e)).map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })
    .map(ByondValue::from)
}

/// Connects two ports' nodes directly (`NetworkHost::connect_entities`,
/// bypassing any geometric connection rule -- pipes manage topology
/// explicitly).
#[auxmacros::bind("/proc/vg_pipe_connect")]
fn pipe_connect(port_a: ByondValue, port_b: ByondValue) -> Result<ByondValue> {
    let (a, b) = (whole(&port_a, "port_a")?, whole(&port_b, "port_b")?);
    let (Some(ea), Some(eb)) = (port_entity(a), port_entity(b)) else {
        return Ok(false.into());
    };
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            let _ = host.connect_entities(ea, eb);
        })
        .map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })
    .map(ByondValue::from)
}

#[auxmacros::bind("/proc/vg_pipe_disconnect")]
fn pipe_disconnect(port_a: ByondValue, port_b: ByondValue) -> Result<ByondValue> {
    let (a, b) = (whole(&port_a, "port_a")?, whole(&port_b, "port_b")?);
    if let (Some(ea), Some(eb)) = (port_entity(a), port_entity(b)) {
        with_world(|w| {
            w.edit_network::<Pipes>(move |host| host.disconnect_entities(ea, eb)).map_err(|e| eyre!("{e}"))?;
            Ok(())
        })?;
    }
    Ok(ByondValue::null())
}

/// Drops every port (a map reload).
#[auxmacros::bind("/proc/vg_pipe_clear")]
fn pipe_clear() -> Result<ByondValue> {
    let ports: Vec<EntityId> = PORTS.with(|p| std::mem::take(&mut *p.borrow_mut()).into_values().collect());
    RELEASE_TARGETS.with(|r| r.borrow_mut().clear());
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            for e in ports {
                host.unbind_node(e);
            }
        })
        .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::null())
}

/// Commits pending topology and returns the regions DM must rebuild, one
/// header per changed or retired region: `region_slot, port_count,
/// prior_count, volume, ports..., prior_region_slots...` (`volume < 0`:
/// the region is gone) -- the exact wire shape `rust_apply_pipe_topology`
/// already parses.
#[auxmacros::bind("/proc/vg_pipe_commit")]
fn pipe_commit() -> Result<ByondValue> {
    with_world(|w| {
        w.commit_network::<Pipes>();
        let releases_cell: std::sync::Arc<std::sync::Mutex<Vec<(EntityId, u32, PipeGas)>>> = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let releases_out = std::sync::Arc::clone(&releases_cell);
        w.edit_network::<Pipes>(move |host| {
            releases_out.lock().expect("not poisoned").extend(host.take_released());
        })
        .map_err(|e| eyre!("{e}"))?;
        let releases = std::mem::take(&mut *releases_cell.lock().expect("not poisoned"));
        for (port_e, _pos, payload) in releases {
            // The port entity is already unbound; recover its DM id (and
            // any release target) from the reverse lookup this module
            // keeps only while the port is live -- `pipe_remove` recorded
            // the target under the *port id*, not the entity, before
            // unbinding. `RELEASE_TARGETS` is small (removed-this-batch
            // ports only) and cleared as it's consumed.
            let port_id = PORTS.with(|p| p.borrow().iter().find(|&(_, &e)| e == port_e).map(|(&id, _)| id));
            let target = port_id.and_then(|id| RELEASE_TARGETS.with(|r| r.borrow_mut().remove(&id)));
            if let Some(target) = target {
                vg_gas::world::with_world(|gw| gw.add_amounts(target, &payload.amounts(), payload.temperature));
            }
        }
        let transitions = w.drain_transitions::<Pipes>();
        let mut out = Vec::new();
        for t in transitions {
            let slot = REGION_SLOTS.with(|s| {
                let mut s = s.borrow_mut();
                if t.retired { s.retire(t.region) } else { Some(s.slot_for(t.region)) }
            });
            let Some(slot) = slot else { continue };
            if t.retired {
                out.extend([slot as f32, 0.0, 0.0, -1.0]);
                continue;
            }
            let vol = region_volume(w, t.region);
            let ports: Vec<f32> = t
                .members
                .iter()
                .filter_map(|&e| PORTS.with(|p| p.borrow().iter().find(|&(_, &pe)| pe == e).map(|(&id, _)| id as f32)))
                .collect();
            let priors: Vec<f32> = t.prior.iter().filter_map(|&raw| REGION_SLOTS.with(|s| s.borrow().raw_slot_of(raw)).map(|s| s as f32)).collect();
            #[allow(clippy::cast_precision_loss)]
            out.extend([slot as f32, ports.len() as f32, priors.len() as f32, vol]);
            out.extend(ports);
            out.extend(priors);
        }
        list(out)
    })
}

fn region_volume(w: &World, raw: u32) -> f32 {
    let Some(r) = RawHandle::from_bits(raw) else { return 0.0 };
    let region = RegionId::<Pipes>::from_raw(r);
    #[allow(clippy::cast_possible_truncation)]
    w.network::<Pipes>().ok().and_then(|h| h.network().region(region).ok().map(|reg| *reg.summary() as f32)).unwrap_or(0.0)
}

/// Registers (or replaces) a region<->region device edge between two
/// ports.
#[auxmacros::bind("/proc/vg_pipe_device_set")]
fn pipe_device_set(id: ByondValue, port_a: ByondValue, port_b: ByondValue, law_kind: ByondValue, p0: ByondValue, p1: ByondValue, p2: ByondValue, p3: ByondValue) -> Result<ByondValue> {
    let id_n = whole(&id, "id")?;
    let (pa, pb) = (whole(&port_a, "port_a")?, whole(&port_b, "port_b")?);
    let (Some(ea), Some(eb)) = (port_entity(pa), port_entity(pb)) else {
        return Ok(false.into());
    };
    let params = device_params(&law_kind, &p0, &p1, &p2, &p3)?;
    let ok = with_world(|w| {
        let old = DEVICES.with(|d| d.borrow().get(&id_n).copied());
        let e = if let Some(e) = old { e } else { w.entities_mut().bind().map_err(|e| eyre!("{e}"))? };
        w.edit_network::<Pipes>(move |host| {
            let _ = host.bind_device(e, ea, eb, 0, params);
        })
        .map_err(|e| eyre!("{e}"))?;
        let ok = true;
        if ok {
            DEVICES.with(|d| d.borrow_mut().insert(id_n, e));
        }
        Ok(ok)
    })?;
    Ok(ok.into())
}

/// Registers (or replaces) a device edge between a port and a turf (a vent
/// pump or scrubber): `turf_mixture_handle` is the turf's gas-mixture
/// handle, not a port id.
#[auxmacros::bind("/proc/vg_pipe_device_set_turf")]
fn pipe_device_set_turf(id: ByondValue, port_a: ByondValue, turf_mixture_handle: ByondValue, law_kind: ByondValue, p0: ByondValue, p1: ByondValue, p2: ByondValue, p3: ByondValue) -> Result<ByondValue> {
    let id_n = whole(&id, "id")?;
    let pa = whole(&port_a, "port_a")?;
    let Some(ea) = port_entity(pa) else {
        return Ok(false.into());
    };
    let Some(MixRef::Turf(cell)) = num(&turf_mixture_handle).ok().and_then(MixRef::from_f32) else {
        return Ok(false.into());
    };
    let params = device_params(&law_kind, &p0, &p1, &p2, &p3)?;
    let ok = with_world(|w| {
        let old = DEVICES.with(|d| d.borrow().get(&id_n).copied());
        let e = if let Some(e) = old { e } else { w.entities_mut().bind().map_err(|e| eyre!("{e}"))? };
        w.edit_network::<Pipes>(move |host| {
            let _ = host.bind_cell_device(e, ea, cell, 0, params);
        })
        .map_err(|e| eyre!("{e}"))?;
        let ok = true;
        if ok {
            DEVICES.with(|d| d.borrow_mut().insert(id_n, e));
        }
        Ok(ok)
    })?;
    Ok(ok.into())
}

fn device_params(law_kind: &ByondValue, p0: &ByondValue, p1: &ByondValue, p2: &ByondValue, p3: &ByondValue) -> Result<DeviceParams> {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let kind = num(law_kind)? as u8;
    Ok(DeviceParams::decode(kind, [num(p0)?, num(p1)?, num(p2)?, num(p3)?]))
}

#[auxmacros::bind("/proc/vg_pipe_device_remove")]
fn pipe_device_remove(id: ByondValue) -> Result<ByondValue> {
    let id_n = whole(&id, "id")?;
    let Some(e) = DEVICES.with(|d| d.borrow_mut().remove(&id_n)) else {
        return Ok(false.into());
    };
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| host.unbind_device(e)).map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })
    .map(ByondValue::from)
}

/// Runs every device edge's flow law once for `dt` seconds -- region<->
/// region edges directly, region<->turf edges (a vent pump/scrubber)
/// through `vg_gas::world`'s turf accessors (this module's own docs) --
/// and returns a flat `id, moles, power_w, target_reached` list per device
/// that had a law set and moved something or drew power.
#[auxmacros::bind("/proc/vg_pipe_step_devices")]
fn pipe_step_devices(dt: ByondValue) -> Result<ByondValue> {
    let dt = num(&dt)?;
    let devices: Vec<(u32, EntityId)> = DEVICES.with(|d| d.borrow().iter().map(|(&id, &e)| (id, e)).collect());
    let mut out = Vec::new();
    with_world(|w| {
        for (id, e) in devices {
            let Ok(host) = w.network::<Pipes>() else { continue };
            let Some(dev_id) = host.device_of(e) else { continue };
            let Ok(dev) = host.network().device(dev_id) else { continue };
            if matches!(dev.data, DeviceParams::None) {
                continue;
            }
            let params = dev.data;
            let (ea, eb) = (dev.a, dev.b);
            drop(host);
            let report = match (ea, eb) {
                (Endpoint::Node(_), Endpoint::Node(_)) => step_region_region(w, e, params, dt),
                (Endpoint::Cell(cell), Endpoint::Node(_)) => step_region_turf(w, e, cell, params, dt, true),
                (Endpoint::Node(_), Endpoint::Cell(cell)) => step_region_turf(w, e, cell, params, dt, false),
                _ => None,
            };
            if let Some(report) = report {
                if report.moles != 0.0 || report.power_w != 0.0 {
                    out.extend([id as f32, report.moles as f32, report.power_w, if report.target_reached { 1.0 } else { 0.0 }]);
                }
            }
        }
        list(out)
    })
}

fn step_region_region(w: &mut World, device_e: EntityId, params: DeviceParams, dt: f32) -> Option<device::StepReport> {
    let (ra, rb, vol_a, vol_b, mut pa, mut pb) = {
        let host = w.network::<Pipes>().ok()?;
        let dev_id = host.device_of(device_e)?;
        let dev = host.network().device(dev_id).ok()?;
        let (Endpoint::Node(na), Endpoint::Node(nb)) = (dev.a, dev.b) else { return None };
        let (Side::Region(ra), Side::Region(rb)) = (host.network().resolve(Endpoint::Node(na)), host.network().resolve(Endpoint::Node(nb))) else {
            return None;
        };
        if ra == rb {
            return None;
        }
        let region_a = host.network().region(ra).ok()?;
        let region_b = host.network().region(rb).ok()?;
        (ra, rb, *region_a.summary(), *region_b.summary(), *region_a.payload(), *region_b.payload())
    };
    let report = device::step(&params, &mut pa, vol_a, &mut pb, vol_b, dt);
    if report.moles != 0.0 || report.power_w != 0.0 {
        let _ = w.edit_network::<Pipes>(move |host| {
            if let Ok(p) = host.payload_mut(ra) {
                *p = pa;
            }
            if let Ok(p) = host.payload_mut(rb) {
                *p = pb;
            }
        });
    }
    Some(report)
}

fn step_region_turf(w: &mut World, device_e: EntityId, cell: u32, params: DeviceParams, dt: f32, cell_is_a: bool) -> Option<device::StepReport> {
    let (region, vol_region, mut region_gas) = {
        let host = w.network::<Pipes>().ok()?;
        let dev_id = host.device_of(device_e)?;
        let dev = host.network().device(dev_id).ok()?;
        let node = if cell_is_a { dev.b } else { dev.a };
        let Endpoint::Node(node) = node else { return None };
        let Side::Region(region) = host.network().resolve(Endpoint::Node(node)) else {
            return None;
        };
        let r = host.network().region(region).ok()?;
        (region, *r.summary(), *r.payload())
    };
    let vol_cell = vg_gas::world::with_world(|gw| gw.turf_device_volume(cell)).unwrap_or(vg_gas::gas::constants::CELL_VOLUME.into());
    let mut turf_gas = vg_gas::world::with_world(|gw| gw.turf_device_probe(cell))?;
    let report = if cell_is_a {
        device::step(&params, &mut turf_gas, vol_cell, &mut region_gas, vol_region, dt)
    } else {
        device::step(&params, &mut region_gas, vol_region, &mut turf_gas, vol_cell, dt)
    };
    if report.moles != 0.0 || report.power_w != 0.0 {
        let _ = w.edit_network::<Pipes>(move |host| {
            if let Ok(p) = host.payload_mut(region) {
                *p = region_gas;
            }
        });
        vg_gas::world::with_world(|gw| gw.turf_device_apply(cell, &turf_gas, vol_cell));
    }
    Some(report)
}
