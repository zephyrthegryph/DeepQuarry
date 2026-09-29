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
//! Ports and devices are World entities: DM mints each one's handle with
//! `SSvg.bind_datum()` (a `/datum/pipe_port`, or the device's machine) and
//! passes it here, so this module keeps no id maps of its own; region
//! results and device reports name ports and devices by those handles.
//! A region's DM-facing handle is a compacted slot (not
//! its raw arena bits, which can exceed `MixRef::Pipe`'s
//! 21-bit address budget), the one piece of bookkeeping this module keeps
//! that `PipeNet` also needed for the same reason -- not for revision or
//! idle-skip tracking, which `NetworkHost`/`World` already provide
//! generically.
//!
//! Turf<->pipe devices (a vent pump or scrubber) still bridge the pipe
//! network and `vg-gas`'s own turf field, each with its own storage
//! (`rust_architecture.md` step 6 is what turns the turf field into a real
//! `FieldKind` and this into a `RegionCell<Pipes, TurfGas>` device law);
//! for now [`pipe_step_devices`] calls `crate::gas` for the
//! turf side directly, the same cross-crate shape heat's `GasExchange`
//! already uses for the same reason (gas is not on the shared `World`
//! yet).

// vg_pipe_device_set/set_turf's argument count is inherent to the DM call
// convention (an id/two endpoints plus a flow law's four parameters,
// matching the pre-port `rust_device_operation` shape); see
// `ffi/src/sched.rs`'s file-level allow and its comment for why an
// item-level one doesn't reach the warning (emitted inside
// `::byondapi::bind`'s own macro expansion).
#![allow(clippy::too_many_arguments)]

use std::cell::RefCell;
use std::collections::HashMap;

use crate::gas::mix::{self, MixRef};
use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::entity::EntityId;
use vg_core::network::{Endpoint, RegionId, Side};
use vg_core::slot::RawHandle;
use vg_core::world::World;
use vg_gas::device::{self, Flow, StepReport};
use vg_gas::kind::device::{DeviceFlow, DeviceValve};
use vg_gas::pipes::{PipeGas, Pipes};

use crate::entity;
use crate::gas::REGION_SLOTS;
use crate::world::{list, num, with_world};

thread_local! {
    /// A removed port's gas goes here if DM named a target mixture
    /// (`RUST_PIPE_OP_REMOVE_TO_MIXTURE`'s replacement), read back when its
    /// `Released` event drains at [`pipe_commit`].
    static RELEASE_TARGETS: RefCell<HashMap<EntityId, MixRef>> = RefCell::new(HashMap::new());
}

/// A port or device handle from DM (an entity `SSvg.bind_datum()` minted).
fn handle_entity(v: &ByondValue) -> Result<EntityId> {
    entity::decode(num(v)?)
}

/// Adds port `port` (its entity handle) holding the gas from
/// `mixture_handle` (a `datum/gas_mixture` handle; `0`/invalid: empty), or
/// changes its volume if it already exists. Returns whether it succeeded.
#[auxmacros::bind("/proc/vg_pipe_upsert")]
fn pipe_upsert(
    port: ByondValue,
    mixture_handle: ByondValue,
    volume: ByondValue,
) -> Result<ByondValue> {
    let e = handle_entity(&port)?;
    let volume = num(&volume)?;
    let fresh = with_world(|w| {
        Ok(w.network::<Pipes>()
            .map_err(|e| eyre!("{e}"))?
            .node_of(e)
            .is_none())
    })?;
    // Outside the world borrow: a turf or pipe mixture reads the world.
    let gas = if fresh {
        gas_from_handle(&mixture_handle)
    } else {
        PipeGas::default()
    };
    let ok = with_world(|w| {
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

/// Map-load topology in one call (`doc/rewrite/init_and_turfs.md` §3.3
/// step 4): [`pipe_upsert`] for every `port, mixture_handle, volume` triple
/// in the flat list `triples`. Returns how many succeeded (a bad row is
/// skipped, not an error).
#[auxmacros::bind("/proc/vg_pipe_upsert_list")]
fn pipe_upsert_list(triples: ByondValue) -> Result<ByondValue> {
    let values = triples.get_list_values()?;
    if values.len() % 3 != 0 {
        bail!("triples must be a flat port, mixture_handle, volume list");
    }
    let mut ok = 0u32;
    for t in values.chunks_exact(3) {
        // One bad row (an unbound handle) doesn't lose the map's other ports.
        if pipe_upsert(t[0], t[1], t[2]).is_ok_and(|v| v.is_true()) {
            ok += 1;
        }
    }
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(ok as f32))
}

fn gas_from_handle(handle: &ByondValue) -> PipeGas {
    let Some(mix_ref) = num(handle).ok().and_then(MixRef::from_f32) else {
        return PipeGas::default();
    };
    mix::load(mix_ref).map_or_else(PipeGas::default, |m| {
        PipeGas::from_amounts(&mix::amounts_of(&m), m.get_temperature())
    })
}

/// Removes a port; its gas share is released, to `mixture_handle` if given
/// (else discarded -- `RUST_PIPE_OP_REMOVE`/`REMOVE_TO_MIXTURE`).
#[auxmacros::bind("/proc/vg_pipe_remove")]
fn pipe_remove(port: ByondValue, mixture_handle: ByondValue) -> Result<ByondValue> {
    let e = handle_entity(&port)?;
    if let Some(target) = num(&mixture_handle).ok().and_then(MixRef::from_f32) {
        RELEASE_TARGETS.with(|r| r.borrow_mut().insert(e, target));
    }
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| host.unbind_node(e))
            .map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })
    .map(ByondValue::from)
}

