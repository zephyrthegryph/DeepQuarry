//! The topology: nodes, edges, regions and device edges, with incremental
//! connected components (see the module docs in `network/mod.rs`).

use std::fmt;

use crate::arena::{Arena, ArenaError};
use crate::handle::{Handle, RawHandle};

/// An additive per-region aggregate of node data (total volume, supply and
/// demand, storage capacity). Must behave like a sum: `add` then `sub` of
/// the same value is a no-op up to rounding.
pub trait Additive: Clone + Default + fmt::Debug + PartialEq + Send + Sync + 'static {
    fn add(&mut self, other: &Self);
    fn sub(&mut self, other: &Self);
}

impl Additive for () {
    fn add(&mut self, (): &Self) {}
    fn sub(&mut self, (): &Self) {}
}

impl Additive for f64 {
    fn add(&mut self, other: &Self) {
        *self += *other;
    }
    fn sub(&mut self, other: &Self) {
        *self -= *other;
    }
}

macro_rules! additive_arrays {
    ($($n:literal)*) => {$(
        impl Additive for [f64; $n] {
            fn add(&mut self, other: &Self) {
                for (a, b) in self.iter_mut().zip(other) {
                    *a += *b;
                }
            }
            fn sub(&mut self, other: &Self) {
                for (a, b) in self.iter_mut().zip(other) {
                    *a -= *b;
                }
            }
        }
    )*};
}

additive_arrays!(1 2 3 4 5 6 7 8);

/// One network kind: pipes, cables, heat-exchange pipes, disposals, ...
/// (`simulation.md` §3). The kind itself is a marker type.
pub trait NetworkKind:
    Clone + Copy + fmt::Debug + Default + PartialEq + Send + Sync + 'static
{
    const NAME: &'static str;
    /// Per-node data: a pipe segment's volume, a cable piece's supply and
    /// demand, a battery's capacity.
    type Node: Clone + fmt::Debug + PartialEq + Send + Sync + 'static;
    /// The additive aggregate of `Node` over a region, maintained by the
    /// framework. It is the weight [`NetworkKind::split`] divides by.
    type Summary: Additive;
    /// The pooled region state: gas moles and energy, stored charge.
    type Payload: Clone + Default + fmt::Debug + PartialEq + Send + Sync + 'static;
    /// Per-device parameters on a device edge (flow law settings, M2).
    type Device: Clone + Default + fmt::Debug + PartialEq + Send + Sync + 'static;
    /// A command against the region payload of a node (one-off draws,
    /// injected gas).
    type Command: Clone + fmt::Debug + Send + Sync + 'static;

    fn summarize(node: &Self::Node) -> Self::Summary;

    /// Carves the share of `payload` that belongs to `part` out of a region
    /// whose summary is `whole`, leaving the rest in `payload`, and returns
    /// it. **Must conserve**: the returned value plus what is left equals
    /// the input. `part` may equal `whole` (the last node of a region).
    fn split(
        payload: &mut Self::Payload,
        whole: &Self::Summary,
        part: &Self::Summary,
    ) -> Self::Payload;

    /// Pools `other` into `into`. **Must conserve.**
    fn merge(into: &mut Self::Payload, other: Self::Payload);

    /// Applies a command to a region's payload. Must be deterministic.
    fn apply(payload: &mut Self::Payload, summary: &Self::Summary, cmd: &Self::Command) {
        let _ = (payload, summary, cmd);
    }

    /// The topology law (`rust_architecture.md` §4.5): whether a node at
    /// `a`'s cell and one at `b`'s cell connect. [`super::host::NetworkHost`]
    /// calls this to confirm every candidate [`NetworkKind::reach`] finds, so
    /// DM never sends topology -- binding a node at a cell is enough. Must be
    /// symmetric (`connects(a, b) == connects(b, a)`): [`super::host::NetworkHost`]
    /// only asks a new node's own `reach`, trusting that a kind whose reach
    /// rule is direction-symmetric (a reverse of a reverse is the original
    /// direction) never needs the other side's `reach` re-checked. The
    /// default never connects anything.
    fn connects(a: (&Self::Node, CellId), b: (&Self::Node, CellId)) -> bool {
        let _ = (a, b);
        false
    }

    /// Cells a node at `cell` might connect to (`rust_architecture.md`
    /// §4.5's occupancy index): the domain's own reach rule -- grid-face
    /// adjacency, a diagonal combination, an explicit cross-z link,
    /// whatever [`NetworkKind::connects`] cares about. A superset is fine;
    /// [`NetworkKind::connects`] confirms each one. The default reaches
    /// nothing beyond `cell` itself, which [`super::host::NetworkHost`]
    /// always includes regardless (same-cell nodes are candidates too).
    fn reach(node: &Self::Node, cell: CellId) -> Vec<CellId> {
        let _ = node;
        vec![cell]
    }

    /// A non-geometric connection group (`rust_architecture.md` §4.5: this
    /// is what replaces power's `links` map): nodes that share a non-`None`
    /// group id connect wherever they are, in addition to whatever
    /// [`NetworkKind::reach`] finds. `None` (the default) opts a node out;
    /// [`NetworkKind::connects`] still confirms every pair a shared group
    /// produces.
    fn link_group(node: &Self::Node) -> Option<u32> {
        let _ = node;
        None
    }
}

