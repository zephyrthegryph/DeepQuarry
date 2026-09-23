//! Pipes on the R7 network framework (`simulation.md` §3): replaces vg-gas's
//! `PipeTopology`.
//!
//! A pipe port (a pipe segment, or one side of a device) is a node whose
//! data is its volume; a region (a connected pipe network) pools its gas as
//! the payload, moles and energy in `f64`, split by volume. Adding an edge
//! merges two regions' gas; removing one splits it in proportion to the
//! parts' volumes; a removed port's share is released (`Released`, which
//! replaces `remove_port_to`).
//!
//! **Ownership.** Until M2 turns devices into edges with flow laws, the only
//! writers of pipe gas are DM devices, so pipe regions are main-owned
//! entities (`rust_core.md` §3.1): [`PipeNet`] drives the `Network` on the
//! main thread, commits DM's topology batch at once and returns the region
//! events, and DM reads and writes region gas synchronously. M2 moves the
//! network into the frame with `network::host::add_network` unchanged.

use std::collections::HashMap;

use vg_core::slot::RawHandle;
use vg_core::network::{DeviceId, Endpoint, Network, NetworkKind, NodeId, RegionEvent, RegionId, Side};

use crate::device::{self, DeviceParams, StepReport};

use crate::cell::{heat_capacity, N, Q};

/// A region's gas: moles of each gas and the thermal energy (J).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PipeGas {
	pub moles: [f64; N],
	pub energy: f64,
	/// The temperature to report when the region holds no gas.
	pub temperature: f32,
}

impl Default for PipeGas {
	fn default() -> Self {
		Self {
			moles: [0.0; N],
			energy: 0.0,
			temperature: crate::gas::constants::TCMB,
		}
	}
}

impl PipeGas {
	#[must_use]
	pub fn from_amounts(amounts: &[f32; Q], temperature: f32) -> Self {
		let mut g = Self {
			temperature,
			..Self::default()
		};
		for (m, &a) in g.moles.iter_mut().zip(amounts) {
			*m = f64::from(a);
		}
		g.energy = f64::from(amounts[N]);
		g
	}

	#[must_use]
	pub fn amounts(&self) -> [f32; Q] {
		let mut out = [0.0; Q];
		for (o, &m) in out.iter_mut().zip(&self.moles) {
			*o = m as f32;
		}
		out[N] = self.energy as f32;
		out
	}

	#[must_use]
	pub fn moles_f32(&self) -> [f32; N] {
		let mut out = [0.0; N];
		for (o, &m) in out.iter_mut().zip(&self.moles) {
			*o = m as f32;
		}
		out
	}

	#[must_use]
	pub fn total(&self) -> f64 {
		self.moles.iter().sum()
	}

	pub fn add(&mut self, other: &Self) {
		for (a, b) in self.moles.iter_mut().zip(&other.moles) {
			*a += b;
		}
		self.energy += other.energy;
	}

	/// The fraction `f` of this gas, removed.
	pub fn carve(&mut self, f: f64) -> Self {
		let mut out = Self {
			temperature: self.temperature,
			..Self::default()
		};
		let f = f.clamp(0.0, 1.0);
		if f >= 1.0 {
			std::mem::swap(&mut out.moles, &mut self.moles);
			std::mem::swap(&mut out.energy, &mut self.energy);
			return out;
		}
		for (o, m) in out.moles.iter_mut().zip(self.moles.iter_mut()) {
			*o = *m * f;
			*m -= *o;
		}
		out.energy = self.energy * f;
		self.energy -= out.energy;
		out
	}

	/// The temperature (the stored one when empty).
	#[must_use]
	pub fn temperature_now(&self) -> f32 {
		let c = heat_capacity(&self.moles_f32());
		if c > crate::gas::constants::MINIMUM_HEAT_CAPACITY {
			((self.energy / f64::from(c)) as f32).max(crate::gas::constants::TCMB)
		} else {
			self.temperature
		}
	}
}

/// The pipe network kind.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Pipes;

