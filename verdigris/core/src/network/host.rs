//! [`NetworkHost`]: entity-keyed topology (`rust_architecture.md` §4.5,
//! Core C). It owns one [`Network<K>`] (the incremental region graph,
//! unchanged) and adds the one thing every domain's own network host used
//! to hand-roll: identity and edge derivation.
//!
//! - **Identity.** A node is named by the entity that bound it (an
//!   [`entity::EntityTable`](crate::entity::EntityTable) handle), never a
//!   domain-private key table. There is one lookup, [`NetworkHost::node_of`],
//!   from entity to the graph's own [`NodeId`]; the reverse direction needs
//!   no table at all, because the entity's raw bits are already the graph's
//!   `key` field (see [`Network::add_node`]'s `key` and
//!   [`RegionEvent::Released`]'s `key`) -- [`decode_key`] reconstructs the
//!   [`EntityId`] from it directly.
//! - **Edges.** DM never sends topology. Binding a node at a cell is enough:
//!   [`NetworkHost::bind_node`] derives edges by calling
//!   [`NetworkKind::connects`] against every other node occupying that cell
//!   or one of [`NetworkKind::reach`]'s target cells (via an occupancy
//!   index, not a scan of every node), and connects the pairs it accepts.
//!   `reach` is the domain's own rule (grid-face adjacency, a diagonal, an
//!   explicit cross-z link, ...); a kind that never overrides it only ever
//!   connects same-cell nodes.
//! - **Batching.** [`NetworkHost::commit`] is exactly
//!   [`Network::commit`]: split-then-merge, so an explosion's edits are one
//!   batch, unchanged from `graph.rs`.
//! - **Devices.** [`NetworkHost::devices`] iterates the dense device arena
//!   directly (no hash lookup), per entity handle.
//!
//! No region state lives here or in a side map: everything about a region
//! is in [`NetworkKind::Payload`], carried by `Network<K>` itself.
//!
//! **Revisions** (for the driver's sleep, `rust_architecture.md` §4.4):
//! every region and device carries a revision that moves whenever its
//! payload, summary, membership or parameters change through this host
//! (a law's write-back, a DM command, a commit). Region and device laws
//! (see [`super::law`]) remember the revision they last stepped and sleep
//! until it moves; a device also wakes when either side's region moves.
//! This replaces gas `PipeNet`'s `seen`/`revisions` tables.
//!
//! **Transitions**: [`NetworkHost::transitions`] folds a commit's events
//! into DM-facing [`Transition`]s ("this region's membership changed,
//! rebuild its wrapper": members, prior regions, retired), keyed by the
//! region handle itself (exact as an `f32`), so no DM slot table exists.

use std::collections::HashMap;

use crate::conservation::Conserved;
use crate::entity::EntityId;
use crate::slot::RawHandle;

use super::graph::{
    CellId, DeviceId, Endpoint, NetError, Network, NetworkKind, NodeId, RegionEvent, RegionId,
};

/// An entity handle, as [`NetworkHost`] identifies nodes and devices.
pub type Entity = EntityId;

/// Recovers the entity a graph `key` (`Network::add_node`'s `key` field,
/// [`RegionEvent::Released`]'s `key`) names. `None` for [`super::NO_KEY`] or
/// any value [`NetworkHost`] did not itself produce.
#[must_use]
pub fn decode_key(key: u32) -> Option<Entity> {
    EntityId::from_bits(key)
}

fn encode_entity(entity: Entity) -> u32 {
    entity.bits()
}

