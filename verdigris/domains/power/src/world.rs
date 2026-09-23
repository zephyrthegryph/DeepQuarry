//! [`PowerWorld`]: the main-thread power host. It owns the cable network,
//! the per-region ledgers, the APCs and SMES units, and turns DM's edits
//! and commands into one [`PowerWorld::step`] per machinery tick that
//! returns the events DM must act on.
//!
//! **Keys.** DM names every cable piece and power machine by a dense key it
//! allocates (below [`MAX_KEY`]). APCs and SMES units are storage entries
//! keyed by their own machine key; an APC is not a node (it connects
//! through its terminal), a SMES is (its output side) and its terminals are.
//!
//! **Geometry.** DM sends where each piece is (`pos`, `d1`, `d2`); the
//! connection rule of `get_connections()` runs here ([`crate::geom`]), so
//! DM never floods the graph. Edits wait for the next commit, which runs
//! at most once per DM call that needs regions: a whole explosion's worth
//! of removed cables is one commit.
//!
//! **Ledger.** Per region and step: `avail` (registered generator supply,
//! one-step pulses and SMES output offered), `load` (every delivered draw).
//! A draw never exceeds `avail - load`. APCs and SMES run inside the step
//! in key order, exactly as the DM machinery pass ran them, and the step
//! ends by planning the next step's supply.

use std::collections::{BTreeMap, HashMap};

use vg_core::RawHandle;
use vg_core::network::{Network, NodeId, RegionEvent, RegionId};

use crate::apc::{Apc, ApcConfig, ApcState, CELLRATE, Grid};
use crate::geom::CableShape;
use crate::kind::{Cables, Load, Summary, sum};
use crate::smes::{SMESRATE, Smes, SmesConfig};

/// Keys are dense indices below this.
pub const MAX_KEY: u32 = vg_core::handle::MAX_SLOTS;

/// Event record types in [`PowerWorld::step`]'s output. Every record is
/// `[type, n, n values...]`.
pub mod ev {
    /// A machine node's region changed: `key, region, members` (region 0:
    /// on no cable).
    pub const BIND: u32 = 1;
    /// A region's published numbers changed: `region, avail, load,
    /// viewavail, viewload, netexcess`.
    pub const REGION: u32 = 2;
    /// A region no longer exists: `region`.
    pub const RETIRED: u32 = 3;
    /// An APC's shown state changed: `key, charge, eqp, lgt, env, charging,
    /// main_status, alarm, autoflag, used_eqp, used_lgt, used_env,
    /// used_charging, used_total, area_bits`.
    pub const APC: u32 = 4;
    /// A SMES changed: `key, charge, inputting, outputting, output_used,
    /// input_available, display`.
    pub const SMES: u32 = 5;
    /// A region browned out (1) or was restored (0): `region, state`.
    pub const BROWNOUT: u32 = 6;
}

/// Energy books since creation (watt-ticks), for conservation checks.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Books {
    /// Offered by generators and pulses (not storage).
    pub generated: f64,
    /// Offered by storage output.
    pub storage_offered: f64,
    /// Delivered to loads (draws, APCs, storage input).
    pub delivered: f64,
    /// Taken out of storage output.
    pub storage_out: f64,
    /// Put into storage input.
    pub storage_in: f64,
}

#[derive(Clone, Debug)]
struct Obj {
    pos: u32,
    node: NodeId<Cables>,
    /// `None`: a machine node.
    shape: Option<CableShape>,
}

/// One region's accounting.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Ledger {
    avail: f64,
    smes_avail: f64,
    load: f64,
    viewavail: f64,
    viewload: f64,
    netexcess: f64,
    brown: bool,
    /// Last published numbers.
    shown: [f64; 5],
    shown_brown: bool,
    fresh: bool,
}

/// Region numbers as DM reads them.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RegionInfo {
    pub region: u32,
    pub avail: f64,
    pub load: f64,
    pub viewavail: f64,
    pub viewload: f64,
    pub netexcess: f64,
    pub summary: Summary,
    pub members: u32,
    pub pool: f64,
}