/// Batched destroy's one pipe release (`doc/rewrite/init_and_turfs.md`
/// §4.4 step 4): [`pipe_remove`] for every pair in `pairs`, a flat
/// `port, mixture_handle, ...` list (`mixture_handle` 0: discard), in one
/// topology edit. Zero/null or bad ports are skipped.
#[auxmacros::bind("/proc/vg_pipe_remove_list")]
fn pipe_remove_list(pairs: ByondValue) -> Result<ByondValue> {
    let values = pairs.get_list_values()?;
    if values.len() % 2 != 0 {
        bail!("pairs must be a flat port, mixture_handle list");
    }
    let mut doomed = Vec::with_capacity(values.len() / 2);
    for pair in values.chunks_exact(2) {
        // A stale or unbound handle is skipped (the rest still go).
        let Ok(e) = handle_entity(&pair[0]) else {
            continue;
        };
        if let Some(target) = num(&pair[1]).ok().and_then(MixRef::from_f32) {
            RELEASE_TARGETS.with(|r| r.borrow_mut().insert(e, target));
        }
        doomed.push(e);
    }
    if doomed.is_empty() {
        return Ok(ByondValue::null());
    }
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            for e in doomed {
                host.unbind_node(e);
            }
        })
        .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::null())
}

/// Connects two ports' nodes directly (`NetworkHost::connect_entities`,
/// bypassing any geometric connection rule -- pipes manage topology
/// explicitly).
#[auxmacros::bind("/proc/vg_pipe_connect")]
fn pipe_connect(port_a: ByondValue, port_b: ByondValue) -> Result<ByondValue> {
    let (ea, eb) = (handle_entity(&port_a)?, handle_entity(&port_b)?);
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            let _ = host.connect_entities(ea, eb);
        })
        .map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })
    .map(ByondValue::from)
}

/// Map-load edges in one call: [`pipe_connect`] for every pair in the flat
/// `port_a, port_b, ...` list `pairs`, in one topology edit.
#[auxmacros::bind("/proc/vg_pipe_connect_list")]
fn pipe_connect_list(pairs: ByondValue) -> Result<ByondValue> {
    let values = pairs.get_list_values()?;
    if values.len() % 2 != 0 {
        bail!("pairs must be a flat port_a, port_b list");
    }
    // A pair with an unbound handle is skipped; the rest still connect.
    let edges = values
        .chunks_exact(2)
        .filter_map(|p| Some((handle_entity(&p[0]).ok()?, handle_entity(&p[1]).ok()?)))
        .collect::<Vec<_>>();
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            for (ea, eb) in edges {
                let _ = host.connect_entities(ea, eb);
            }
        })
        .map_err(|e| eyre!("{e}"))?;
        Ok(())
    })?;
    Ok(ByondValue::null())
}

#[auxmacros::bind("/proc/vg_pipe_disconnect")]
fn pipe_disconnect(port_a: ByondValue, port_b: ByondValue) -> Result<ByondValue> {
    let (ea, eb) = (handle_entity(&port_a)?, handle_entity(&port_b)?);
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| host.disconnect_entities(ea, eb))
            .map_err(|e| eyre!("{e}"))?;
        Ok(())
    })?;
    Ok(ByondValue::null())
}