/// A grid cell index (`grid::GridDims`'s turf index): what
/// [`NetworkKind::connects`] and [`super::host::NetworkHost`]'s occupancy
/// index key nodes by.
pub type CellId = u32;

pub type NodeId<K> = Handle<Node<K>>;
pub type EdgeId<K> = Handle<Edge<K>>;
pub type RegionId<K> = Handle<Region<K>>;
pub type DeviceId<K> = Handle<Device<K>>;

/// No external key.
pub const NO_KEY: u32 = u32::MAX;

/// A pipe segment or cable piece.
#[derive(Clone, Debug)]
pub struct Node<K: NetworkKind> {
    /// Turf cell index.
    pub pos: u32,
    /// Kind within the network (manifold, straight pipe, node cable, ...).
    pub kind: u16,
    /// The owner's external key (DM's registry index), or [`NO_KEY`].
    pub key: u32,
    pub data: K::Node,
    region: RegionId<K>,
    prev: Option<NodeId<K>>,
    next: Option<NodeId<K>>,
    edges: Vec<EdgeId<K>>,
    devices: Vec<DeviceId<K>>,
}

impl<K: NetworkKind> Node<K> {
    #[must_use]
    pub fn region(&self) -> RegionId<K> {
        self.region
    }

    #[must_use]
    pub fn edges(&self) -> &[EdgeId<K>] {
        &self.edges
    }

    #[must_use]
    pub fn devices(&self) -> &[DeviceId<K>] {
        &self.devices
    }
}

/// A connection between two nodes.
#[derive(Clone, Copy, Debug)]
pub struct Edge<K: NetworkKind> {
    pub a: NodeId<K>,
    pub b: NodeId<K>,
}

impl<K: NetworkKind> Edge<K> {
    #[must_use]
    pub fn other(&self, n: NodeId<K>) -> NodeId<K> {
        if self.a == n { self.b } else { self.a }
    }
}

/// A connected component with its pooled payload.
#[derive(Clone, Debug)]
pub struct Region<K: NetworkKind> {
    head: Option<NodeId<K>>,
    members: u32,
    summary: K::Summary,
    payload: K::Payload,
}

impl<K: NetworkKind> Region<K> {
    #[must_use]
    pub fn members(&self) -> u32 {
        self.members
    }
    #[must_use]
    pub fn summary(&self) -> &K::Summary {
        &self.summary
    }
    #[must_use]
    pub fn payload(&self) -> &K::Payload {
        &self.payload
    }
}

/// One side of a device edge.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Endpoint<K: NetworkKind> {
    /// A network node; the device acts on that node's region.
    Node(NodeId<K>),
    /// A field cell (a turf), by cell index.
    Cell(u32),
    /// The node it was attached to was removed.
    Detached,
}

/// Where a device side acts right now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side<K: NetworkKind> {
    Region(RegionId<K>),
    Cell(u32),
    Detached,
}

/// A device edge between regions and field cells (a pump between a pipe
/// region and a turf, a valve between two regions). Flow laws are M2's; the
/// framework keeps the endpoints valid across topology changes.
#[derive(Clone, Debug)]
pub struct Device<K: NetworkKind> {
    pub a: Endpoint<K>,
    pub b: Endpoint<K>,
    pub kind: u16,
    pub key: u32,
    pub data: K::Device,
}