struct RegionGrid<'a> {
    ledger: &'a mut Ledger,
    delivered: &'a mut f64,
}

impl Grid for RegionGrid<'_> {
    fn avail(&self) -> f64 {
        self.ledger.avail
    }
    fn surplus(&self) -> f64 {
        self.ledger.avail - self.ledger.load
    }
    fn draw(&mut self, watts: f64) -> f64 {
        let d = watts.min(self.ledger.avail - self.ledger.load).max(0.0);
        self.ledger.load += d;
        *self.delivered += d;
        d
    }
}

/// A grid with nothing on it (an APC without a terminal region).
struct NoGrid;

impl Grid for NoGrid {
    fn avail(&self) -> f64 {
        0.0
    }
    fn surplus(&self) -> f64 {
        0.0
    }
    fn draw(&mut self, _: f64) -> f64 {
        0.0
    }
}

/// The power host. See the module docs.
#[derive(Default)]
pub struct PowerWorld {
    net: Network<Cables>,
    objs: Vec<Option<Obj>>,
    at: HashMap<u32, Vec<u32>>,
    links: HashMap<u32, Vec<u32>>,
    ledgers: HashMap<RawHandle, Ledger>,
    apcs: BTreeMap<u32, Apc>,
    smes: BTreeMap<u32, Smes>,
    /// Terminal node key -> the APC it serves.
    apc_terminal: HashMap<u32, u32>,
    /// Persistent supply per machine node key.
    supply: HashMap<u32, f64>,
    /// One-step supply per machine node key (legacy `add_avail` pulses).
    pulses: HashMap<u32, f64>,
    /// Last reported region per machine node key.
    bound: HashMap<u32, u32>,
    shown_apc: HashMap<u32, ApcState>,
    shown_smes: HashMap<u32, [f64; 6]>,
    books: Books,
    out: Vec<f32>,
    touched: Vec<NodeId<Cables>>,
    scratch_devices: Vec<vg_core::network::DeviceId<Cables>>,
    steps: u64,
}

/// Region id as DM sees it: the raw handle bits plus one, so no region is 0
/// (DM's null); at most 2^24, exact in f32.
#[must_use]
pub fn region_id(r: RegionId<Cables>) -> u32 {
    raw_id(r.raw())
}

fn raw_id(r: RawHandle) -> u32 {
    r.bits() + 1
}

/// A monitor-visible change: any number moving by more than 1% (or 1 W), or
/// crossing zero. The smoothed view settles geometrically; without this each
/// region would publish for ~50 steps after every change.
fn visibly_changed(old: &[f64; 5], new: &[f64; 5]) -> bool {
    old.iter().zip(new).any(|(&a, &b)| {
        (a > 0.0) != (b > 0.0) || (a - b).abs() > (0.01 * a.abs().max(b.abs())).max(1.0)
    })
}

fn push(out: &mut Vec<f32>, kind: u32, values: &[f64]) {
    out.push(kind as f32);
    out.push(values.len() as f32);
    out.extend(values.iter().map(|&v| v as f32));
}

impl PowerWorld {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn books(&self) -> Books {
        self.books
    }

    #[must_use]
    pub fn network(&self) -> &Network<Cables> {
        &self.net
    }

    #[must_use]
    pub fn steps(&self) -> u64 {
        self.steps
    }

    fn obj(&self, key: u32) -> Option<&Obj> {
        self.objs.get(key as usize).and_then(Option::as_ref)
    }

    fn slot(&mut self, key: u32) -> Result<&mut Option<Obj>, String> {
        if key >= MAX_KEY {
            return Err(format!("power key {key} out of range"));
        }
        let i = key as usize;
        if self.objs.len() <= i {
            self.objs.resize(i + 1, None);
        }
        Ok(&mut self.objs[i])
    }

    // ---- topology --------------------------------------------------------

