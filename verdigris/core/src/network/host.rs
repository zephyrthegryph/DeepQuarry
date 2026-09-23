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
//!   [`Handle`] from it directly.
//! - **Edges.** DM never sends topology. Binding a node at a cell is enough:
//!   [`NetworkHost::bind_node`] derives edges by calling
//!   [`NetworkKind::connects`] against every other node occupying that cell
//!   or one of its six grid neighbors (via an occupancy index, not a scan of
//!   every node), and connects the pairs it accepts.
//! - **Batching.** [`NetworkHost::commit`] is exactly
//!   [`Network::commit`]: split-then-merge, so an explosion's edits are one
//!   batch, unchanged from `graph.rs`.
//! - **Devices.** [`NetworkHost::devices`] iterates the dense device arena
//!   directly (no hash lookup), per entity handle.
//!
//! No region state lives here or in a side map: everything about a region
//! is in [`NetworkKind::Payload`], carried by `Network<K>` itself.

use std::collections::HashMap;

use crate::entity::EntitySlots;
use crate::grid::{Face, GridDims};
use crate::handle::{Handle, RawHandle};

use super::graph::{
    CellId, DeviceId, Endpoint, NetError, Network, NetworkKind, NodeId, RegionEvent, RegionId,
};

/// An entity handle, as [`NetworkHost`] identifies nodes and devices.
pub type Entity = Handle<EntitySlots>;

/// Recovers the entity a graph `key` (`Network::add_node`'s `key` field,
/// [`RegionEvent::Released`]'s `key`) names. `None` for [`super::NO_KEY`] or
/// any value [`NetworkHost`] did not itself produce.
#[must_use]
pub fn decode_key(key: u32) -> Option<Entity> {
    RawHandle::from_bits(key).map(Handle::from_raw)
}

fn encode_entity(entity: Entity) -> u32 {
    entity.raw().bits()
}

/// Entity-keyed topology over one [`NetworkKind`] (`rust_architecture.md`
/// §4.5). See the module docs.
pub struct NetworkHost<K: NetworkKind> {
    net: Network<K>,
    dims: GridDims,
    nodes: HashMap<Entity, NodeId<K>>,
    /// Cell -> entities with a node bound there, for [`bind_node`]'s edge
    /// search (same cell and the six grid neighbors, not every node).
    occupants: HashMap<CellId, Vec<Entity>>,
    devices: HashMap<Entity, DeviceId<K>>,
}

impl<K: NetworkKind> NetworkHost<K> {
    #[must_use]
    pub fn new(dims: GridDims) -> Self {
        Self {
            net: Network::default(),
            dims,
            nodes: HashMap::new(),
            occupants: HashMap::new(),
            devices: HashMap::new(),
        }
    }

    #[must_use]
    pub fn network(&self) -> &Network<K> {
        &self.net
    }

    #[must_use]
    pub fn dims(&self) -> GridDims {
        self.dims
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
    /// connects it to every occupant of `cell` or a neighboring cell that
    /// [`NetworkKind::connects`] accepts. Replaces whatever `entity` had
    /// bound before (an edit, not an error).
    ///
    /// # Errors
    /// [`NetError`] if the underlying arena is full.
    pub fn bind_node(&mut self, entity: Entity, cell: CellId, kind: u16, data: K::Node) -> Result<NodeId<K>, NetError> {
        if self.nodes.contains_key(&entity) {
            self.unbind_node(entity);
        }
        let node = self
            .net
            .add_node(cell, kind, encode_entity(entity), data, K::Payload::default())?;
        self.nodes.insert(entity, node);
        self.occupants.entry(cell).or_default().push(entity);
        self.connect_new_node(entity, node, cell);
        Ok(node)
    }

    fn candidate_cells(&self, cell: CellId) -> Vec<CellId> {
        let mut cells = vec![cell];
        for face in Face::ALL {
            if let Some(n) = self.dims.neighbor(cell, face) {
                cells.push(n);
            }
        }
        cells
    }

    fn connect_new_node(&mut self, entity: Entity, node: NodeId<K>, cell: CellId) {
        let my_data = self
            .net
            .node(node)
            .expect("just added")
            .data
            .clone();
        let mut peers: Vec<NodeId<K>> = Vec::new();
        for c in self.candidate_cells(cell) {
            let Some(occupants) = self.occupants.get(&c) else {
                continue;
            };
            for &other_entity in occupants {
                if other_entity == entity {
                    continue;
                }
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
        }
        for peer in peers {
            let _ = self.net.connect(node, peer);
        }
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
        let d = self.net.add_device(ea, eb, kind, encode_entity(entity), data)?;
        self.devices.insert(entity, d);
        Ok(d)
    }

    pub fn unbind_device(&mut self, entity: Entity) {
        if let Some(d) = self.devices.remove(&entity) {
            let _ = self.net.remove_device(d);
        }
    }

    /// Every bound device, by its own entity -- dense iteration over the
    /// device arena (`rust_architecture.md` §4.5's "device iteration is
    /// dense"), not a hash lookup per device.
    pub fn devices(&self) -> impl Iterator<Item = Entity> + '_ {
        self.devices.keys().copied()
    }

    /// Resolves the split-then-merge batch and returns the events since the
    /// last commit (unchanged from [`Network::commit`]: an explosion's
    /// thousand edits are one pass).
    pub fn commit(&mut self) -> Vec<RegionEvent<K>> {
        self.net.commit()
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
        self.net.payload_mut(region)
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
        self.net.command(node, cmd)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::arena::Arena;

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
    }

    fn entity(i: u32) -> Entity {
        let mut arena: Arena<()> = Arena::default();
        // Allocate up to index i so the returned handle's index is exactly
        // i, generation 0 -- a cheap, deterministic way to mint distinct
        // test entities without a real EntityTable.
        let mut last = arena.insert(()).unwrap();
        for _ in 0..i {
            last = arena.insert(()).unwrap();
        }
        Handle::from_raw(last.raw())
    }

    fn dims() -> GridDims {
        GridDims::new(100, 1, 1).unwrap()
    }

    #[test]
    fn adjacent_cells_connect_and_share_a_region() {
        let mut host: NetworkHost<Line> = NetworkHost::new(dims());
        let a = entity(0);
        let b = entity(1);
        host.bind_node(a, 5, 0, ()).unwrap();
        host.bind_node(b, 6, 0, ()).unwrap();
        host.commit();
        assert_eq!(host.region_of(a), host.region_of(b), "adjacent cells connect");
    }

    #[test]
    fn distant_cells_do_not_connect() {
        let mut host: NetworkHost<Line> = NetworkHost::new(dims());
        let a = entity(0);
        let b = entity(1);
        host.bind_node(a, 5, 0, ()).unwrap();
        host.bind_node(b, 50, 0, ()).unwrap();
        host.commit();
        assert_ne!(host.region_of(a), host.region_of(b));
    }

    #[test]
    fn unbind_splits_and_releases_a_conserved_share() {
        let mut host: NetworkHost<Line> = NetworkHost::new(dims());
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
        let mut host: NetworkHost<Line> = NetworkHost::new(dims());
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
        let mut host: NetworkHost<Line> = NetworkHost::new(dims());
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
