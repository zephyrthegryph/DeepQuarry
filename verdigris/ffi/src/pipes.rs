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
//! network and `vg-gas`'s own turf field, each with its own storage. The flows
//! themselves are a real World law ([`vg_gas::laws::PipeDeviceStep`], on its own
//! `Period`): [`stage_devices`] builds every device's job (the turf side read
//! through `crate::gas`) into the main-owned [`DeviceJobs`] global before the
//! World's step and [`apply_devices`] writes the result back after it, the
//! same cross-domain shape heat uses for its mixture probes.

// vg_pipe_device_set/set_turf's argument count is inherent to the DM call
// convention (an id/two endpoints plus a flow law's four parameters,
// matching the pre-port `rust_device_operation` shape); see
// `ffi/src/sched.rs`'s file-level allow and its comment for why an
// item-level one doesn't reach the warning (emitted inside
// `::byondapi::bind`'s own macro expansion).
#![allow(clippy::too_many_arguments)]

use rustc_hash::{FxHashMap, FxHashSet};
use std::cell::{Cell, RefCell};
use std::collections::HashMap;

use crate::gas::mix::{self, MixRef};
use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::entity::EntityId;
use vg_core::network::{Endpoint, RegionId, Side};
use vg_core::slot::RawHandle;
use vg_core::world::World;
use vg_gas::device::Flow;
use vg_gas::kind::device::{DeviceFlow, DeviceValve};
use vg_gas::kind::device::{rate_kind, role};
use vg_gas::laws::{BudgetJob, BudgetKind, BudgetLeg, DeviceJob, DeviceJobs, DeviceSide};
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
    let source = mixture_arg(&mixture_handle)?;
    let fresh = with_world(|w| {
        Ok(w.network::<Pipes>()
            .map_err(|e| eyre!("{e}"))?
            .node_of(e)
            .is_none())
    })?;
    // Outside the world borrow: a turf or pipe mixture reads the world.
    let gas = if fresh {
        gas_from_ref(source)
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

/// A gas mixture argument: the `/datum/gas_mixture` itself (its handle is
/// checked against its generation by [`MixRef::of`]), or `0`/null for none. A
/// bare handle number is refused: it cannot say which mixture it was minted for.
fn mixture_arg(v: &ByondValue) -> Result<Option<MixRef>> {
    if v.is_null() {
        return Ok(None);
    }
    if let Ok(n) = v.get_number() {
        if n == 0.0 {
            return Ok(None);
        }
        bail!("pass the gas mixture datum, not its bare handle {n}");
    }
    MixRef::of(v).map(Some)
}

fn gas_from_ref(source: Option<MixRef>) -> PipeGas {
    let Some(mix_ref) = source else {
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
    // A refused target still removes the port (its gas is discarded) and then
    // reports the refusal, so a stale mixture never strands a doomed port.
    let target = mixture_arg(&mixture_handle);
    if let Ok(Some(target)) = target {
        RELEASE_TARGETS.with(|r| r.borrow_mut().insert(e, target));
    }
    with_world(|w| {
        w.edit_network::<Pipes>(move |host| host.unbind_node(e))
            .map_err(|e| eyre!("{e}"))?;
        Ok(true)
    })?;
    target?;
    Ok(true.into())
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
    let mut refused: Option<eyre::Report> = None;
    for pair in values.chunks_exact(2) {
        // A stale or unbound handle is skipped (the rest still go).
        let Ok(e) = handle_entity(&pair[0]) else {
            continue;
        };
        match mixture_arg(&pair[1]) {
            Ok(Some(target)) => {
                RELEASE_TARGETS.with(|r| r.borrow_mut().insert(e, target));
            }
            Ok(None) => {}
            // The port still goes (its gas is discarded); the refusal is reported after.
            Err(err) => refused = refused.or(Some(err)),
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
    if let Some(err) = refused {
        return Err(err);
    }
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

/// [`pipe_device_set`] for every `device, port_a, port_b` triple in the flat
/// list `triples`, in one call (round-start device registration). Returns how
/// many succeeded; a bad row is skipped, not an error.
#[auxmacros::bind("/proc/vg_pipe_device_set_list")]
fn pipe_device_set_list(triples: ByondValue) -> Result<ByondValue> {
    let values = triples.get_list_values()?;
    if values.len() % 3 != 0 {
        bail!("triples must be a flat device, port_a, port_b list");
    }
    let mut ok = 0u32;
    for t in values.chunks_exact(3) {
        if pipe_device_set(t[0], t[1], t[2]).is_ok_and(|v| v.is_true()) {
            ok += 1;
        }
    }
    #[allow(clippy::cast_precision_loss)]
    Ok(ByondValue::from(ok as f32))
}

/// Registers (or replaces) a device edge between a port and a turf (a vent
/// pump or scrubber): `turf_air` is the turf's `/datum/gas_mixture` (checked
/// against its generation), not a port id. See [`pipe_device_set`]'s own docs on flows.
/// The turf cell a device edge can face; space, walls and other main-owned
/// mixtures have none.
const fn turf_cell(r: Option<MixRef>) -> Option<u32> {
    match r {
        Some(MixRef::Turf(cell)) => Some(cell),
        _ => None,
    }
}

#[auxmacros::bind("/proc/vg_pipe_device_set_turf")]
fn pipe_device_set_turf(
    id: ByondValue,
    port_a: ByondValue,
    turf_air: ByondValue,
) -> Result<ByondValue> {
    let e = handle_entity(&id)?;
    let ea = handle_entity(&port_a)?;
    let Some(cell) = turf_cell(mixture_arg(&turf_air)?) else {
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
/// Built once per [`stage_devices`] call: one pass over the flow rows and
/// one over the valve rows, O(devices + rows). The previous per-device lookup
/// rescanned every row for every device (O(devices x rows)), which on
/// Southern Cross (~thousands of vents/scrubbers) cost ~130 ms per SSair fire.
#[derive(Default)]
struct DeviceLaws {
    flows: Vec<Flow>,
    valve_open: bool,
    /// What the device's flow and valve rows were, as their write stamps (`World::row_stamp`): any write to any of
    /// them, or a row coming or going, changes it.
    flow_sig: Sig,
    valve_sig: Sig,
    /// The device has a leg of a budget group (filters and mixers), stepped as that group and not as a plain flow.
    in_group: bool,
}

/// A set of rows' write stamps, folded: a stamp is never reused and a rewrite takes a new, larger one, so the count,
/// the largest and the sum together differ whenever a row was written, added or removed.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Sig {
    n: u32,
    max: u64,
    sum: u64,
}

impl Sig {
    fn add(&mut self, stamp: u64) {
        self.n += 1;
        self.max = self.max.max(stamp);
        self.sum = self.sum.wrapping_add(stamp);
    }
}

/// Every budget leg of the world, by group: `(device entity index, row)`.
type BudgetGroups = FxHashMap<u32, Vec<(u32, DeviceFlow)>>;

fn device_law_index(w: &World) -> (FxHashMap<u32, DeviceLaws>, BudgetGroups) {
    let mut index: FxHashMap<u32, DeviceLaws> = FxHashMap::default();
    let mut groups = BudgetGroups::default();
    for e in w.entities_with::<DeviceFlow>() {
        if let Some(row) = w.read::<DeviceFlow>(e) {
            let stamp = w.row_stamp::<DeviceFlow>(e).unwrap_or(0);
            let law = index.entry(row.device).or_default();
            law.flow_sig.add(stamp);
            if row.is_budget() {
                law.in_group = true;
                groups.entry(row.group).or_default().push((row.device, row));
            } else {
                law.flows.push(row.flow());
            }
        }
    }
    for e in w.entities_with::<DeviceValve>() {
        if let Some(v) = w.read::<DeviceValve>(e) {
            let law = index.entry(v.device).or_default();
            law.valve_sig
                .add(w.row_stamp::<DeviceValve>(e).unwrap_or(0));
            if v.open {
                law.valve_open = true;
            }
        }
    }
    (index, groups)
}

/// The gas mixture of the pipe region port `port` (a packed entity id) is in now: its DM-facing handle follows the port
/// through every merge (the surviving region) and split (the side the port is on).
pub(crate) fn port_mixture(w: &World, port: u32) -> Option<MixRef> {
    let entity = EntityId::from_bits(port)?;
    let region = w.network::<Pipes>().ok()?.region_of(entity)?;
    let slot = REGION_SLOTS.with(|s| s.borrow_mut().slot_for(region.raw().bits()));
    Some(MixRef::Pipe(slot))
}

/// Who owns a staged side, and what it held when it was read (a side is written back only if the step changed it).
enum SideOwner {
    /// A pipe region's payload.
    Region { id: RegionId<Pipes>, before: PipeGas },
    /// A turf's gas, written back as the difference from `before`.
    Turf { cell: u32, before: PipeGas },
}

thread_local! {
    /// The owners of the sides last staged, in side order.
    static STAGED: RefCell<Vec<SideOwner>> = const { RefCell::new(Vec::new()) };
    /// The devices whose last step changed nothing, by device entity index, with everything that step's result depended on.
    static SETTLED: RefCell<FxHashMap<u32, Settled>> = RefCell::new(FxHashMap::default());
    /// The inputs of each staged job (in job order; `None`: not a candidate for settling), for [`apply_devices`] to file
    /// under [`SETTLED`] when the job turns out settled.
    static STAGED_KEYS: RefCell<Vec<Option<(u32, SettleKey)>>> = const { RefCell::new(Vec::new()) };
    /// The staging pass count, to drop [`SETTLED`] entries of devices that were not seen.
    static STAGE_PASS: Cell<u64> = const { Cell::new(0) };
}

/// One side of a device edge as the settle cache knows it, without reading its gas: a region by id and revision (the
/// host bumps a region's revision on every payload write and every membership change), a turf by everything its probe
/// reads.
#[derive(Clone, Copy, PartialEq)]
enum SideKey {
    Region { id: u32, rev: u64 },
    Turf(crate::gas::TurfStamp),
}

/// Which gas a side is, for deciding whether an earlier job in the step could have changed it.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum SideId {
    Region(u32),
    Turf(u32),
}

/// Everything one device's job in a step is a function of, short of the step length (fixed by `WorldConfig::dt`): its
/// flow and valve rows (write stamps), its edge (device handle and what each end resolves to) and both sides' gas.
/// Equal keys give an equal job on an equal start, so a job that changed nothing from this key changes nothing again.
#[derive(Clone, Copy, PartialEq)]
struct SettleKey {
    flows: Sig,
    valve: Sig,
    device: u32,
    a: SideKey,
    b: SideKey,
}

impl SettleKey {
    fn side_ids(&self) -> (SideId, SideId) {
        let id = |s: &SideKey| match s {
            SideKey::Region { id, .. } => SideId::Region(*id),
            SideKey::Turf(t) => SideId::Turf(t.cell()),
        };
        (id(&self.a), id(&self.b))
    }
}

struct Settled {
    key: SettleKey,
    seen: u64,
}

/// The sides staged so far, looked up by what they are (a region, a turf cell), so devices that meet on one share it.
#[derive(Default)]
struct Staging {
    sides: Vec<DeviceSide>,
    owners: Vec<SideOwner>,
    regions: FxHashMap<u32, usize>,
    turfs: FxHashMap<u32, usize>,
}

impl Staging {
    /// The side of region `id`, reading its payload and volume on first use.
    fn region(&mut self, w: &World, id: RegionId<Pipes>) -> Option<usize> {
        let key = id.raw().bits();
        if let Some(&at) = self.regions.get(&key) {
            return Some(at);
        }
        let host = w.network::<Pipes>().ok()?;
        let region = host.network().region(id).ok()?;
        let gas = *region.payload();
        let at = self.sides.len();
        self.sides.push(DeviceSide {
            gas,
            volume: *region.summary(),
            touched: false,
        });
        self.owners.push(SideOwner::Region { id, before: gas });
        self.regions.insert(key, at);
        Some(at)
    }

    /// The side of turf `cell`, read through `crate::gas`'s accessors on first use.
    fn turf(&mut self, w: &World, cell: u32) -> Option<usize> {
        if let Some(&at) = self.turfs.get(&cell) {
            return Some(at);
        }
        let (gas, volume) = crate::gas::turf_device_probe(w, cell)?;
        let at = self.sides.len();
        self.sides.push(DeviceSide {
            gas,
            volume,
            touched: false,
        });
        self.owners.push(SideOwner::Turf { cell, before: gas });
        self.turfs.insert(cell, at);
        Some(at)
    }
}

/// Stages every device edge's flows, valve and the two sides' gas as the [`DeviceJobs`] global, for the World's next
/// step ([`PipeDeviceStep`] runs them, once per its period): region <-> region edges from the pipe network, region <->
/// turf edges (a vent pump/scrubber) with the turf read through `crate::gas`'s accessors (this module's own docs).
/// Devices on one region or turf share its side. [`apply_devices`] takes the result after the step.
pub(crate) fn stage_devices(w: &mut World) -> Result<()> {
    // Sub-laps of the frame's `pace_stage` (counters `frame.us.stage_*`, which overlap it): the idle profile put most of the
    // native frame's cost in this function, and these name which part of it.
    let mut lap = StageLaps::start();
    let mut staging = Staging::default();
    let mut jobs = Vec::new();
    let devices: Vec<EntityId> = w
        .network::<Pipes>()
        .map(|h| h.devices().map(|(_, e)| e).collect())
        .unwrap_or_default();
    lap.lap("stage_devices_list");
    let (laws, groups) = device_law_index(w);
    lap.lap("stage_law_index");
    crate::metrics::registry().counter("stage.devices").add(devices.len() as u64);
    // A budget leg's device: its entity and the regions across its edge.
    let mut legs: FxHashMap<u32, (EntityId, RegionId<Pipes>, RegionId<Pipes>)> =
        FxHashMap::default();
    let pass = STAGE_PASS.with(|p| {
        p.set(p.get() + 1);
        p.get()
    });
    let mut keys: Vec<Option<(u32, SettleKey)>> = Vec::new();
    // Sides a job that will run could change before a later job's turn: a settled job on neither is skipped.
    let mut touched: FxHashSet<SideId> = FxHashSet::default();
    let mut skipped = 0_u64;
    let mut settled = SETTLED.take();
    for e in devices {
        let Some(law) = laws.get(&e.index()) else {
            continue;
        };
        if law.flows.is_empty() && !law.valve_open && !law.in_group {
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
        let resolve = |endpoint| match host.network().resolve(endpoint) {
            Side::Region(r) => Some(r),
            _ => None,
        };
        let region_key = |r: RegionId<Pipes>| SideKey::Region {
            id: r.raw().bits(),
            rev: host.region_revision(r),
        };
        // A turf device's flow treats the turf as side `a` (vent pump, scrubber), wherever the graph stores the
        // cell.
        let ends = match (ea, eb) {
            (Endpoint::Node(_), Endpoint::Node(_)) => match (resolve(ea), resolve(eb)) {
                (Some(ra), Some(rb)) if ra != rb => Some((Err(ra), rb)),
                _ => None,
            },
            (Endpoint::Cell(cell), node @ Endpoint::Node(_))
            | (node @ Endpoint::Node(_), Endpoint::Cell(cell)) => resolve(node).map(|r| (Ok(cell), r)),
            _ => None,
        };
        let key = ends.as_ref().and_then(|&(first, region_b)| {
            let a = match first {
                Ok(cell) => SideKey::Turf(crate::gas::turf_device_stamp(w, cell)?),
                Err(r) => region_key(r),
            };
            Some(SettleKey {
                flows: law.flow_sig,
                valve: law.valve_sig,
                device: dev_id.raw().bits(),
                a,
                b: region_key(region_b),
            })
        });
        drop(host);
        let Some((first, region_b)) = ends else {
            continue;
        };
        // A settled device (its last step changed nothing, and nothing it depends on has changed since) is skipped,
        // unless a job running earlier in this step could have changed a side of it first.
        let keyed = key.filter(|_| !law.in_group).map(|k| (e.index(), k));
        if let Some((idx, k)) = &keyed {
            if let Some(entry) = settled.get_mut(idx) {
                entry.seen = pass;
                if entry.key == *k {
                    let (a, b) = k.side_ids();
                    if !touched.contains(&a) && !touched.contains(&b) {
                        skipped += 1;
                        continue;
                    }
                }
            }
        }
        if law.in_group
            && let Err(region_a) = first
        {
            legs.insert(e.index(), (e, region_a, region_b));
        }
        if law.flows.is_empty() && !law.valve_open {
            continue;
        }
        let a = match first {
            Ok(cell) => staging.turf(w, cell),
            Err(region_a) => staging.region(w, region_a),
        };
        let b = staging.region(w, region_b);
        if let (Some(a), Some(b)) = (a, b) {
            if let Some(k) = &key {
                let (ia, ib) = k.side_ids();
                touched.insert(ia);
                touched.insert(ib);
            }
            keys.push(keyed);
            jobs.push(DeviceJob {
                entity: entity::entity_value(e),
                flows: law.flows.clone(),
                valve_open: law.valve_open,
                a,
                b,
                moles: 0.0,
                power_w: 0.0,
                target_reached: false,
                settled: true,
            });
        }
    }
    lap.lap("stage_device_loop");
    let mut budgets = Vec::new();
    for rows in groups.values() {
        budgets.extend(stage_budget(w, &mut staging, rows, &legs));
    }
    lap.lap("stage_budgets");
    let Staging { sides, owners, .. } = staging;
    settled.retain(|_, s| s.seen == pass);
    SETTLED.set(settled);
    STAGED_KEYS.set(keys);
    crate::metrics::registry().counter("stage.jobs").add(jobs.len() as u64);
    crate::metrics::registry().counter("stage.skipped").add(skipped);
    crate::metrics::registry().counter("stage.sides").add(sides.len() as u64);
    STAGED.with_borrow_mut(|s| *s = owners);
    let set = w
        .set_global(DeviceJobs { sides, jobs, budgets })
        .map_err(|e| eyre!("{e}"));
    lap.lap("stage_set_global");
    set
}

/// Cumulative wall time of the parts of [`stage_devices`] (`frame.us.stage_*`).
struct StageLaps(std::time::Instant);

impl StageLaps {
    fn start() -> Self {
        Self(std::time::Instant::now())
    }

    fn lap(&mut self, part: &'static str) {
        let now = std::time::Instant::now();
        #[allow(clippy::cast_possible_truncation)]
        crate::frame::trace_lap(part, (now - self.0).as_micros() as u64);
        self.0 = now;
    }
}

/// One budget group (a filter's or mixer's legs) as a [`BudgetJob`]: the hub is the region the legs share (a filter's source
/// is side `a` of its edges, a mixer's output side `b`), each leg the region across its edge.
fn stage_budget(
    w: &World,
    staging: &mut Staging,
    rows: &[(u32, DeviceFlow)],
    legs: &FxHashMap<u32, (EntityId, RegionId<Pipes>, RegionId<Pipes>)>,
) -> Option<BudgetJob> {
    let (_, first) = rows.first()?;
    let kind = if first.rate_kind == rate_kind::MIX {
        BudgetKind::Mix
    } else {
        BudgetKind::Filter
    };
    let hub_of = |&(_, a, b): &(EntityId, RegionId<Pipes>, RegionId<Pipes>)| match kind {
        BudgetKind::Filter => (a, b),
        BudgetKind::Mix => (b, a),
    };
    let (hub_region, _) = hub_of(legs.get(&first.device)?);
    let hub = staging.region(w, hub_region)?;
    let mut staged = Vec::new();
    let mut entity = 0.0;
    for (device, row) in rows {
        let Some(edge) = legs.get(device) else {
            continue;
        };
        let (hub_here, leg_region) = hub_of(edge);
        if hub_here != hub_region {
            continue;
        }
        let Some(side) = staging.region(w, leg_region) else {
            continue;
        };
        if staged.is_empty() {
            entity = entity::entity_value(edge.0);
        }
        staged.push(BudgetLeg {
            side,
            mask: row.gases,
            clean: row.role == role::CLEAN,
            ratio: row.ratio,
        });
    }
    (!staged.is_empty()).then_some(BudgetJob {
        kind,
        entity,
        hub,
        legs: staged,
        rate: first.rate,
        power_w: first.power_w,
        efficiency: first.efficiency,
        moles: 0.0,
        power_draw: 0.0,
    })
}

/// Writes the stepped sides back (region payloads, each turf's difference) and returns a flat `device handle, moles,
/// power_w, target_reached` list per device that moved something or drew power (each becomes a
/// `NATIVE_NOTICE_PIPE_DEVICE` notice). Clears the global; a side the step did not change is not written.
pub(crate) fn apply_devices(w: &mut World) -> Vec<f32> {
    let done = w
        .global::<DeviceJobs>()
        .map(|j| j.clone())
        .unwrap_or_default();
    let owners = STAGED.with_borrow_mut(std::mem::take);
    let keys = STAGED_KEYS.take();
    let pass = STAGE_PASS.with(Cell::get);
    SETTLED.with_borrow_mut(|settled| {
        for (job, key) in done.jobs.iter().zip(keys) {
            let Some((idx, key)) = key else { continue };
            if job.settled {
                settled.insert(idx, Settled { key, seen: pass });
            } else {
                settled.remove(&idx);
            }
        }
    });
    let _ = w.set_global(DeviceJobs::default());
    for (side, owner) in done.sides.iter().zip(owners) {
        match owner {
            SideOwner::Region { id, before } => {
                if side.gas != before {
                    let gas = side.gas;
                    let _ = w.edit_network::<Pipes>(move |host| {
                        if let Ok(p) = host.payload_mut(id) {
                            *p = gas;
                        }
                    });
                }
            }
            SideOwner::Turf { cell, before } => {
                if side.gas != before {
                    crate::gas::turf_device_apply(w, cell, &before, &side.gas);
                }
            }
        }
    }
    let mut out = Vec::new();
    for budget in &done.budgets {
        if budget.moved() {
            out.extend([budget.entity, budget.moles as f32, budget.power_draw, 0.0]);
        }
    }
    for job in &done.jobs {
        if job.moved() {
            out.extend([
                job.entity,
                job.moles as f32,
                job.power_w,
                if job.target_reached { 1.0 } else { 0.0 },
            ]);
        }
    }
    out
}

#[cfg(test)]
mod handle_tests {
    use super::*;

    #[test]
    fn a_device_edge_faces_only_a_turf_cell() {
        assert_eq!(turf_cell(Some(MixRef::Turf(7))), Some(7));
        assert_eq!(turf_cell(Some(MixRef::Main(7))), None);
        assert_eq!(turf_cell(Some(MixRef::Pipe(7))), None);
        assert_eq!(turf_cell(None), None);
    }

    #[test]
    fn a_stale_turf_handle_is_refused_before_a_device_edge_is_made() {
        let cell = 4_000_101;
        let stamped = mix::bump_turf_generation(cell);
        #[allow(clippy::cast_precision_loss)]
        let id = MixRef::Turf(cell).id() as f32;
        let ok = mix::checked_ref(id, Some(stamped)).unwrap();
        assert_eq!(turf_cell(Some(ok)), Some(cell));
        mix::bump_turf_generation(cell);
        assert!(mix::checked_ref(id, Some(stamped)).is_err());
    }

    #[test]
    fn an_empty_gas_source_is_a_vacuum_port() {
        let gas = gas_from_ref(None);
        assert_eq!(gas, PipeGas::default());
    }
}

#[cfg(test)]
mod settle_tests {
    use super::*;
    use vg_core::component::Component;
    use vg_gas::cell::{GasCell, N, Q};
    use vg_gas::gas::ids::GAS_OXYGEN;
    use vg_gas::kind::device::{direction, stop_cmp, stop_side};

    fn gas(moles: f32, kelvin: f32) -> PipeGas {
        let mut amounts = [0.0_f32; Q];
        amounts[GAS_OXYGEN] = moles;
        amounts[N] = moles * 20.0 * kelvin;
        PipeGas::from_amounts(&amounts, kelvin)
    }

    fn flow_row(device: EntityId, rate_kind: u8, rate: f32) -> DeviceFlow {
        DeviceFlow {
            device: device.index(),
            rate_kind,
            rate,
            ..DeviceFlow::default()
        }
    }

    /// Every flow shape the stager handles, on a small network of eight one-node regions and a 4x4 room: a power pump
    /// that reaches its target, a downhill gate that equalizes, a volume pump with a stop, a valve, a masked fraction, a
    /// flow with a limit, a regulator, and two vents on one turf.
    struct Rig {
        ports: Vec<EntityId>,
        gate_row: EntityId,
        valve_row: EntityId,
    }

    fn build_rig(w: &mut World) -> Rig {
        let key = crate::gas::turf_key().unwrap();
        let mut air = [0.0; N];
        air[0] = 82.0;
        air[1] = 21.8;
        for cell in 0..16 {
            crate::gas::register_cell(
                w,
                key,
                cell,
                GasCell::new(air, 293.15),
                2500.0,
                false,
                Some(0),
            );
        }
        build_copy(w, 3)
    }

    /// One copy of the rig on room cell `cell` (the room must be registered).
    fn build_copy(w: &mut World, cell: u32) -> Rig {
        let ports: Vec<EntityId> = (0..8).map(|_| w.spawn().unwrap()).collect();
        let moles = [40.0, 5.0, 10.0, 0.0, 20.0, 2.0, 30.0, 1.0];
        w.edit_network::<Pipes>({
            let ports = ports.clone();
            move |host| {
                for (i, &p) in ports.iter().enumerate() {
                    let _ = host.bind_node(p, 0, 0, 100.0 + 25.0 * i as f32);
                }
            }
        })
        .unwrap();
        w.commit_network::<Pipes>();
        w.edit_network::<Pipes>({
            let ports = ports.clone();
            move |host| {
                for (i, &p) in ports.iter().enumerate() {
                    let region = host.region_of(p).unwrap();
                    *host.payload_mut(region).unwrap() = gas(moles[i], 290.0 + 5.0 * i as f32);
                }
            }
        })
        .unwrap();
        let device = |w: &mut World, a: usize, b: Option<usize>, cell: u32| {
            let d = w.spawn().unwrap();
            let ports = ports.clone();
            w.edit_network::<Pipes>(move |host| {
                let _ = match b {
                    Some(b) => host.bind_device(d, ports[a], ports[b], 0, ()),
                    None => host.bind_cell_device(d, ports[a], cell, 0, ()),
                };
            })
            .unwrap();
            d
        };
        let pump = device(w, 0, Some(1), 0);
        let gate = device(w, 1, Some(2), 0);
        let vpump = device(w, 2, Some(3), 0);
        let valve = device(w, 3, Some(4), 0);
        let split = device(w, 4, Some(5), 0);
        let limited = device(w, 5, Some(6), 0);
        let regulator = device(w, 6, Some(7), 0);
        let vent = device(w, 2, None, cell);
        let scrubber = device(w, 6, None, cell);
        let bind = |w: &mut World, row: DeviceFlow| w.bind_value(None, row).unwrap();
        bind(
            w,
            DeviceFlow {
                stop_side: stop_side::B,
                stop_cmp: stop_cmp::AT_LEAST,
                stop_kpa: 150.0,
                ..flow_row(pump, rate_kind::POWER, 7500.0)
            },
        );
        let gate_row = bind(
            w,
            DeviceFlow {
                direction: direction::DOWNHILL,
                ..flow_row(gate, rate_kind::VOLUME, 200.0)
            },
        );
        bind(
            w,
            DeviceFlow {
                stop_side: stop_side::B,
                stop_cmp: stop_cmp::AT_LEAST,
                stop_kpa: 300.0,
                ..flow_row(vpump, rate_kind::VOLUME, 100.0)
            },
        );
        bind(
            w,
            DeviceFlow {
                gases: 1 << GAS_OXYGEN,
                ..flow_row(split, rate_kind::FRACTION, 0.5)
            },
        );
        bind(
            w,
            DeviceFlow {
                stop_side: stop_side::B,
                stop_cmp: stop_cmp::AT_LEAST,
                stop_kpa: 200.0,
                limit_side: stop_side::A,
                limit_cmp: stop_cmp::AT_LEAST,
                limit_kpa: 20.0,
                ..flow_row(limited, rate_kind::VOLUME, 80.0)
            },
        );
        bind(
            w,
            DeviceFlow {
                stop_side: stop_side::B,
                stop_cmp: stop_cmp::AT_LEAST,
                stop_kpa: 120.0,
                ..flow_row(regulator, rate_kind::UNLIMITED, 0.0)
            },
        );
        // The vent releases into the room up to a target; the scrubber siphons the same turf.
        bind(
            w,
            DeviceFlow {
                stop_side: stop_side::A,
                stop_cmp: stop_cmp::AT_LEAST,
                stop_kpa: 110.0,
                ..flow_row(vent, rate_kind::VOLUME, 40.0)
            },
        );
        bind(w, flow_row(scrubber, rate_kind::VOLUME, 30.0));
        let valve_row = w
            .bind_value(
                None,
                DeviceValve {
                    device: valve.index(),
                    open: true,
                },
            )
            .unwrap();
        Rig {
            ports,
            gate_row,
            valve_row,
        }
    }

    struct Outcome {
        reports: Vec<Vec<f32>>,
        jobs: Vec<usize>,
        regions: Vec<PipeGas>,
        turfs: Vec<Option<(PipeGas, f64)>>,
    }

    fn set_rate(w: &mut World, row: EntityId, rate: f64) {
        let kind = w.kind_of::<DeviceFlow>().unwrap();
        let field = DeviceFlow::field_id("rate").unwrap();
        w.set(row, kind, field, None, rate).unwrap();
    }

    /// Runs the rig `steps` steps, staging and applying as `pace` does, poking it from outside at fixed steps. With
    /// `cache` off the settled cache is emptied before each stage, which is exactly a stager that never skips.
    fn run(cache: bool, steps: usize) -> Outcome {
        crate::world::configure_for_test(4, 4, 1).unwrap();
        let rig = with_world(|w| Ok(build_rig(w))).unwrap();
        let (mut reports, mut jobs) = (Vec::new(), Vec::new());
        for step in 0..steps {
            let staged = with_world(|w| {
                match step {
                    // DM changes a setting: the gate rate.
                    30 => set_rate(w, rig.gate_row, 350.0),
                    // DM writes a setting it already had: nothing may change.
                    45 => set_rate(w, rig.gate_row, 350.0),
                    // Gas arrives in a region from outside (a canister, a reaction).
                    60 => {
                        let port = rig.ports[4];
                        w.edit_network::<Pipes>(move |host| {
                            let region = host.region_of(port).unwrap();
                            *host.payload_mut(region).unwrap() = gas(90.0, 320.0);
                        })
                        .unwrap();
                    }
                    // The valve closes.
                    75 => {
                        let kind = w.kind_of::<DeviceValve>().unwrap();
                        let field = DeviceValve::field_id("open").unwrap();
                        w.set(rig.valve_row, kind, field, None, 0.0).unwrap();
                    }
                    _ => {}
                }
                if !cache {
                    SETTLED.take();
                }
                stage_devices(w)?;
                let staged = w
                    .global::<DeviceJobs>()
                    .map_err(|e| eyre!("{e}"))?
                    .jobs
                    .len();
                w.step_blocking();
                Ok((staged, apply_devices(w)))
            })
            .unwrap();
            jobs.push(staged.0);
            reports.push(staged.1);
        }
        with_world(|w| {
            let regions = {
                let host = w.network::<Pipes>().unwrap();
                rig.ports
                    .iter()
                    .map(|&p| *host.payload(host.region_of(p).unwrap()).unwrap())
                    .collect()
            };
            let turfs = (0..16)
                .map(|c| crate::gas::turf_device_probe(w, c))
                .collect();
            Ok(Outcome {
                reports,
                jobs,
                regions,
                turfs,
            })
        })
        .unwrap()
    }

    #[test]
    fn the_settle_cache_changes_no_gas_and_no_report_and_skips_work() {
        let count = |name: &str| crate::metrics::registry().counter(name).get();
        let probe = || {
            (
                count("stage.jobs"),
                count("stage.skipped"),
                count("frame.us.stage_device_loop"),
                count("frame.us.stage_law_index"),
            )
        };
        let t0 = probe();
        let off = run(false, 90);
        let t1 = probe();
        let on = run(true, 90);
        let t2 = probe();
        eprintln!(
            "counters over 90 steps (jobs, skipped, device_loop us, law_index us): cache off {:?}, cache on {:?}",
            (t1.0 - t0.0, t1.1 - t0.1, t1.2 - t0.2, t1.3 - t0.3),
            (t2.0 - t1.0, t2.1 - t1.1, t2.2 - t1.2, t2.3 - t1.3)
        );
        assert_eq!(
            on.reports, off.reports,
            "every step reports the same device movement"
        );
        assert_eq!(
            on.regions, off.regions,
            "every region ends with the same gas"
        );
        assert!(on.turfs == off.turfs, "the room ends with the same gas");
        assert!(
            on.jobs.iter().zip(&off.jobs).all(|(a, b)| a <= b),
            "the cache never stages a job the plain stager would not"
        );
        let (cached, plain): (usize, usize) = (on.jobs.iter().sum(), off.jobs.iter().sum());
        assert!(
            cached < plain,
            "a settling network stages fewer jobs: {cached} vs {plain}"
        );
        eprintln!(
            "settle cache: jobs staged over 90 steps {cached} (cache) vs {plain} (none); last step {} vs {}",
            on.jobs[89], off.jobs[89]
        );
    }

    #[test]
    fn every_writer_of_a_device_row_moves_its_stamp_and_a_rewrite_of_the_same_value_does_not() {
        crate::world::configure_for_test(2, 2, 1).unwrap();
        with_world(|w| {
            let kind = w.kind_of::<DeviceFlow>().unwrap();
            let device = w.spawn().unwrap();
            // bind
            let row = w
                .bind_value(None, flow_row(device, rate_kind::VOLUME, 10.0))
                .unwrap();
            let bound = w.row_stamp::<DeviceFlow>(row).unwrap();
            assert!(bound > 0, "a bound row has a stamp");
            // set (the DM write path): a new value moves it, the same value does not
            set_rate(w, row, 20.0);
            let set = w.row_stamp::<DeviceFlow>(row).unwrap();
            assert!(set > bound, "set moves the stamp");
            set_rate(w, row, 20.0);
            assert_eq!(
                w.row_stamp::<DeviceFlow>(row),
                Some(set),
                "the same value is no change"
            );
            // put (a whole-row transfer): likewise
            w.put(row, flow_row(device, rate_kind::VOLUME, 30.0))
                .unwrap();
            let put = w.row_stamp::<DeviceFlow>(row).unwrap();
            assert!(put > set, "put moves the stamp");
            w.put(row, flow_row(device, rate_kind::VOLUME, 30.0))
                .unwrap();
            assert_eq!(
                w.row_stamp::<DeviceFlow>(row),
                Some(put),
                "the same row is no change"
            );
            // another row's writes never move this one
            let other = w
                .bind_value(None, flow_row(device, rate_kind::VOLUME, 1.0))
                .unwrap();
            set_rate(w, other, 2.0);
            assert_eq!(w.row_stamp::<DeviceFlow>(row), Some(put));
            // detach and bind again: a fresh, larger stamp, never a repeat
            w.detach(row, kind).unwrap();
            assert_eq!(w.row_stamp::<DeviceFlow>(row), None, "no row, no stamp");
            let again = w
                .bind_value(Some(row), flow_row(device, rate_kind::VOLUME, 30.0))
                .unwrap();
            assert!(
                w.row_stamp::<DeviceFlow>(again).unwrap() > put,
                "a re-bound row never reuses a stamp"
            );
            // the valve kind stamps too
            let valve = w
                .bind_value(
                    None,
                    DeviceValve {
                        device: device.index(),
                        open: false,
                    },
                )
                .unwrap();
            let before = w.row_stamp::<DeviceValve>(valve).unwrap();
            let vkind = w.kind_of::<DeviceValve>().unwrap();
            w.set(
                valve,
                vkind,
                DeviceValve::field_id("open").unwrap(),
                None,
                1.0,
            )
            .unwrap();
            assert!(w.row_stamp::<DeviceValve>(valve).unwrap() > before);
            Ok(())
        })
        .unwrap();
    }

    /// The idle server in miniature, at its real device count: `COPIES` rigs (about 2700 devices) left to settle, then the
    /// stage counters per step. Run with `cargo test --release -- --ignored --nocapture idle_stage_counters`.
    #[test]
    #[ignore = "a counter measurement, not a check"]
    fn idle_stage_counters() {
        const COPIES: u32 = 300;
        const STEPS: usize = 120;
        let count = |name: &str| crate::metrics::registry().counter(name).get();
        for cache in [false, true] {
            crate::world::configure_for_test(4, 4, 1).unwrap();
            with_world(|w| {
                let key = crate::gas::turf_key().unwrap();
                let mut air = [0.0; N];
                air[0] = 82.0;
                air[1] = 21.8;
                for cell in 0..16 {
                    crate::gas::register_cell(
                        w,
                        key,
                        cell,
                        GasCell::new(air, 293.15),
                        2500.0,
                        false,
                        Some(0),
                    );
                }
                for i in 0..COPIES {
                    build_copy(w, i % 16);
                }
                Ok(())
            })
            .unwrap();
            let mut last = (0, 0, 0, 0);
            let mut tail = (0_u64, 0_u64, 0_u64, 0_u64, 0_u64);
            for step in 0..STEPS {
                let before = (
                    count("stage.jobs"),
                    count("stage.skipped"),
                    count("frame.us.stage_device_loop"),
                    count("frame.us.stage_law_index"),
                    count("frame.us.stage_set_global"),
                );
                with_world(|w| {
                    if !cache {
                        SETTLED.take();
                    }
                    stage_devices(w)?;
                    w.step_blocking();
                    let _ = apply_devices(w);
                    Ok(())
                })
                .unwrap();
                let after = (
                    count("stage.jobs"),
                    count("stage.skipped"),
                    count("frame.us.stage_device_loop"),
                    count("frame.us.stage_law_index"),
                    count("frame.us.stage_set_global"),
                );
                last = (
                    after.0 - before.0,
                    after.1 - before.1,
                    after.2 - before.2,
                    after.3 - before.3,
                );
                if step >= STEPS - 20 {
                    tail.0 += after.0 - before.0;
                    tail.1 += after.1 - before.1;
                    tail.2 += after.2 - before.2;
                    tail.3 += after.3 - before.3;
                    tail.4 += after.4 - before.4;
                }
            }
            eprintln!(
                "cache {}: devices {} | last step: jobs {}, skipped {}, device_loop {} us, law_index {} us | mean of last 20 steps: jobs {}, skipped {}, device_loop {} us, law_index {} us, set_global {} us",
                if cache { "on " } else { "off" },
                COPIES * 9,
                last.0,
                last.1,
                last.2,
                last.3,
                tail.0 / 20,
                tail.1 / 20,
                tail.2 / 20,
                tail.3 / 20,
                tail.4 / 20
            );
        }
    }

    #[test]
    fn a_settled_network_stages_fewer_jobs_and_a_changed_row_wakes_its_device() {
        crate::world::configure_for_test(4, 4, 1).unwrap();
        let rig = with_world(|w| Ok(build_rig(w))).unwrap();
        let staged = |w: &mut World| {
            stage_devices(w).unwrap();
            let n = w.global::<DeviceJobs>().unwrap().jobs.len();
            w.step_blocking();
            let _ = apply_devices(w);
            n
        };
        let counts: Vec<usize> = (0..80)
            .map(|_| with_world(|w| Ok(staged(w))).unwrap())
            .collect();
        let quiet = counts[79];
        assert!(quiet < counts[0], "the network settles: {counts:?}");
        let after_write = with_world(|w| {
            set_rate(w, rig.gate_row, 999.0);
            Ok(staged(w))
        })
        .unwrap();
        assert!(
            after_write > quiet,
            "a changed row is staged again: {quiet} -> {after_write}"
        );
    }
}