    /// Adds a cable piece. Replaces any object already under `key`.
    ///
    /// # Errors
    /// A key out of range or a full arena.
    pub fn add_cable(&mut self, key: u32, pos: u32, shape: CableShape) -> Result<(), String> {
        self.slot(key)?;
        self.remove(key);
        let node = self
            .net
            .add_node(pos, 0, key, Load::default(), 0.0)
            .map_err(|e| format!("{e:?}"))?;
        *self.slot(key)? = Some(Obj {
            pos,
            node,
            shape: Some(shape),
        });
        // Neighbours by the get_connections() rule.
        let mut peers: Vec<u32> = Vec::new();
        for (t, need) in shape.reaches(pos) {
            if let Some(keys) = self.at.get(&t) {
                for &k in keys {
                    if let Some(Obj { shape: Some(s), .. }) = self.obj(k)
                        && s.has(need)
                    {
                        peers.push(k);
                    }
                }
            }
        }
        if let Some(keys) = self.at.get(&pos) {
            for &k in keys {
                match self.obj(k) {
                    Some(Obj { shape: Some(s), .. }) if s.shares_end(&shape) => peers.push(k),
                    Some(Obj { shape: None, .. }) if shape.is_knot() => peers.push(k),
                    _ => {}
                }
            }
        }
        if shape.link != 0 {
            let group = self.links.entry(shape.link).or_default();
            peers.extend(group.iter().copied());
            group.push(key);
        }
        self.at.entry(pos).or_default().push(key);
        self.connect_all(key, node, &peers);
        Ok(())
    }

    /// Adds a power machine node (a generator, terminal, SMES, ...). It
    /// joins every knot cable on its turf.
    ///
    /// # Errors
    /// A key out of range or a full arena.
    pub fn add_machine(&mut self, key: u32, pos: u32) -> Result<(), String> {
        self.slot(key)?;
        self.remove(key);
        let load = self.load_of(key);
        let node = self
            .net
            .add_node(pos, 1, key, load, 0.0)
            .map_err(|e| format!("{e:?}"))?;
        *self.slot(key)? = Some(Obj {
            pos,
            node,
            shape: None,
        });
        let peers: Vec<u32> = self
            .at
            .get(&pos)
            .map(|keys| {
                keys.iter()
                    .copied()
                    .filter(|&k| matches!(self.obj(k), Some(Obj { shape: Some(s), .. }) if s.is_knot()))
                    .collect()
            })
            .unwrap_or_default();
        self.at.entry(pos).or_default().push(key);
        self.bound.entry(key).or_insert(u32::MAX);
        self.connect_all(key, node, &peers);
        Ok(())
    }

    fn connect_all(&mut self, key: u32, node: NodeId<Cables>, peers: &[u32]) {
        for &p in peers {
            if p == key {
                continue;
            }
            let Some(other) = self.obj(p).map(|o| o.node) else {
                continue;
            };
            if self.net.find_edge(node, other).is_none() {
                let _ = self.net.connect(node, other);
            }
        }
    }

    /// Removes a cable piece or machine node (no-op for an unknown key).
    pub fn remove(&mut self, key: u32) {
        let Some(obj) = self.objs.get_mut(key as usize).and_then(Option::take) else {
            return;
        };
        if let Some(keys) = self.at.get_mut(&obj.pos) {
            keys.retain(|&k| k != key);
            if keys.is_empty() {
                self.at.remove(&obj.pos);
            }
        }
        if let Some(s) = obj.shape
            && s.link != 0
            && let Some(group) = self.links.get_mut(&s.link)
        {
            group.retain(|&k| k != key);
        }
        let _ = self.net.remove_node(obj.node);
        self.pulses.remove(&key);
        if obj.shape.is_none() {
            // Reported as unbound at the next commit.
            self.bound.insert(key, u32::MAX);
        }
    }

    /// Whether `key` names a live cable or machine node.
    #[must_use]
    pub fn contains(&self, key: u32) -> bool {
        self.obj(key).is_some()
    }

