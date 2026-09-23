//! Frame integration for networks: DM-facing [`NetworkPort`], worker-side
//! [`NetworkState`] and the published [`NetworkView`].
//!
//! DM names nodes and devices by its own dense keys (registry indices below
//! [`MAX_KEY`]), so it never waits for a handle. The port queues [`Edit`]s
//! and sends each [`NetworkPort::commit`] as one transaction; commands
//! against a node's region payload travel in the same ordered stream. Once
//! per frame the network's task applies everything received, commits, and
//! publishes:
//! - a [`NetworkView`]: copy-on-write stores of node key -> region, region
//!   slot -> [`RegionEntry`] and device key -> [`DeviceEntry`]; unchanged
//!   chunks are shared with the previous view;
//! - an [`Outbox`] of region events ([`EventKind::TopologyChanged`], codes
//!   in [`topo`]) and, as take results keyed by node key, each removed
//!   node's released payload.
//!
//! Region channels for watches: a kind's region scalars are mirrored into
//! an ordinary cell [`Domain`](crate::owner::Domain) store with
//! [`NetworkState::mirror`] (cell = region slot), so `Changed`, `Threshold`
//! and `Band` watches work on regions unchanged (see `tests/network_sim.rs`).

use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex};

use crate::command::Seq;
use crate::cow::{ChunkLayout, CowStore};
use crate::frame::{Res, Task};
use crate::handle::{MAX_SLOTS, RawHandle};
use crate::mailbox::Latest;
use crate::outbox::{Event, EventKind, Outbox, OutboxSlot, TakeResult};
use crate::sim::SimBuilder;

use super::graph::{DeviceId, Endpoint, Network, NetworkKind, NodeId, RegionEvent, Side};

/// Keys are dense indices below this (the view stores are indexed by them).
pub const MAX_KEY: u32 = MAX_SLOTS;

/// `value` codes of [`EventKind::TopologyChanged`] events. `key` is the
/// region's raw handle; `extra` is the other region's (or 0).
pub mod topo {
    /// A new region.
    pub const CREATED: f32 = 1.0;
    /// `extra` was pooled into `key` and retired.
    pub const MERGED: f32 = 2.0;
    /// `extra` was carved out of `key`.
    pub const SPLIT: f32 = 3.0;
    /// `key` lost its last node.
    pub const RETIRED: f32 = 4.0;
    /// `key`'s summary or payload changed.
    pub const CHANGED: f32 = 5.0;
    /// Device `key` (a device key, not a region) lost a node endpoint.
    pub const DEVICE_DETACHED: f32 = 6.0;
}

/// One side of a device, by DM key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EndKey {
    Node(u32),
    Cell(u32),
}

/// A topology or data edit, by DM key.
#[derive(Clone, Debug, PartialEq)]
pub enum Edit<K: NetworkKind> {
    AddNode {
        key: u32,
        pos: u32,
        kind: u16,
        data: K::Node,
        payload: K::Payload,
    },
    RemoveNode {
        key: u32,
    },
    SetNode {
        key: u32,
        data: K::Node,
    },
    Connect {
        a: u32,
        b: u32,
    },
    Disconnect {
        a: u32,
        b: u32,
    },
    AddDevice {
        key: u32,
        a: EndKey,
        b: EndKey,
        kind: u16,
        data: K::Device,
    },
    RemoveDevice {
        key: u32,
    },
    SetDevice {
        key: u32,
        data: K::Device,
    },
}

enum Message<K: NetworkKind> {
    Batch(Vec<Edit<K>>),
    Command { node: u32, cmd: K::Command },
}

/// A region as published.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct RegionEntry<K: NetworkKind> {
    /// The live region in this slot, if any.
    pub region: Option<RawHandle>,
    pub members: u32,
    pub summary: K::Summary,
    pub payload: K::Payload,
}

/// A device side as published.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ViewSide {
    /// No device under this key.
    #[default]
    None,
    Region(RawHandle),
    Cell(u32),
    Detached,
}

/// A device as published: its resolved sides and parameters.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DeviceEntry<K: NetworkKind> {
    pub a: ViewSide,
    pub b: ViewSide,
    pub kind: u16,
    pub data: K::Device,
}

