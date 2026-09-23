//! Binds for `vg-power` (M3): the power host that composes `vg-power`'s
//! declarations and laws (`rust_architecture.md` §6) over one
//! [`NetworkHost<Cables>`] (§4.5). DM (`code/modules/power/power_bridge.dm`)
//! queues edits and commands in one flat list and sends it with
//! [`vg_power_edit`](power_edit) (an explosion's edits are one call and one
//! commit), draws synchronously, and makes one [`power_step`] call per
//! machinery tick, which returns the events it must act on.
//!
//! Everything runs on BYOND's main thread.
//!
//! **Identity.** DM still names each cable piece and power machine by a
//! dense power key (`power_key_alloc()`); that key is the row of power's
//! component store here. Every row is also an entity in the shared entity
//! table (`entity.rs`), minted when DM first sends the node, with a power
//! component (kind [`KIND_NODE`]) naming the row -- and the entity, not the
//! key, is what [`NetworkHost`] identifies the node by. A generic
//! `entity_unbind` detaches the row through [`DomainRegistry::detach`];
//! [`power_key_of`] maps an entity back to its key.
//!
//! **Laws.** The APC, SMES and region balance are `vg_power::laws`'s pure
//! functions, applied here once per step in key order (the DM machinery
//! pass's order). Region state is the network payload ([`PowerLedger`]),
//! never a side ledger.

use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, HashMap, HashSet};

use byondapi::prelude::*;
use eyre::{Result, bail, eyre};
use vg_core::entity::{ComponentRef, EntityId};
use vg_core::network::{NetworkHost, RegionEvent, RegionId};
use vg_core::units::Watts;
use vg_power::components::{Apc, Cable, ChannelSetting, Smes};
use vg_power::geom::pos;
use vg_power::laws::{self, Grid, NoGrid};
use vg_power::{Cables, PowerLedger, PowerNode};

use crate::entity;
use crate::registry::{self, DomainRegistry};

/// Power's domain index in the entity table (gas is 0).
/// @dm-define VG_DOMAIN_POWER
pub const DOMAIN: usize = 1;
/// The one component kind a power row uses: a cable piece and a machine
/// node are both rows of the same store, keyed by DM's power key.
/// @dm-define VG_POWER_NODE
pub const KIND_NODE: u16 = 1;

// --- DM constants: edit ops. Each op is `op, n, n values`. -----------------

/// `key, x, y, z, d1, d2, z_above, z_below, link_id`
/// @dm-define POWER_OP_CABLE
pub const OP_CABLE: u32 = 1;
/// `key, x, y, z`
/// @dm-define POWER_OP_MACHINE
pub const OP_MACHINE: u32 = 2;
/// `key`
/// @dm-define POWER_OP_REMOVE
pub const OP_REMOVE: u32 = 3;
/// `key, watts`: persistent supply.
/// @dm-define POWER_OP_SUPPLY
pub const OP_SUPPLY: u32 = 4;
/// `key, watts`: supply for the next step only.
/// @dm-define POWER_OP_PULSE
pub const OP_PULSE: u32 = 5;
/// `key, terminal (-1 none), flags, max_charge, chargelevel, charge (-1
/// keep), eqp, lgt, env (-1 keep), autoflag (-1 keep)`
/// @dm-define POWER_OP_APC
pub const OP_APC: u32 = 6;
/// `key, eqp, lgt, env`: the area's static load (W).
/// @dm-define POWER_OP_AREA_LOAD
pub const OP_AREA_LOAD: u32 = 7;
/// `key, eqp, lgt, env`: one-off area use (W) for the next step.
/// @dm-define POWER_OP_ONEOFF
pub const OP_ONEOFF: u32 = 8;
/// `key, flags, capacity, input_level, output_level, charge (-1 keep),
/// terminal keys...`
/// @dm-define POWER_OP_SMES
pub const OP_SMES: u32 = 9;
/// `key, charge`
/// @dm-define POWER_OP_CHARGE
pub const OP_CHARGE: u32 = 10;
/// `key`: forget an APC or SMES.
/// @dm-define POWER_OP_REMOVE_STORAGE
pub const OP_REMOVE_STORAGE: u32 = 11;

/// APC flags.
/// @dm-define POWER_APC_ACTIVE
pub const APC_ACTIVE: u32 = 1;
/// @dm-define POWER_APC_HAS_CELL
pub const APC_HAS_CELL: u32 = 2;
/// @dm-define POWER_APC_FAILED
pub const APC_FAILED: u32 = 4;
/// @dm-define POWER_APC_SHORTED
pub const APC_SHORTED: u32 = 8;
/// @dm-define POWER_APC_OPERATING
pub const APC_OPERATING: u32 = 16;
/// @dm-define POWER_APC_CHARGEMODE
pub const APC_CHARGEMODE: u32 = 32;