/// Drops every port (a map reload).
#[auxmacros::bind("/proc/vg_pipe_clear")]
fn pipe_clear() -> Result<ByondValue> {
    RELEASE_TARGETS.with(|r| r.borrow_mut().clear());
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            for e in host.node_entities() {
                host.unbind_node(e);
            }
        })
        .map_err(|e| eyre!("{e}"))
    })?;
    Ok(ByondValue::null())
}

/// Commits pending topology and returns the regions DM must rebuild, one
/// header per changed or retired region: `region_handle, port_count,
/// prior_count, volume, ports..., prior_region_handles...` (`volume < 0`:
/// the region is gone) -- the exact wire shape `rust_apply_pipe_topology`
/// already parses.
#[auxmacros::bind("/proc/vg_pipe_commit")]
fn pipe_commit() -> Result<ByondValue> {
    let mut released: Vec<(MixRef, PipeGas)> = Vec::new();
    let out = with_world(|w| {
        w.commit_network::<Pipes>();
        let releases_cell: std::sync::Arc<std::sync::Mutex<Vec<(EntityId, u32, PipeGas)>>> =
            std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let releases_out = std::sync::Arc::clone(&releases_cell);
        w.edit_network::<Pipes>(move |host| {
            releases_out
                .lock()
                .expect("not poisoned")
                .extend(host.take_released());
        })
        .map_err(|e| eyre!("{e}"))?;
        let releases = std::mem::take(&mut *releases_cell.lock().expect("not poisoned"));
        for (port_e, _pos, payload) in releases {
            // `pipe_remove` recorded any target under the port's entity.
            let target = RELEASE_TARGETS.with(|r| r.borrow_mut().remove(&port_e));
            if let Some(target) = target {
                released.push((target, payload));
            }
        }
        let transitions = w.drain_transitions::<Pipes>();
        let mut out = Vec::new();
        for t in transitions {
            let slot = REGION_SLOTS.with(|s| {
                let mut s = s.borrow_mut();
                if t.retired {
                    s.retire(t.region)
                } else {
                    Some(s.slot_for(t.region))
                }
            });
            let Some(slot) = slot else { continue };
            if t.retired {
                out.extend([handle(slot), 0.0, 0.0, -1.0]);
                continue;
            }
            let vol = region_volume(w, t.region);
            let ports: Vec<f32> = t.members.iter().map(|&e| entity::entity_value(e)).collect();
            let priors: Vec<f32> = t
                .prior
                .iter()
                .filter_map(|&raw| {
                    REGION_SLOTS
                        .with(|s| s.borrow().raw_slot_of(raw))
                        .map(handle)
                })
                .collect();
            #[allow(clippy::cast_precision_loss)]
            out.extend([handle(slot), ports.len() as f32, priors.len() as f32, vol]);
            out.extend(ports);
            out.extend(priors);
        }
        Ok(out)
    })?;
    // Released gas goes to its target outside the world borrow: a turf or
    // pipe target reaches the world again.
    for (target, payload) in released {
        mix::add_amounts(target, &payload.amounts(), payload.temperature);
    }
    list(out)
}

/// A region slot as DM's gas handle for it (`vg_bind_handle` takes it).
#[allow(clippy::cast_precision_loss)]
fn handle(slot: u32) -> f32 {
    MixRef::Pipe(slot).id() as f32
}

fn region_volume(w: &World, raw: u32) -> f32 {
    let Some(r) = RawHandle::from_bits(raw) else {
        return 0.0;
    };
    let region = RegionId::<Pipes>::from_raw(r);
    #[allow(clippy::cast_possible_truncation)]
    w.network::<Pipes>()
        .ok()
        .and_then(|h| {
            h.network()
                .region(region)
                .ok()
                .map(|reg| *reg.summary() as f32)
        })
        .unwrap_or(0.0)
}