impl NetworkKind for Pipes {
	const NAME: &'static str = "pipes";
	/// A port's volume (L).
	type Node = f32;
	/// The region's volume.
	type Summary = f64;
	type Payload = PipeGas;
	/// A device edge's flow law and parameters (M2, `device.rs`).
	type Device = DeviceParams;
	type Command = ();

	fn summarize(node: &f32) -> f64 {
		f64::from(node.max(0.0))
	}

	fn split(payload: &mut PipeGas, whole: &f64, part: &f64) -> PipeGas {
		let f = if *whole <= 0.0 || part >= whole {
			1.0
		} else {
			(part / whole).max(0.0)
		};
		payload.carve(f)
	}

	fn merge(into: &mut PipeGas, other: PipeGas) {
		if into.total() <= 0.0 {
			into.temperature = other.temperature;
		}
		into.add(&other);
	}
}

/// DM topology opcodes (`RUST_PIPE_OP_*`).
pub mod op {
	pub const UPSERT: u8 = 1;
	pub const REMOVE: u8 = 2;
	pub const CONNECT: u8 = 3;
	pub const DISCONNECT: u8 = 4;
	pub const CLEAR: u8 = 5;
	pub const REMOVE_TO_MIXTURE: u8 = 7;
}

/// A region as DM sees it after a commit.
#[derive(Clone, Debug, PartialEq)]
pub struct Transition {
	/// The region's DM slot.
	pub slot: u32,
	/// Member port ids (empty and `retired` for a region that is gone).
	pub ports: Vec<u32>,
	/// DM slots of regions merged into or split from this one.
	pub prior: Vec<u32>,
	pub volume: f32,
	pub retired: bool,
}

/// Gas released by a removed port, with where DM asked it to go.
#[derive(Clone, Debug, PartialEq)]
pub struct Release {
	pub port: u32,
	/// The mixture handle DM named (`REMOVE_TO_MIXTURE`), if any.
	pub target: Option<u32>,
	pub gas: PipeGas,
}

/// One device edge's flow-law result for a tick, for DM's stalled /
/// target-reached / filter-saturated events and power billing.
#[derive(Clone, Debug, PartialEq)]
pub struct DeviceStep {
	/// The device's DM id.
	pub key: u32,
	pub report: StepReport,
}

/// The main-owned pipe network: ports by DM id, and stable small slots for
/// regions (a region's DM gas handle is `PIPE_BASE + slot`).
#[derive(Default)]
pub struct PipeNet {
	pub net: Network<Pipes>,
	ports: HashMap<u32, NodeId<Pipes>>,
	targets: HashMap<u32, u32>,
	/// Device edges (M2) by DM id.
	devices: HashMap<u32, DeviceId<Pipes>>,
	slots: Vec<Option<RawHandle>>,
	slot_of: HashMap<RawHandle, u32>,
	free: Vec<u32>,
	/// Per slot: bumped on every change (DM's `revision()`).
	revisions: Vec<u32>,
	/// Gas lost because DM removed a port with nowhere to put it (mol).
	pub discarded: f64,
}

impl PipeNet {
	#[must_use]
	pub fn new() -> Self {
		Self::default()
	}

	/// The node for a DM port id.
	#[must_use]
	pub fn port(&self, port: u32) -> Option<NodeId<Pipes>> {
		self.ports.get(&port).copied()
	}

	/// The live region behind a DM slot.
	#[must_use]
	pub fn region_of_slot(&self, slot: u32) -> Option<RegionId<Pipes>> {
		let raw = (*self.slots.get(slot as usize)?)?;
		let r = RegionId::<Pipes>::from_raw(raw);
		self.net.region(r).is_ok().then_some(r)
	}

	/// The DM slot of a region, allocating one.
	pub fn slot_of(&mut self, r: RegionId<Pipes>) -> u32 {
		if let Some(&s) = self.slot_of.get(&r.raw()) {
			return s;
		}
		let s = self.free.pop().unwrap_or_else(|| {
			self.slots.push(None);
			self.revisions.push(0);
			u32::try_from(self.slots.len() - 1).unwrap_or(u32::MAX)
		});
		self.slots[s as usize] = Some(r.raw());
		self.slot_of.insert(r.raw(), s);
		self.revisions[s as usize] = self.revisions[s as usize].wrapping_add(1);
		s
	}