/// SMES flags.
/// @dm-define POWER_SMES_INPUT
pub const SMES_INPUT: u32 = 1;
/// @dm-define POWER_SMES_OUTPUT
pub const SMES_OUTPUT: u32 = 2;

// --- DM constants: events from `vg_power_step`. -----------------------------

/// @dm-define POWER_EV_BIND
pub const EV_BIND: u32 = 1;
/// @dm-define POWER_EV_REGION
pub const EV_REGION: u32 = 2;
/// @dm-define POWER_EV_RETIRED
pub const EV_RETIRED: u32 = 3;
/// @dm-define POWER_EV_APC
pub const EV_APC: u32 = 4;
/// @dm-define POWER_EV_SMES
pub const EV_SMES: u32 = 5;
/// @dm-define POWER_EV_BROWNOUT
pub const EV_BROWNOUT: u32 = 6;

/// Numbers in a `vg_power_region` reply: region, avail, load, netexcess,
/// supply, eqp, lgt, env, capacity, members.
/// @dm-define POWER_REGION_STRIDE
pub const REGION_STRIDE: u32 = 10;

const _: () = assert!(REGION_STRIDE == 10);

/// `APC_EXTERNAL_POWER_*`: what DM shows as the APC's main status.
const STATUS_NOT_CONNECTED: u8 = 0;
const STATUS_NO_ENERGY: u8 = 1;
const STATUS_GOOD: u8 = 2;

/// Node kinds in the graph.
const NODE_CABLE: u16 = 0;
const NODE_MACHINE: u16 = 1;

/// One power component row: a cable piece or a machine node DM named by
/// `key`.
struct Row {
    entity: EntityId,
    /// `None`: a machine node.
    cable: Option<Cable>,
    /// Registered persistent supply (W).
    supply: f64,
    /// One-step supply (a legacy `add_avail` pulse), added at the next step.
    pulse: f64,
    /// The APC this machine is the terminal of.
    serves_apc: Option<u32>,
    /// Machines only: the region last reported to DM in a `POWER_EV_BIND`
    /// (`u32::MAX`: never reported).
    bound: u32,
}

/// An APC component plus what DM reads back from it.
struct ApcRow {
    apc: Apc,
    terminal: Option<u32>,
    main_status: u8,
    /// Used equipment, lighting, environment, charging, total (W).
    lastused: [f64; 5],
}

/// A SMES component plus its per-step plan and results.
struct SmesRow {
    smes: Smes,
    terminals: Vec<u32>,
    offer: f64,
    target_load: f64,
    inputting: u8,
    outputting: u8,
    output_used: f64,
    input_available: f64,
}

#[derive(Default)]
struct PowerHost {
    net: NetworkHost<Cables>,
    rows: Vec<Option<Row>>,
    apcs: BTreeMap<u32, ApcRow>,
    smes: BTreeMap<u32, SmesRow>,
    /// Storage (SMES) output offered on each region this step: the part of
    /// `avail` that is used last.
    storage_offer: HashMap<RegionId<Cables>, f64>,
    /// Regions that existed at the last step (a new region's first
    /// brownout state is not an event).
    known: HashSet<RegionId<Cables>>,
    /// Regions whose last reported numbers were non-zero.
    live: HashSet<RegionId<Cables>>,
    /// Machine keys removed since the last commit, reported as unbound.
    unbound: Vec<u32>,
    out: Vec<f32>,
}

/// A region as DM sees it: the raw handle bits plus one (never 0, DM's
/// null), exact in f32.
fn region_id(r: RegionId<Cables>) -> u32 {
    r.raw().bits() + 1
}

#[allow(clippy::cast_possible_truncation, clippy::cast_precision_loss)]
fn push(out: &mut Vec<f32>, kind: u32, values: &[f64]) {
    out.push(kind as f32);
    out.push(values.len() as f32);
    out.extend(values.iter().map(|&v| v as f32));
}

const fn channel_code(c: ChannelSetting) -> u8 {
    match c {
        ChannelSetting::Off => 0,
        ChannelSetting::OffAuto => 1,
        ChannelSetting::On => 2,
        ChannelSetting::OnAuto => 3,
    }
}

const fn channel_of(code: u32) -> ChannelSetting {
    match code {
        0 => ChannelSetting::Off,
        1 => ChannelSetting::OffAuto,
        2 => ChannelSetting::On,
        _ => ChannelSetting::OnAuto,
    }
}

/// Area demand this step: one-offs always, static load while the channel
/// is on.
fn apc_demand(apc: &Apc) -> [Watts; 3] {
    [0, 1, 2].map(|c| {
        let base = if apc.channels[c].powered() {
            apc.static_load[c]
        } else {
            Watts::ZERO
        };
        apc.oneoff[c] + base
    })
}