/// What a commit (or an immediate edit) changed, in order.
#[derive(Clone, Debug, PartialEq)]
pub enum RegionEvent<K: NetworkKind> {
    /// A new region (a new node's singleton). Split children are reported
    /// as [`RegionEvent::Split`] instead.
    Created { region: RegionId<K> },
    /// `from` was pooled into `into` and retired.
    Merged {
        into: RegionId<K>,
        from: RegionId<K>,
    },
    /// `into` was carved out of `from`; `from` keeps the remainder and its ID.
    Split {
        from: RegionId<K>,
        into: RegionId<K>,
    },
    /// The region lost its last node.
    Retired { region: RegionId<K> },
    /// Node data or the payload changed without a topology change.
    Changed { region: RegionId<K> },
    /// A removed node's share of its region's payload (DM dumps it on the
    /// turf at `pos`, or discards it).
    Released {
        key: u32,
        pos: u32,
        payload: K::Payload,
    },
    /// A device lost a node endpoint.
    DeviceDetached { device: DeviceId<K> },
}

/// Why an edit failed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NetError {
    Arena(ArenaError),
    /// An edge from a node to itself.
    SelfLoop,
    /// No edge joins those nodes.
    NoEdge,
}

impl From<ArenaError> for NetError {
    fn from(e: ArenaError) -> Self {
        Self::Arena(e)
    }
}

impl fmt::Display for NetError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Arena(e) => write!(f, "{e}"),
            Self::SelfLoop => f.write_str("self-loop edge"),
            Self::NoEdge => f.write_str("no such edge"),
        }
    }
}

impl std::error::Error for NetError {}

/// Counters from the last commit (for metrics and benches).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CommitStats {
    /// Regions searched for a split.
    pub split_regions: u32,
    /// Nodes visited by split searches.
    pub visited: u64,
    /// Regions carved off.
    pub splits: u32,
    pub merges: u32,
    /// Nodes relabelled by merges and splits.
    pub relabelled: u64,
}

struct Group<K: NetworkKind> {
    parent: u32,
    /// Every node this group found.
    members: Vec<NodeId<K>>,
    /// Found but not yet expanded, from `head`.
    frontier: Vec<NodeId<K>>,
    head: usize,
    done: bool,
}

/// Reusable split-search scratch, indexed by node slot.
struct Scratch<K: NetworkKind> {
    epoch: u32,
    stamp: Vec<u32>,
    owner: Vec<u32>,
    groups: Vec<Group<K>>,
    active: Vec<u32>,
}

impl<K: NetworkKind> Default for Scratch<K> {
    fn default() -> Self {
        Self {
            epoch: 0,
            stamp: Vec::new(),
            owner: Vec::new(),
            groups: Vec::new(),
            active: Vec::new(),
        }
    }
}

/// A network of one kind: topology, incremental regions and device edges.
///
/// Edits change the graph at once; region maintenance for edge and node
/// *removals* (splits) and edge *additions* (merges) is deferred to
/// [`Network::commit`], so a batch of edits costs one pass. A batch is
/// equivalent to applying its removals, then its additions, in order.
pub struct Network<K: NetworkKind> {
    nodes: Arena<Node<K>>,
    edges: Arena<Edge<K>>,
    regions: Arena<Region<K>>,
    devices: Arena<Device<K>>,
    /// (region, seed) pairs from removals, resolved at commit.
    pending_splits: Vec<(RegionId<K>, NodeId<K>)>,
    /// Edges added since the last commit.
    pending_merges: Vec<(EdgeId<K>, NodeId<K>, NodeId<K>)>,
    events: Vec<RegionEvent<K>>,
    touched_nodes: Vec<NodeId<K>>,
    touched_devices: Vec<DeviceId<K>>,
    scratch: Scratch<K>,
    stats: CommitStats,
    revision: u64,
}

impl<K: NetworkKind> Default for Network<K> {
    fn default() -> Self {
        Self::new()
    }
}

impl<K: NetworkKind> Network<K> {
    #[must_use]
    pub fn new() -> Self {
        Self {
            nodes: Arena::new(),
            edges: Arena::new(),
            regions: Arena::new(),
            devices: Arena::new(),
            pending_splits: Vec::new(),
            pending_merges: Vec::new(),
            events: Vec::new(),
            touched_nodes: Vec::new(),
            touched_devices: Vec::new(),
            scratch: Scratch::default(),
            stats: CommitStats::default(),
            revision: 0,
        }
    }

    // ---- reads -------------------------------------------------------

    /// # Errors
    /// A stale or unknown handle.
    pub fn node(&self, n: NodeId<K>) -> Result<&Node<K>, NetError> {
        Ok(self.nodes.get(n)?)
    }

    /// # Errors
    /// A stale or unknown handle.
    pub fn edge(&self, e: EdgeId<K>) -> Result<&Edge<K>, NetError> {
        Ok(self.edges.get(e)?)
    }

