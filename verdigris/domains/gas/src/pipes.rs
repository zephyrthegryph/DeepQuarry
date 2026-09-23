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

use vg_core::handle::RawHandle;
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

	/// Total moles of the gases in `mask` (a `1 << gas_id` bitset; 0 means
	/// every gas). The ideal-gas helpers below are the single
	/// implementation `device::Flow` uses - the M2 device-law collapse
	/// moved them off `device.rs` and onto the mixture type they operate
	/// on, instead of five copies of the same formula.
	#[must_use]
	pub fn masked_total(&self, mask: u32) -> f64 {
		if mask == 0 {
			return self.total();
		}
		(0..N)
			.filter(|i| mask & (1 << i) != 0)
			.map(|i| self.moles[i])
			.sum()
	}

	/// Pressure (kPa) at volume `volume` (L), `pV = nRT`.
	#[must_use]
	pub fn pressure(&self, volume: f64) -> f32 {
		if volume <= 0.0 {
			return 0.0;
		}
		let t = self.temperature_now();
		((self.total() * f64::from(crate::gas::constants::R_IDEAL_GAS_EQUATION) * f64::from(t)) / volume) as f32
	}

	/// The moles a volume (L) at this mixture's current density represents.
	#[must_use]
	pub fn moles_for_volume(&self, volume: f64, take_l: f64) -> f64 {
		if volume <= 0.0 {
			return 0.0;
		}
		self.total() * (take_l / volume).clamp(0.0, 1.0)
	}

	/// Carves `moles` of the gases in `mask` (0: every gas) out of this
	/// mixture, splitting energy by the carved gases' share of the total
	/// heat capacity so both sides keep their own temperature. Clamped to
	/// what's actually there; conserves mass and energy with the caller
	/// (whatever it does with the returned share).
	pub fn carve_masked(&mut self, mask: u32, moles: f64) -> Self {
		if mask == 0 {
			let total = self.total();
			let f = if total > 0.0 { (moles / total).clamp(0.0, 1.0) } else { 0.0 };
			return self.carve(f);
		}
		let masked_total = self.masked_total(mask);
		let mut out = Self {
			temperature: self.temperature_now(),
			..Self::default()
		};
		if masked_total <= 0.0 {
			return out;
		}
		let f = (moles / masked_total).clamp(0.0, 1.0);
		let mut removed_frac_of_total = 0.0f64;
		for i in 0..N {
			if mask & (1 << i) != 0 {
				let amt = self.moles[i] * f;
				out.moles[i] = amt;
				self.moles[i] -= amt;
				removed_frac_of_total += amt;
			}
		}
		let total = self.total() + removed_frac_of_total;
		let e = if total > 0.0 {
			self.energy * (removed_frac_of_total / total)
		} else {
			0.0
		};
		out.energy = e;
		self.energy -= e;
		out
	}

	/// Moves `moles` of the gases in `mask` from `self` into `to`, clamped
	/// to what's masked and available. Returns the moles actually moved.
	pub fn transfer_masked(&mut self, to: &mut Self, mask: u32, moles: f64) -> f64 {
		if moles <= 0.0 || self.masked_total(mask) <= crate::gas::constants::GAS_MIN_MOLES.into() {
			return 0.0;
		}
		let carved = self.carve_masked(mask, moles);
		let moved = carved.total();
		to.add(&carved);
		moved
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

/// A device edge's idle-skip state (M2 follow-up: settled regions put their
/// device edges to sleep the same way M1b's field idle-skip does for
/// cells). `asleep` once a step moved nothing and drew no power; woken by a
/// setting change (`add_device`/`add_turf_device`/`set_device`) or by
/// either endpoint's revision moving since the last step (another device
/// on the same region, a DM write, or - for a turf endpoint - a dirty
/// field cell).
#[derive(Clone, Copy, Debug, Default)]
struct DeviceActivity {
	asleep: bool,
	rev_a: u32,
	rev_b: u32,
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
	/// Idle-skip state per device, keyed the same as `devices`.
	activity: HashMap<u32, DeviceActivity>,
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
				self.activity.remove(&id);
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
				self.activity.remove(&id);
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
		self.activity.remove(&id);
		self.net.remove_device(d).is_ok()
	}

	/// Replaces a device's parameters (a setting change): always wakes it,
	/// so the new setting takes effect on the very next step.
	pub fn set_device(&mut self, id: u32, params: DeviceParams) -> bool {
		let Some(&d) = self.devices.get(&id) else {
			return false;
		};
		self.activity.remove(&id);
		self.net.set_device_data(d, params).is_ok()
	}

	/// The change-revision of a region, for device idle-skip: the DM slot
	/// revision if it has one (bumped on every payload write, including a
	/// device's own step - see `gas_mut`/`touch_region`), or 0 for a region
	/// DM has never bound a slot to (rare; treated as "always changed" so a
	/// brand new region's devices step at least once).
	#[must_use]
	pub(crate) fn region_revision(&self, r: RegionId<Pipes>) -> u32 {
		self.slot_of
			.get(&r.raw())
			.map_or(0, |&s| self.revision(s))
	}

	/// Whether a device edge is asleep given its endpoints' current
	/// revisions - the same idle-skip state `step_devices` tracks for
	/// region<->region edges, shared with `GasWorld::step_turf_devices` for
	/// region<->turf edges (a vent pump or scrubber), which resolves its own
	/// "region" (`region_revision`) and "turf" (the field cell's own
	/// revision) sides and calls this directly since it steps outside
	/// `PipeNet`.
	#[must_use]
	pub(crate) fn device_asleep(&self, id: u32, rev_a: u32, rev_b: u32) -> bool {
		self.activity
			.get(&id)
			.is_some_and(|a| a.asleep && a.rev_a == rev_a && a.rev_b == rev_b)
	}

	/// Records a device edge's idle-skip state after a step (or after
	/// deciding not to step it because it was already asleep).
	pub(crate) fn set_device_activity(&mut self, id: u32, asleep: bool, rev_a: u32, rev_b: u32) {
		self.activity.insert(id, DeviceActivity { asleep, rev_a, rev_b });
	}

	/// Runs every awake device edge's flow law once (`device.rs`), moving
	/// gas between the regions on each side and bumping their DM slot
	/// revisions. A device that settled (moved nothing, drew no power) on
	/// its last step and whose endpoints haven't changed since is asleep
	/// and costs nothing but a `HashMap` lookup this tick - the same
	/// idle-skip M1b's field already does for settled cells. Edges with a
	/// field-cell (turf) endpoint are skipped; `GasWorld::step_turf_devices`
	/// runs those.
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
			let (Side::Region(ra), Side::Region(rb)) =
				(self.net.resolve(Endpoint::Node(na)), self.net.resolve(Endpoint::Node(nb)))
			else {
				continue;
			};
			if ra == rb {
				continue;
			}
			let rev_a = self.region_revision(ra);
			let rev_b = self.region_revision(rb);
			let activity = self.activity.entry(key).or_default();
			if activity.asleep && activity.rev_a == rev_a && activity.rev_b == rev_b {
				continue;
			}
			let params = dev.data;
			let Ok(region_a) = self.net.region(ra) else { continue };
			let Ok(region_b) = self.net.region(rb) else { continue };
			let vol_a = *region_a.summary();
			let vol_b = *region_b.summary();
			let mut pa = *region_a.payload();
			let mut pb = *region_b.payload();
			let report = device::step(&params, &mut pa, vol_a, &mut pb, vol_b, dt);
			let settled = report.moles == 0.0 && report.power_w == 0.0;
			let (mut rev_a, mut rev_b) = (rev_a, rev_b);
			if !settled {
				*self.net.payload_mut(ra).expect("resolved above") = pa;
				*self.net.payload_mut(rb).expect("resolved above") = pb;
				if let Some(&sa) = self.slot_of.get(&ra.raw()) {
					self.bump(sa);
					rev_a = self.revision(sa);
				}
				if let Some(&sb) = self.slot_of.get(&rb.raw()) {
					self.bump(sb);
					rev_b = self.revision(sb);
				}
			}
			self.activity.insert(
				key,
				DeviceActivity {
					asleep: settled,
					rev_a,
					rev_b,
				},
			);
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
		assert!(net.add_device(500, 1, 2, DeviceParams::decode(1, [101.325, 5000.0, 0.0, 0.0])));
		let before = net.totals()[GAS_OXYGEN];
		let mut reached = false;
		let mut asleep_steps = 0;
		for _ in 0..200 {
			let steps = net.step_devices(1.0);
			// Idle-skip: once settled (target reached, nothing left to move)
			// and neither region has changed since, the device sleeps and
			// step_devices reports nothing for it at all.
			if steps.is_empty() {
				asleep_steps += 1;
				continue;
			}
			assert_eq!(steps.len(), 1);
			assert_eq!(steps[0].key, 500);
			reached |= steps[0].report.target_reached;
		}
		assert!((net.totals()[GAS_OXYGEN] - before).abs() < 1e-6, "conserves mass");
		assert!(reached, "reaches its target pressure");
		assert!(asleep_steps > 0, "the pump never went to sleep once settled");
	}

	#[test]
	fn step_devices_skips_edges_already_in_one_region() {
		let mut net = PipeNet::new();
		net.upsert(1, 1, 100.0, gas(50.0, 293.0));
		net.upsert(2, 2, 100.0, gas(0.0, 293.0));
		net.connect(1, 2);
		net.commit();
		assert!(net.add_device(9, 1, 2, DeviceParams::Equalize { open: true }));
		let steps = net.step_devices(1.0);
		assert!(steps.is_empty(), "same region already: nothing to move");
	}

	#[test]
	fn sleeping_device_wakes_when_a_setting_changes() {
		let mut net = PipeNet::new();
		net.upsert(1, 1, 1000.0, gas(1000.0, 293.0));
		net.upsert(2, 2, 1000.0, gas(0.0, 293.0));
		net.commit();
		assert!(net.add_device(1, 1, 2, DeviceParams::decode(1, [50.0, 5000.0, 0.0, 0.0])));
		for _ in 0..50 {
			net.step_devices(1.0);
		}
		// Settled at its (low) target: should now be asleep.
		assert!(net.step_devices(1.0).is_empty(), "did not sleep once settled");
		// Raising the target is a setting change: must wake it and move more gas.
		assert!(net.set_device(1, DeviceParams::decode(1, [200.0, 5000.0, 0.0, 0.0])));
		let steps = net.step_devices(1.0);
		assert_eq!(steps.len(), 1, "a setting change did not wake the device");
		assert!(steps[0].report.moles > 0.0, "the new target didn't move any gas");
	}

	#[test]
	fn sleeping_device_wakes_when_a_shared_region_changes_externally() {
		let mut net = PipeNet::new();
		net.upsert(1, 1, 1000.0, gas(1000.0, 293.0));
		net.upsert(2, 2, 1000.0, gas(0.0, 293.0));
		net.upsert(3, 3, 1000.0, gas(1000.0, 293.0));
		net.commit();
		assert!(net.add_device(1, 1, 2, DeviceParams::decode(1, [50.0, 5000.0, 0.0, 0.0])));
		for _ in 0..50 {
			net.step_devices(1.0);
		}
		assert!(net.step_devices(1.0).is_empty(), "did not sleep once settled");
		// Another writer (a second device pumping into the same output
		// region) bumps port 2's region without touching device 1 at all.
		assert!(net.add_device(2, 3, 2, DeviceParams::decode(2, [50.0, 0.0, 0.0, 0.0])));
		// Device iteration order isn't guaranteed, so device 1 may see the
		// change this tick or the next; either is a correct wake.
		let mut woke = false;
		for _ in 0..2 {
			woke |= net.step_devices(1.0).iter().any(|s| s.key == 1);
		}
		assert!(woke, "a shared region's external change did not wake the sleeping device");
	}

	#[test]
	fn add_turf_device_creates_a_cell_node_edge_step_devices_skips() {
		use vg_core::network::Endpoint;

		let mut net = PipeNet::new();
		net.upsert(1, 1, 100.0, gas(50.0, 293.0));
		net.commit();
		assert!(net.add_turf_device(7, 1, 42, DeviceParams::Equalize { open: true }));
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
		assert!(net.add_device(1, 1, 2, DeviceParams::Equalize { open: true }));
		assert!(net.remove_device(1));
		let steps = net.step_devices(1.0);
		assert!(steps.is_empty());
	}
}