	fn retire_slot(&mut self, raw: RawHandle) -> Option<u32> {
		let s = self.slot_of.remove(&raw)?;
		self.slots[s as usize] = None;
		self.revisions[s as usize] = self.revisions[s as usize].wrapping_add(1);
		self.free.push(s);
		Some(s)
	}

	#[must_use]
	pub fn revision(&self, slot: u32) -> u32 {
		self.revisions.get(slot as usize).copied().unwrap_or(0)
	}

	/// Bumps the DM slot revision for a region, if it has one (M2's
	/// turf-device bridge mutates region payloads from outside `PipeNet`,
	/// via [`Network::payload_mut`], so it cannot reach the private
	/// `slot_of`/`bump` bookkeeping directly).
	pub fn touch_region(&mut self, r: RegionId<Pipes>) {
		if let Some(&s) = self.slot_of.get(&r.raw()) {
			self.bump(s);
		}
	}

	pub fn bump(&mut self, slot: u32) {
		if let Some(r) = self.revisions.get_mut(slot as usize) {
			*r = r.wrapping_add(1);
		}
	}

	/// Region gas and volume by slot.
	#[must_use]
	pub fn gas(&self, slot: u32) -> Option<(&PipeGas, f64)> {
		let r = self.region_of_slot(slot)?;
		let region = self.net.region(r).ok()?;
		Some((region.payload(), *region.summary()))
	}

	/// Mutable region gas by slot.
	pub fn gas_mut(&mut self, slot: u32) -> Option<(&mut PipeGas, f64)> {
		let r = self.region_of_slot(slot)?;
		let volume = *self.net.region(r).ok()?.summary();
		self.bump(slot);
		Some((self.net.payload_mut(r).ok()?, volume))
	}

	/// Live ports.
	#[must_use]
	pub fn port_count(&self) -> usize {
		self.ports.len()
	}

	/// Total gas in every region (for conservation checks).
	#[must_use]
	pub fn totals(&self) -> [f64; Q] {
		let mut out = [0.0; Q];
		for (_, region) in self.net.regions() {
			for (o, m) in out.iter_mut().zip(&region.payload().moles) {
				*o += m;
			}
			out[N] += region.payload().energy;
		}
		out
	}

	/// Adds a port holding `gas`, or changes its volume if it exists.
	pub fn upsert(&mut self, port: u32, pos: u32, volume: f32, gas: PipeGas) -> bool {
		if let Some(n) = self.port(port) {
			return self.net.set_node_data(n, volume).is_ok();
		}
		match self.net.add_node(pos, 0, port, volume, gas) {
			Ok(n) => {
				self.ports.insert(port, n);
				true
			}
			Err(_) => false,
		}
	}

	/// Removes a port; its gas share is released to `target` (a DM mixture
	/// handle) if given.
	pub fn remove(&mut self, port: u32, target: Option<u32>) -> bool {
		let Some(n) = self.ports.remove(&port) else {
			return false;
		};
		if let Some(t) = target {
			self.targets.insert(port, t);
		}
		self.net.remove_node(n).is_ok()
	}

	pub fn connect(&mut self, a: u32, b: u32) -> bool {
		match (self.port(a), self.port(b)) {
			(Some(a), Some(b)) => self.net.connect(a, b).is_ok(),
			_ => false,
		}
	}

	pub fn disconnect(&mut self, a: u32, b: u32) {
		if let (Some(a), Some(b)) = (self.port(a), self.port(b)) {
			let _ = self.net.disconnect(a, b);
		}
	}

	// ---- devices (M2: flow-law edges) --------------------------------

	/// Adds (or replaces) a device edge between two ports, with its flow
	/// law and parameters. Both ports must already be live.
	pub fn add_device(&mut self, id: u32, port_a: u32, port_b: u32, params: DeviceParams) -> bool {
		let (Some(a), Some(b)) = (self.port(port_a), self.port(port_b)) else {
			return false;
		};
		if let Some(&d) = self.devices.get(&id) {
			let _ = self.net.remove_device(d);
		}
		match self
			.net
			.add_device(Endpoint::Node(a), Endpoint::Node(b), 0, id, params)
		{
			Ok(d) => {
				self.devices.insert(id, d);
				true
			}
			Err(_) => false,
		}
	}