/// An immutable snapshot of a network, published once per frame.
#[derive(Clone, Debug)]
pub struct NetworkView<K: NetworkKind> {
    pub version: u64,
    /// Commits applied so far.
    pub revision: u64,
    /// Node key -> region raw bits + 1 (0: no node).
    nodes: CowStore<u32>,
    regions: CowStore<RegionEntry<K>>,
    devices: CowStore<DeviceEntry<K>>,
}

impl<K: NetworkKind> NetworkView<K> {
    fn empty() -> Self {
        Self {
            version: 0,
            revision: 0,
            nodes: CowStore::new(ChunkLayout::linear(MAX_KEY)),
            regions: CowStore::new(ChunkLayout::linear(MAX_SLOTS)),
            devices: CowStore::new(ChunkLayout::linear(MAX_KEY)),
        }
    }

    /// The region node `key` belongs to.
    #[must_use]
    pub fn region_of(&self, key: u32) -> Option<RawHandle> {
        let bits = self.nodes.get(key)?;
        bits.checked_sub(1).and_then(RawHandle::from_bits)
    }

    /// A live region's entry (`None` for a stale handle).
    #[must_use]
    pub fn region(&self, region: RawHandle) -> Option<RegionEntry<K>> {
        self.regions
            .get(region.index())
            .filter(|e| e.region == Some(region))
    }

    /// Node `key`'s region entry.
    #[must_use]
    pub fn region_of_node(&self, key: u32) -> Option<RegionEntry<K>> {
        self.region(self.region_of(key)?)
    }

    /// Device `key`'s entry.
    #[must_use]
    pub fn device(&self, key: u32) -> Option<DeviceEntry<K>> {
        self.devices.get(key).filter(|d| d.a != ViewSide::None)
    }

    /// The region store by slot (for scans and for the replay hash).
    #[must_use]
    pub fn regions(&self) -> &CowStore<RegionEntry<K>> {
        &self.regions
    }
}

/// Counters over the network's life.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct HostStats {
    pub batches: u64,
    pub edits: u64,
    pub commands: u64,
    /// Edits or commands naming an unknown key, or otherwise invalid.
    pub rejected: u64,
}

/// The worker side: the network and its publication state. Lives in the
/// frame world as a resource; only the network's task writes it.
pub struct NetworkState<K: NetworkKind> {
    pub net: Network<K>,
    node_keys: Vec<Option<NodeId<K>>>,
    device_keys: Vec<Option<DeviceId<K>>>,
    rx: Mutex<Receiver<Message<K>>>,
    views: Arc<Latest<Arc<NetworkView<K>>>>,
    view: NetworkView<K>,
    outbox: Outbox<K::Payload>,
    outbox_slot: Arc<OutboxSlot<K::Payload>>,
    /// This frame's events (for kind steps and mirrors that run after).
    events: Vec<RegionEvent<K>>,
    /// Region slots whose entry changed this frame.
    changed_slots: Vec<u32>,
    stats: HostStats,
    touched_nodes: Vec<NodeId<K>>,
    touched_devices: Vec<DeviceId<K>>,
}

fn slot<T>(keys: &[Option<T>], key: u32) -> Option<T>
where
    T: Copy,
{
    keys.get(key as usize).copied().flatten()
}

impl<K: NetworkKind> NetworkState<K> {
    /// A detached state and port pair (for hosts that drive
    /// [`NetworkState::step`] themselves; [`add_network`] wires one into a
    /// sim).
    #[must_use]
    pub fn new() -> (Self, NetworkPort<K>) {
        let (tx, rx) = channel();
        let views = Arc::new(Latest::new());
        let outbox_slot = Arc::new(OutboxSlot::default());
        let state = Self {
            net: Network::new(),
            node_keys: Vec::new(),
            device_keys: Vec::new(),
            rx: Mutex::new(rx),
            views: Arc::clone(&views),
            view: NetworkView::empty(),
            outbox: Outbox::default(),
            outbox_slot: Arc::clone(&outbox_slot),
            events: Vec::new(),
            changed_slots: Vec::new(),
            stats: HostStats::default(),
            touched_nodes: Vec::new(),
            touched_devices: Vec::new(),
        };
        let port = NetworkPort {
            tx,
            views,
            pinned: Arc::new(NetworkView::empty()),
            outbox_slot,
            batch: Vec::new(),
        };
        (state, port)
    }