/// Area channel bits (1 equipment, 2 lighting, 4 environment).
fn apc_channel_bits(apc: &Apc) -> u8 {
    let on = apc.operating && !apc.shorted_or_grid_check && !apc.failed;
    (0..3).fold(0, |b, c| b | (u8::from(on && apc.channels[c].powered()) << c))
}

/// `chargedisplay()`: the five-step charge gauge.
#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn smes_display(s: &Smes) -> u8 {
    let cap = if s.charge.capacity > 0.0 {
        s.charge.capacity
    } else {
        5e6
    };
    (5.5 * s.charge.charge / cap).round() as u8
}

/// A region payload as one law's [`Grid`].
struct LedgerGrid<'a>(&'a mut PowerLedger);

impl Grid for LedgerGrid<'_> {
    fn avail(&self) -> Watts {
        self.0.avail
    }
    fn surplus(&self) -> Watts {
        self.0.netexcess()
    }
    fn draw(&mut self, watts: Watts) -> Watts {
        let d = watts.get().min(self.0.netexcess().get()).max(0.0);
        self.0.load += Watts(d);
        Watts(d)
    }
}

impl PowerHost {
    fn row(&self, key: u32) -> Option<&Row> {
        self.rows.get(key as usize).and_then(Option::as_ref)
    }

    fn row_mut(&mut self, key: u32) -> Option<&mut Row> {
        self.rows.get_mut(key as usize).and_then(Option::as_mut)
    }

    fn row_count(&self) -> u32 {
        u32::try_from(self.rows.len()).unwrap_or(u32::MAX)
    }

    fn region_of_key(&self, key: u32) -> Option<RegionId<Cables>> {
        self.net.region_of(self.row(key)?.entity)
    }

    /// The node data `key` contributes: a cable's shape, or a machine's
    /// supply and the area demand it serves as an APC terminal.
    fn node_data(&self, key: u32) -> Option<PowerNode> {
        let row = self.row(key)?;
        Some(match row.cable {
            Some(c) => PowerNode::Cable(c),
            None => PowerNode::Machine {
                supply: Watts(row.supply),
                demand: row
                    .serves_apc
                    .and_then(|a| self.apcs.get(&a))
                    .map_or([Watts::ZERO; 3], |a| apc_demand(&a.apc)),
            },
        })
    }

    fn refresh_node(&mut self, key: u32) {
        let Some(data) = self.node_data(key) else {
            return;
        };
        let entity = self.row(key).expect("node_data found it").entity;
        let current = self
            .net
            .node_of(entity)
            .and_then(|n| self.net.network().node(n).ok())
            .map(|n| &n.data);
        if current != Some(&data) {
            let _ = self.net.set_node_data(entity, data);
        }
    }

    /// Creates or replaces `key`'s node (a cable if `cable` is given).
    fn add_node(&mut self, key: u32, p: u32, cable: Option<Cable>) -> Result<()> {
        if key >= vg_core::entity::MAX_SLOTS {
            bail!("power key {key} out of range");
        }
        let i = key as usize;
        if self.rows.len() <= i {
            self.rows.resize_with(i + 1, || None);
        }
        let old = self.rows[i].take();
        let entity = if let Some(row) = old.as_ref() {
            self.net.unbind_node(row.entity);
            row.entity
        } else {
            ensure_registered();
            let id = entity::bind_or_reuse(0.0)?;
            entity::attach(id, DOMAIN, ComponentRef::new(KIND_NODE, key)).map_err(|e| eyre!("{e}"))?;
            id
        };
        self.rows[i] = Some(Row {
            entity,
            cable,
            supply: old.as_ref().map_or(0.0, |r| r.supply),
            pulse: 0.0,
            serves_apc: old.as_ref().and_then(|r| r.serves_apc),
            bound: old.as_ref().map_or(u32::MAX, |r| r.bound),
        });
        let data = self.node_data(key).expect("just stored");
        let kind = if cable.is_some() { NODE_CABLE } else { NODE_MACHINE };
        self.net.bind_node(entity, p, kind, data).map_err(|e| eyre!("{e}"))?;
        Ok(())
    }

    /// Drops `key`'s row and node. `release` frees its entity too (false
    /// when the entity table is already unbinding it).
    fn remove(&mut self, key: u32, release: bool) {
        let Some(row) = self.rows.get_mut(key as usize).and_then(Option::take) else {
            return;
        };
        self.net.unbind_node(row.entity);
        if release {
            entity::release(row.entity);
        }
        if row.cable.is_none() {
            self.unbound.push(key);
        }
    }