    /// Commits pending topology and reconciles ledgers. Called by every
    /// read that needs regions; a no-op when nothing is pending.
    pub fn commit(&mut self) {
        let events = self.net.commit();
        let mut retired: Vec<RawHandle> = Vec::new();
        let mut touched_regions: Vec<RegionId<Cables>> = Vec::new();
        for e in events {
            match e {
                RegionEvent::Created { region } => {
                    self.ledgers.entry(region.raw()).or_default();
                    touched_regions.push(region);
                }
                RegionEvent::Merged { into, from } => {
                    let gone = self.ledgers.remove(&from.raw()).unwrap_or_default();
                    let l = self.ledgers.entry(into.raw()).or_default();
                    l.load += gone.load;
                    l.viewavail += gone.viewavail;
                    l.viewload += gone.viewload;
                    retired.push(from.raw());
                    touched_regions.push(into);
                }
                RegionEvent::Split { from, into } => {
                    let parent = self.ledgers.get(&from.raw()).copied().unwrap_or_default();
                    self.ledgers.insert(
                        into.raw(),
                        Ledger {
                            brown: parent.brown,
                            shown_brown: parent.shown_brown,
                            fresh: true,
                            ..Ledger::default()
                        },
                    );
                    touched_regions.push(from);
                    touched_regions.push(into);
                }
                RegionEvent::Retired { region } => {
                    self.ledgers.remove(&region.raw());
                    retired.push(region.raw());
                }
                RegionEvent::Changed { region } => touched_regions.push(region),
                RegionEvent::Released { .. } | RegionEvent::DeviceDetached { .. } => {}
            }
        }
        for r in retired {
            if !self.ledgers.contains_key(&r) {
                push(&mut self.out, ev::RETIRED, &[f64::from(raw_id(r))]);
            }
        }
        // Topology changed supply: re-plan what each touched region offers
        // now, so a split side does not keep its parent's supply.
        touched_regions.sort_by_key(|r| r.raw().bits());
        touched_regions.dedup();
        if !touched_regions.is_empty() {
            self.plan_supply(Some(&touched_regions));
        }
        // Machine rebinds: a machine is bound to its region while that
        // region holds more than the machine itself (a cable reached it).
        // Machines are few, so every commit checks them all.
        self.touched.clear();
        self.net
            .drain_touched(&mut self.touched, &mut self.scratch_devices);
        self.scratch_devices.clear();
        let keys: Vec<u32> = self.bound.keys().copied().collect();
        for key in keys {
            let (region, members) = self
                .obj(key)
                .and_then(|o| self.net.node(o.node).ok())
                .map(|n| {
                    let r = n.region();
                    (region_id(r), self.net.region(r).map_or(0, |x| x.members()))
                })
                .unwrap_or((0, 0));
            let bound = if members > 1 { region } else { 0 };
            if self.bound.get(&key) != Some(&bound) {
                push(
                    &mut self.out,
                    ev::BIND,
                    &[f64::from(key), f64::from(bound), f64::from(members)],
                );
            }
            if self.obj(key).is_some() {
                self.bound.insert(key, bound);
            } else {
                self.bound.remove(&key);
            }
        }
    }

    // ---- ledger ------------------------------------------------------------

    /// The node data a machine key contributes (supply, served demand,
    /// storage capacity).
    fn load_of(&self, key: u32) -> Load {
        let mut load = Load {
            supply: self.supply.get(&key).copied().unwrap_or(0.0),
            ..Load::default()
        };
        if let Some(apc) = self.apc_terminal.get(&key).and_then(|a| self.apcs.get(a)) {
            load.demand = apc.demand();
            load.capacity = apc.config.max_charge;
        }
        if let Some(s) = self.smes.get(&key) {
            load.capacity = s.config.capacity;
        }
        load
    }

    fn refresh_node(&mut self, key: u32) {
        let load = self.load_of(key);
        if let Some(node) = self.obj(key).map(|o| o.node)
            && self.net.node(node).is_ok_and(|n| n.data != load)
        {
            let _ = self.net.set_node_data(node, load);
        }
    }