    /// # Errors
    /// A stale or unknown handle.
    pub fn region(&self, r: RegionId<K>) -> Result<&Region<K>, NetError> {
        Ok(self.regions.get(r)?)
    }

    /// # Errors
    /// A stale or unknown handle.
    pub fn device(&self, d: DeviceId<K>) -> Result<&Device<K>, NetError> {
        Ok(self.devices.get(d)?)
    }

    /// The region a node belongs to. Between an edit and its commit this is
    /// the pre-commit region (new nodes sit in their own singleton).
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn region_of(&self, n: NodeId<K>) -> Result<RegionId<K>, NetError> {
        Ok(self.nodes.get(n)?.region)
    }

    pub fn nodes(&self) -> impl Iterator<Item = (NodeId<K>, &Node<K>)> {
        self.nodes.iter()
    }

    pub fn edges(&self) -> impl Iterator<Item = (EdgeId<K>, &Edge<K>)> {
        self.edges.iter()
    }

    pub fn regions(&self) -> impl Iterator<Item = (RegionId<K>, &Region<K>)> {
        self.regions.iter()
    }

    pub fn devices(&self) -> impl Iterator<Item = (DeviceId<K>, &Device<K>)> {
        self.devices.iter()
    }

    #[must_use]
    pub fn node_count(&self) -> usize {
        self.nodes.len()
    }

    #[must_use]
    pub fn edge_count(&self) -> usize {
        self.edges.len()
    }

    #[must_use]
    pub fn region_count(&self) -> usize {
        self.regions.len()
    }

    /// Commits so far.
    #[must_use]
    pub fn revision(&self) -> u64 {
        self.revision
    }

    /// Whether edits are waiting for [`Network::commit`].
    #[must_use]
    pub fn has_pending(&self) -> bool {
        !self.pending_splits.is_empty() || !self.pending_merges.is_empty()
    }

    /// The last commit's counters.
    #[must_use]
    pub fn stats(&self) -> CommitStats {
        self.stats
    }

    /// A region's members, in list order.
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn members(&self, r: RegionId<K>) -> Result<Vec<NodeId<K>>, NetError> {
        let region = self.regions.get(r)?;
        let mut out = Vec::with_capacity(region.members as usize);
        let mut cur = region.head;
        while let Some(n) = cur {
            out.push(n);
            cur = self.nodes.get(n)?.next;
        }
        Ok(out)
    }

    /// Where a device side acts now.
    #[must_use]
    pub fn resolve(&self, end: Endpoint<K>) -> Side<K> {
        match end {
            Endpoint::Node(n) => self
                .nodes
                .get(n)
                .map_or(Side::Detached, |node| Side::Region(node.region)),
            Endpoint::Cell(c) => Side::Cell(c),
            Endpoint::Detached => Side::Detached,
        }
    }

    /// The edge joining `a` and `b`, if any.
    #[must_use]
    pub fn find_edge(&self, a: NodeId<K>, b: NodeId<K>) -> Option<EdgeId<K>> {
        let (na, nb) = (self.nodes.get(a).ok()?, self.nodes.get(b).ok()?);
        let (from, list) = if na.edges.len() <= nb.edges.len() {
            (a, &na.edges)
        } else {
            (b, &nb.edges)
        };
        let to = if from == a { b } else { a };
        list.iter()
            .copied()
            .find(|&e| self.edges.get(e).is_ok_and(|edge| edge.other(from) == to))
    }

    // ---- edits -------------------------------------------------------

    /// Adds a node in its own singleton region holding `payload`.
    ///
    /// # Errors
    /// An arena is full.
    pub fn add_node(
        &mut self,
        pos: u32,
        kind: u16,
        key: u32,
        data: K::Node,
        payload: K::Payload,
    ) -> Result<NodeId<K>, NetError> {
        let summary = K::summarize(&data);
        let region = self.regions.insert(Region {
            head: None,
            members: 0,
            summary,
            payload,
        })?;
        let node = match self.nodes.insert(Node {
            pos,
            kind,
            key,
            data,
            region,
            prev: None,
            next: None,
            edges: Vec::new(),
            devices: Vec::new(),
        }) {
            Ok(n) => n,
            Err(e) => {
                let _ = self.regions.remove(region);
                return Err(e.into());
            }
        };
        self.link(region, node);
        self.events.push(RegionEvent::Created { region });
        self.touched_nodes.push(node);
        Ok(node)
    }