    /// Commits pending topology, re-plans the regions it touched and
    /// reports machine rebinds and retired regions.
    fn commit(&mut self) {
        let mut touched: Vec<RegionId<Cables>> = Vec::new();
        for e in self.net.commit() {
            match e {
                RegionEvent::Created { region } | RegionEvent::Changed { region } => touched.push(region),
                RegionEvent::Merged { into, from } => {
                    self.retire(from);
                    touched.push(into);
                }
                RegionEvent::Split { from, into } => {
                    touched.push(from);
                    touched.push(into);
                }
                RegionEvent::Retired { region } => self.retire(region),
                RegionEvent::Released { .. } | RegionEvent::DeviceDetached { .. } => {}
            }
        }
        touched.sort_by_key(|r| r.raw().bits());
        touched.dedup();
        touched.retain(|r| self.net.network().region(*r).is_ok());
        if !touched.is_empty() {
            self.plan(&touched);
        }
        for key in std::mem::take(&mut self.unbound) {
            if self.row(key).is_none() {
                push(&mut self.out, EV_BIND, &[f64::from(key), 0.0, 0.0]);
            }
        }
        // A machine is bound to its region while that region holds more
        // than the machine itself (a cable reached it).
        for key in 0..self.row_count() {
            let Some(row) = self.row(key) else {
                continue;
            };
            if row.cable.is_some() {
                continue;
            }
            let (region, members) = self
                .net
                .region_of(row.entity)
                .and_then(|r| self.net.network().region(r).ok().map(|x| (region_id(r), x.members())))
                .unwrap_or((0, 0));
            let bound = if members > 1 { region } else { 0 };
            if row.bound != bound {
                push(&mut self.out, EV_BIND, &[f64::from(key), f64::from(bound), f64::from(members)]);
                self.row_mut(key).expect("listed").bound = bound;
            }
        }
    }

    fn retire(&mut self, region: RegionId<Cables>) {
        self.known.remove(&region);
        self.live.remove(&region);
        self.storage_offer.remove(&region);
        push(&mut self.out, EV_RETIRED, &[f64::from(region_id(region))]);
    }

    fn commit_if_pending(&mut self) {
        if self.net.network().has_pending() {
            self.commit();
        }
    }

    /// Plans `regions`' supply for the coming step: registered supply
    /// (the region summary) plus SMES output offers.
    fn plan(&mut self, regions: &[RegionId<Cables>]) {
        let mut offers: HashMap<RegionId<Cables>, f64> = HashMap::new();
        let keys: Vec<u32> = self.smes.keys().copied().collect();
        for key in keys {
            let region = self.region_of_key(key);
            let s = self.smes.get_mut(&key).expect("listed");
            s.offer = laws::smes_plan(&s.smes, region.is_some(), false).offer.get();
            s.outputting = if s.offer > 0.0 {
                2
            } else {
                u8::from(region.is_none() || s.smes.charge.charge <= 0.0)
            };
            if let Some(r) = region {
                *offers.entry(r).or_default() += s.offer;
            }
        }
        for &r in regions {
            let Ok(region) = self.net.network().region(r) else {
                continue;
            };
            let offer = offers.get(&r).copied().unwrap_or(0.0);
            let supply = laws::planned_supply([region.summary().supply], [Watts(offer)]);
            if let Ok(p) = self.net.payload_mut(r) {
                p.avail = supply;
            }
            self.storage_offer.insert(r, offer);
        }
    }

    fn all_regions(&self) -> Vec<RegionId<Cables>> {
        self.net.network().regions().map(|(r, _)| r).collect()
    }

    fn draw(&mut self, key: u32, watts: f64) -> f64 {
        self.commit_if_pending();
        let Some(r) = self.region_of_key(key) else {
            return 0.0;
        };
        self.net
            .payload_mut(r)
            .map_or(0.0, |p| LedgerGrid(p).draw(Watts(watts)).get())
    }

    /// One machinery tick: pulses, APCs, storage input and output, region
    /// balance and brownouts, then the next step's supply. Returns the
    /// events (the `POWER_EV_*` records), including those commits since
    /// the last step buffered.
    fn step(&mut self) -> Vec<f32> {
        self.commit();

        // Pulses: one-step supply on the pulsing machine's region.
        for key in 0..self.row_count() {
            let pulse = match self.row_mut(key) {
                Some(row) => std::mem::take(&mut row.pulse),
                None => continue,
            };
            if pulse > 0.0
                && let Some(r) = self.region_of_key(key)
                && let Ok(p) = self.net.payload_mut(r)
            {
                p.avail += Watts(pulse);
            }
        }

        self.step_apcs();
        self.step_smes();

        // Region balance, brownouts, and the published numbers.
        let regions = self.all_regions();
        for &r in &regions {
            let Ok(p) = self.net.payload_mut(r) else {
                continue;
            };
            let brown = laws::brownout(p.avail, p.load);
            let was_brown = std::mem::replace(&mut p.brown, brown);
            let (avail, load) = (p.avail.get(), p.load.get());
            p.load = Watts::ZERO;
            let id = f64::from(region_id(r));
            let nonzero = avail > 0.0 || load > 0.0;
            if nonzero || self.live.contains(&r) {
                push(&mut self.out, EV_REGION, &[id, avail, load, avail - load]);
            }
            if nonzero {
                self.live.insert(r);
            } else {
                self.live.remove(&r);
            }
            if !self.known.insert(r) && brown != was_brown {
                push(&mut self.out, EV_BROWNOUT, &[id, f64::from(u8::from(brown))]);
            }
        }
        self.plan(&regions);
        self.report_storage();
        std::mem::take(&mut self.out)
    }