    #[must_use]
    pub fn stats(&self) -> HostStats {
        self.stats
    }

    /// The handle behind node `key`.
    #[must_use]
    pub fn node(&self, key: u32) -> Option<NodeId<K>> {
        slot(&self.node_keys, key)
    }

    /// The handle behind device `key`.
    #[must_use]
    pub fn device(&self, key: u32) -> Option<DeviceId<K>> {
        slot(&self.device_keys, key)
    }

    /// This frame's region events, in order.
    #[must_use]
    pub fn events(&self) -> &[RegionEvent<K>] {
        &self.events
    }

    /// The frame task body: applies every received batch and command in
    /// order, then publishes the view and the outbox.
    pub fn step(&mut self) {
        self.events.clear();
        self.changed_slots.clear();
        let rx = self
            .rx
            .get_mut()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let messages: Vec<Message<K>> = rx.try_iter().collect();
        for msg in messages {
            match msg {
                Message::Batch(edits) => {
                    self.stats.batches += 1;
                    for edit in edits {
                        self.stats.edits += 1;
                        if !self.apply_edit(edit) {
                            self.stats.rejected += 1;
                        }
                    }
                    let events = self.net.commit();
                    self.events.extend(events);
                }
                Message::Command { node, cmd } => {
                    self.stats.commands += 1;
                    match self.node(node) {
                        Some(n) if self.net.command(n, &cmd).is_ok() => {}
                        _ => self.stats.rejected += 1,
                    }
                }
            }
        }
        // Flushes commands' `Changed` events (a no-op commit otherwise).
        let events = self.net.commit();
        self.events.extend(events);
        self.refresh_view();
        self.publish();
    }

    fn apply_edit(&mut self, edit: Edit<K>) -> bool {
        match edit {
            Edit::AddNode {
                key,
                pos,
                kind,
                data,
                payload,
            } => {
                if key >= MAX_KEY || self.node(key).is_some() {
                    return false;
                }
                let Ok(n) = self.net.add_node(pos, kind, key, data, payload) else {
                    return false;
                };
                let i = key as usize;
                if self.node_keys.len() <= i {
                    self.node_keys.resize(i + 1, None);
                }
                self.node_keys[i] = Some(n);
                true
            }
            Edit::RemoveNode { key } => {
                let Some(n) = self.node(key) else {
                    return false;
                };
                self.node_keys[key as usize] = None;
                self.view.nodes.set(key, 0);
                self.net.remove_node(n).is_ok()
            }
            Edit::SetNode { key, data } => self
                .node(key)
                .is_some_and(|n| self.net.set_node_data(n, data).is_ok()),
            Edit::Connect { a, b } => match (self.node(a), self.node(b)) {
                (Some(a), Some(b)) => self.net.connect(a, b).is_ok(),
                _ => false,
            },
            Edit::Disconnect { a, b } => match (self.node(a), self.node(b)) {
                (Some(a), Some(b)) => self.net.disconnect(a, b).is_ok(),
                _ => false,
            },
            Edit::AddDevice {
                key,
                a,
                b,
                kind,
                data,
            } => {
                if key >= MAX_KEY || self.device(key).is_some() {
                    return false;
                }
                let (Some(ea), Some(eb)) = (self.endpoint(a), self.endpoint(b)) else {
                    return false;
                };
                let Ok(d) = self.net.add_device(ea, eb, kind, key, data) else {
                    return false;
                };
                let i = key as usize;
                if self.device_keys.len() <= i {
                    self.device_keys.resize(i + 1, None);
                }
                self.device_keys[i] = Some(d);
                true
            }
            Edit::RemoveDevice { key } => {
                let Some(d) = self.device(key) else {
                    return false;
                };
                self.device_keys[key as usize] = None;
                self.view.devices.set(key, DeviceEntry::default());
                self.net.remove_device(d).is_ok()
            }
            Edit::SetDevice { key, data } => self
                .device(key)
                .is_some_and(|d| self.net.set_device_data(d, data).is_ok()),
        }
    }