    /// Sets a machine's persistent supply (W). Repeating a value is free.
    pub fn set_supply(&mut self, key: u32, watts: f64) {
        let watts = watts.max(0.0);
        if watts == 0.0 {
            self.supply.remove(&key);
        } else {
            self.supply.insert(key, watts);
        }
        self.refresh_node(key);
    }

    /// Adds one-step supply (legacy `add_avail` from a pulse source).
    pub fn pulse(&mut self, key: u32, watts: f64) {
        if watts > 0.0 && self.contains(key) {
            *self.pulses.entry(key).or_default() += watts;
        }
    }

    fn region_of_key(&mut self, key: u32) -> Option<RegionId<Cables>> {
        let node = self.obj(key)?.node;
        if self.net.has_pending() {
            self.commit();
        }
        self.net.node(node).ok().map(vg_core::network::Node::region)
    }

    /// A one-off draw by the machine or cable `key` from its region:
    /// delivered watts, never more than the region's `avail - load`.
    pub fn draw(&mut self, key: u32, watts: f64) -> f64 {
        let Some(r) = self.region_of_key(key) else {
            return 0.0;
        };
        let l = self.ledgers.entry(r.raw()).or_default();
        let d = watts.min(l.avail - l.load).max(0.0);
        l.load += d;
        self.books.delivered += d;
        d
    }

    /// The region numbers `key` is on.
    pub fn region_info(&mut self, key: u32) -> Option<RegionInfo> {
        let r = self.region_of_key(key)?;
        let region = self.net.region(r).ok()?;
        let l = self.ledgers.get(&r.raw()).copied().unwrap_or_default();
        Some(RegionInfo {
            region: region_id(r),
            avail: l.avail,
            load: l.load,
            viewavail: l.viewavail,
            viewload: l.viewload,
            netexcess: l.netexcess,
            summary: *region.summary(),
            members: region.members(),
            pool: *region.payload(),
        })
    }

    /// Member keys of the region `key` is on (cables and machines).
    pub fn members(&mut self, key: u32) -> Vec<u32> {
        let Some(r) = self.region_of_key(key) else {
            return Vec::new();
        };
        self.net
            .members(r)
            .unwrap_or_default()
            .into_iter()
            .filter_map(|n| self.net.node(n).ok().map(|n| n.key))
            .collect()
    }

    // ---- storage -----------------------------------------------------------

    /// Creates or updates an APC. `state` overrides the runtime state only
    /// when given (a new APC, a cell swap, a reboot).
    pub fn set_apc(
        &mut self,
        key: u32,
        config: ApcConfig,
        terminal: Option<u32>,
        state: Option<ApcState>,
    ) {
        let apc = self.apcs.entry(key).or_default();
        let old_terminal = apc.terminal;
        apc.config = config;
        apc.terminal = terminal;
        if let Some(s) = state {
            apc.state = s;
        }
        apc.state.charge = apc.state.charge.clamp(0.0, config.max_charge.max(0.0));
        if old_terminal != terminal {
            if let Some(t) = old_terminal {
                self.apc_terminal.remove(&t);
                self.refresh_node(t);
            }
            if let Some(t) = terminal {
                self.apc_terminal.insert(t, key);
            }
        }
        if let Some(t) = terminal {
            self.refresh_node(t);
        }
    }

    #[must_use]
    pub fn apc(&self, key: u32) -> Option<&Apc> {
        self.apcs.get(&key)
    }

    /// Sets an APC area's static load per channel (W).
    pub fn set_area_load(&mut self, key: u32, load: [f64; 3]) {
        if let Some(apc) = self.apcs.get_mut(&key) {
            apc.static_load = load.map(|v| v.max(0.0));
            if let Some(t) = apc.terminal {
                self.refresh_node(t);
            }
        }
    }