/// Entity-keyed topology over one [`NetworkKind`] (`rust_architecture.md`
/// §4.5). See the module docs.
pub struct NetworkHost<K: NetworkKind> {
    net: Network<K>,
    nodes: HashMap<Entity, NodeId<K>>,
    /// Cell -> entities with a node bound there, for [`bind_node`]'s edge
    /// search (same cell and [`NetworkKind::reach`]'s targets, not every
    /// node).
    occupants: HashMap<CellId, Vec<Entity>>,
    /// [`NetworkKind::link_group`] id -> entities sharing it, for the same
    /// search's non-geometric side.
    groups: HashMap<u32, Vec<Entity>>,
    devices: HashMap<Entity, DeviceId<K>>,
    /// Revision per region slot index (see the module docs).
    region_rev: Vec<u64>,
    /// Revision per device slot index.
    device_rev: Vec<u64>,
    clock: u64,
    /// Payload a removed node released, not yet taken by DM, as `(entity,
    /// cell, payload)`.
    released: Vec<(Entity, u32, K::Payload)>,
}

/// A region as DM sees it after a commit: rebuild the wrapper keyed by
/// `region` (a region handle, exact as an `f32`).
#[derive(Clone, Debug, PartialEq)]
pub struct Transition {
    /// The region's raw handle bits.
    pub region: u32,
    /// Member entities (empty for a retired region).
    pub members: Vec<Entity>,
    /// Regions merged into or split from this one (raw handle bits).
    pub prior: Vec<u32>,
    pub retired: bool,
}

impl<K: NetworkKind> Default for NetworkHost<K> {
    fn default() -> Self {
        Self::new()
    }
}

impl<K: NetworkKind> NetworkHost<K> {
    #[must_use]
    pub fn new() -> Self {
        Self {
            net: Network::default(),
            nodes: HashMap::new(),
            occupants: HashMap::new(),
            groups: HashMap::new(),
            devices: HashMap::new(),
            region_rev: Vec::new(),
            device_rev: Vec::new(),
            clock: 0,
            released: Vec::new(),
        }
    }

    fn bump_region(&mut self, r: RegionId<K>) {
        self.clock += 1;
        let i = r.index() as usize;
        if self.region_rev.len() <= i {
            self.region_rev.resize(i + 1, 0);
        }
        self.region_rev[i] = self.clock;
    }

    fn bump_device(&mut self, d: DeviceId<K>) {
        self.clock += 1;
        let i = d.index() as usize;
        if self.device_rev.len() <= i {
            self.device_rev.resize(i + 1, 0);
        }
        self.device_rev[i] = self.clock;
    }

    /// The revision of `region` (0: never changed through this host).
    #[must_use]
    pub fn region_revision(&self, region: RegionId<K>) -> u64 {
        self.region_rev.get(region.index() as usize).copied().unwrap_or(0)
    }

    /// The revision of device `d`, including both sides' regions: a device
    /// law sleeps while this stays what it last saw.
    #[must_use]
    pub fn device_revision(&self, d: DeviceId<K>) -> u64 {
        let own = self.device_rev.get(d.index() as usize).copied().unwrap_or(0);
        let Ok(dev) = self.net.device(d) else {
            return own;
        };
        let side = |end| match self.net.resolve(end) {
            super::graph::Side::Region(r) => self.region_revision(r),
            _ => 0,
        };
        own.max(side(dev.a)).max(side(dev.b))
    }

    #[must_use]
    pub fn network(&self) -> &Network<K> {
        &self.net
    }

    #[must_use]
    pub fn node_of(&self, entity: Entity) -> Option<NodeId<K>> {
        self.nodes.get(&entity).copied()
    }

    #[must_use]
    pub fn contains(&self, entity: Entity) -> bool {
        self.nodes.contains_key(&entity)
    }

    /// Binds `entity`'s node at `cell` in its own singleton region, and
    /// connects it to every occupant of `cell` or one of
    /// [`NetworkKind::reach`]'s target cells that [`NetworkKind::connects`]
    /// accepts. Replaces whatever `entity` had bound before (an edit, not
    /// an error).
    ///
    /// # Errors
    /// [`NetError`] if the underlying arena is full.
    pub fn bind_node(&mut self, entity: Entity, cell: CellId, kind: u16, data: K::Node) -> Result<NodeId<K>, NetError> {
        if self.nodes.contains_key(&entity) {
            self.unbind_node(entity);
        }
        let group = K::link_group(&data);
        let node = self
            .net
            .add_node(cell, kind, encode_entity(entity), data, K::Payload::default())?;
        self.nodes.insert(entity, node);
        self.occupants.entry(cell).or_default().push(entity);
        if let Some(g) = group {
            self.groups.entry(g).or_default().push(entity);
        }
        self.connect_new_node(entity, node, cell);
        Ok(node)
    }