    fn endpoint(&self, end: EndKey) -> Option<Endpoint<K>> {
        match end {
            EndKey::Node(k) => self.node(k).map(Endpoint::Node),
            EndKey::Cell(c) => Some(Endpoint::Cell(c)),
        }
    }

    fn view_side(&self, end: Endpoint<K>) -> ViewSide {
        match self.net.resolve(end) {
            Side::Region(r) => ViewSide::Region(r.raw()),
            Side::Cell(c) => ViewSide::Cell(c),
            Side::Detached => ViewSide::Detached,
        }
    }

    fn refresh_view(&mut self) {
        let mut regions: Vec<RawHandle> = Vec::new();
        for ev in &self.events {
            match ev {
                RegionEvent::Created { region }
                | RegionEvent::Retired { region }
                | RegionEvent::Changed { region } => regions.push(region.raw()),
                RegionEvent::Merged { into, from } => {
                    regions.extend([into.raw(), from.raw()]);
                }
                RegionEvent::Split { from, into } => {
                    regions.extend([from.raw(), into.raw()]);
                }
                RegionEvent::Released { .. } | RegionEvent::DeviceDetached { .. } => {}
            }
        }
        regions.sort_unstable();
        regions.dedup();
        for raw in regions {
            let slot = raw.index();
            let entry = match self.net.region(crate::handle::Handle::from_raw(raw)) {
                Ok(reg) => RegionEntry {
                    region: Some(raw),
                    members: reg.members(),
                    summary: reg.summary().clone(),
                    payload: reg.payload().clone(),
                },
                // Retired, or retired and the slot reused by a later region
                // (which has its own event and wins by generation below).
                Err(_) => {
                    if self.view.regions.with(slot, |e| e.region == Some(raw)) == Some(true) {
                        RegionEntry::default()
                    } else {
                        continue;
                    }
                }
            };
            self.view.regions.set(slot, entry);
            self.changed_slots.push(slot);
        }
        self.changed_slots.sort_unstable();
        self.changed_slots.dedup();

        let mut nodes = std::mem::take(&mut self.touched_nodes);
        let mut devices = std::mem::take(&mut self.touched_devices);
        self.net.drain_touched(&mut nodes, &mut devices);
        for &n in &nodes {
            if let Ok(node) = self.net.node(n) {
                if node.key < MAX_KEY && slot(&self.node_keys, node.key) == Some(n) {
                    self.view
                        .nodes
                        .set(node.key, node.region().raw().bits() + 1);
                }
            }
        }
        for &d in &devices {
            if let Ok(dev) = self.net.device(d) {
                let entry = DeviceEntry {
                    a: self.view_side(dev.a),
                    b: self.view_side(dev.b),
                    kind: dev.kind,
                    data: dev.data.clone(),
                };
                if dev.key < MAX_KEY && slot(&self.device_keys, dev.key) == Some(d) {
                    self.view.devices.set(dev.key, entry);
                }
            }
        }
        nodes.clear();
        devices.clear();
        self.touched_nodes = nodes;
        self.touched_devices = devices;
        self.view.revision = self.net.revision();
    }