    /// Replaces a node's data, adjusting its region's summary.
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn set_node_data(&mut self, n: NodeId<K>, data: K::Node) -> Result<(), NetError> {
        let node = self.nodes.get_mut(n)?;
        let old = K::summarize(&node.data);
        let new = K::summarize(&data);
        node.data = data;
        let r = node.region;
        let region = self.regions.get_mut(r).expect("node's region is live");
        region.summary.sub(&old);
        region.summary.add(&new);
        self.events.push(RegionEvent::Changed { region: r });
        Ok(())
    }

    /// Applies a payload command to the region `n` belongs to now.
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn command(&mut self, n: NodeId<K>, cmd: &K::Command) -> Result<RegionId<K>, NetError> {
        let r = self.nodes.get(n)?.region;
        let region = self.regions.get_mut(r).expect("node's region is live");
        K::apply(&mut region.payload, &region.summary, cmd);
        self.events.push(RegionEvent::Changed { region: r });
        Ok(r)
    }

    /// Mutable access to a region's payload (the kind's step, M2/M3).
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn payload_mut(&mut self, r: RegionId<K>) -> Result<&mut K::Payload, NetError> {
        Ok(&mut self.regions.get_mut(r)?.payload)
    }

    /// Connects two nodes. Connecting already-connected nodes returns the
    /// existing edge. The merge happens at commit.
    ///
    /// # Errors
    /// A stale handle, a full arena or a self-loop.
    pub fn connect(&mut self, a: NodeId<K>, b: NodeId<K>) -> Result<EdgeId<K>, NetError> {
        if a == b {
            return Err(NetError::SelfLoop);
        }
        self.nodes.get(a)?;
        self.nodes.get(b)?;
        if let Some(e) = self.find_edge(a, b) {
            return Ok(e);
        }
        let e = self.edges.insert(Edge { a, b })?;
        self.nodes.get_mut(a).expect("checked").edges.push(e);
        self.nodes.get_mut(b).expect("checked").edges.push(e);
        self.pending_merges.push((e, a, b));
        Ok(e)
    }

    /// Removes an edge. A possible split is resolved at commit.
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn remove_edge(&mut self, e: EdgeId<K>) -> Result<(), NetError> {
        let edge = self.edges.remove(e)?;
        for n in [edge.a, edge.b] {
            let node = self.nodes.get_mut(n).expect("edge endpoints are live");
            let i = node
                .edges
                .iter()
                .position(|&x| x == e)
                .expect("edge is in its endpoints' lists");
            node.edges.swap_remove(i);
        }
        let ra = self.nodes.get(edge.a).expect("live").region;
        let rb = self.nodes.get(edge.b).expect("live").region;
        // An edge between different regions was added in this batch and
        // never merged: removing it cannot split anything.
        if ra == rb {
            self.pending_splits.push((ra, edge.a));
            self.pending_splits.push((ra, edge.b));
        }
        Ok(())
    }

    /// Removes the edge joining `a` and `b`.
    ///
    /// # Errors
    /// [`NetError::NoEdge`] if they are not connected.
    pub fn disconnect(&mut self, a: NodeId<K>, b: NodeId<K>) -> Result<(), NetError> {
        let e = self.find_edge(a, b).ok_or(NetError::NoEdge)?;
        self.remove_edge(e)
    }

    /// Removes a node and its edges. Its share of the region payload is
    /// carved out at once and reported as [`RegionEvent::Released`]; its
    /// devices are detached. A possible split is resolved at commit.
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn remove_node(&mut self, n: NodeId<K>) -> Result<(), NetError> {
        let node = self.nodes.get(n)?;
        let edges = node.edges.clone();
        for e in edges {
            self.remove_edge(e)?;
        }
        let devices = std::mem::take(&mut self.nodes.get_mut(n).expect("live").devices);
        for d in devices {
            if let Ok(dev) = self.devices.get_mut(d) {
                for end in [&mut dev.a, &mut dev.b] {
                    if *end == Endpoint::Node(n) {
                        *end = Endpoint::Detached;
                    }
                }
                self.events.push(RegionEvent::DeviceDetached { device: d });
                self.touched_devices.push(d);
            }
        }
        let r = self.nodes.get(n).expect("live").region;
        self.unlink(r, n);
        let node = self.nodes.remove(n).expect("live");
        let part = K::summarize(&node.data);
        let region = self.regions.get_mut(r).expect("node's region is live");
        let whole = region.summary.clone();
        let mut released = K::split(&mut region.payload, &whole, &part);
        region.summary.sub(&part);
        if region.members == 0 {
            let region = self.regions.remove(r).expect("live");
            K::merge(&mut released, region.payload);
            self.events.push(RegionEvent::Retired { region: r });
        }
        self.events.push(RegionEvent::Released {
            key: node.key,
            pos: node.pos,
            payload: released,
        });
        Ok(())
    }