/// Registers (or replaces) a region<->region device edge between two
/// ports. Carries no flow law of its own (`rust_architecture.md` §8.5 step
/// 6's pipe-device redesign): DM attaches that afterward by creating a
/// `/obj/effect/device_flow_row`/`device_valve_row` instance, binding it
/// (`vg_bind_gas`, generated), and setting its `device` field to this
/// device's `vg_entity` handle -- no bespoke bind here, just the generic
/// `vg_component_*` accessors every component gets.
#[auxmacros::bind("/proc/vg_pipe_device_set")]
fn pipe_device_set(id: ByondValue, port_a: ByondValue, port_b: ByondValue) -> Result<ByondValue> {
    let e = handle_entity(&id)?;
    let (ea, eb) = (handle_entity(&port_a)?, handle_entity(&port_b)?);
    let ok = with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            let _ = host.bind_device(e, ea, eb, 0, ());
        })
        .map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })?;
    Ok(ok.into())
}

/// Registers (or replaces) a device edge between a port and a turf (a vent
/// pump or scrubber): `turf_mixture_handle` is the turf's gas-mixture
/// handle, not a port id. See [`pipe_device_set`]'s own docs on flows.
#[auxmacros::bind("/proc/vg_pipe_device_set_turf")]
fn pipe_device_set_turf(
    id: ByondValue,
    port_a: ByondValue,
    turf_mixture_handle: ByondValue,
) -> Result<ByondValue> {
    let e = handle_entity(&id)?;
    let ea = handle_entity(&port_a)?;
    let Some(MixRef::Turf(cell)) = num(&turf_mixture_handle).ok().and_then(MixRef::from_f32) else {
        return Ok(false.into());
    };
    let ok = with_world(|w| {
        w.edit_network::<Pipes>(move |host| {
            let _ = host.bind_cell_device(e, ea, cell, 0, ());
        })
        .map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })?;
    Ok(ok.into())
}

#[auxmacros::bind("/proc/vg_pipe_device_remove")]
fn pipe_device_remove(id: ByondValue) -> Result<ByondValue> {
    let e = handle_entity(&id)?;
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| host.unbind_device(e))
            .map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })
    .map(ByondValue::from)
}

/// Every `Flow`/valve-open bound to each device entity, keyed by the device
/// entity's slot index (`DeviceFlow`/`DeviceValve` rows, no op wire: DM
/// creates and configures them directly through the generated
/// `vg_component_*` accessors -- `rust_architecture.md` §8.5 step 6's
/// pipe-device redesign). Several flows on the same device compose in
/// `DeviceFlow` bind order (a filter's passthrough plus its filtered flow, a
/// mixer's two inputs).
///
/// Built once per [`pipe_step_devices`] call: one pass over the flow rows and
/// one over the valve rows, O(devices + rows). The previous per-device lookup
/// rescanned every row for every device (O(devices x rows)), which on
/// Southern Cross (~thousands of vents/scrubbers) cost ~130 ms per SSair fire.
#[derive(Default)]
struct DeviceLaws {
    flows: Vec<Flow>,
    valve_open: bool,
}

fn device_law_index(w: &World) -> HashMap<u32, DeviceLaws> {
    let mut index: HashMap<u32, DeviceLaws> = HashMap::new();
    for e in w.entities_with::<DeviceFlow>() {
        if let Some(row) = w.read::<DeviceFlow>(e) {
            index.entry(row.device).or_default().flows.push(row.flow());
        }
    }
    for e in w.entities_with::<DeviceValve>() {
        if let Some(v) = w.read::<DeviceValve>(e) {
            if v.open {
                index.entry(v.device).or_default().valve_open = true;
            }
        }
    }
    index
}

/// Runs every device edge's flow(s)/valve once for `dt` seconds -- region
/// <-> region edges directly, region<->turf edges (a vent pump/scrubber)
/// through `crate::gas`'s turf accessors (this module's own docs) --
/// and returns a flat `device handle, moles, power_w, target_reached` list
/// per device that moved something or drew power.
#[auxmacros::bind("/proc/vg_pipe_step_devices")]
fn pipe_step_devices(dt: ByondValue) -> Result<ByondValue> {
    let dt = num(&dt)?;
    let mut out = Vec::new();
    with_world(|w| {
        let devices: Vec<EntityId> = w
            .network::<Pipes>()
            .map(|h| h.devices().map(|(_, e)| e).collect())
            .unwrap_or_default();
        let laws = device_law_index(w);
        for e in devices {
            let Some(law) = laws.get(&e.index()) else {
                continue;
            };
            let (flows, valve_open) = (&law.flows, law.valve_open);
            if flows.is_empty() && !valve_open {
                continue;
            }
            let Ok(host) = w.network::<Pipes>() else {
                continue;
            };
            let Some(dev_id) = host.device_of(e) else {
                continue;
            };
            let Ok(dev) = host.network().device(dev_id) else {
                continue;
            };
            let (ea, eb) = (dev.a, dev.b);
            drop(host);
            let report = match (ea, eb) {
                (Endpoint::Node(_), Endpoint::Node(_)) => {
                    step_region_region(w, e, flows, valve_open, dt)
                }
                // A turf device's flow treats the turf as side `a` (vent
                // pump, scrubber), wherever the graph stores the cell.
                (Endpoint::Cell(cell), Endpoint::Node(_))
                | (Endpoint::Node(_), Endpoint::Cell(cell)) => {
                    step_region_turf(w, e, cell, flows, valve_open, dt)
                }
                _ => None,
            };
            if let Some(report) = report {
                if report.moles != 0.0 || report.power_w != 0.0 {
                    out.extend([
                        entity::entity_value(e),
                        report.moles as f32,
                        report.power_w,
                        if report.target_reached { 1.0 } else { 0.0 },
                    ]);
                }
            }
        }
        list(out)
    })
}