    fn publish(&mut self) {
        let frame_seq = Seq(self.view.version + 1);
        for ev in &self.events {
            let (key, extra, value) = match ev {
                RegionEvent::Created { region } => (region.raw().bits(), 0, topo::CREATED),
                RegionEvent::Merged { into, from } => {
                    (into.raw().bits(), from.raw().bits(), topo::MERGED)
                }
                RegionEvent::Split { from, into } => {
                    (from.raw().bits(), into.raw().bits(), topo::SPLIT)
                }
                RegionEvent::Retired { region } => (region.raw().bits(), 0, topo::RETIRED),
                RegionEvent::Changed { region } => (region.raw().bits(), 0, topo::CHANGED),
                RegionEvent::DeviceDetached { device } => {
                    let key = self.net.device(*device).map_or(u32::MAX, |d| d.key);
                    (key, 0, topo::DEVICE_DETACHED)
                }
                RegionEvent::Released { key, payload, .. } => {
                    self.outbox.push_take(TakeResult {
                        seq: frame_seq,
                        cell: *key,
                        value: payload.clone(),
                    });
                    continue;
                }
            };
            self.outbox.push_event(Event {
                kind: EventKind::TopologyChanged,
                key,
                value,
                extra,
                generation: 0,
            });
        }
        self.view.version += 1;
        self.views.put(Arc::new(self.view.clone()));
        let mut outbox = std::mem::take(&mut self.outbox);
        outbox.stamp(self.view.version);
        self.outbox_slot.publish(outbox);
    }

    /// Mirrors region scalars into a cell store (cell = region slot) for the
    /// region slots that changed this frame; vacated slots get
    /// `V::default()`. Call from a task that writes the mirror domain, after
    /// the network's task, so watches see region channels.
    pub fn mirror<V: Clone + Default>(
        &self,
        store: &mut CowStore<V>,
        f: impl Fn(&RegionEntry<K>) -> V,
    ) {
        for &slot in &self.changed_slots {
            let value = self
                .view
                .regions
                .with(slot, |e| {
                    if e.region.is_some() {
                        f(e)
                    } else {
                        V::default()
                    }
                })
                .unwrap_or_default();
            store.set(slot, value);
        }
    }

    /// The live (unpublished) view.
    #[must_use]
    pub fn live_view(&self) -> &NetworkView<K> {
        &self.view
    }
}

/// The DM-facing side. Lock-free: edits and commands go through an mpsc
/// channel, views through a single-slot mailbox.
pub struct NetworkPort<K: NetworkKind> {
    tx: Sender<Message<K>>,
    views: Arc<Latest<Arc<NetworkView<K>>>>,
    pinned: Arc<NetworkView<K>>,
    outbox_slot: Arc<OutboxSlot<K::Payload>>,
    batch: Vec<Edit<K>>,
}

impl<K: NetworkKind> NetworkPort<K> {
    /// Queues an edit in the open transaction.
    pub fn edit(&mut self, edit: Edit<K>) {
        self.batch.push(edit);
    }

    /// Sends the open transaction as one commit (an explosion is one call).
    pub fn commit(&mut self) {
        if !self.batch.is_empty() {
            let batch = std::mem::take(&mut self.batch);
            let _ = self.tx.send(Message::Batch(batch));
        }
    }

    /// Queues a command against node `node`'s region payload. Commits the
    /// open transaction first, so the order DM issued things in holds.
    pub fn command(&mut self, node: u32, cmd: K::Command) {
        self.commit();
        let _ = self.tx.send(Message::Command { node, cmd });
    }

    /// Pins the newest published view, if a new one arrived. Returns
    /// whether it changed.
    pub fn refresh(&mut self) -> bool {
        match self.views.take() {
            Some(v) => {
                self.pinned = v;
                true
            }
            None => false,
        }
    }

    #[must_use]
    pub fn pinned(&self) -> &Arc<NetworkView<K>> {
        &self.pinned
    }

    /// Everything published since the last call (region events and
    /// released payloads).
    pub fn take_outbox(&mut self) -> Outbox<K::Payload> {
        self.outbox_slot.collect().unwrap_or_default()
    }
}

/// Registers a network with a sim: a `net:<name>` frame resource and a
/// task that runs [`NetworkState::step`] each frame. Tasks that step the
/// kind's physics or mirror region channels declare a write or read of the
/// returned resource after this call.
pub fn add_network<K: NetworkKind>(
    builder: &mut SimBuilder,
    name: &str,
) -> (Res<NetworkState<K>>, NetworkPort<K>) {
    let (state, port) = NetworkState::<K>::new();
    let res = builder.add_resource(format!("net:{name}"), state);
    builder.add_task(
        Task::new(format!("net:{name}"), move |ctx| {
            ctx.write(res).step();
        })
        .writes(res.id()),
    );
    (res, port)
}