    /// Adds one-off area use per channel (W) for the next step.
    pub fn add_area_oneoff(&mut self, key: u32, used: [f64; 3]) {
        if let Some(apc) = self.apcs.get_mut(&key) {
            for (a, b) in apc.oneoff.iter_mut().zip(used) {
                *a += b.max(0.0);
            }
        }
    }

    /// Sets an APC's channel settings (the UI, wires, hacking).
    pub fn set_apc_channels(&mut self, key: u32, channels: [u8; 3], autoflag: Option<u8>) {
        if let Some(apc) = self.apcs.get_mut(&key) {
            apc.state.channels = channels;
            if let Some(a) = autoflag {
                apc.state.autoflag = a;
            }
            if let Some(t) = apc.terminal {
                self.refresh_node(t);
            }
        }
    }

    /// Sets the charge of an APC cell or SMES (DM changed it directly).
    pub fn set_charge(&mut self, key: u32, charge: f64) {
        if let Some(apc) = self.apcs.get_mut(&key) {
            apc.state.charge = charge.clamp(0.0, apc.config.max_charge.max(0.0));
        }
        if let Some(s) = self.smes.get_mut(&key) {
            s.state.charge = charge.clamp(0.0, s.config.capacity.max(0.0));
        }
    }

    /// Creates or updates a SMES.
    pub fn set_smes(&mut self, key: u32, config: SmesConfig, terminals: Vec<u32>, charge: Option<f64>) {
        let s = self.smes.entry(key).or_default();
        s.config = config;
        s.terminals = terminals;
        if let Some(c) = charge {
            s.state.charge = c;
        }
        s.state.charge = s.state.charge.clamp(0.0, config.capacity.max(0.0));
        self.refresh_node(key);
    }

    #[must_use]
    pub fn smes(&self, key: u32) -> Option<&Smes> {
        self.smes.get(&key)
    }

    /// Forgets an APC or SMES (its node, if any, stays).
    pub fn remove_storage(&mut self, key: u32) {
        if let Some(apc) = self.apcs.remove(&key) {
            if let Some(t) = apc.terminal {
                self.apc_terminal.remove(&t);
                self.refresh_node(t);
            }
            self.shown_apc.remove(&key);
        }
        if self.smes.remove(&key).is_some() {
            self.refresh_node(key);
            self.shown_smes.remove(&key);
        }
    }

    // ---- the step ----------------------------------------------------------

    fn node_region(&self, key: u32) -> Option<RegionId<Cables>> {
        let node = self.obj(key)?.node;
        self.net.node(node).ok().map(vg_core::network::Node::region)
    }

    /// Plans each region's supply for the coming step: registered supply,
    /// pulses and SMES output. `only` limits it to some regions (after a
    /// topology change, keeping their load).
    fn plan_supply(&mut self, only: Option<&[RegionId<Cables>]>) {
        let mut offers: HashMap<RawHandle, (f64, f64)> = HashMap::new();
        let smes_keys: Vec<u32> = self.smes.keys().copied().collect();
        for key in smes_keys {
            let region = self.node_region(key);
            let s = self.smes.get_mut(&key).expect("listed");
            s.plan_output(region.is_some());
            if let Some(r) = region {
                offers.entry(r.raw()).or_default().1 += s.state.offer;
            }
        }
        for (&key, &w) in &self.pulses {
            if let Some(r) = self.node_region(key) {
                offers.entry(r.raw()).or_default().0 += w;
            }
        }
        let regions: Vec<RegionId<Cables>> = match only {
            Some(rs) => rs.to_vec(),
            None => self.net.regions().map(|(r, _)| r).collect(),
        };
        for r in regions {
            let Ok(region) = self.net.region(r) else {
                continue;
            };
            let gen_supply = region.summary()[sum::SUPPLY];
            let (pulse, smes) = offers.get(&r.raw()).copied().unwrap_or_default();
            // After a mid-step topology change the region's supply is what
            // its own members offer; what was already drawn stays drawn.
            let l = self.ledgers.entry(r.raw()).or_default();
            l.avail = gen_supply + pulse + smes;
            l.smes_avail = smes;
        }
    }