    /// Every other bound entity that might connect to a node at `cell`:
    /// [`NetworkKind::reach`]'s target cells (plus `cell` itself) and, if
    /// `data` names one, [`NetworkKind::link_group`]'s members -- not every
    /// node, and never `exclude` itself.
    fn candidate_entities(&self, exclude: Entity, data: &K::Node, cell: CellId) -> Vec<Entity> {
        let mut candidates: Vec<Entity> = Vec::new();
        let mut cells = K::reach(data, cell);
        if !cells.contains(&cell) {
            cells.push(cell);
        }
        for c in cells {
            if let Some(occ) = self.occupants.get(&c) {
                candidates.extend(occ.iter().copied());
            }
        }
        if let Some(g) = K::link_group(data)
            && let Some(members) = self.groups.get(&g)
        {
            candidates.extend(members.iter().copied());
        }
        candidates.retain(|&e| e != exclude);
        candidates
    }

    fn connect_new_node(&mut self, entity: Entity, node: NodeId<K>, cell: CellId) {
        let my_data = self
            .net
            .node(node)
            .expect("just added")
            .data
            .clone();
        let mut peers: Vec<NodeId<K>> = Vec::new();
        for other_entity in self.candidate_entities(entity, &my_data, cell) {
            let Some(&other_node) = self.nodes.get(&other_entity) else {
                continue;
            };
            let Ok(other) = self.net.node(other_node) else {
                continue;
            };
            if K::connects((&my_data, cell), (&other.data, other.pos)) {
                peers.push(other_node);
            }
        }
        for peer in peers {
            let _ = self.net.connect(node, peer);
        }
    }

    /// Replaces `entity`'s node data in place (a machine's supply or served
    /// demand changed). Connectivity is not re-derived: a change that could
    /// alter [`NetworkKind::connects`] (a cable's shape) is a rebind via
    /// [`NetworkHost::bind_node`], not this.
    ///
    /// # Errors
    /// [`NetError`] if `entity` has no node here.
    pub fn set_node_data(&mut self, entity: Entity, data: K::Node) -> Result<(), NetError> {
        let node = self.node_of(entity).ok_or(NetError::NoEdge)?;
        self.net.set_node_data(node, data)?;
        let r = self.net.node(node)?.region();
        self.bump_region(r);
        Ok(())
    }

    /// Removes `entity`'s node. A no-op if it has none. Its share of the
    /// region payload is released at once
    /// ([`RegionEvent::Released`], resolved via [`decode_key`]); a possible
    /// split waits for [`NetworkHost::commit`].
    pub fn unbind_node(&mut self, entity: Entity) {
        let Some(node) = self.nodes.remove(&entity) else {
            return;
        };
        if let Ok(n) = self.net.node(node) {
            let cell = n.pos;
            if let Some(occupants) = self.occupants.get_mut(&cell) {
                occupants.retain(|&e| e != entity);
                if occupants.is_empty() {
                    self.occupants.remove(&cell);
                }
            }
            if let Some(g) = K::link_group(&n.data)
                && let Some(members) = self.groups.get_mut(&g)
            {
                members.retain(|&e| e != entity);
                if members.is_empty() {
                    self.groups.remove(&g);
                }
            }
        }
        let _ = self.net.remove_node(node);
    }

    /// Adds a device edge between two entities' nodes (a pump between two
    /// cable/pipe regions). Node endpoints must already be bound.
    ///
    /// # Errors
    /// [`NetError`] for a node not bound here, or a full arena.
    pub fn bind_device(&mut self, entity: Entity, a: Entity, b: Entity, kind: u16, data: K::Device) -> Result<DeviceId<K>, NetError> {
        let ea = self.node_of(a).map_or(Endpoint::Detached, Endpoint::Node);
        let eb = self.node_of(b).map_or(Endpoint::Detached, Endpoint::Node);
        self.add_device(entity, ea, eb, kind, data)
    }