    /// Adds a device edge. Node endpoints must be live.
    ///
    /// # Errors
    /// A stale node handle or a full arena.
    pub fn add_device(
        &mut self,
        a: Endpoint<K>,
        b: Endpoint<K>,
        kind: u16,
        key: u32,
        data: K::Device,
    ) -> Result<DeviceId<K>, NetError> {
        for end in [a, b] {
            if let Endpoint::Node(n) = end {
                self.nodes.get(n)?;
            }
        }
        let d = self.devices.insert(Device {
            a,
            b,
            kind,
            key,
            data,
        })?;
        for end in [a, b] {
            if let Endpoint::Node(n) = end {
                let devs = &mut self.nodes.get_mut(n).expect("checked").devices;
                if !devs.contains(&d) {
                    devs.push(d);
                }
            }
        }
        self.touched_devices.push(d);
        Ok(d)
    }

    /// Removes a device edge.
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn remove_device(&mut self, d: DeviceId<K>) -> Result<Device<K>, NetError> {
        let dev = self.devices.remove(d)?;
        for end in [dev.a, dev.b] {
            if let Endpoint::Node(n) = end {
                if let Ok(node) = self.nodes.get_mut(n) {
                    node.devices.retain(|&x| x != d);
                }
            }
        }
        self.touched_devices.push(d);
        Ok(dev)
    }

    /// Replaces a device's parameters.
    ///
    /// # Errors
    /// A stale or unknown handle.
    pub fn set_device_data(&mut self, d: DeviceId<K>, data: K::Device) -> Result<(), NetError> {
        self.devices.get_mut(d)?.data = data;
        self.touched_devices.push(d);
        Ok(())
    }

    // ---- commit ------------------------------------------------------

    /// Resolves every pending split, then every pending merge, and returns
    /// the events since the last commit (including immediate ones such as
    /// `Created` and `Released`).
    pub fn commit(&mut self) -> Vec<RegionEvent<K>> {
        self.stats = CommitStats::default();
        let mut splits = std::mem::take(&mut self.pending_splits);
        // Group seeds by region; the stable sort keeps seed order within a
        // region, so the result depends only on the edit sequence.
        splits.sort_by_key(|(r, _)| r.raw());
        let mut i = 0;
        let mut seeds = Vec::new();
        while i < splits.len() {
            let r = splits[i].0;
            seeds.clear();
            while i < splits.len() && splits[i].0 == r {
                seeds.push(splits[i].1);
                i += 1;
            }
            if self.regions.contains(r) {
                self.split_region(r, &seeds);
            }
        }
        splits.clear();
        self.pending_splits = splits;

        let merges = std::mem::take(&mut self.pending_merges);
        for &(e, a, b) in &merges {
            let live = self
                .edges
                .get(e)
                .is_ok_and(|edge| edge.a == a && edge.b == b);
            if !live {
                continue;
            }
            let ra = self.nodes.get(a).expect("edge endpoint").region;
            let rb = self.nodes.get(b).expect("edge endpoint").region;
            if ra != rb {
                self.merge_regions(ra, rb);
            }
        }
        self.revision += 1;
        std::mem::take(&mut self.events)
    }

    /// Nodes and devices whose region or data changed since the last call
    /// (for publishing views). May contain duplicates and removed handles.
    pub fn drain_touched(&mut self, nodes: &mut Vec<NodeId<K>>, devices: &mut Vec<DeviceId<K>>) {
        nodes.append(&mut self.touched_nodes);
        devices.append(&mut self.touched_devices);
    }

    fn link(&mut self, r: RegionId<K>, n: NodeId<K>) {
        let region = self.regions.get_mut(r).expect("live region");
        let old_head = region.head.replace(n);
        region.members += 1;
        let node = self.nodes.get_mut(n).expect("live node");
        node.region = r;
        node.prev = None;
        node.next = old_head;
        if let Some(h) = old_head {
            self.nodes.get_mut(h).expect("live node").prev = Some(n);
        }
    }

    fn unlink(&mut self, r: RegionId<K>, n: NodeId<K>) {
        let node = self.nodes.get_mut(n).expect("live node");
        let (prev, next) = (node.prev.take(), node.next.take());
        match prev {
            Some(p) => self.nodes.get_mut(p).expect("live node").next = next,
            None => self.regions.get_mut(r).expect("live region").head = next,
        }
        if let Some(x) = next {
            self.nodes.get_mut(x).expect("live node").prev = prev;
        }
        self.regions.get_mut(r).expect("live region").members -= 1;
    }

