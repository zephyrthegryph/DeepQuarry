//! Rust-authoritative pipe topology.
//!
//! DM publishes stable ports and physical connection edges. The graph owns
//! component identity and returns deterministic region transitions after a
//! topology transaction. Gas rebinding is deliberately applied only after the
//! complete transaction, so removing hundreds of pipes in one explosion cannot
//! repeatedly tear down and reconstruct the same network.

use parking_lot::Mutex;
use rustc_hash::{FxHashMap, FxHashSet};
use std::collections::VecDeque;
use std::sync::LazyLock;

pub type PipePortId = u32;
pub type PipeRegionId = u32;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PipePort {
	pub mixture: usize,
	pub volume: f32,
	pub region: PipeRegionId,
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct PipeEdgeKey {
	pub first: PipePortId,
	pub second: PipePortId,
}

impl PipeEdgeKey {
	pub fn new(first: PipePortId, second: PipePortId) -> Option<Self> {
		(first != second).then(|| {
			if first < second {
				Self { first, second }
			} else {
				Self {
					first: second,
					second: first,
				}
			}
		})
	}
}

/// A physical connection owns its revision and wake state. Region processing
/// can therefore retain an unsettled edge directly instead of repeatedly
/// rediscovering it by scanning every member cell.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PipeEdge {
	pub revision: u64,
	pub active: bool,
	pub pressure_residual_kpa: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PipeRegionTransition {
	pub region: PipeRegionId,
	pub ports: Vec<PipePortId>,
	/// Volume contributed by each pre-transaction region. This is the exact
	/// ledger needed to split/merge its gas inventory conservatively.
	pub prior_regions: Vec<(PipeRegionId, f32)>,
	/// Conservative gas recipe for the replacement region. Each source is read
	/// from the pre-commit arena snapshot and multiplied by `ratio` exactly once.
	pub sources: Vec<PipeGasSource>,
	pub total_volume: f32,
	/// A tombstone retires a region that lost its final port. It deliberately
	/// carries no gas recipe; the owner of the final port must detach its gas
	/// before removing that port.
	pub retired: bool,
	pub detached_target: usize,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PipeGasSource {
	pub mixture: usize,
	pub ratio: f32,
}

#[derive(Clone, Debug, Default, PartialEq)]
struct PipeRegion {
	ports: FxHashSet<PipePortId>,
	total_volume: f32,
	mixture: usize,
}

#[derive(Clone, Debug)]
struct PendingPipeDetachment {
	target_volume: f32,
	sources: FxHashMap<usize, f32>,
}

#[derive(Default)]
pub struct PipeTopology {
	ports: FxHashMap<PipePortId, PipePort>,
	edges: FxHashMap<PipeEdgeKey, PipeEdge>,
	adjacency: FxHashMap<PipePortId, FxHashSet<PipePortId>>,
	regions: FxHashMap<PipeRegionId, PipeRegion>,
	dirty_ports: FxHashSet<PipePortId>,
	dirty_regions: FxHashSet<PipeRegionId>,
	pending_detachments: FxHashMap<usize, PendingPipeDetachment>,
	next_region: PipeRegionId,
	topology_revision: u64,
}

impl PipeTopology {
	pub fn upsert_port(&mut self, id: PipePortId, mixture: usize, volume: f32) {
		let previous_region = self.ports.get(&id).map_or(0, |port| port.region);
		self.dirty_ports.insert(id);
		if previous_region != 0 {
			self.dirty_regions.insert(previous_region);
		}
		self.ports.insert(
			id,
			PipePort {
				mixture,
				volume: volume.max(0.0),
				region: previous_region,
			},
		);
		self.adjacency.entry(id).or_default();
		self.topology_revision = self.topology_revision.wrapping_add(1);
	}

	pub fn remove_port(&mut self, id: PipePortId) {
		let Some(removed) = self.ports.remove(&id) else {
			return;
		};
		if removed.region != 0 {
			self.dirty_regions.insert(removed.region);
		}
		if let Some(neighbors) = self.adjacency.remove(&id) {
			for neighbor in neighbors {
				self.dirty_ports.insert(neighbor);
				self.adjacency.entry(neighbor).or_default().remove(&id);
				if let Some(key) = PipeEdgeKey::new(id, neighbor) {
					self.edges.remove(&key);
				}
			}
		}
		self.topology_revision = self.topology_revision.wrapping_add(1);
	}

	pub fn remove_port_to(&mut self, id: PipePortId, target_mixture: usize, target_volume: f32) {
		let Some(port) = self.ports.get(&id).copied() else {
			return;
		};
		let (source, ratio) = if port.region != 0 {
			self.regions
				.get(&port.region)
				.filter(|region| region.mixture != 0 && region.total_volume > 0.0)
				.map(|region| (region.mixture, port.volume / region.total_volume))
				.unwrap_or((0, 0.0))
		} else {
			(port.mixture, 1.0)
		};
		let receipt = self
			.pending_detachments
			.entry(target_mixture)
			.or_insert_with(|| {
				let mut sources = FxHashMap::default();
				sources.insert(target_mixture, 1.0);
				PendingPipeDetachment {
					target_volume: target_volume.max(1.0),
					sources,
				}
			});
		if source != 0 && ratio > 0.0 {
			*receipt.sources.entry(source).or_insert(0.0) += ratio;
		}
		self.remove_port(id);
	}

	pub fn connect(&mut self, first: PipePortId, second: PipePortId) -> bool {
		let Some(key) = PipeEdgeKey::new(first, second) else {
			return false;
		};
		if !self.ports.contains_key(&first) || !self.ports.contains_key(&second) {
			return false;
		}
		if self.edges.contains_key(&key) {
			return true;
		}
		self.dirty_ports.extend([first, second]);
		for id in [first, second] {
			let region = self.ports.get(&id).map_or(0, |port| port.region);
			if region != 0 {
				self.dirty_regions.insert(region);
			}
		}
		self.edges.insert(
			key,
			PipeEdge {
				revision: self.topology_revision.wrapping_add(1),
				active: true,
				pressure_residual_kpa: f32::INFINITY,
			},
		);
		self.adjacency.entry(first).or_default().insert(second);
		self.adjacency.entry(second).or_default().insert(first);
		self.topology_revision = self.topology_revision.wrapping_add(1);
		true
	}

	pub fn disconnect(&mut self, first: PipePortId, second: PipePortId) {
		let Some(key) = PipeEdgeKey::new(first, second) else {
			return;
		};
		if self.edges.remove(&key).is_none() {
			return;
		}
		self.dirty_ports.extend([first, second]);
		for id in [first, second] {
			let region = self.ports.get(&id).map_or(0, |port| port.region);
			if region != 0 {
				self.dirty_regions.insert(region);
			}
		}
		self.adjacency.entry(first).or_default().remove(&second);
		self.adjacency.entry(second).or_default().remove(&first);
		self.topology_revision = self.topology_revision.wrapping_add(1);
	}

	pub fn mark_edge_residual(
		&mut self,
		first: PipePortId,
		second: PipePortId,
		pressure_residual_kpa: f32,
		settle_threshold_kpa: f32,
	) {
		let Some(key) = PipeEdgeKey::new(first, second) else {
			return;
		};
		let Some(edge) = self.edges.get_mut(&key) else {
			return;
		};
		edge.pressure_residual_kpa = pressure_residual_kpa.abs();
		edge.active = edge.pressure_residual_kpa > settle_threshold_kpa;
		edge.revision = edge.revision.wrapping_add(1);
	}

	pub fn active_edges(&self) -> impl Iterator<Item = (PipeEdgeKey, PipeEdge)> + '_ {
		self.edges
			.iter()
			.filter(|(_, edge)| edge.active)
			.map(|(&key, &edge)| (key, edge))
	}

	/// Record the arena mixture chosen by DM as this region's public handle.
	/// This is a binding operation, not a topology mutation.
	pub fn bind_region_mixture(&mut self, region: PipeRegionId, mixture: usize) -> bool {
		let Some(existing) = self.regions.get_mut(&region) else {
			return false;
		};
		existing.mixture = mixture;
		for port in &existing.ports {
			if let Some(entry) = self.ports.get_mut(port) {
				entry.mixture = mixture;
			}
		}
		true
	}

	pub fn clear(&mut self) {
		*self = Self::default();
	}

	/// Atomically materialize only connected regions touched by a batch of edits.
	/// Existing region IDs survive merges and exactly one side of a split; all
	/// other split children receive fresh IDs. The result is deterministic even
	/// when DM published the same edits in a different order.
	pub fn commit(&mut self) -> Vec<PipeRegionTransition> {
		if self.dirty_ports.is_empty() && self.dirty_regions.is_empty() {
			return Vec::new();
		}

		let mut affected_ports = std::mem::take(&mut self.dirty_ports);
		let affected_regions = std::mem::take(&mut self.dirty_regions);
		for region in &affected_regions {
			if let Some(existing) = self.regions.get(region) {
				affected_ports.extend(existing.ports.iter().copied());
			}
		}
		let mut roots = affected_ports
			.into_iter()
			.filter(|id| self.ports.contains_key(id))
			.collect::<Vec<_>>();
		roots.sort_unstable();
		let mut visited = FxHashSet::default();
		let mut components = Vec::new();
		for root in roots {
			if !visited.insert(root) {
				continue;
			}
			let mut queue = VecDeque::from([root]);
			let mut ports = Vec::new();
			while let Some(port) = queue.pop_front() {
				ports.push(port);
				let mut neighbors = self
					.adjacency
					.get(&port)
					.into_iter()
					.flatten()
					.copied()
					.collect::<Vec<_>>();
				neighbors.sort_unstable();
				for neighbor in neighbors {
					if self.ports.contains_key(&neighbor) && visited.insert(neighbor) {
						queue.push_back(neighbor);
					}
				}
			}
			ports.sort_unstable();
			components.push(ports);
		}

		let mut used_regions = self
			.regions
			.keys()
			.filter(|region| !affected_regions.contains(region))
			.copied()
			.collect::<FxHashSet<_>>();
		let mut transitions = Vec::with_capacity(components.len());
		for ports in components {
			let mut prior_volume_by_region = FxHashMap::default();
			let mut unbound_sources = FxHashMap::default();
			for port in &ports {
				let entry = self.ports.get(port).expect("component port vanished");
				if entry.region != 0 {
					*prior_volume_by_region.entry(entry.region).or_insert(0.0) += entry.volume;
				} else {
					unbound_sources.insert(entry.mixture, 1.0);
				}
			}
			let mut prior_regions = prior_volume_by_region.into_iter().collect::<Vec<_>>();
			prior_regions.sort_unstable_by_key(|entry| entry.0);
			let region = prior_regions
				.iter()
				.map(|entry| entry.0)
				.find(|region| used_regions.insert(*region))
				.unwrap_or_else(|| {
					self.next_region = self.next_region.wrapping_add(1).max(1);
					used_regions.insert(self.next_region);
					self.next_region
				});
			let mut sources = Vec::new();
			for &(prior_region, contributed_volume) in &prior_regions {
				if let Some(previous) = self.regions.get(&prior_region) {
					if previous.mixture != 0 && previous.total_volume > 0.0 {
						sources.push(PipeGasSource {
							mixture: previous.mixture,
							ratio: (contributed_volume / previous.total_volume).clamp(0.0, 1.0),
						});
					}
				}
			}
			for (mixture, count) in unbound_sources {
				sources.push(PipeGasSource {
					mixture,
					ratio: count,
				});
			}
			sources.sort_unstable_by_key(|source| source.mixture);
			let mut total_volume = 0.0;
			for port in &ports {
				let entry = self.ports.get_mut(port).expect("component port vanished");
				entry.region = region;
				total_volume += entry.volume;
			}
			transitions.push(PipeRegionTransition {
				region,
				ports,
				prior_regions,
				sources,
				total_volume,
				retired: false,
				detached_target: 0,
			});
		}
		let represented_prior_regions = transitions
			.iter()
			.flat_map(|transition| transition.prior_regions.iter().map(|entry| entry.0))
			.collect::<FxHashSet<_>>();
		for region in affected_regions.iter().copied() {
			if represented_prior_regions.contains(&region) {
				continue;
			}
			transitions.push(PipeRegionTransition {
				region,
				ports: Vec::new(),
				prior_regions: vec![(region, 0.0)],
				sources: Vec::new(),
				total_volume: 0.0,
				retired: true,
				detached_target: 0,
			});
		}
		for (target, receipt) in std::mem::take(&mut self.pending_detachments) {
			let mut sources = receipt
				.sources
				.into_iter()
				.map(|(mixture, ratio)| PipeGasSource { mixture, ratio })
				.collect::<Vec<_>>();
			sources.sort_unstable_by_key(|source| source.mixture);
			transitions.push(PipeRegionTransition {
				region: 0,
				ports: Vec::new(),
				prior_regions: Vec::new(),
				sources,
				total_volume: receipt.target_volume,
				retired: false,
				detached_target: target,
			});
		}
		for region in affected_regions {
			self.regions.remove(&region);
		}
		for transition in &transitions {
			self.regions.insert(
				transition.region,
				PipeRegion {
					ports: transition.ports.iter().copied().collect(),
					total_volume: transition.total_volume,
					mixture: 0,
				},
			);
		}
		transitions
	}
}

pub static PIPE_TOPOLOGY: LazyLock<Mutex<PipeTopology>> =
	LazyLock::new(|| Mutex::new(PipeTopology::default()));

#[cfg(test)]
mod tests {
	use super::*;

	fn port(topology: &mut PipeTopology, id: PipePortId) {
		topology.upsert_port(id, id as usize, 200.0);
	}

	#[test]
	fn batched_mass_removal_rebuilds_each_survivor_once() {
		let mut topology = PipeTopology::default();
		for id in 1..=1_000 {
			port(&mut topology, id);
			if id > 1 {
				assert!(topology.connect(id - 1, id));
			}
		}
		assert_eq!(topology.commit().len(), 1);
		for id in 201..=800 {
			topology.remove_port(id);
		}
		let regions = topology.commit();
		assert_eq!(regions.len(), 2);
		assert_eq!(regions[0].ports, (1..=200).collect::<Vec<_>>());
		assert_eq!(regions[1].ports, (801..=1_000).collect::<Vec<_>>());
	}

	#[test]
	fn merge_and_split_have_deterministic_stable_region_identity() {
		let mut topology = PipeTopology::default();
		for id in 1..=4 {
			port(&mut topology, id);
		}
		topology.connect(1, 2);
		topology.connect(3, 4);
		let initial = topology.commit();
		let first_region = initial[0].region;
		let second_region = initial[1].region;
		assert_ne!(first_region, second_region);

		topology.connect(2, 3);
		let merged = topology.commit();
		assert_eq!(merged.len(), 1);
		assert_eq!(merged[0].region, first_region.min(second_region));
		assert_eq!(merged[0].prior_regions.len(), 2);

		topology.disconnect(2, 3);
		let split = topology.commit();
		assert_eq!(split.len(), 2);
		assert_eq!(split[0].region, merged[0].region);
		assert_ne!(split[1].region, merged[0].region);
	}

	#[test]
	fn edge_liveness_is_owned_by_the_edge() {
		let mut topology = PipeTopology::default();
		port(&mut topology, 1);
		port(&mut topology, 2);
		topology.connect(1, 2);
		topology.mark_edge_residual(1, 2, 20.0, 0.1);
		assert_eq!(topology.active_edges().count(), 1);
		topology.mark_edge_residual(1, 2, 0.05, 0.1);
		assert_eq!(topology.active_edges().count(), 0);
	}

	#[test]
	fn split_recipes_partition_the_precommit_region_exactly_once() {
		let mut topology = PipeTopology::default();
		port(&mut topology, 1);
		port(&mut topology, 2);
		topology.connect(1, 2);
		let initial = topology.commit();
		assert_eq!(initial.len(), 1);
		assert_eq!(initial[0].sources.len(), 2);
		let region = initial[0].region;
		assert!(topology.bind_region_mixture(region, 99));

		topology.disconnect(1, 2);
		let split = topology.commit();
		assert_eq!(split.len(), 2);
		for child in split {
			assert_eq!(child.sources.len(), 1);
			assert_eq!(child.sources[0].mixture, 99);
			assert!((child.sources[0].ratio - 0.5).abs() < f32::EPSILON);
		}
	}

	#[test]
	fn commit_does_not_revisit_untouched_regions() {
		let mut topology = PipeTopology::default();
		for id in 1..=4 {
			port(&mut topology, id);
		}
		topology.connect(1, 2);
		topology.connect(3, 4);
		let initial = topology.commit();
		assert_eq!(initial.len(), 2);
		for transition in initial {
			assert!(
				topology.bind_region_mixture(transition.region, transition.region as usize + 100)
			);
		}
		assert!(topology.commit().is_empty());

		topology.disconnect(1, 2);
		let changed = topology.commit();
		assert_eq!(changed.len(), 2);
		assert!(changed.iter().all(|transition| transition.ports[0] <= 2));
	}

	#[test]
	fn removing_the_final_port_emits_a_region_tombstone() {
		let mut topology = PipeTopology::default();
		port(&mut topology, 1);
		let initial = topology.commit();
		let region = initial[0].region;
		topology.bind_region_mixture(region, 99);
		topology.remove_port(1);
		let transitions = topology.commit();
		assert_eq!(transitions.len(), 1);
		assert_eq!(transitions[0].region, region);
		assert!(transitions[0].retired);
		assert!(transitions[0].ports.is_empty());
	}

	#[test]
	fn removed_ports_to_one_target_coalesce_into_one_receipt() {
		let mut topology = PipeTopology::default();
		port(&mut topology, 1);
		port(&mut topology, 2);
		topology.connect(1, 2);
		let initial = topology.commit();
		let region = initial[0].region;
		topology.bind_region_mixture(region, 99);
		topology.remove_port_to(1, 500, 2_500.0);
		topology.remove_port_to(2, 500, 2_500.0);
		let transitions = topology.commit();
		let receipt = transitions
			.iter()
			.find(|transition| transition.detached_target == 500)
			.unwrap();
		assert_eq!(receipt.sources.len(), 2);
		assert_eq!(
			receipt.sources[0],
			PipeGasSource {
				mixture: 99,
				ratio: 1.0
			}
		);
		assert_eq!(
			receipt.sources[1],
			PipeGasSource {
				mixture: 500,
				ratio: 1.0
			}
		);
	}
}