    fn step_apcs(&mut self) {
        let keys: Vec<u32> = self.apcs.keys().copied().collect();
        for key in keys {
            let terminal = self.apcs[&key].terminal;
            let region = terminal.and_then(|t| self.region_of_key(t));
            let Self { net, apcs, .. } = self;
            let a = apcs.get_mut(&key).expect("listed");
            let demand = apc_demand(&a.apc);
            if a.apc.active {
                a.lastused = [
                    demand[0].get(),
                    demand[1].get(),
                    demand[2].get(),
                    0.0,
                    demand.iter().map(|w| w.get()).sum(),
                ];
            }
            let payload = region.and_then(|r| net.payload_mut(r).ok());
            a.main_status = match &payload {
                Some(p) if p.avail.get() > 0.0 && p.netexcess().get() < 0.0 => STATUS_NO_ENERGY,
                Some(p) if p.avail.get() > 0.0 => STATUS_GOOD,
                _ => STATUS_NOT_CONNECTED,
            };
            let (_, charged) = match payload {
                Some(p) => laws::apc_tick(&mut a.apc, demand, &mut LedgerGrid(p)),
                None => laws::apc_tick(&mut a.apc, demand, &mut NoGrid),
            };
            if a.apc.active {
                a.lastused[3] = charged.get();
            }
            if apc_demand(&a.apc) != demand
                && let Some(t) = terminal
            {
                self.refresh_node(t);
            }
        }
    }

    fn step_smes(&mut self) {
        let keys: Vec<u32> = self.smes.keys().copied().collect();

        // Input: what each terminal region has left over, shared in
        // proportion to what the units ask for.
        let mut asks: HashMap<RegionId<Cables>, f64> = HashMap::new();
        let mut inputs: Vec<(u32, Vec<RegionId<Cables>>)> = Vec::with_capacity(keys.len());
        for &key in &keys {
            let mut regions: Vec<RegionId<Cables>> = self.smes[&key]
                .terminals
                .iter()
                .filter_map(|&t| self.region_of_key(t))
                .collect();
            regions.sort_by_key(|r| r.raw().bits());
            regions.dedup();
            let output_connected = self.region_of_key(key).is_some();
            let s = self.smes.get_mut(&key).expect("listed");
            s.target_load = laws::smes_plan(&s.smes, output_connected, !regions.is_empty())
                .target_load
                .get();
            for r in &regions {
                *asks.entry(*r).or_default() += s.target_load;
            }
            inputs.push((key, regions));
        }
        let excess: HashMap<RegionId<Cables>, f64> = asks
            .keys()
            .map(|&r| (r, self.net.payload(r).map_or(0.0, |p| p.netexcess().get().max(0.0))))
            .collect();
        for (key, regions) in inputs {
            let Self { net, smes, .. } = self;
            let s = smes.get_mut(&key).expect("listed");
            let mut got = 0.0;
            for r in regions {
                let share = laws::storage_input_share(Watts(s.target_load), Watts(asks[&r]), Watts(excess[&r]));
                if let Ok(p) = net.payload_mut(r) {
                    got += LedgerGrid(p).draw(share).get();
                }
            }
            laws::smes_charge_in(&mut s.smes, Watts(got));
            s.input_available = got;
            s.inputting = if got <= 0.0 {
                0
            } else if got + 0.01 >= s.target_load {
                2
            } else {
                1
            };
        }

        // Output: storage is the last supply to be used.
        for key in keys {
            let used = self.region_of_key(key).and_then(|r| {
                let p = self.net.payload(r)?;
                let offered = self.storage_offer.get(&r).copied().unwrap_or(0.0);
                let non_storage = (p.avail.get() - offered).max(0.0);
                Some(((p.load.get() - non_storage).clamp(0.0, offered), offered))
            });
            let s = self.smes.get_mut(&key).expect("listed");
            s.output_used = match used {
                Some((used, offered)) => {
                    let share = laws::storage_output_share(Watts(s.offer), Watts(offered), Watts(used));
                    laws::smes_discharge_out(&mut s.smes, share).get()
                }
                None => 0.0,
            };
        }
    }