    /// Adds a device edge between `a`'s node and a field cell (a vent
    /// between a pipe region and its turf).
    ///
    /// # Errors
    /// [`NetError`] for a full arena.
    pub fn bind_cell_device(&mut self, entity: Entity, a: Entity, cell: u32, kind: u16, data: K::Device) -> Result<DeviceId<K>, NetError> {
        let ea = self.node_of(a).map_or(Endpoint::Detached, Endpoint::Node);
        self.add_device(entity, ea, Endpoint::Cell(cell), kind, data)
    }

    fn add_device(&mut self, entity: Entity, a: Endpoint<K>, b: Endpoint<K>, kind: u16, data: K::Device) -> Result<DeviceId<K>, NetError> {
        self.unbind_device(entity);
        let d = self.net.add_device(a, b, kind, encode_entity(entity), data)?;
        self.devices.insert(entity, d);
        self.bump_device(d);
        Ok(d)
    }

    pub fn unbind_device(&mut self, entity: Entity) {
        if let Some(d) = self.devices.remove(&entity) {
            let _ = self.net.remove_device(d);
        }
    }

    /// Every bound device as `(device, its entity)`: dense iteration over
    /// the device arena (`rust_architecture.md` §4.5), not a hash lookup
    /// per device.
    pub fn devices(&self) -> impl Iterator<Item = (DeviceId<K>, Entity)> + '_ {
        self.net
            .devices()
            .filter_map(|(d, dev)| decode_key(dev.key).map(|e| (d, e)))
    }

    /// Every region, densely.
    pub fn regions(&self) -> impl Iterator<Item = RegionId<K>> + '_ {
        self.net.regions().map(|(r, _)| r)
    }

    /// Resolves the split-then-merge batch and returns the events since the
    /// last commit (unchanged from [`Network::commit`]: an explosion's
    /// thousand edits are one pass). Every region the batch touched moves
    /// its revision; released shares are kept for
    /// [`take_released`](Self::take_released).
    pub fn commit(&mut self) -> Vec<RegionEvent<K>> {
        let events = self.net.commit();
        for ev in &events {
            match ev {
                RegionEvent::Created { region } | RegionEvent::Changed { region } | RegionEvent::Retired { region } => {
                    self.bump_region(*region);
                }
                RegionEvent::Merged { into, from } => {
                    self.bump_region(*into);
                    self.bump_region(*from);
                }
                RegionEvent::Split { from, into } => {
                    self.bump_region(*from);
                    self.bump_region(*into);
                }
                RegionEvent::Released { key, pos, payload } => {
                    if let Some(e) = decode_key(*key) {
                        self.released.push((e, *pos, payload.clone()));
                    }
                }
                RegionEvent::DeviceDetached { device } => self.bump_device(*device),
            }
        }
        events
    }

    /// Folds a commit's events into DM-facing [`Transition`]s: every region
    /// whose membership changed (with the regions it absorbed or split
    /// from) and every region that is gone.
    #[must_use]
    pub fn transitions(&self, events: &[RegionEvent<K>]) -> Vec<Transition> {
        let mut touched: Vec<RawHandle> = Vec::new();
        let mut prior: HashMap<RawHandle, Vec<u32>> = HashMap::new();
        let mut retired: Vec<RawHandle> = Vec::new();
        for ev in events {
            match ev {
                RegionEvent::Created { region } | RegionEvent::Changed { region } => touched.push(region.raw()),
                RegionEvent::Merged { into, from } => {
                    touched.push(into.raw());
                    prior.entry(into.raw()).or_default().push(from.raw().bits());
                    retired.push(from.raw());
                }
                RegionEvent::Split { from, into } => {
                    touched.extend([from.raw(), into.raw()]);
                    prior.entry(into.raw()).or_default().push(from.raw().bits());
                }
                RegionEvent::Retired { region } => retired.push(region.raw()),
                RegionEvent::Released { .. } | RegionEvent::DeviceDetached { .. } => {}
            }
        }
        let mut out = Vec::new();
        retired.sort_unstable();
        retired.dedup();
        for raw in retired {
            if self.net.region(RegionId::<K>::from_raw(raw)).is_err() {
                out.push(Transition {
                    region: raw.bits(),
                    members: Vec::new(),
                    prior: Vec::new(),
                    retired: true,
                });
            }
        }
        touched.sort_unstable();
        touched.dedup();
        for raw in touched {
            let r = RegionId::<K>::from_raw(raw);
            if self.net.region(r).is_err() {
                continue;
            }
            let mut p = prior.remove(&raw).unwrap_or_default();
            p.sort_unstable();
            p.dedup();
            out.push(Transition {
                region: raw.bits(),
                members: self.members(r),
                prior: p,
                retired: false,
            });
        }
        out
    }

    #[must_use]
    pub fn region_of(&self, entity: Entity) -> Option<RegionId<K>> {
        let node = self.node_of(entity)?;
        self.net.node(node).ok().map(super::graph::Node::region)
    }

    #[must_use]
    pub fn payload(&self, region: RegionId<K>) -> Option<&K::Payload> {
        self.net.region(region).ok().map(super::graph::Region::payload)
    }

    /// Mutable access to a region's payload -- the kind's own law reads and
    /// writes it directly; no side ledger.
    ///
    /// # Errors
    /// [`NetError`] for a stale or unknown region.
    pub fn payload_mut(&mut self, region: RegionId<K>) -> Result<&mut K::Payload, NetError> {
        self.net.region(region)?;
        self.bump_region(region);
        self.net.payload_mut(region)
    }

    /// Replaces a region's payload if it differs (a law's write-back),
    /// moving its revision only on a real change. Returns whether it
    /// changed.
    ///
    /// # Errors
    /// [`NetError`] for a stale or unknown region.
    pub fn set_payload(&mut self, region: RegionId<K>, payload: K::Payload) -> Result<bool, NetError> {
        let slot = self.net.payload_mut(region)?;
        if *slot == payload {
            return Ok(false);
        }
        *slot = payload;
        self.bump_region(region);
        Ok(true)
    }

    /// Both sides of a device as `(region, summary, payload)`, if both are
    /// distinct live regions (a device whose sides share a region, or with
    /// a cell or detached side, has no pair).
    #[must_use]
    pub fn device_pair(&self, d: DeviceId<K>) -> Option<[(RegionId<K>, K::Summary, K::Payload); 2]> {
        let dev = self.net.device(d).ok()?;
        let (super::graph::Side::Region(a), super::graph::Side::Region(b)) =
            (self.net.resolve(dev.a), self.net.resolve(dev.b))
        else {
            return None;
        };
        if a == b {
            return None;
        }
        let ra = self.net.region(a).ok()?;
        let rb = self.net.region(b).ok()?;
        Some([
            (a, ra.summary().clone(), ra.payload().clone()),
            (b, rb.summary().clone(), rb.payload().clone()),
        ])
    }

    /// Replaces a device's parameters (only a real change moves its
    /// revision).
    ///
    /// # Errors
    /// [`NetError`] if `entity` has no device here.
    pub fn set_device_data(&mut self, entity: Entity, data: K::Device) -> Result<(), NetError> {
        let d = *self.devices.get(&entity).ok_or(NetError::NoEdge)?;
        if self.net.device(d)?.data == data {
            return Ok(());
        }
        self.net.set_device_data(d, data)?;
        self.bump_device(d);
        Ok(())
    }

    /// The device `entity` bound, if any.
    #[must_use]
    pub fn device_of(&self, entity: Entity) -> Option<DeviceId<K>> {
        self.devices.get(&entity).copied()
    }

    /// Payload removed nodes released since the last call, as `(entity,
    /// cell, payload)`: the entity that was unbound and where it was.
    pub fn take_released(&mut self) -> Vec<(Entity, u32, K::Payload)> {
        std::mem::take(&mut self.released)
    }

    /// Every entity with a node on `region`.
    #[must_use]
    pub fn members(&self, region: RegionId<K>) -> Vec<Entity> {
        let Ok(nodes) = self.net.members(region) else {
            return Vec::new();
        };
        nodes
            .into_iter()
            .filter_map(|n| self.net.node(n).ok().and_then(|node| decode_key(node.key)))
            .collect()
    }

    /// Applies a command to `entity`'s node's region payload.
    ///
    /// # Errors
    /// [`NetError`] if `entity` has no node here.
    pub fn command(&mut self, entity: Entity, cmd: &K::Command) -> Result<RegionId<K>, NetError> {
        let node = self.node_of(entity).ok_or(NetError::NoEdge)?;
        let r = self.net.command(node, cmd)?;
        self.bump_region(r);
        Ok(r)
    }
}

