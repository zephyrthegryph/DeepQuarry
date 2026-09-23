//! R7: the network framework (`simulation.md` §3), generalizing vg-gas's
//! `PipeTopology`.
//!
//! A [`Network<K>`] holds **nodes** (pipe segments, cable pieces: a cell
//! position, a kind, an external key and the kind's per-node data) and
//! **edges** in [`Arena`](crate::Arena)s, and maintains **regions**, the
//! connected components, incrementally:
//!
//! - adding an edge **merges** its endpoints' regions: the smaller region's
//!   nodes are relabelled into the larger (O(smaller));
//! - removing an edge or node **splits** only the affected region, by a
//!   lockstep multi-source search from the removed edges' surviving
//!   endpoints (see [`Network::commit`] and below);
//! - region IDs are stable: a merge keeps the larger region's ID, a split
//!   keeps the parent ID for the part the search never had to finish.
//!
//! Each region carries a **payload** ([`NetworkKind::Payload`]: gas, a
//! charge) and an additive **summary** of its nodes' data
//! ([`NetworkKind::Summary`]: volume; supply, demand and capacity). Merges
//! and splits go through the kind's `merge` and `split` hooks, which must
//! conserve; a removed node's share is carved out and reported as
//! [`RegionEvent::Released`], so the total is conserved across any edit.
//!
//! **Batches.** Edits change the graph at once but region maintenance
//! waits for [`Network::commit`], so an explosion's thousand removals are
//! one pass: all splits (grouped per region) and then all merges. A batch
//! is exactly equivalent to committing its removals and then its additions
//! one by one (tested), and always yields the same partition as any other
//! order of the same edits.
//!
//! **Split algorithm.** For each region with removals, every surviving
//! endpoint seeds a breadth-first group; groups expand one node per round
//! each and are unioned when they touch. A group whose frontier empties is
//! a closed component and becomes a new region; the search stops once a
//! single group is still open, and that group keeps the region. A cut in a
//! tree therefore costs about twice its smaller side, and a cut that does
//! not disconnect costs until the two searches meet. Pipe and cable
//! networks are nearly trees, so this beats a dynamic-connectivity
//! structure (Holm et al., O(log^2 n) amortized with large constants and
//! O(m log n) memory) in practice; see the `network` benches.
//!
//! **Devices.** A [`Device`] is an edge between two [`Endpoint`]s, each a
//! node (acting on that node's region) or a field cell. The framework keeps
//! endpoints valid (a removed node detaches them) and resolves them to
//! [`Side`]s; flow laws are M2's.
//!
//! **Frame integration** is in [`host`]: [`host::add_network`] registers the
//! network as a frame resource with a task that applies DM's batches and
//! commands and publishes a copy-on-write [`host::NetworkView`] and an
//! outbox of region events.

mod graph;
pub mod host;

pub use graph::{
    Additive, CommitStats, Device, DeviceId, Edge, EdgeId, Endpoint, NO_KEY, NetError, Network,
    NetworkKind, Node, NodeId, Region, RegionEvent, RegionId, Side,
};

#[cfg(test)]
mod tests;