    /// One machinery tick: APCs, storage input and output, the monitor
    /// view, then the next step's supply. Returns the events (see [`ev`]),
    /// including those that commits since the last step buffered.
    pub fn step(&mut self) -> Vec<f32> {
        self.commit();
        self.steps += 1;

        // APCs, in key order (the DM roster order is arbitrary; key order
        // is deterministic).
        let apc_keys: Vec<u32> = self.apcs.keys().copied().collect();
        for key in apc_keys {
            let region = self
                .apcs
                .get(&key)
                .and_then(|a| a.terminal)
                .and_then(|t| self.node_region(t));
            let apc = self.apcs.get_mut(&key).expect("listed");
            let old_demand = apc.demand();
            if let Some(r) = region {
                let ledger = self.ledgers.entry(r.raw()).or_default();
                let mut grid = RegionGrid {
                    ledger,
                    delivered: &mut self.books.delivered,
                };
                apc.tick(&mut grid);
            } else {
                apc.tick(&mut NoGrid);
            }
            let changed_demand = apc.demand() != old_demand;
            let terminal = apc.terminal;
            if changed_demand && let Some(t) = terminal {
                self.refresh_node(t);
            }
        }

        // SMES input: what each terminal region has left over, shared in
        // proportion to what the units ask for.
        let smes_keys: Vec<u32> = self.smes.keys().copied().collect();
        let mut asks: HashMap<RawHandle, f64> = HashMap::new();
        let mut terminal_regions: HashMap<u32, Vec<RawHandle>> = HashMap::new();
        for &key in &smes_keys {
            let terms: Vec<u32> = self.smes[&key].terminals.clone();
            let regions: Vec<RawHandle> = terms
                .iter()
                .filter_map(|&t| self.node_region(t))
                .map(|r| r.raw())
                .collect();
            let s = self.smes.get_mut(&key).expect("listed");
            s.plan_input(!regions.is_empty());
            for r in &regions {
                *asks.entry(*r).or_default() += s.state.target_load;
            }
            terminal_regions.insert(key, regions);
        }
        let mut fractions: HashMap<RawHandle, f64> = HashMap::new();
        for (r, ask) in &asks {
            let l = self.ledgers.entry(*r).or_default();
            let excess = (l.avail - l.load).max(0.0);
            let f = if *ask > 0.0 {
                (excess / ask).clamp(0.0, 1.0)
            } else {
                0.0
            };
            fractions.insert(*r, f);
        }
        for &key in &smes_keys {
            let regions = &terminal_regions[&key];
            let s = self.smes.get_mut(&key).expect("listed");
            let mut got = 0.0;
            for r in regions {
                let alloc = s.state.target_load * fractions.get(r).copied().unwrap_or(0.0);
                let l = self.ledgers.entry(*r).or_default();
                let alloc = alloc.min((l.avail - l.load).max(0.0));
                l.load += alloc;
                got += alloc;
            }
            self.books.delivered += got;
            let room = ((s.config.capacity - s.state.charge) / SMESRATE).max(0.0);
            self.books.storage_in += got.min(room);
            s.state.charge += got.min(room) * SMESRATE;
            s.state.input_available = got;
            s.state.inputting = if got <= 0.0 {
                0
            } else if got + 0.01 >= s.state.target_load {
                2
            } else {
                1
            };
        }

        // SMES output: storage is the last supply to be used.
        for &key in &smes_keys {
            let Some(r) = self.node_region(key) else {
                let s = self.smes.get_mut(&key).expect("listed");
                s.state.output_used = 0.0;
                continue;
            };
            let l = self.ledgers.get(&r.raw()).copied().unwrap_or_default();
            let non_smes = (l.avail - l.smes_avail).max(0.0);
            let used = (l.load - non_smes).clamp(0.0, l.smes_avail);
            let s = self.smes.get_mut(&key).expect("listed");
            let share = if l.smes_avail > 0.0 {
                used * s.state.offer / l.smes_avail
            } else {
                0.0
            };
            let share = share.min(s.state.charge / SMESRATE);
            s.state.charge = (s.state.charge - share * SMESRATE).max(0.0);
            s.state.output_used = share;
            self.books.storage_out += share;
        }

        // Monitor view, brownouts, then next step's supply.
        let regions: Vec<RegionId<Cables>> = self.net.regions().map(|(r, _)| r).collect();
        for r in &regions {
            let l = self.ledgers.entry(r.raw()).or_default();
            self.books.generated += l.avail - l.smes_avail;
            self.books.storage_offered += l.smes_avail;
            l.netexcess = l.avail - l.load;
            l.viewavail = (0.8f64.mul_add(l.viewavail, 0.2 * l.avail)).round();
            l.viewload = (0.8f64.mul_add(l.viewload, 0.2 * l.load)).round();
            l.brown = l.avail <= 0.0 || l.netexcess < -1.0;
        }
        self.pulses.clear();
        self.plan_supply(None);
        for r in &regions {
            let l = self.ledgers.get_mut(&r.raw()).expect("entered above");
            let shown = [l.avail, l.load, l.viewavail, l.viewload, l.netexcess];
            let id = f64::from(region_id(*r));
            if !l.fresh {
                l.shown_brown = l.brown;
            }
            if !l.fresh || visibly_changed(&l.shown, &shown) {
                l.shown = shown;
                l.fresh = true;
                push(&mut self.out, ev::REGION, &[id, shown[0], shown[1], shown[2], shown[3], shown[4]]);
            }
            if l.brown != l.shown_brown {
                l.shown_brown = l.brown;
                push(&mut self.out, ev::BROWNOUT, &[id, f64::from(u8::from(l.brown))]);
            }
            l.load = 0.0;
        }

        // Storage reports.
        for (&key, apc) in &self.apcs {
            // The trend counters (longtermpower, chargecount) cycle on a
            // settled APC and DM never shows them: they are not reported.
            let shown = ApcState {
                longtermpower: 0,
                chargecount: 0,
                ..apc.state
            };
            if self.shown_apc.get(&key) != Some(&shown) {
                self.shown_apc.insert(key, shown);
                let s = &apc.state;
                push(
                    &mut self.out,
                    ev::APC,
                    &[
                        f64::from(key),
                        s.charge,
                        f64::from(s.channels[0]),
                        f64::from(s.channels[1]),
                        f64::from(s.channels[2]),
                        f64::from(s.charging),
                        f64::from(s.main_status),
                        f64::from(u8::from(s.alarm)),
                        f64::from(s.autoflag),
                        s.lastused[0],
                        s.lastused[1],
                        s.lastused[2],
                        s.lastused[3],
                        s.lastused[4],
                        f64::from(apc.channel_bits()),
                    ],
                );
            }
        }
        for (&key, s) in &self.smes {
            let st = &s.state;
            let shown = [
                st.charge,
                f64::from(st.inputting),
                f64::from(st.outputting),
                st.output_used,
                st.input_available,
                f64::from(s.display()),
            ];
            if self.shown_smes.get(&key) != Some(&shown) {
                self.shown_smes.insert(key, shown);
                let mut v = vec![f64::from(key)];
                v.extend_from_slice(&shown);
                push(&mut self.out, ev::SMES, &v);
            }
        }
        std::mem::take(&mut self.out)
    }

    /// Takes the events buffered by edits and reads since the last step.
    pub fn take_events(&mut self) -> Vec<f32> {
        std::mem::take(&mut self.out)
    }

    /// Stored energy in every APC cell and SMES (their own units).
    #[must_use]
    pub fn stored(&self) -> (f64, f64) {
        (
            self.apcs.values().map(|a| a.state.charge).sum(),
            self.smes.values().map(|s| s.state.charge).sum(),
        )
    }

    /// `CELLRATE` and `SMESRATE`, for DM parity checks.
    #[must_use]
    pub const fn rates() -> (f64, f64) {
        (CELLRATE, SMESRATE)
    }
}