    fn report_storage(&mut self) {
        for (&key, a) in &self.apcs {
            let apc = &a.apc;
            push(
                &mut self.out,
                EV_APC,
                &[
                    f64::from(key),
                    apc.cell.charge,
                    f64::from(channel_code(apc.channels[0])),
                    f64::from(channel_code(apc.channels[1])),
                    f64::from(channel_code(apc.channels[2])),
                    f64::from(apc.charging),
                    f64::from(a.main_status),
                    f64::from(u8::from(apc.alarm)),
                    f64::from(apc.autoflag),
                    a.lastused[0],
                    a.lastused[1],
                    a.lastused[2],
                    a.lastused[3],
                    a.lastused[4],
                    f64::from(apc_channel_bits(apc)),
                ],
            );
        }
        for (&key, s) in &self.smes {
            push(
                &mut self.out,
                EV_SMES,
                &[
                    f64::from(key),
                    s.smes.charge.charge,
                    f64::from(s.inputting),
                    f64::from(s.outputting),
                    s.output_used,
                    s.input_available,
                    f64::from(smes_display(&s.smes)),
                ],
            );
        }
    }

    fn set_supply(&mut self, key: u32, watts: f64) {
        if let Some(row) = self.row_mut(key) {
            row.supply = watts.max(0.0);
            self.refresh_node(key);
        }
    }

    fn set_apc_terminal(&mut self, key: u32, terminal: Option<u32>) {
        let old = self.apcs.get(&key).and_then(|a| a.terminal);
        if old == terminal {
            return;
        }
        if let Some(t) = old {
            if let Some(row) = self.row_mut(t) {
                row.serves_apc = None;
            }
            self.refresh_node(t);
        }
        if let Some(a) = self.apcs.get_mut(&key) {
            a.terminal = terminal;
        }
        if let Some(t) = terminal
            && let Some(row) = self.row_mut(t)
        {
            row.serves_apc = Some(key);
        }
    }

    fn remove_storage(&mut self, key: u32) {
        if self.apcs.contains_key(&key) {
            self.set_apc_terminal(key, None);
            self.apcs.remove(&key);
        }
        self.smes.remove(&key);
    }

    fn release_all(&mut self) {
        for row in self.rows.drain(..).flatten() {
            entity::release(row.entity);
        }
    }
}

thread_local! {
    static HOST: RefCell<PowerHost> = RefCell::new(PowerHost::default());
    static REGISTERED: Cell<bool> = const { Cell::new(false) };
}

fn with<T>(f: impl FnOnce(&mut PowerHost) -> Result<T>) -> Result<T> {
    HOST.with(|w| f(&mut w.borrow_mut()))
}

/// Power's [`DomainRegistry`] handler: the generic unbind (`entity_unbind`)
/// and `verdigris_init`/`verdigris_cleanup` drive this without knowing
/// power exists.
struct Shared;

impl DomainRegistry for Shared {
    fn detach(&mut self, comp: ComponentRef) {
        if comp.kind != KIND_NODE {
            return;
        }
        HOST.with_borrow_mut(|h| h.remove(comp.cell, false));
    }

    fn describe(&self, comp: ComponentRef) -> Vec<(String, String)> {
        if comp.kind != KIND_NODE {
            return Vec::new();
        }
        vec![("power_key".into(), comp.cell.to_string())]
    }

    fn reset(&mut self) {
        // The entity table itself is rebuilt by the caller
        // (`entity::reset_all`).
        HOST.with_borrow_mut(|h| *h = PowerHost::default());
    }
}

fn ensure_registered() {
    REGISTERED.with(|done| {
        if !done.get() {
            #[allow(clippy::cast_possible_truncation)]
            registry::register_domain(DOMAIN as u32, Box::new(Shared));
            done.set(true);
        }
    });
}

fn list(values: &[f32]) -> Result<ByondValue> {
    let items: Vec<ByondValue> = values.iter().map(|&v| ByondValue::from(v)).collect();
    let list = ByondValue::new_list()?;
    list.write_list(&items)?;
    Ok(list)
}