/// Runs every flow then the valve gate on `(a, b)` in sequence, folding
/// into one report: total moles moved (signed a->b), power drawn, and
/// whether any stop target was reached this tick.
fn step_all(
    flows: &[Flow],
    valve_open: bool,
    a: &mut PipeGas,
    vol_a: f64,
    b: &mut PipeGas,
    vol_b: f64,
    dt: f32,
) -> StepReport {
    let mut total = StepReport::default();
    for flow in flows {
        let r = device::step(flow, a, vol_a, b, vol_b, dt);
        total.moles += r.moles;
        total.power_w += r.power_w;
        total.target_reached |= r.target_reached;
    }
    if valve_open {
        let r = device::step_valve(true, a, vol_a, b, vol_b);
        total.moles += r.moles;
    }
    total
}

fn step_region_region(
    w: &mut World,
    device_e: EntityId,
    flows: &[Flow],
    valve_open: bool,
    dt: f32,
) -> Option<StepReport> {
    let (ra, rb, vol_a, vol_b, mut pa, mut pb) = {
        let host = w.network::<Pipes>().ok()?;
        let dev_id = host.device_of(device_e)?;
        let dev = host.network().device(dev_id).ok()?;
        let (Endpoint::Node(na), Endpoint::Node(nb)) = (dev.a, dev.b) else {
            return None;
        };
        let (Side::Region(ra), Side::Region(rb)) = (
            host.network().resolve(Endpoint::Node(na)),
            host.network().resolve(Endpoint::Node(nb)),
        ) else {
            return None;
        };
        if ra == rb {
            return None;
        }
        let region_a = host.network().region(ra).ok()?;
        let region_b = host.network().region(rb).ok()?;
        (
            ra,
            rb,
            *region_a.summary(),
            *region_b.summary(),
            *region_a.payload(),
            *region_b.payload(),
        )
    };
    let report = step_all(flows, valve_open, &mut pa, vol_a, &mut pb, vol_b, dt);
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

fn step_region_turf(
    w: &mut World,
    device_e: EntityId,
    cell: u32,
    flows: &[Flow],
    valve_open: bool,
    dt: f32,
) -> Option<StepReport> {
    let (region, vol_region, mut region_gas) = {
        let host = w.network::<Pipes>().ok()?;
        let dev_id = host.device_of(device_e)?;
        let dev = host.network().device(dev_id).ok()?;
        let ((Endpoint::Node(node), _) | (_, Endpoint::Node(node))) = (dev.a, dev.b) else {
            return None;
        };
        let Side::Region(region) = host.network().resolve(Endpoint::Node(node)) else {
            return None;
        };
        let r = host.network().region(region).ok()?;
        (region, *r.summary(), *r.payload())
    };
    let (turf_before, vol_cell) = crate::gas::turf_device_probe(w, cell)?;
    let mut turf_gas = turf_before;
    let report = step_all(
        flows,
        valve_open,
        &mut turf_gas,
        vol_cell,
        &mut region_gas,
        vol_region,
        dt,
    );
    if report.moles != 0.0 || report.power_w != 0.0 {
        let _ = w.edit_network::<Pipes>(move |host| {
            if let Ok(p) = host.payload_mut(region) {
                *p = region_gas;
            }
        });
        crate::gas::turf_device_apply(w, cell, &turf_before, &turf_gas);
    }
    Some(report)
}