/// Every region's payload counts toward the conservation check
/// (`rust_architecture.md` §4.9), plus released shares DM has not taken.
impl<K: NetworkKind> Conserved for NetworkHost<K>
where
    K::Payload: Conserved,
{
    fn totals(&self, visit: &mut dyn FnMut(&'static str, f64)) {
        for (_, region) in self.net.regions() {
            region.payload().totals(visit);
        }
        for (_, _, p) in &self.released {
            p.totals(visit);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A one-dimensional cable-like kind: nodes connect only to a same- or
    /// adjacent-cell node on the East/West axis (mirroring real cable
    /// geometry without needing the real power domain here).
    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    struct Line;

    impl NetworkKind for Line {
        const NAME: &'static str = "line";
        type Node = ();
        type Summary = f64;
        type Payload = f64;
        type Device = ();
        type Command = f64;

        fn summarize((): &()) -> f64 {
            1.0
        }
        fn split(payload: &mut f64, whole: &f64, part: &f64) -> f64 {
            if *whole <= 0.0 {
                return 0.0;
            }
            let share = *payload * (*part / *whole);
            *payload -= share;
            share
        }
        fn merge(into: &mut f64, other: f64) {
            *into += other;
        }
        fn apply(payload: &mut f64, _: &f64, cmd: &f64) {
            *payload += *cmd;
        }
        fn connects((_, a): (&(), CellId), (_, b): (&(), CellId)) -> bool {
            a.abs_diff(b) == 1
        }
        fn reach((): &(), cell: CellId) -> Vec<CellId> {
            [cell.wrapping_sub(1), cell + 1].into_iter().collect()
        }
    }

    /// A kind whose only connection rule is a shared, non-geometric group
    /// id (ender cables: joined wherever they are, matched only by id).
    #[derive(Clone, Copy, Debug, Default, PartialEq)]
    struct Linked;

    impl NetworkKind for Linked {
        const NAME: &'static str = "linked";
        type Node = u32;
        type Summary = f64;
        type Payload = f64;
        type Device = ();
        type Command = f64;

        fn summarize(_: &u32) -> f64 {
            1.0
        }
        fn split(payload: &mut f64, whole: &f64, part: &f64) -> f64 {
            if *whole <= 0.0 {
                return 0.0;
            }
            let share = *payload * (*part / *whole);
            *payload -= share;
            share
        }
        fn merge(into: &mut f64, other: f64) {
            *into += other;
        }
        fn connects((a, _): (&u32, CellId), (b, _): (&u32, CellId)) -> bool {
            a == b
        }
        fn link_group(node: &u32) -> Option<u32> {
            Some(*node)
        }
    }

    #[test]
    fn same_link_group_connects_regardless_of_distance() {
        let mut host: NetworkHost<Linked> = NetworkHost::new();
        let a = entity(0);
        let b = entity(1);
        let unrelated = entity(2);
        host.bind_node(a, 1, 0, 7).unwrap();
        host.bind_node(b, 9_999, 0, 7).unwrap();
        host.bind_node(unrelated, 2, 0, 42).unwrap();
        host.commit();
        assert_eq!(host.region_of(a), host.region_of(b), "same link id, far apart cells");
        assert_ne!(host.region_of(a), host.region_of(unrelated));
    }

    fn entity(i: u32) -> Entity {
        EntityId::from_bits(i).unwrap()
    }

    #[test]
    fn adjacent_cells_connect_and_share_a_region() {
        let mut host: NetworkHost<Line> = NetworkHost::new();
        let a = entity(0);
        let b = entity(1);
        host.bind_node(a, 5, 0, ()).unwrap();
        host.bind_node(b, 6, 0, ()).unwrap();
        host.commit();
        assert_eq!(host.region_of(a), host.region_of(b), "adjacent cells connect");
    }

    #[test]
    fn distant_cells_do_not_connect() {
        let mut host: NetworkHost<Line> = NetworkHost::new();
        let a = entity(0);
        let b = entity(1);
        host.bind_node(a, 5, 0, ()).unwrap();
        host.bind_node(b, 50, 0, ()).unwrap();
        host.commit();
        assert_ne!(host.region_of(a), host.region_of(b));
    }

    #[test]
    fn unbind_splits_and_releases_a_conserved_share() {
        let mut host: NetworkHost<Line> = NetworkHost::new();
        let a = entity(0);
        let b = entity(1);
        let c = entity(2);
        host.bind_node(a, 1, 0, ()).unwrap();
        host.bind_node(b, 2, 0, ()).unwrap();
        host.bind_node(c, 3, 0, ()).unwrap();
        host.commit();
        let region = host.region_of(a).unwrap();
        *host.payload_mut(region).unwrap() = 30.0;

        host.unbind_node(b);
        let events = host.commit();

        let released: f64 = events
            .iter()
            .filter_map(|e| match e {
                RegionEvent::Released { key, payload, .. } if decode_key(*key) == Some(b) => Some(*payload),
                _ => None,
            })
            .sum();
        assert!((released - 10.0).abs() < 1e-9, "b's third share released, got {released}");
        assert_ne!(host.region_of(a), host.region_of(c), "removing the middle node splits the line");
        let total: f64 =
            *host.payload(host.region_of(a).unwrap()).unwrap() + *host.payload(host.region_of(c).unwrap()).unwrap() + released;
        assert!((total - 30.0).abs() < 1e-9, "conserved across the split: {total}");
    }

    #[test]
    fn members_resolve_back_to_the_entities_that_bound_them() {
        let mut host: NetworkHost<Line> = NetworkHost::new();
        let a = entity(0);
        let b = entity(1);
        host.bind_node(a, 1, 0, ()).unwrap();
        host.bind_node(b, 2, 0, ()).unwrap();
        host.commit();
        let region = host.region_of(a).unwrap();
        let mut members = host.members(region);
        members.sort_by_key(|e| e.index());
        let mut expect = [a, b];
        expect.sort_by_key(|e| e.index());
        assert_eq!(members, expect);
    }

    #[test]
    fn rebinding_the_same_entity_replaces_its_node() {
        let mut host: NetworkHost<Line> = NetworkHost::new();
        let a = entity(0);
        let b = entity(1);
        host.bind_node(a, 1, 0, ()).unwrap();
        host.bind_node(b, 2, 0, ()).unwrap();
        host.commit();
        assert_eq!(host.region_of(a), host.region_of(b));

        // Rebind a far away: it no longer connects to b, and the old
        // occupancy entry at cell 1 is gone (no ghost edge back).
        host.bind_node(a, 50, 0, ()).unwrap();
        host.commit();
        assert_ne!(host.region_of(a), host.region_of(b));
        let c = entity(2);
        host.bind_node(c, 1, 0, ()).unwrap();
        host.commit();
        assert_ne!(host.region_of(c), host.region_of(a), "cell 1's old occupant (a) is gone");
    }
}