fn key_of(v: f32) -> Result<u32> {
    if !(v >= 0.0 && v.fract() == 0.0 && v < 16_777_216.0) {
        bail!("bad power key {v}");
    }
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    Ok(v as u32)
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn small(v: f32) -> u32 {
    v.max(0.0) as u32
}

fn keep(v: f32) -> Option<f32> {
    (v >= 0.0).then_some(v)
}

fn watts(v: f32) -> Watts {
    Watts::from(v.max(0.0))
}

fn apply(w: &mut PowerHost, op: u32, a: &[f32]) -> Result<()> {
    let need = |n: usize| -> Result<()> {
        if a.len() < n {
            bail!("power op {op} needs {n} values, got {}", a.len());
        }
        Ok(())
    };
    match op {
        OP_CABLE => {
            need(9)?;
            let cable = Cable {
                d1: u8::try_from(small(a[4]))?,
                d2: u8::try_from(small(a[5]))?,
                up: small(a[6]),
                down: small(a[7]),
                link: small(a[8]),
            };
            let p = pos(small(a[1]), small(a[2]), small(a[3]));
            w.add_node(key_of(a[0])?, p, Some(cable))?;
        }
        OP_MACHINE => {
            need(4)?;
            let p = pos(small(a[1]), small(a[2]), small(a[3]));
            w.add_node(key_of(a[0])?, p, None)?;
        }
        OP_REMOVE => {
            need(1)?;
            w.remove(key_of(a[0])?, true);
        }
        OP_SUPPLY => {
            need(2)?;
            w.set_supply(key_of(a[0])?, f64::from(a[1]));
        }
        OP_PULSE => {
            need(2)?;
            if a[1] > 0.0
                && let Some(row) = w.row_mut(key_of(a[0])?)
            {
                row.pulse += f64::from(a[1]);
            }
        }
        OP_APC => {
            need(10)?;
            let key = key_of(a[0])?;
            let terminal = (a[1] >= 0.0).then(|| key_of(a[1])).transpose()?;
            let flags = small(a[2]);
            let row = w.apcs.entry(key).or_insert_with(|| ApcRow {
                apc: Apc::default(),
                terminal: None,
                main_status: STATUS_NOT_CONNECTED,
                lastused: [0.0; 5],
            });
            let apc = &mut row.apc;
            apc.active = flags & APC_ACTIVE != 0;
            apc.has_cell = flags & APC_HAS_CELL != 0;
            apc.failed = flags & APC_FAILED != 0;
            apc.shorted_or_grid_check = flags & APC_SHORTED != 0;
            apc.operating = flags & APC_OPERATING != 0;
            apc.chargemode = flags & APC_CHARGEMODE != 0;
            apc.cell.capacity = f64::from(a[3].max(0.0));
            apc.chargelevel = f64::from(a[4].max(0.0));
            if let Some(c) = keep(a[5]) {
                apc.cell.charge = f64::from(c);
            }
            apc.cell.clamp();
            for (i, v) in a[6..9].iter().enumerate() {
                if let Some(c) = keep(*v) {
                    apc.channels[i] = channel_of(small(c));
                }
            }
            if let Some(f) = keep(a[9]) {
                apc.autoflag = u8::try_from(small(f).min(255))?;
            }
            w.set_apc_terminal(key, terminal);
            if let Some(t) = terminal {
                w.refresh_node(t);
            }
        }
        OP_AREA_LOAD => {
            need(4)?;
            let key = key_of(a[0])?;
            if let Some(row) = w.apcs.get_mut(&key) {
                row.apc.static_load = [watts(a[1]), watts(a[2]), watts(a[3])];
                if let Some(t) = row.terminal {
                    w.refresh_node(t);
                }
            }
        }
        OP_ONEOFF => {
            need(4)?;
            if let Some(row) = w.apcs.get_mut(&key_of(a[0])?) {
                for (o, v) in row.apc.oneoff.iter_mut().zip([a[1], a[2], a[3]]) {
                    *o += watts(v);
                }
            }
        }
        OP_SMES => {
            need(6)?;
            let key = key_of(a[0])?;
            let flags = small(a[1]);
            let terminals = a[6..].iter().map(|&t| key_of(t)).collect::<Result<Vec<u32>>>()?;
            let row = w.smes.entry(key).or_insert_with(|| SmesRow {
                smes: Smes::default(),
                terminals: Vec::new(),
                offer: 0.0,
                target_load: 0.0,
                inputting: 0,
                outputting: 0,
                output_used: 0.0,
                input_available: 0.0,
            });
            let s = &mut row.smes;
            s.charge.capacity = f64::from(a[2].max(0.0));
            s.input_level = watts(a[3]);
            s.output_level = watts(a[4]);
            s.input_enabled = flags & SMES_INPUT != 0;
            s.output_enabled = flags & SMES_OUTPUT != 0;
            if let Some(c) = keep(a[5]) {
                s.charge.charge = f64::from(c);
            }
            s.charge.clamp();
            row.terminals = terminals;
        }
        OP_CHARGE => {
            need(2)?;
            let key = key_of(a[0])?;
            let charge = f64::from(a[1]);
            if let Some(row) = w.apcs.get_mut(&key) {
                row.apc.cell.charge = charge;
                row.apc.cell.clamp();
            }
            if let Some(row) = w.smes.get_mut(&key) {
                row.smes.charge.charge = charge;
                row.smes.charge.clamp();
            }
        }
        OP_REMOVE_STORAGE => {
            need(1)?;
            w.remove_storage(key_of(a[0])?);
        }
        _ => bail!("unknown power op {op}"),
    }
    Ok(())
}

/// Applies a flat list of edits and commands (`op, n, n values` each; the
/// `POWER_OP_*` defines). Topology waits for the next read or step, so a
/// batch commits once.
#[auxmacros::bind("/proc/power_edit")]
fn power_edit(ops: ByondValue) -> Result<ByondValue> {
    let values: Vec<f32> = ops
        .get_list_values()?
        .iter()
        .map(|v| Ok(v.get_number()?))
        .collect::<Result<Vec<f32>>>()?;
    with(|w| {
        let mut i = 0;
        while i + 1 < values.len() {
            let op = small(values[i]);
            let n = small(values[i + 1]) as usize;
            let end = (i + 2 + n).min(values.len());
            apply(w, op, &values[i + 2..end])?;
            i = end;
        }
        Ok(())
    })?;
    Ok(ByondValue::null())
}

/// One machinery tick. Returns the events as `type, n, n values` records
/// (the `POWER_EV_*` defines).
#[auxmacros::bind("/proc/power_step")]
fn power_step() -> Result<ByondValue> {
    let events = with(|w| Ok(w.step()))?;
    list(&events)
}

/// Draws up to `watts` for `key` from its region now; returns what was
/// delivered.
#[auxmacros::bind("/proc/power_draw")]
fn power_draw(key: ByondValue, watts: ByondValue) -> Result<ByondValue> {
    let key = key_of(key.get_number()?)?;
    let watts = f64::from(watts.get_number()?);
    #[allow(clippy::cast_possible_truncation)]
    let got = with(|w| Ok(w.draw(key, watts)))? as f32;
    Ok(ByondValue::from(got))
}

/// The region `key` is on, `POWER_REGION_STRIDE` numbers (region, avail,
/// load, netexcess, supply, eqp, lgt, env, 0 (reserved), members), or
/// null.
#[auxmacros::bind("/proc/power_region")]
fn power_region(key: ByondValue) -> Result<ByondValue> {
    let key = key_of(key.get_number()?)?;
    let values = with(|w| {
        w.commit_if_pending();
        let Some(r) = w.region_of_key(key) else {
            return Ok(None);
        };
        let Ok(region) = w.net.network().region(r) else {
            return Ok(None);
        };
        let p = region.payload();
        let s = region.summary();
        #[allow(clippy::cast_precision_loss)]
        Ok(Some([
            region_id(r) as f32,
            f32::from(p.avail),
            f32::from(p.load),
            f32::from(p.netexcess()),
            f32::from(s.supply),
            f32::from(s.demand[0]),
            f32::from(s.demand[1]),
            f32::from(s.demand[2]),
            0.0,
            region.members() as f32,
        ]))
    })?;
    match values {
        Some(v) => list(&v),
        None => Ok(ByondValue::null()),
    }
}

/// Keys of every cable and machine on `key`'s region.
#[auxmacros::bind("/proc/power_members")]
fn power_members(key: ByondValue) -> Result<ByondValue> {
    let key = key_of(key.get_number()?)?;
    let keys = with(|w| {
        w.commit_if_pending();
        let Some(r) = w.region_of_key(key) else {
            return Ok(Vec::new());
        };
        #[allow(clippy::cast_precision_loss)]
        Ok(w.net
            .members(r)
            .into_iter()
            .filter_map(|e| entity::component_of(e, DOMAIN, KIND_NODE))
            .map(|c| c.cell as f32)
            .collect::<Vec<f32>>())
    })?;
    list(&keys)
}

/// Forgets everything (world start and admin repair), freeing every
/// entity the power rows minted.
#[auxmacros::bind("/proc/power_reset")]
fn power_reset() -> Result<ByondValue> {
    with(|w| {
        w.release_all();
        *w = PowerHost::default();
        Ok(())
    })?;
    Ok(ByondValue::null())
}

/// This entity's power key, or `null` if it has no power component.
///
/// # Errors
/// A bad `entity` value.
#[auxmacros::bind("/proc/power_key_of")]
fn power_key_of(entity: ByondValue) -> Result<ByondValue> {
    let v = entity.get_number()?;
    if v == 0.0 {
        return Ok(ByondValue::null());
    }
    #[allow(clippy::cast_precision_loss)]
    match entity::resolve(v, DOMAIN, KIND_NODE) {
        Ok(comp) => Ok(ByondValue::from(comp.cell as f32)),
        Err(_) => Ok(ByondValue::null()),
    }
}