    /// Pools the smaller region into the larger (ties keep the lower slot),
    /// relabelling only the smaller one's nodes.
    fn merge_regions(&mut self, ra: RegionId<K>, rb: RegionId<K>) {
        let ma = self.regions.get(ra).expect("live").members;
        let mb = self.regions.get(rb).expect("live").members;
        let (into, from) = if ma > mb || (ma == mb && ra.raw() < rb.raw()) {
            (ra, rb)
        } else {
            (rb, ra)
        };
        let gone = self.regions.remove(from).expect("live");
        let mut cur = gone.head;
        while let Some(n) = cur {
            cur = self.nodes.get(n).expect("member").next;
            self.link(into, n);
            self.touched_nodes.push(n);
            self.touch_devices_of(n);
        }
        self.stats.relabelled += u64::from(gone.members);
        self.stats.merges += 1;
        let region = self.regions.get_mut(into).expect("live");
        region.summary.add(&gone.summary);
        K::merge(&mut region.payload, gone.payload);
        self.events.push(RegionEvent::Merged { into, from });
    }

    fn touch_devices_of(&mut self, n: NodeId<K>) {
        let node = self.nodes.get(n).expect("live");
        self.touched_devices.extend_from_slice(&node.devices);
    }

    /// Lockstep multi-source search inside region `r` from `seeds` (the
    /// surviving endpoints of removed edges). Each seed grows its own
    /// breadth-first group, one node per group per round; groups that touch
    /// are unioned. A group whose queue empties is a closed component and
    /// is carved off; the search stops as soon as one group is left open,
    /// and that group keeps `r`, its ID and the remaining payload without
    /// ever being fully traversed. Cost is O(sum of the carved components
    /// plus as much of the remainder as the rounds took), i.e. about twice
    /// the smaller side of a single cut.
    fn split_region(&mut self, r: RegionId<K>, seeds: &[NodeId<K>]) {
        self.stats.split_regions += 1;
        let slots = self.nodes.slots();
        let sc = &mut self.scratch;
        if sc.stamp.len() < slots {
            sc.stamp.resize(slots, 0);
            sc.owner.resize(slots, 0);
        }
        sc.epoch = sc.epoch.wrapping_add(1);
        if sc.epoch == 0 {
            sc.stamp.fill(0);
            sc.epoch = 1;
        }
        let epoch = sc.epoch;
        sc.groups.clear();
        sc.active.clear();
        for &s in seeds {
            let Ok(node) = self.nodes.get(s) else {
                continue;
            };
            let i = s.index() as usize;
            if node.region != r || sc.stamp[i] == epoch {
                continue;
            }
            let g = u32::try_from(sc.groups.len()).expect("seed count fits u32");
            sc.stamp[i] = epoch;
            sc.owner[i] = g;
            sc.groups.push(Group {
                parent: g,
                members: vec![s],
                frontier: vec![s],
                head: 0,
                done: false,
            });
            sc.active.push(g);
        }
        let mut live = sc.active.len();
        let mut visited = live as u64;
        'rounds: while live > 1 {
            let mut k = 0;
            while k < sc.active.len() {
                let mut g = sc.active[k];
                if sc.groups[g as usize].parent != g || sc.groups[g as usize].done {
                    sc.active.swap_remove(k);
                    continue;
                }
                let grp = &mut sc.groups[g as usize];
                if grp.head == grp.frontier.len() {
                    grp.done = true;
                    live -= 1;
                    sc.active.swap_remove(k);
                    if live <= 1 {
                        break 'rounds;
                    }
                    continue;
                }
                let x = grp.frontier[grp.head];
                grp.head += 1;
                let node = self.nodes.get(x).expect("queued nodes are live");
                for &e in &node.edges {
                    let y = self.edges.get(e).expect("adjacent edge").other(x);
                    if self.nodes.get(y).expect("edge endpoint").region != r {
                        continue;
                    }
                    let yi = y.index() as usize;
                    if sc.stamp[yi] != epoch {
                        sc.stamp[yi] = epoch;
                        sc.owner[yi] = g;
                        let grp = &mut sc.groups[g as usize];
                        grp.members.push(y);
                        grp.frontier.push(y);
                        visited += 1;
                        continue;
                    }
                    let o = find(&mut sc.groups, sc.owner[yi]);
                    if o == g {
                        continue;
                    }
                    // Two open groups met: union them, small into large.
                    let (big, small) = if sc.groups[g as usize].members.len()
                        >= sc.groups[o as usize].members.len()
                    {
                        (g, o)
                    } else {
                        (o, g)
                    };
                    let sm = &mut sc.groups[small as usize];
                    sm.parent = big;
                    let members = std::mem::take(&mut sm.members);
                    let mut frontier = std::mem::take(&mut sm.frontier);
                    let pending = frontier.split_off(sm.head);
                    sm.head = 0;
                    let bg = &mut sc.groups[big as usize];
                    bg.members.extend_from_slice(&members);
                    bg.frontier.extend_from_slice(&pending);
                    live -= 1;
                    g = big;
                    if live <= 1 {
                        break 'rounds;
                    }
                }
                k += 1;
            }
        }
        self.stats.visited += visited;
        // Carve every closed group, in group order.
        let carved: Vec<Vec<NodeId<K>>> = sc
            .groups
            .iter_mut()
            .filter(|grp| grp.done)
            .map(|grp| std::mem::take(&mut grp.members))
            .collect();
        for members in carved {
            self.carve(r, &members);
        }
    }

    fn carve(&mut self, r: RegionId<K>, members: &[NodeId<K>]) {
        let mut part = K::Summary::default();
        for &n in members {
            part.add(&K::summarize(&self.nodes.get(n).expect("member").data));
            self.unlink(r, n);
        }
        let from = self.regions.get_mut(r).expect("live");
        let whole = from.summary.clone();
        let payload = K::split(&mut from.payload, &whole, &part);
        from.summary.sub(&part);
        let into = self
            .regions
            .insert(Region {
                head: None,
                members: 0,
                summary: part,
                payload,
            })
            .expect("a split never needs more regions than nodes");
        for &n in members {
            self.link(into, n);
            self.touched_nodes.push(n);
            self.touch_devices_of(n);
        }
        self.stats.splits += 1;
        self.stats.relabelled += members.len() as u64;
        self.events.push(RegionEvent::Split { from: r, into });
    }

    // ---- reference ---------------------------------------------------

    /// The partition by a full rebuild (union-find over every live edge),
    /// as sorted lists of node raw handles, sorted. For tests and debug
    /// validation; O(nodes + edges).
    #[must_use]
    pub fn rebuild_partition(&self) -> Vec<Vec<RawHandle>> {
        let slots = self.nodes.slots();
        let mut parent: Vec<usize> = (0..slots).collect();
        fn root(p: &mut [usize], mut x: usize) -> usize {
            while p[x] != x {
                p[x] = p[p[x]];
                x = p[x];
            }
            x
        }
        for (_, e) in self.edges.iter() {
            let (a, b) = (
                root(&mut parent, e.a.index() as usize),
                root(&mut parent, e.b.index() as usize),
            );
            if a != b {
                parent[a.max(b)] = a.min(b);
            }
        }
        let mut by_root: std::collections::BTreeMap<usize, Vec<RawHandle>> = Default::default();
        for (n, _) in self.nodes.iter() {
            let rt = root(&mut parent, n.index() as usize);
            by_root.entry(rt).or_default().push(n.raw());
        }
        canonical(by_root.into_values().collect())
    }

    /// The partition the incremental regions hold, in the same form as
    /// [`Network::rebuild_partition`]. Panics if a region's member list is
    /// inconsistent with the nodes' region labels.
    #[must_use]
    pub fn partition(&self) -> Vec<Vec<RawHandle>> {
        let mut parts = Vec::with_capacity(self.regions.len());
        for (r, region) in self.regions.iter() {
            let members = self.members(r).expect("live region");
            assert_eq!(members.len(), region.members as usize, "member count");
            for &n in &members {
                assert_eq!(self.nodes.get(n).expect("member").region, r, "label");
            }
            parts.push(members.into_iter().map(Handle::raw).collect());
        }
        canonical(parts)
    }
}

fn canonical(mut parts: Vec<Vec<RawHandle>>) -> Vec<Vec<RawHandle>> {
    for p in &mut parts {
        p.sort_unstable();
    }
    parts.sort_unstable();
    parts
}

fn find<K: NetworkKind>(groups: &mut [Group<K>], mut g: u32) -> u32 {
    let mut root = g;
    while groups[root as usize].parent != root {
        root = groups[root as usize].parent;
    }
    while groups[g as usize].parent != root {
        let next = groups[g as usize].parent;
        groups[g as usize].parent = root;
        g = next;
    }
    root
}