	/// Adds (or replaces) a device edge between a pipe port and a field cell
	/// (a turf) - a vent pump or scrubber (M2, `simulation.md` §5, stepped
	/// by `GasWorld::step_turf_devices`, not this network's own
	/// `step_devices`). `cell` is the Rust field-cell index, from the
	/// turf's gas-mixture handle (`world::MixRef::Turf`).
	pub fn add_turf_device(&mut self, id: u32, port: u32, cell: u32, params: DeviceParams) -> bool {
		let Some(node) = self.port(port) else {
			return false;
		};
		if let Some(&d) = self.devices.get(&id) {
			let _ = self.net.remove_device(d);
		}
		match self
			.net
			.add_device(Endpoint::Cell(cell), Endpoint::Node(node), 0, id, params)
		{
			Ok(d) => {
				self.devices.insert(id, d);
				true
			}
			Err(_) => false,
		}
	}

	/// Removes a device edge.
	pub fn remove_device(&mut self, id: u32) -> bool {
		let Some(d) = self.devices.remove(&id) else {
			return false;
		};
		self.net.remove_device(d).is_ok()
	}

	/// Replaces a device's parameters (a setting change).
	pub fn set_device(&mut self, id: u32, params: DeviceParams) -> bool {
		let Some(&d) = self.devices.get(&id) else {
			return false;
		};
		self.net.set_device_data(d, params).is_ok()
	}

	/// Runs every device edge's flow law once (`device.rs`), moving gas
	/// between the regions on each side and bumping their DM slot
	/// revisions. Edges with a field-cell (turf) endpoint are skipped until
	/// the pipe/turf field bridge lands; that leaves vent pumps and
	/// scrubbers, whose non-network side is a turf, for a follow-up.
	pub fn step_devices(&mut self, dt: f32) -> Vec<DeviceStep> {
		let ids: Vec<DeviceId<Pipes>> = self.net.devices().map(|(id, _)| id).collect();
		let mut out = Vec::with_capacity(ids.len());
		for id in ids {
			let Ok(dev) = self.net.device(id) else {
				continue;
			};
			if matches!(dev.data, DeviceParams::None) {
				continue;
			}
			let (Endpoint::Node(na), Endpoint::Node(nb)) = (dev.a, dev.b) else {
				continue;
			};
			let key = dev.key;
			let params = dev.data.clone();
			let (Side::Region(ra), Side::Region(rb)) =
				(self.net.resolve(Endpoint::Node(na)), self.net.resolve(Endpoint::Node(nb)))
			else {
				continue;
			};
			if ra == rb {
				continue;
			}
			let Ok(region_a) = self.net.region(ra) else { continue };
			let Ok(region_b) = self.net.region(rb) else { continue };
			let vol_a = *region_a.summary();
			let vol_b = *region_b.summary();
			let mut pa = region_a.payload().clone();
			let mut pb = region_b.payload().clone();
			let report = device::step(&params, &mut pa, vol_a, &mut pb, vol_b, dt);
			if report.moles != 0.0 || report.power_w != 0.0 {
				*self.net.payload_mut(ra).expect("resolved above") = pa;
				*self.net.payload_mut(rb).expect("resolved above") = pb;
				if let Some(&sa) = self.slot_of.get(&ra.raw()) {
					self.bump(sa);
				}
				if let Some(&sb) = self.slot_of.get(&rb.raw()) {
					self.bump(sb);
				}
			}
			out.push(DeviceStep { key, report });
		}
		out
	}

	/// Drops everything (a map reload); returns the gas that was pooled.
	pub fn clear(&mut self) -> Vec<Release> {
		let ports: Vec<u32> = self.ports.keys().copied().collect();
		for p in ports {
			self.remove(p, None);
		}
		let (_, releases) = self.commit();
		releases
	}

	/// Commits the batch: resolves splits and merges, and returns the
	/// regions DM must rebuild (every region whose membership changed, and
	/// every region that is gone) and the released gas.
	pub fn commit(&mut self) -> (Vec<Transition>, Vec<Release>) {
		let events = self.net.commit();
		let mut touched: Vec<RawHandle> = Vec::new();
		let mut prior: HashMap<RawHandle, Vec<RawHandle>> = HashMap::new();
		let mut retired: Vec<RawHandle> = Vec::new();
		let mut releases = Vec::new();
		for ev in events {
			match ev {
				RegionEvent::Created { region } | RegionEvent::Changed { region } => {
					touched.push(region.raw());
				}
				RegionEvent::Merged { into, from } => {
					touched.push(into.raw());
					prior.entry(into.raw()).or_default().push(from.raw());
					retired.push(from.raw());
				}
				RegionEvent::Split { from, into } => {
					touched.extend([from.raw(), into.raw()]);
					prior.entry(into.raw()).or_default().push(from.raw());
				}
				RegionEvent::Retired { region } => retired.push(region.raw()),
				RegionEvent::Released { key, payload, .. } => {
					let target = self.targets.remove(&key);
					if target.is_none() {
						self.discarded += payload.total();
					}
					releases.push(Release {
						port: key,
						target,
						gas: payload,
					});
				}
				RegionEvent::DeviceDetached { .. } => {}
			}
		}
		let mut out = Vec::new();
		// Regions that are gone: report their slot as retired.
		retired.sort_unstable();
		retired.dedup();
		for raw in &retired {
			if self.net.region(RegionId::<Pipes>::from_raw(*raw)).is_ok() {
				continue;
			}
			if let Some(slot) = self.retire_slot(*raw) {
				out.push(Transition {
					slot,
					ports: Vec::new(),
					prior: Vec::new(),
					volume: 0.0,
					retired: true,
				});
			}
		}
		touched.sort_unstable();
		touched.dedup();
		for raw in touched {
			let r = RegionId::<Pipes>::from_raw(raw);
			let Ok(region) = self.net.region(r) else {
				continue;
			};
			let volume = *region.summary() as f32;
			let ports = self
				.net
				.members(r)
				.unwrap_or_default()
				.into_iter()
				.filter_map(|n| self.net.node(n).ok().map(|n| n.key))
				.collect();
			let known = self.slot_of.contains_key(&raw);
			let slot = self.slot_of(r);
			let mut prior_slots: Vec<u32> = prior
				.get(&raw)
				.map(|v| {
					v.iter()
						.filter_map(|p| self.slot_of.get(p).copied())
						.collect()
				})
				.unwrap_or_default();
			// A region keeps its slot across merges and splits: DM rebuilds
			// its wrapper under the same key.
			if known {
				prior_slots.push(slot);
			}
			prior_slots.sort_unstable();
			prior_slots.dedup();
			self.bump(slot);
			out.push(Transition {
				slot,
				ports,
				prior: prior_slots,
				volume,
				retired: false,
			});
		}
		(out, releases)
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::gas::ids::GAS_OXYGEN;

	fn gas(o2: f64, t: f64) -> PipeGas {
		let mut g = PipeGas::default();
		g.moles[GAS_OXYGEN] = o2;
		g.energy = o2 * 20.0 * t;
		g
	}

	fn total(net: &PipeNet, released: &[Release]) -> f64 {
		net.totals()[GAS_OXYGEN]
			+ released
				.iter()
				.map(|r| r.gas.moles[GAS_OXYGEN])
				.sum::<f64>()
	}

	#[test]
	fn merges_pool_and_splits_share_by_volume() {
		let mut net = PipeNet::new();
		for p in 1..=4 {
			net.upsert(p, p, 100.0, gas(10.0 * f64::from(p), 293.0));
		}
		for (a, b) in [(1, 2), (2, 3), (3, 4)] {
			net.connect(a, b);
		}
		let (t, _) = net.commit();
		let live: Vec<_> = t.iter().filter(|t| !t.retired).collect();
		assert_eq!(live.len(), 1);
		assert_eq!(live[0].ports.len(), 4);
		assert!((net.totals()[GAS_OXYGEN] - 100.0).abs() < 1e-9);
		net.disconnect(2, 3);
		let (t, _) = net.commit();
		let live: Vec<_> = t.iter().filter(|t| !t.retired).collect();
		assert_eq!(live.len(), 2);
		for r in live {
			let (g, v) = net.gas(r.slot).unwrap();
			assert!((v - 200.0).abs() < 1e-9);
			assert!((g.moles[GAS_OXYGEN] - 50.0).abs() < 1e-9);
		}
	}

	#[test]
	fn removing_a_port_releases_its_share() {
		let mut net = PipeNet::new();
		net.upsert(1, 1, 100.0, gas(30.0, 293.0));
		net.upsert(2, 2, 200.0, gas(0.0, 293.0));
		net.connect(1, 2);
		net.commit();
		net.remove(1, Some(77));
		let (_, released) = net.commit();
		assert_eq!(released.len(), 1);
		assert_eq!(released[0].target, Some(77));
		assert!((released[0].gas.moles[GAS_OXYGEN] - 10.0).abs() < 1e-9);
		assert!((total(&net, &released) - 30.0).abs() < 1e-9);
	}

	#[test]
	fn step_devices_moves_gas_between_regions_and_conserves() {
		let mut net = PipeNet::new();
		net.upsert(1, 1, 1000.0, gas(1000.0, 293.0));
		net.upsert(2, 2, 1000.0, gas(0.0, 293.0));
		net.commit();
		assert!(net.add_device(
			500,
			1,
			2,
			DeviceParams::Pump {
				target_kpa: 101.325,
				power_w: 5000.0,
			},
		));
		let before = net.totals()[GAS_OXYGEN];
		let mut reached = false;
		for _ in 0..200 {
			let steps = net.step_devices(1.0);
			assert_eq!(steps.len(), 1);
			assert_eq!(steps[0].key, 500);
			reached |= steps[0].report.target_reached;
		}
		assert!((net.totals()[GAS_OXYGEN] - before).abs() < 1e-6, "conserves mass");
		assert!(reached, "reaches its target pressure");
	}

	#[test]
	fn step_devices_skips_edges_already_in_one_region() {
		let mut net = PipeNet::new();
		net.upsert(1, 1, 100.0, gas(50.0, 293.0));
		net.upsert(2, 2, 100.0, gas(0.0, 293.0));
		net.connect(1, 2);
		net.commit();
		assert!(net.add_device(9, 1, 2, DeviceParams::Valve { open: true }));
		let steps = net.step_devices(1.0);
		assert!(steps.is_empty(), "same region already: nothing to move");
	}

	#[test]
	fn add_turf_device_creates_a_cell_node_edge_step_devices_skips() {
		use vg_core::network::Endpoint;

		let mut net = PipeNet::new();
		net.upsert(1, 1, 100.0, gas(50.0, 293.0));
		net.commit();
		assert!(net.add_turf_device(7, 1, 42, DeviceParams::Valve { open: true }));
		let &device_id = net.devices.get(&7).expect("device registered under id 7");
		let device = net.net.device(device_id).expect("device is live");
		assert_eq!((device.a, device.b), (Endpoint::Cell(42), Endpoint::Node(net.port(1).unwrap())));
		// PipeNet::step_devices only steps Node<->Node edges: this one has a
		// Cell endpoint, so GasWorld::step_turf_devices is the one that runs
		// it (world.rs's own test covers that path end to end).
		assert!(net.step_devices(1.0).is_empty());
	}

	#[test]
	fn remove_device_stops_future_steps() {
		let mut net = PipeNet::new();
		net.upsert(1, 1, 100.0, gas(50.0, 293.0));
		net.upsert(2, 2, 100.0, gas(0.0, 293.0));
		net.commit();
		assert!(net.add_device(1, 1, 2, DeviceParams::Valve { open: true }));
		assert!(net.remove_device(1));
		let steps = net.step_devices(1.0);
		assert!(steps.is_empty());
	}
}
