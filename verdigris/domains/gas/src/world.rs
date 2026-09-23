//! The gas world: every gas the DLL holds, by owner (`rust_core.md` §3.1).
//!
//! - **Main-owned mixtures** ([`Mains`]): tanks, lungs, canisters, device
//!   buffers and scratch mixtures. DM reads and writes them synchronously,
//!   with no staleness.
//! - **Turf gas** ([`Field`]): the cells of the R6 turf gas field
//!   ([`TurfGas`]), owned by the field's worker. DM reads the pinned view
//!   plus its own writes (the overlay); DM writes are [`GasCmd`]s with
//!   absolute amounts.
//! - **Pipe gas** ([`PipeNet`]): region payloads of the R7 pipe network.
//!   Until M2 moves device flow into the frame, only DM touches them, so they
//!   are main-owned too.
//!
//! A `/datum/gas_mixture` holds one number, its handle ([`MixRef`]), in
//! `_extools_pointer_gasmixture`. Every DM gas proc goes through
//! [`with_mix`] / [`with_mix_mut`], which dispatch on the owner, so DM's gas
//! API (`return_air`, `remove`, `merge`, `get_moles`, ...) is unchanged.
//!
//! Everything here lives on BYOND's main thread (a thread local): there are
//! no locks on the DM path. The only shared state is the heat exchange
//! buffer ([`Exchange`]), which frame threads of the heat world reach with
//! `try_lock` only.

use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, RwLock};

use byondapi::prelude::*;
use eyre::{bail, eyre, Result};
use vg_core::command::Seq;
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::field::{add_field, FieldConfig, FieldKey, FieldState, Geom, GeomCmd};
use vg_core::frame::{Res, Task};
use vg_core::grid::{DirMask, Face, GridDims};
use vg_core::outbox::{Event, EventKind, Lane, Outbox, Wake, WatchId};
use vg_core::owner::{DomainState, View};
use vg_core::revision::Counter;
use vg_core::sim::{Mode, Sim, SimBuilder, SimConfig, WatchKey};
use vg_core::watch::{Cond, WatchPort, WatchState};

use crate::cell::{flags, heat_capacity, GasCell, GasCmd, TurfGas, N, Q};
use crate::device;
use crate::gas::constants::{CELL_VOLUME, GAS_MIN_MOLES, TCMB};
use crate::gas::Mixture;
use crate::pipes::{self, PipeGas, PipeNet};

// --- Handles -----------------------------------------------------------------

/// Main-owned mixtures use handles `0..PIPE_BASE`.
/// @dm-define GAS_HANDLE_PIPE_BASE
pub const PIPE_BASE: u32 = 2097152;
/// Turf cells use `TURF_BASE + cell`.
/// @dm-define GAS_HANDLE_TURF_BASE
pub const TURF_BASE: u32 = 4194304;
/// Every handle is below this (exact as an `f32`).
pub const ID_LIMIT: u32 = 1 << 24;

/// What a gas handle names.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum MixRef {
	/// A main-owned mixture slot.
	Main(u32),
	/// A pipe region, by its DM slot.
	Pipe(u32),
	/// A turf's gas, by cell index.
	Turf(u32),
}

impl MixRef {
	#[must_use]
	pub fn from_id(id: u32) -> Option<Self> {
		match id {
			i if i < PIPE_BASE => Some(Self::Main(i)),
			i if i < TURF_BASE => Some(Self::Pipe(i - PIPE_BASE)),
			i if i < ID_LIMIT => Some(Self::Turf(i - TURF_BASE)),
			_ => None,
		}
	}

	#[must_use]
	pub fn from_f32(v: f32) -> Option<Self> {
		if !(v >= 0.0 && v.fract() == 0.0 && v < ID_LIMIT as f32) {
			return None;
		}
		Self::from_id(v as u32)
	}

	#[must_use]
	pub const fn id(self) -> u32 {
		match self {
			Self::Main(i) => i,
			Self::Pipe(s) => PIPE_BASE + s,
			Self::Turf(c) => TURF_BASE + c,
		}
	}

	/// The handle a gas mixture datum holds.
	///
	/// # Errors
	/// If the datum has no valid handle.
	pub fn of(v: &ByondValue) -> Result<Self> {
		let n = v.read_number_id(byond_string!("_extools_pointer_gasmixture"))?;
		Self::from_f32(n).ok_or_else(|| eyre!("invalid gas mixture handle {n}"))
	}

	/// Writes the handle into a gas mixture datum.
	///
	/// # Errors
	/// If the var cannot be written.
	pub fn store(self, v: &mut ByondValue) -> Result<()> {
		#[allow(clippy::cast_precision_loss)]
		v.write_var_id(
			byond_string!("_extools_pointer_gasmixture"),
			&ByondValue::from(self.id() as f32),
		)?;
		Ok(())
	}
}

// --- Main-owned mixtures ----------------------------------------------------

struct Slot {
	mix: Mixture,
	revision: Counter,
	live: bool,
}

/// The main-owned mixture slab. Slots are reused; a handle is only valid
/// while its datum lives (as before).
#[derive(Default)]
pub struct Mains {
	slots: Vec<Slot>,
	free: Vec<u32>,
	live: usize,
}

impl Mains {
	/// Allocates a slot.
	///
	/// # Errors
	/// If every main handle is in use.
	pub fn alloc(&mut self, mix: Mixture) -> Result<u32> {
		self.live += 1;
		if let Some(i) = self.free.pop() {
			let slot = &mut self.slots[i as usize];
			slot.mix = mix;
			slot.revision.bump();
			slot.live = true;
			return Ok(i);
		}
		let i = u32::try_from(self.slots.len())?;
		if i >= PIPE_BASE {
			self.live -= 1;
			bail!("out of main gas mixture handles ({PIPE_BASE})");
		}
		self.slots.push(Slot {
			mix,
			revision: Counter::new(),
			live: true,
		});
		Ok(i)
	}

	pub fn free(&mut self, i: u32) {
		if let Some(slot) = self.slots.get_mut(i as usize) {
			if slot.live {
				slot.live = false;
				slot.mix = Mixture::new();
				slot.revision.bump();
				self.free.push(i);
				self.live -= 1;
			}
		}
	}

	#[must_use]
	pub fn get(&self, i: u32) -> Option<&Mixture> {
		self.slots
			.get(i as usize)
			.filter(|s| s.live)
			.map(|s| &s.mix)
	}

	pub fn get_mut(&mut self, i: u32) -> Option<&mut Mixture> {
		self.slots
			.get_mut(i as usize)
			.filter(|s| s.live)
			.map(|s| &mut s.mix)
	}

	fn bump(&mut self, i: u32) {
		if let Some(s) = self.slots.get_mut(i as usize) {
			s.revision.bump();
		}
	}

	#[must_use]
	pub fn revision(&self, i: u32) -> u32 {
		self.slots.get(i as usize).map_or(0, |s| s.revision.get())
	}

	#[must_use]
	pub fn live(&self) -> usize {
		self.live
	}

	#[must_use]
	pub fn capacity(&self) -> usize {
		self.slots.len()
	}

	/// Total gas over every live slot (for conservation checks).
	#[must_use]
	pub fn totals(&self) -> [f64; Q] {
		let mut out = [0.0; Q];
		for s in self.slots.iter().filter(|s| s.live) {
			let m = s.mix.moles_array();
			for (o, v) in out.iter_mut().zip(m) {
				*o += f64::from(v);
			}
			out[N] += f64::from(s.mix.thermal_energy());
		}
		out
	}
}

// --- The heat exchange buffer ------------------------------------------------

/// What the heat world's frame threads see of gas (`vg_heat::GasExchange`),
/// and the energy they move, applied to gas as commands on the main thread
/// (an exchange buffer, `rust_core.md` §3.6). Frame threads only `try_lock`.
/// The turf-field views (gas cells, geometry) the heat world reads, swapped
/// in together each frame.
type FieldViews = Option<(Arc<View<GasCell>>, Arc<View<Geom>>)>;

#[derive(Default)]
pub struct Exchange {
	views: Mutex<FieldViews>,
	/// Probes of main-owned and pipe gas, by handle, refreshed each tick.
	probes: Mutex<HashMap<u32, vg_heat::GasProbe>>,
	requests: Mutex<Vec<u32>>,
	/// Energy to add (J), by gas.
	pending: Mutex<Vec<(vg_heat::GasRef, f32)>>,
	/// Turf cells whose gas temperature moved (for the solid ↔ gas coupling).
	changed: Mutex<Vec<u32>>,
}

fn cell_probe(cells: &View<GasCell>, geom: &View<Geom>, cell: u32) -> Option<vg_heat::GasProbe> {
	let g = geom.get(cell)?;
	if !g.is_node() {
		return None;
	}
	let c = cells.get(cell)?;
	Some(vg_heat::GasProbe {
		temperature: c.temperature,
		capacity: c.heat_capacity(),
		reservoir: g.reservoir || c.is_immutable(),
	})
}

impl Exchange {
	fn probe(&self, gas: vg_heat::GasRef) -> Option<vg_heat::GasProbe> {
		let turf = match gas {
			vg_heat::GasRef::Turf(cell) => Some(cell),
			vg_heat::GasRef::Mixture(id) => match MixRef::from_id(id)? {
				MixRef::Turf(cell) => Some(cell),
				_ => None,
			},
		};
		if let Some(cell) = turf {
			let views = self.views.try_lock().ok()?;
			let (cells, geom) = views.as_ref()?;
			return cell_probe(cells, geom, cell);
		}
		let vg_heat::GasRef::Mixture(id) = gas else {
			return None;
		};
		let probe = self.probes.try_lock().ok()?.get(&id).copied();
		if probe.is_none() {
			if let Ok(mut r) = self.requests.try_lock() {
				r.push(id);
			}
		}
		probe
	}
}

/// The `GasExchange` the heat world is built with.
pub struct HeatGas(pub Arc<Exchange>);

impl vg_heat::GasExchange for HeatGas {
	fn probe(&self, gas: vg_heat::GasRef) -> Option<vg_heat::GasProbe> {
		self.0.probe(gas)
	}

	fn exchange(
		&self,
		gas: vg_heat::GasRef,
		f: &mut dyn FnMut(vg_heat::GasProbe) -> f32,
	) -> Option<f32> {
		let probe = self.0.probe(gas)?;
		let mut pending = self.0.pending.try_lock().ok()?;
		let e = f(probe);
		if e == 0.0 || !e.is_finite() {
			return Some(0.0);
		}
		if probe.reservoir {
			// Space and planet air: the energy leaves the books (the heat
			// ledger records it).
			return Some(e);
		}
		if probe.capacity <= 0.0 {
			return Some(0.0);
		}
		// Never cool gas below TCMB.
		let e = e.max(-(probe.temperature - TCMB).max(0.0) * probe.capacity);
		pending.push((gas, e));
		Some(e)
	}

	fn take_changed(&self, out: &mut Vec<u32>) {
		if let Ok(mut c) = self.0.changed.try_lock() {
			out.append(&mut c);
		}
	}
}

// --- The field's frame-side post step -----------------------------------------

/// Per planet id, the atmosphere planet cells relax back to.
pub type Planets = Arc<RwLock<Vec<GasCell>>>;

/// A pressure difference above this (kPa, times the old diffusion constant
/// 0.125) is a `PressureJump` (spacewind).
const PRESSURE_EVENT: f32 = 5.0;
const PRESSURE_EVENT_SCALE: f32 = 0.125;
/// Planet cells relax this fraction of the way back each frame.
const PLANET_RELAX: f32 = 0.25;
/// Gas temperature moves above this (K) are reported to the heat world.
const HEAT_CHANGED_K: f32 = 0.5;

/// Worker-side state of the gas step that runs after the field: domain
/// events for DM, planet relaxation, heat notifications.
pub struct Post {
	last: Option<CowStore<GasCell>>,
	planets: Planets,
	planet_dirty: Vec<u32>,
	exchange: Arc<Exchange>,
	dims: GridDims,
	/// The field's reservoir ledger, published for the main thread.
	ledger: Arc<Mutex<Vec<f64>>>,
	stats: Arc<Mutex<vg_core::field::FieldStats>>,
	/// Chunks the next step will simulate, plus planet cells still relaxing.
	awake: Arc<std::sync::atomic::AtomicUsize>,
	pub events: u64,
}

impl Post {
	fn run(
		&mut self,
		dom: &mut DomainState<TurfGas>,
		geom: &CowStore<Geom>,
		state: &FieldState<TurfGas>,
	) {
		if let Ok(mut l) = self.ledger.try_lock() {
			l.clear();
			l.extend_from_slice(state.ledger());
		}
		if let Ok(mut s) = self.stats.try_lock() {
			*s = state.stats();
		}
		let layout = dom.store.layout();
		let changed: Vec<usize> = match &self.last {
			Some(last) => dom.store.chunks_differing_from(last).collect(),
			None => (0..layout.chunk_count())
				.filter(|&c| dom.store.chunk(c).is_some())
				.collect(),
		};
		let mut events = Vec::new();
		let mut heat_changed = Vec::new();
		let mut touched_cells = Vec::new();
		let planets = self.planets.try_read().ok();
		for &chunk in &changed {
			let Some(values) = dom.store.chunk(chunk) else {
				continue;
			};
			let before = self.last.as_ref().and_then(|l| l.chunk(chunk));
			for (i, cell) in values.iter().enumerate() {
				let Some(index) = layout.index_of(chunk, i) else {
					continue;
				};
				let g = geom.get(index).unwrap_or_default();
				if !g.is_node() {
					continue;
				}
				let old = before.map(|b| &b[i]);
				if cell.planet > 0 && g.reservoir {
					if let Some(base) = planets
						.as_ref()
						.and_then(|p| p.get(cell.planet as usize).copied())
					{
						if cell.moles != base.moles || cell.energy != base.energy {
							self.planet_dirty.push(index);
						}
					}
					continue;
				}
				if g.reservoir {
					continue;
				}
				if cell.flags & flags::REACT != 0 {
					events.push(Event {
						kind: EventKind::ReactionCheck,
						key: index,
						value: 0.0,
						extra: 0,
						generation: 0,
					});
				}
				let touched = cell.flags & flags::TOUCHED != 0;
				if touched {
					touched_cells.push(index);
				}
				if old.map_or(cell.vis != 0, |o| o.vis != cell.vis)
					|| (touched && (cell.vis != 0 || old.is_some_and(|o| o.vis != 0)))
				{
					events.push(Event {
						kind: EventKind::VisualChange,
						key: index,
						value: f32::from(cell.vis),
						extra: 0,
						generation: 0,
					});
				}
				if old.is_none_or(|o| (o.temperature - cell.temperature).abs() > HEAT_CHANGED_K) {
					heat_changed.push(index);
				}
				// Spacewind across this cell's positive faces.
				for face in [Face::East, Face::North, Face::West, Face::South] {
					let Some(nb) = self.dims.neighbor(index, face) else {
						continue;
					};
					let gb = geom.get(nb).unwrap_or_default();
					if !gb.is_node()
						|| g.blocked.contains(face)
						|| gb.blocked.contains(face.opposite())
					{
						continue;
					}
					let pb = dom.store.with(nb, |c| c.pressure).unwrap_or(0.0);
					let moved = (cell.pressure - pb) * PRESSURE_EVENT_SCALE;
					// Each face once: from its higher side, or from this
					// cell when the neighbour is a reservoir.
					if moved > PRESSURE_EVENT {
						events.push(Event {
							kind: EventKind::PressureJump,
							key: index,
							value: moved,
							extra: nb,
							generation: 0,
						});
					}
				}
			}
		}
		drop(planets);
		for index in touched_cells {
			if let Some(c) = dom.store.get_mut(index) {
				c.flags &= !flags::TOUCHED;
			}
		}
		self.relax_planets(dom);
		let out = dom.outbox_mut();
		self.events += events.len() as u64;
		for e in events {
			out.push_event(e);
		}
		if !heat_changed.is_empty() {
			if let Ok(mut c) = self.exchange.changed.try_lock() {
				c.append(&mut heat_changed);
			}
		}
		self.last = Some(dom.store.snapshot());
		let awake = state.active_chunks().count() + self.planet_dirty.len();
		self.awake.store(awake, std::sync::atomic::Ordering::Release);
	}

	fn relax_planets(&mut self, dom: &mut DomainState<TurfGas>) {
		if self.planet_dirty.is_empty() {
			return;
		}
		let Ok(planets) = self.planets.try_read() else {
			return;
		};
		self.planet_dirty.sort_unstable();
		self.planet_dirty.dedup();
		let mut keep = Vec::new();
		for &index in &self.planet_dirty {
			let Some(cell) = dom.store.get_mut(index) else {
				continue;
			};
			if cell.planet == 0 {
				continue;
			}
			let Some(base) = planets.get(cell.planet as usize).copied() else {
				continue;
			};
			let mut settled = true;
			for (m, b) in cell.moles.iter_mut().zip(base.moles) {
				*m += (b - *m) * PLANET_RELAX;
				if (*m - b).abs() > GAS_MIN_MOLES * 10.0 {
					settled = false;
				} else {
					*m = b;
				}
			}
			cell.energy += (base.energy - cell.energy) * PLANET_RELAX;
			if (cell.energy - base.energy).abs() > 1.0 {
				settled = false;
			} else {
				cell.energy = base.energy;
			}
			cell.refresh_in(CELL_VOLUME);
			if !settled {
				keep.push(index);
			}
		}
		self.planet_dirty = keep;
	}
}

// --- Dirty observations (machines.dm's gas subscribers) -----------------------

/// Floats per record from [`GasWorld::drain_observations`].
pub const OBSERVATION_STRIDE: usize = 15;
const _: () = assert!(PIPE_BASE == 1 << 21 && TURF_BASE == 1 << 22);
const PRESSURE_DIRTY_EPSILON: f32 = 0.5;
const TEMPERATURE_DIRTY_EPSILON: f32 = 0.5;
/// Total moles across every species, matching the settled/revision bands in
/// `cell.rs` (`SETTLED_MOLES`, `REVISION_MOLES`). Checked against the sum of
/// per-species drift rather than any one species crossing it (below), or
/// settling noise spread thinly across several trace gases in a large idle
/// mixture racks up spurious composition-dirty flags one species at a time
/// even though the mixture as a whole is not meaningfully changing.
const COMPOSITION_DIRTY_EPSILON: f32 = 0.05;
use crate::gas::{
	GAS_CHANGE_COMPOSITION as CHANGE_COMPOSITION, GAS_CHANGE_PRESSURE as CHANGE_PRESSURE,
	GAS_CHANGE_TEMPERATURE as CHANGE_TEMPERATURE,
};

#[derive(Clone, Copy, Debug, PartialEq)]
struct Signature {
	pressure: f32,
	temperature: f32,
	moles: [f32; N],
}

impl Signature {
	fn of(mix: &Mixture) -> Self {
		Self {
			pressure: mix.return_pressure(),
			temperature: mix.get_temperature(),
			moles: mix.moles_array(),
		}
	}

	fn mask_since(&self, after: &Self) -> u8 {
		let mut mask = 0;
		if (self.pressure - after.pressure).abs() >= PRESSURE_DIRTY_EPSILON {
			mask |= CHANGE_PRESSURE;
		}
		if (self.temperature - after.temperature).abs() >= TEMPERATURE_DIRTY_EPSILON {
			mask |= CHANGE_TEMPERATURE;
		}
		let moles_drift: f32 = self
			.moles
			.iter()
			.zip(&after.moles)
			.map(|(a, b)| (a - b).abs())
			.sum();
		if moles_drift >= COMPOSITION_DIRTY_EPSILON {
			mask |= CHANGE_COMPOSITION;
		}
		mask
	}
}

#[derive(Default)]
struct Dirty {
	/// Watched handle -> (interest mask, baseline).
	watched: HashMap<u32, (u8, Signature)>,
	dirty: HashMap<u32, u8>,
}

impl Dirty {
	fn check(&mut self, id: u32, after: &Signature) {
		let Some((interest, base)) = self.watched.get_mut(&id) else {
			return;
		};
		let mask = base.mask_since(after);
		if mask == 0 {
			return;
		}
		if mask & CHANGE_PRESSURE != 0 {
			base.pressure = after.pressure;
		}
		if mask & CHANGE_TEMPERATURE != 0 {
			base.temperature = after.temperature;
		}
		if mask & CHANGE_COMPOSITION != 0 {
			base.moles = after.moles;
		}
		let mask = mask & *interest;
		if mask != 0 {
			*self.dirty.entry(id).or_default() |= mask;
		}
	}
}

// --- Watches on main-owned mixtures ------------------------------------------

/// Main-owned mixtures as a watchable domain: the reactor's watches read
/// pressure and temperature from a store the gas world updates on writes,
/// and are evaluated synchronously each gas tick.
pub struct MixWatch;

impl vg_core::owner::Domain for MixWatch {
	type Value = GasProbeCell;
	type Command = ();
	const NAME: &'static str = "gas_mix";
	fn apply(_: &mut GasProbeCell, (): &()) -> vg_core::owner::Applied {
		vg_core::owner::Applied::default()
	}
}

/// Pressure, temperature and total moles of a watched main-owned mixture.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GasProbeCell {
	pub pressure: f32,
	pub temperature: f32,
	pub total: f32,
	pub oxygen: f32,
	pub plasma: f32,
	pub carbon_dioxide: f32,
}

// Same channel table as the turf field, so DM uses one set of CH_GAS_*.
vg_core::channels! { pub mod mix_ch for MixWatch {
	PRESSURE: Scalar<Kpa> hysteresis 0.5 => |c, o| o[0] = c.pressure,
	TEMPERATURE: Scalar<Kelvin> hysteresis 0.5 => |c, o| o[0] = c.temperature,
	MOLES: Scalar<Moles> hysteresis 0.1 => |c, o| o[0] = c.total,
	OXYGEN: Scalar<Moles> hysteresis 0.05 => |c, o| o[0] = c.oxygen,
	PLASMA: Scalar<Moles> hysteresis 0.05 => |c, o| o[0] = c.plasma,
	CARBON_DIOXIDE: Scalar<Moles> hysteresis 0.05 => |c, o| o[0] = c.carbon_dioxide,
}}

impl GasProbeCell {
	fn of(mix: &Mixture) -> Self {
		use crate::gas::ids::{GAS_CARBON_DIOXIDE, GAS_OXYGEN, GAS_PLASMA};
		Self {
			pressure: mix.return_pressure(),
			temperature: mix.get_temperature(),
			total: mix.total_moles(),
			oxygen: mix.get_moles(GAS_OXYGEN),
			plasma: mix.get_moles(GAS_PLASMA),
			carbon_dioxide: mix.get_moles(GAS_CARBON_DIOXIDE),
		}
	}
}

struct MixWatches {
	store: CowStore<GasProbeCell>,
	state: WatchState<MixWatch>,
	port: WatchPort<MixWatch>,
	/// Watch count per slot (only watched slots mirror into the store).
	watched: HashMap<u32, u32>,
	cells: HashMap<WatchId, Vec<u32>>,
}

impl MixWatches {
	fn new() -> Self {
		let layout = ChunkLayout::linear_with_chunk(PIPE_BASE, 1024);
		Self {
			store: CowStore::new(layout),
			state: WatchState::new(layout),
			port: WatchPort::new(layout),
			watched: HashMap::new(),
			cells: HashMap::new(),
		}
	}

	fn evaluate(&mut self, out: &mut Vec<Wake>) {
		if self.watched.is_empty() && self.port.queued() == 0 {
			return;
		}
		let mut outbox: Outbox<GasProbeCell> = Outbox::default();
		self.port.dispatch(&mut self.state);
		self.state.evaluate(&self.store, &mut outbox);
		self.port.filter(&mut outbox);
		out.extend(outbox.wakes().iter().map(|w| Wake {
			source: w.source,
			..*w
		}));
	}
}

fn cond_cells(cond: &Cond, out: &mut Vec<u32>) {
	match cond {
		Cond::Changed { cell, .. }
		| Cond::Threshold { cell, .. }
		| Cond::Band { cell, .. }
		| Cond::ThresholdSet { cell, .. } => out.push(*cell),
		Cond::Difference { a, b, .. } => out.extend([*a, *b]),
		Cond::Any(cs) | Cond::All(cs) => {
			for c in cs {
				cond_cells(c, out);
			}
		}
	}
}

fn map_cells(cond: &Cond, f: &impl Fn(u32) -> u32) -> Cond {
	match cond {
		Cond::Changed { cell, mask } => Cond::Changed {
			cell: f(*cell),
			mask: *mask,
		},
		Cond::Threshold { cell, level } => Cond::Threshold {
			cell: f(*cell),
			level: *level,
		},
		Cond::Band {
			cell,
			ch,
			unit,
			levels,
			hysteresis,
		} => Cond::Band {
			cell: f(*cell),
			ch: *ch,
			unit: *unit,
			levels: levels.clone(),
			hysteresis: *hysteresis,
		},
		Cond::Difference { a, b, level, abs } => Cond::Difference {
			a: f(*a),
			b: f(*b),
			level: *level,
			abs: *abs,
		},
		Cond::ThresholdSet { cell, ch } => Cond::ThresholdSet {
			cell: f(*cell),
			ch: *ch,
		},
		Cond::Any(cs) => Cond::Any(cs.iter().map(|c| map_cells(c, f)).collect()),
		Cond::All(cs) => Cond::All(cs.iter().map(|c| map_cells(c, f)).collect()),
	}
}

// --- The turf field ------------------------------------------------------------

/// Seconds of gas simulated per frame (SSair's `wait`).
pub const FRAME_DT: f32 = 0.5;
/// Sub-step cap per frame.
pub const MAX_SUBSTEPS: u32 = 16;

/// A take (whole-cell transfer out) waiting for the worker's exact value.
struct PendingTake {
	dest: MixRef,
	seen: [f32; Q],
}

/// The turf gas field and its sim.
pub struct Field {
	pub sim: Sim,
	pub key: FieldKey<TurfGas>,
	pub watch: WatchKey<TurfGas>,
	pub post: Res<Post>,
	pub state: Res<FieldState<TurfGas>>,
	pub dims: GridDims,
	masks: HashMap<u32, u8>,
	z_links: Vec<u8>,
	planets: Planets,
	planet_ids: HashMap<String, u8>,
	takes: HashMap<Seq, PendingTake>,
	ledger: Arc<Mutex<Vec<f64>>>,
	stats: Arc<Mutex<vg_core::field::FieldStats>>,
	awake: Arc<std::sync::atomic::AtomicUsize>,
	/// Frames not started because nothing was awake and nothing was queued.
	pub idle_skips: u64,
	pub frames: u64,
	pub mode: Mode,
}

/// Turf cells above this many z-levels of headroom are not addressable.
fn z_capacity(max_x: u32, max_y: u32, max_z: u32) -> u32 {
	let layer = u64::from(max_x.max(1)) * u64::from(max_y.max(1));
	let limit = u64::from(ID_LIMIT - TURF_BASE) / layer;
	let want = u64::from(max_z.max(1)).saturating_mul(2).max(16);
	u32::try_from(want.min(limit).max(u64::from(max_z.max(1)))).unwrap_or(max_z)
}

impl Field {
	/// Builds the field over a `max_x` x `max_y` map with room for
	/// `max_z` levels and headroom.
	///
	/// # Errors
	/// If the grid does not fit the handle range or the sim cannot build.
	pub fn new(
		max_x: u32,
		max_y: u32,
		max_z: u32,
		mode: Mode,
		exchange: &Arc<Exchange>,
	) -> Result<Self> {
		let z = z_capacity(max_x, max_y, max_z);
		let dims = GridDims::new(max_x.max(1), max_y.max(1), z)
			.ok_or_else(|| eyre!("gas grid {max_x}x{max_y}x{z} does not fit"))?;
		if dims.layer_len() * dims.max_z() > ID_LIMIT - TURF_BASE {
			bail!("gas grid {max_x}x{max_y}x{z} exceeds the turf handle range");
		}
		let threads = std::thread::available_parallelism()
			.map_or(1, |n| n.get().saturating_sub(2))
			.clamp(1, 4);
		let mut b = SimBuilder::new(SimConfig {
			threads,
			mode,
			..SimConfig::default()
		});
		let key = add_field::<TurfGas>(
			&mut b,
			dims,
			FieldConfig {
				dt: FRAME_DT,
				max_substeps: MAX_SUBSTEPS,
			},
		);
		let planets: Planets = Arc::new(RwLock::new(vec![GasCell::default()]));
		let ledger = Arc::new(Mutex::new(vec![0.0; Q]));
		let stats = Arc::new(Mutex::new(vg_core::field::FieldStats::default()));
		let awake = Arc::new(std::sync::atomic::AtomicUsize::new(1));
		let post = b.add_resource(
			"gas:post",
			Post {
				last: None,
				planets: Arc::clone(&planets),
				planet_dirty: Vec::new(),
				exchange: Arc::clone(exchange),
				dims,
				ledger: Arc::clone(&ledger),
				stats: Arc::clone(&stats),
				awake: Arc::clone(&awake),
				events: 0,
			},
		);
		let (cells, geometry, fstate) = (key.cells.state(), key.geometry.state(), key.state);
		b.add_task(
			Task::new("gas:post", move |ctx| {
				let geom = ctx.read(geometry);
				let field = ctx.read(fstate);
				let mut dom = ctx.write(cells);
				ctx.write(post).run(&mut dom, &geom.store, &field);
			})
			.reads(geometry.id())
			.reads(fstate.id())
			.writes(cells.id())
			.writes(post.id()),
		);
		let watch = b.add_watches(key.cells);
		let sim = b
			.build()
			.map_err(|e| eyre!("gas sim failed to build: {e}"))?;
		Ok(Self {
			sim,
			key,
			watch,
			post,
			state: key.state,
			dims,
			masks: HashMap::new(),
			z_links: Vec::new(),
			planets,
			planet_ids: HashMap::new(),
			takes: HashMap::new(),
			ledger,
			stats,
			awake,
			idle_skips: 0,
			frames: 0,
			mode,
		})
	}

	/// The field's last step statistics (as of the last reclaimed frame).
	#[must_use]
	pub fn stats(&self) -> vg_core::field::FieldStats {
		*self
			.stats
			.lock()
			.unwrap_or_else(std::sync::PoisonError::into_inner)
	}

	/// Chunks the next step will simulate, plus planet cells still relaxing,
	/// as of the last reclaimed frame.
	#[must_use]
	pub fn awake_chunks(&self) -> usize {
		self.awake.load(std::sync::atomic::Ordering::Acquire)
	}

	/// Whether a frame would do nothing: every chunk asleep, no planet cell
	/// relaxing, no command or watch registration queued, no frame running.
	#[must_use]
	pub fn idle(&mut self) -> bool {
		self.awake.load(std::sync::atomic::Ordering::Acquire) == 0
			&& !self.sim.frame_running()
			&& self.sim.port_ref(self.key.cells).queued() == 0
			&& self.sim.port_ref(self.key.geometry).queued() == 0
			&& self.sim.watches(self.watch).queued() == 0
	}

	/// Registered turf cells.
	#[must_use]
	pub fn registered(&self) -> usize {
		self.masks.len()
	}

	/// What flowed into reservoirs so far (as of the last frame).
	#[must_use]
	pub fn ledger(&self) -> Vec<f64> {
		self.ledger
			.lock()
			.unwrap_or_else(std::sync::PoisonError::into_inner)
			.clone()
	}

	/// Copies every registered cell into a new field of the same x/y (the
	/// map grew past the z headroom). Call on a settled sim.
	pub fn copy_into(&self, to: &mut Field) {
		to.z_links.clone_from(&self.z_links);
		{
			let from = self
				.planets
				.read()
				.unwrap_or_else(std::sync::PoisonError::into_inner)
				.clone();
			*to.planets
				.write()
				.unwrap_or_else(std::sync::PoisonError::into_inner) = from;
		}
		to.planet_ids.clone_from(&self.planet_ids);
		for (&cell, &mask) in &self.masks {
			if !to.contains(cell) {
				continue;
			}
			if let Some((value, geom)) = self.read(cell) {
				to.register(cell, value, geom.capacity, geom.reservoir, Some(mask));
			}
		}
	}

	#[must_use]
	pub fn contains(&self, cell: u32) -> bool {
		cell < self.dims.layer_len() * self.dims.max_z()
	}

	/// The cell and its geometry as DM sees them now.
	#[must_use]
	pub fn read(&self, cell: u32) -> Option<(GasCell, Geom)> {
		let g = self.sim.port_ref(self.key.geometry).read(cell)?;
		let c = self.sim.port_ref(self.key.cells).read(cell)?;
		Some((c, g))
	}

	fn effective_mask(&self, cell: u32, mask: u8) -> DirMask {
		let z = cell / self.dims.layer_len();
		let link = self.z_links.get(z as usize).copied().unwrap_or(0);
		let mut m = mask & DirMask::ALL.0;
		if link & Face::Up.bit() == 0 {
			m |= Face::Up.bit();
		}
		if link & Face::Down.bit() == 0 {
			m |= Face::Down.bit();
		}
		DirMask(m)
	}

	fn geom(&mut self, cell: u32, cmd: GeomCmd) {
		let _ = self.sim.port(self.key.geometry).submit(cell, cmd);
	}

	/// Sets a cell's DM air-block mask (`None` keeps the current one).
	pub fn set_mask(&mut self, cell: u32, mask: Option<u8>) {
		let mask = match mask {
			Some(m) => {
				self.masks.insert(cell, m);
				m
			}
			None => match self.masks.get(&cell) {
				Some(&m) => m,
				None => {
					self.masks.insert(cell, 0);
					0
				}
			},
		};
		let effective = self.effective_mask(cell, mask);
		let current = self
			.sim
			.port_ref(self.key.geometry)
			.read(cell)
			.map(|g| g.blocked);
		if current != Some(effective) {
			self.geom(cell, GeomCmd::Blocked(effective));
		}
	}

	/// Re-derives every registered cell's mask (the z-links changed).
	pub fn set_z_links(&mut self, links: Vec<u8>) {
		self.z_links = links;
		let cells: Vec<(u32, u8)> = self.masks.iter().map(|(&c, &m)| (c, m)).collect();
		for (cell, mask) in cells {
			self.set_mask(cell, Some(mask));
		}
	}

	/// Registers a cell with its gas. `reservoir` for space and planets.
	pub fn register(
		&mut self,
		cell: u32,
		mut value: GasCell,
		volume: f32,
		reservoir: bool,
		mask: Option<u8>,
	) {
		let volume = if volume > 0.0 { volume } else { CELL_VOLUME };
		value.refresh_in(volume);
		let _ = self.sim.port(self.key.cells).put(cell, value);
		let current = self
			.sim
			.port_ref(self.key.geometry)
			.read(cell)
			.unwrap_or_default();
		if current.capacity != volume {
			self.geom(cell, GeomCmd::Capacity(volume));
		}
		if current.reservoir != reservoir {
			self.geom(cell, GeomCmd::Reservoir(reservoir));
		}
		self.set_mask(cell, mask);
	}

	/// Drops a cell from the field (it became a wall, or its turf went away).
	pub fn unregister(&mut self, cell: u32) {
		self.masks.remove(&cell);
		let current = self
			.sim
			.port_ref(self.key.geometry)
			.read(cell)
			.unwrap_or_default();
		if current.capacity != 0.0 {
			self.geom(cell, GeomCmd::Capacity(0.0));
		}
		if current.reservoir {
			self.geom(cell, GeomCmd::Reservoir(false));
		}
		if self.sim.port_ref(self.key.cells).read(cell) != Some(GasCell::default()) {
			let _ = self.sim.port(self.key.cells).put(cell, GasCell::default());
		}
	}

	#[must_use]
	pub fn is_registered(&self, cell: u32) -> bool {
		self.masks.contains_key(&cell)
	}

	/// The planet id for an atmosphere string, registering its baseline.
	pub fn planet_id(&mut self, key: &str, baseline: GasCell) -> u8 {
		if let Some(&id) = self.planet_ids.get(key) {
			return id;
		}
		let mut planets = self
			.planets
			.write()
			.unwrap_or_else(std::sync::PoisonError::into_inner);
		if planets.len() >= 255 {
			return 0;
		}
		let id = u8::try_from(planets.len()).unwrap_or(0);
		planets.push(baseline);
		self.planet_ids.insert(key.to_owned(), id);
		id
	}

	/// Whether `a` and `b` are face neighbours that share air (as DM sees
	/// the geometry now).
	#[must_use]
	pub fn shares(&self, a: u32, b: u32) -> bool {
		Face::ALL
			.into_iter()
			.any(|f| self.dims.neighbor(a, f) == Some(b) && self.open(a, f).is_some())
	}

	/// The neighbour across `face` if air crosses it.
	#[must_use]
	pub fn open(&self, cell: u32, face: Face) -> Option<u32> {
		let geom = self.sim.port_ref(self.key.geometry);
		let ga = geom.read(cell)?;
		if !ga.is_node() || ga.blocked.contains(face) {
			return None;
		}
		let nb = self.dims.neighbor(cell, face)?;
		let gb = geom.read(nb)?;
		(gb.is_node() && !gb.blocked.contains(face.opposite())).then_some(nb)
	}

	/// Bits of the faces across which the cell shares air.
	#[must_use]
	pub fn open_dirs(&self, cell: u32) -> u8 {
		Face::ALL
			.into_iter()
			.filter(|&f| self.open(cell, f).is_some())
			.fold(0, |acc, f| acc | f.bit())
	}

	/// DM's diagnostic view: registered, mask, z links, z.
	#[must_use]
	pub fn info(&self, cell: u32) -> [f32; 4] {
		let z = cell / self.dims.layer_len();
		let mask = self.masks.get(&cell).copied();
		[
			f32::from(u8::from(mask.is_some())),
			f32::from(mask.unwrap_or(DirMask::ALL.0)),
			f32::from(self.z_links.get(z as usize).copied().unwrap_or(0)),
			z as f32,
		]
	}
}

// --- The gas world -------------------------------------------------------------

/// Counters for `auxmos_diagnostics` and the metrics.
#[derive(Clone, Copy, Debug, Default)]
pub struct Stats {
	pub ticks: u64,
	pub events: u64,
	pub reactions: u64,
	pub visuals: u64,
	pub pressure: u64,
	pub commands: u64,
	pub last_tick_us: f64,
	pub takes_reconciled: u64,
}

/// Every gas the DLL holds.
pub struct GasWorld {
	pub mains: Mains,
	pub field: Option<Field>,
	pub pipes: PipeNet,
	pub exchange: Arc<Exchange>,
	dirty: Dirty,
	mix_watches: MixWatches,
	pub stats: Stats,
	/// Wakes from gas watches since the reactor last collected them.
	pub wakes: Vec<Wake>,
	/// Overlay (commands, views) or fallback (main-thread deltas), chosen at
	/// field build.
	pub mode: Mode,
}

impl Default for GasWorld {
	fn default() -> Self {
		Self {
			mains: Mains::default(),
			field: None,
			pipes: PipeNet::new(),
			exchange: Arc::new(Exchange::default()),
			dirty: Dirty::default(),
			mix_watches: MixWatches::new(),
			stats: Stats::default(),
			wakes: Vec::new(),
			mode: Mode::Overlay,
		}
	}
}

thread_local! {
	static WORLD: RefCell<GasWorld> = RefCell::new(GasWorld::default());
}

/// Runs `f` on the gas world. Never call DM (which may call back into gas
/// binds) from inside `f`.
pub fn with_world<T>(f: impl FnOnce(&mut GasWorld) -> T) -> T {
	WORLD.with_borrow_mut(f)
}

/// Energy of a mixture as DM sees it, in `f64`.
fn energy_of(mix: &Mixture) -> f64 {
	f64::from(heat_capacity(&mix.moles_array())) * f64::from(mix.get_temperature())
}

/// Moles and energy of a mixture (every gas, then energy).
#[must_use]
pub fn amounts_of(mix: &Mixture) -> [f32; Q] {
	let mut out = [0.0; Q];
	out[..N].copy_from_slice(&mix.moles_array());
	out[N] = energy_of(mix) as f32;
	out
}

/// A mixture from a cell.
#[must_use]
pub fn mixture_of_cell(cell: &GasCell, volume: f32) -> Mixture {
	Mixture::from_parts(
		&cell.moles,
		cell.temperature_now(),
		volume,
		cell.is_immutable(),
	)
}

/// A cell holding a mixture's gas.
#[must_use]
pub fn cell_of_mixture(mix: &Mixture) -> GasCell {
	let mut cell = GasCell::new(mix.moles_array(), mix.get_temperature());
	if mix.is_immutable() {
		cell.flags |= flags::IMMUTABLE;
	}
	cell
}

fn mixture_of_pipe(gas: &PipeGas, volume: f64) -> Mixture {
	Mixture::from_parts(
		&gas.moles_f32(),
		gas.temperature_now(),
		volume as f32,
		false,
	)
}

impl GasWorld {
	/// Loads a mixture by value (turf and pipe gas are built on the fly).
	#[must_use]
	pub fn load(&self, r: MixRef) -> Option<Mixture> {
		match r {
			MixRef::Main(i) => self.mains.get(i).cloned(),
			MixRef::Pipe(s) => {
				let (gas, volume) = self.pipes.gas(s)?;
				Some(mixture_of_pipe(gas, volume))
			}
			MixRef::Turf(c) => {
				let field = self.field.as_ref()?;
				let (cell, geom) = field.read(c)?;
				let volume = if geom.capacity > 0.0 {
					geom.capacity
				} else {
					CELL_VOLUME
				};
				Some(mixture_of_cell(&cell, volume))
			}
		}
	}

	/// Stores `after` into `r`, which held `before` (as loaded). Turf writes
	/// become one command with the absolute difference (`rust_core.md` §3.2).
	pub fn store(&mut self, r: MixRef, before: &Mixture, after: &Mixture) {
		if before.same_state(after) {
			return;
		}
		match r {
			MixRef::Main(i) => {
				if let Some(m) = self.mains.get_mut(i) {
					*m = after.clone();
				}
				self.mains.bump(i);
				self.touched(r, after);
			}
			MixRef::Pipe(s) => {
				let (b, a) = (before.moles_array(), after.moles_array());
				let de = energy_of(after) - energy_of(before);
				let t = after.get_temperature();
				if let Some((gas, _)) = self.pipes.gas_mut(s) {
					for i in 0..N {
						if a[i] != b[i] {
							gas.moles[i] = (gas.moles[i] + f64::from(a[i] - b[i])).max(0.0);
						}
					}
					gas.energy = (gas.energy + de).max(0.0);
					gas.temperature = t;
				}
				self.touched(r, after);
			}
			MixRef::Turf(c) => {
				let Some(field) = self.field.as_mut() else {
					return;
				};
				let Some((cell, _)) = field.read(c) else {
					return;
				};
				if cell.is_immutable() {
					return;
				}
				let (b, a) = (before.moles_array(), after.moles_array());
				let mut d = [0.0f32; Q];
				for i in 0..N {
					d[i] = a[i] - b[i];
				}
				// Energy relative to the cell's own (exact) energy, so a
				// read-modify-write never adds rounding noise.
				let e_after = if after.get_temperature() == before.get_temperature() && a == b {
					f64::from(cell.energy)
				} else {
					energy_of(after)
				};
				d[N] = (e_after - f64::from(cell.energy)) as f32;
				if d.iter().all(|v| *v == 0.0) {
					return;
				}
				let _ = field.sim.port(field.key.cells).submit(c, GasCmd::Delta(d));
				self.stats.commands += 1;
				self.touched(r, after);
			}
		}
	}

	/// Steps device edges with a field-cell (turf) endpoint for `dt` seconds
	/// (M2, `simulation.md` §5): a vent pump or scrubber facing a turf on
	/// one side and a pipe region on the other. Region<->region edges are
	/// [`PipeNet::step_devices`]'s job; this one bridges the pipe network
	/// and the R6 gas field, each with its own storage, through the same
	/// [`GasWorld::load`]/[`GasWorld::store`] round trip every other turf
	/// gas write (DM's `adjust_gas`, `merge`, ...) already uses, so a
	/// device's turf write is exactly as safe as any other.
	pub fn step_turf_devices(&mut self, dt: f32) -> Vec<pipes::DeviceStep> {
		use vg_core::network::{Endpoint, Side};

		let ids: Vec<_> = self.pipes.net.devices().map(|(id, _)| id).collect();
		let mut out = Vec::with_capacity(ids.len());
		for id in ids {
			let Ok(dev) = self.pipes.net.device(id) else {
				continue;
			};
			if matches!(dev.data, device::DeviceParams::None) {
				continue;
			}
			let (cell, node, cell_is_a) = match (dev.a, dev.b) {
				(Endpoint::Cell(c), Endpoint::Node(n)) => (c, n, true),
				(Endpoint::Node(n), Endpoint::Cell(c)) => (c, n, false),
				_ => continue,
			};
			let key = dev.key;
			let params = dev.data.clone();
			let Side::Region(region) = self.pipes.net.resolve(Endpoint::Node(node)) else {
				continue;
			};

			// Idle-skip (M2 follow-up): a settled edge whose region and
			// turf cell haven't changed since its last step costs nothing
			// but two revision lookups, the same as `PipeNet::step_devices`
			// does for region<->region edges.
			let rev_region_before = self.pipes.region_revision(region);
			let rev_cell_before = self.revision(MixRef::Turf(cell));
			let (rev_a_before, rev_b_before) = if cell_is_a {
				(rev_cell_before, rev_region_before)
			} else {
				(rev_region_before, rev_cell_before)
			};
			if self.pipes.device_asleep(key, rev_a_before, rev_b_before) {
				continue;
			}

			let Ok(r) = self.pipes.net.region(region) else {
				continue;
			};
			let vol_region = *r.summary();
			let mut region_gas = *r.payload();

			let Some(before_mix) = self.load(MixRef::Turf(cell)) else {
				continue;
			};
			let Some(field) = self.field.as_ref() else {
				continue;
			};
			let Some((_, geom)) = field.read(cell) else {
				continue;
			};
			let vol_cell = f64::from(if geom.capacity > 0.0 { geom.capacity } else { CELL_VOLUME });
			let mut turf_gas = PipeGas::from_amounts(&amounts_of(&before_mix), before_mix.get_temperature());

			let report = if cell_is_a {
				device::step(&params, &mut turf_gas, vol_cell, &mut region_gas, vol_region, dt)
			} else {
				device::step(&params, &mut region_gas, vol_region, &mut turf_gas, vol_cell, dt)
			};

			let settled = report.moles == 0.0 && report.power_w == 0.0;
			if !settled {
				if let Ok(payload) = self.pipes.net.payload_mut(region) {
					*payload = region_gas;
				}
				self.pipes.touch_region(region);
				let after_mix = mixture_of_pipe(&turf_gas, vol_cell);
				self.store(MixRef::Turf(cell), &before_mix, &after_mix);
			}

			let rev_region_after = self.pipes.region_revision(region);
			let rev_cell_after = self.revision(MixRef::Turf(cell));
			let (rev_a_after, rev_b_after) = if cell_is_a {
				(rev_cell_after, rev_region_after)
			} else {
				(rev_region_after, rev_cell_after)
			};
			self.pipes.set_device_activity(key, settled, rev_a_after, rev_b_after);

			out.push(pipes::DeviceStep { key, report });
		}
		out
	}

	fn touched(&mut self, r: MixRef, after: &Mixture) {
		let id = r.id();
		if self.dirty.watched.contains_key(&id) {
			self.dirty.check(id, &Signature::of(after));
		}
		if let MixRef::Main(i) = r {
			if self.mix_watches.watched.contains_key(&i) {
				self.mix_watches.store.set(i, GasProbeCell::of(after));
			}
		}
	}

	#[must_use]
	pub fn revision(&self, r: MixRef) -> u32 {
		match r {
			MixRef::Main(i) => self.mains.revision(i),
			MixRef::Pipe(s) => self.pipes.revision(s),
			MixRef::Turf(c) => self
				.field
				.as_ref()
				.and_then(|f| f.read(c))
				.map_or(0, |(cell, _)| cell.revision()),
		}
	}

	/// Moves a whole turf cell's gas into main slot `dest` with a `Take`: the
	/// worker reports the exact value removed, and the difference from what
	/// DM saw is reconciled into `dest` when it arrives (R5).
	pub fn take_turf(&mut self, cell: u32, dest: u32) -> Option<Mixture> {
		let field = self.field.as_mut()?;
		let (seen, geom) = field.read(cell)?;
		if seen.is_immutable() || !geom.is_node() || geom.reservoir {
			return None;
		}
		let port = field.sim.port(field.key.cells);
		let taken = port.take(cell).ok()?.into_inner();
		let seq = port.last_seq();
		// Take resets the cell; keep what is not gas.
		let mut empty = GasCell {
			planet: seen.planet,
			temperature: seen.temperature,
			..GasCell::default()
		};
		empty.refresh_in(geom.capacity.max(1.0));
		let _ = port.submit(cell, GasCmd::Planet(seen.planet));
		field.takes.insert(
			seq,
			PendingTake {
				dest: MixRef::Main(dest),
				seen: taken.amounts(),
			},
		);
		Some(mixture_of_cell(&taken, geom.capacity))
	}

	/// Adds amounts to a mixture (reconciliations, released pipe gas,
	/// heat). Negative amounts clamp at zero.
	pub fn add_amounts(&mut self, r: MixRef, amounts: &[f32; Q], temperature_hint: f32) {
		match r {
			MixRef::Turf(c) => {
				if let Some(field) = self.field.as_mut() {
					let _ = field
						.sim
						.port(field.key.cells)
						.submit(c, GasCmd::Delta(*amounts));
				}
			}
			MixRef::Pipe(s) => {
				if let Some((gas, _)) = self.pipes.gas_mut(s) {
					for (moles, &amount) in gas.moles.iter_mut().zip(amounts.iter()).take(N) {
						*moles = (*moles + f64::from(amount)).max(0.0);
					}
					gas.energy = (gas.energy + f64::from(amounts[N])).max(0.0);
					if gas.total() > 0.0 && temperature_hint > 0.0 && gas.energy == 0.0 {
						gas.temperature = temperature_hint;
					}
				}
			}
			MixRef::Main(i) => {
				let Some(before) = self.mains.get(i).cloned() else {
					return;
				};
				if before.is_immutable() {
					return;
				}
				let mut moles = before.moles_array();
				for (m, a) in moles.iter_mut().zip(amounts) {
					*m = (*m + a).max(0.0);
				}
				let energy = (energy_of(&before) + f64::from(amounts[N])).max(0.0);
				let c = f64::from(heat_capacity(&moles));
				let t = if c > f64::from(crate::gas::constants::MINIMUM_HEAT_CAPACITY) {
					((energy / c) as f32).max(TCMB)
				} else if temperature_hint > 0.0 {
					temperature_hint
				} else {
					before.get_temperature()
				};
				let after = Mixture::from_parts(&moles, t, before.volume, false);
				let mut after = after;
				after.set_min_heat_capacity(before.min_heat_capacity());
				self.store(r, &before, &after);
			}
		}
	}

	// --- Dirty observations -------------------------------------------------

	pub fn watch_dirty(&mut self, id: u32, mask: u8) {
		let Some(r) = MixRef::from_id(id) else {
			return;
		};
		let sig = self
			.load(r)
			.map_or(Signature::of(&Mixture::new()), |m| Signature::of(&m));
		self.dirty.watched.insert(id, (mask, sig));
	}

	pub fn unwatch_dirty(&mut self, id: u32) {
		self.dirty.watched.remove(&id);
		self.dirty.dirty.remove(&id);
	}

	/// Checks every watched turf against the pinned view (turf gas changes
	/// on the worker, so it is not seen by `store`).
	fn check_watched_turfs(&mut self) {
		let ids: Vec<u32> = self
			.dirty
			.watched
			.keys()
			.copied()
			.filter(|&id| matches!(MixRef::from_id(id), Some(MixRef::Turf(_))))
			.collect();
		for id in ids {
			if let Some(m) = MixRef::from_id(id).and_then(|r| self.load(r)) {
				self.dirty.check(id, &Signature::of(&m));
			}
		}
	}

	/// Drains dirty notifications: id, mask pairs.
	pub fn drain_dirty(&mut self) -> Vec<(u32, u8)> {
		self.check_watched_turfs();
		let mut out: Vec<(u32, u8)> = self.dirty.dirty.drain().collect();
		out.sort_unstable();
		out
	}

	/// Drains dirty notifications with the control-relevant state of each
	/// mixture, `OBSERVATION_STRIDE` floats per record: id, mask, revision,
	/// pressure, temperature, volume, o2, co2, plasma, methane, n2o,
	/// volatile fuel, miasma, zauker, total moles.
	pub fn drain_observations(&mut self) -> Vec<f32> {
		use crate::gas::ids::*;
		let changes = self.drain_dirty();
		let gases = [
			GAS_OXYGEN,
			GAS_CARBON_DIOXIDE,
			GAS_PLASMA,
			GAS_METHANE,
			GAS_NITROUS_OXIDE,
			GAS_VOLATILE_FUEL,
			GAS_MIASMA,
			GAS_ZAUKER,
		];
		let mut values = Vec::with_capacity(changes.len() * OBSERVATION_STRIDE);
		for (id, mask) in changes {
			let Some(r) = MixRef::from_id(id) else {
				continue;
			};
			let Some(m) = self.load(r) else {
				continue;
			};
			#[allow(clippy::cast_precision_loss)]
			values.extend([
				id as f32,
				f32::from(mask),
				(self.revision(r) & 0x00FF_FFFF) as f32,
				m.return_pressure(),
				m.get_temperature(),
				m.volume,
			]);
			values.extend(gases.iter().map(|&g| m.get_moles(g)));
			values.push(m.total_moles());
		}
		values
	}

	// --- Reactor watches ------------------------------------------------------

	/// Registers a watch on gas handles (turf cells or main-owned mixtures;
	/// one kind per condition). Returns `(port, id)`: port 0 the turf field,
	/// 1 the main mixtures.
	///
	/// # Errors
	/// If the handles are invalid or mixed, or the condition is rejected.
	pub fn watch(&mut self, sub: u32, lane: Lane, cond: &Cond) -> Result<(u8, WatchId)> {
		let mut ids = Vec::new();
		cond_cells(cond, &mut ids);
		let refs: Vec<MixRef> = ids
			.iter()
			.map(|&id| MixRef::from_id(id).ok_or_else(|| eyre!("bad gas handle {id}")))
			.collect::<Result<_>>()?;
		if refs.iter().all(|r| matches!(r, MixRef::Turf(_))) {
			let field = self
				.field
				.as_mut()
				.ok_or_else(|| eyre!("the gas field is not built"))?;
			let cond = map_cells(cond, &|id| id - TURF_BASE);
			let id = field
				.sim
				.watches(field.watch)
				.watch(sub, lane, &cond)
				.map_err(|e| eyre!("{e:?}"))?;
			return Ok((0, id));
		}
		if refs.iter().all(|r| matches!(r, MixRef::Main(_))) {
			let id = self
				.mix_watches
				.port
				.watch(sub, lane, cond)
				.map_err(|e| eyre!("{e:?}"))?;
			for &slot in &ids {
				*self.mix_watches.watched.entry(slot).or_default() += 1;
				if let Some(m) = self.mains.get(slot) {
					let p = GasProbeCell::of(m);
					self.mix_watches.store.set(slot, p);
				}
			}
			self.mix_watches.cells.insert(id, ids);
			return Ok((1, id));
		}
		bail!(
			"gas watches take turf gas or main-owned mixtures (not pipes), one kind per condition"
		)
	}

	pub fn unwatch(&mut self, port: u8, id: WatchId) {
		if port == 0 {
			if let Some(field) = self.field.as_mut() {
				let _ = field.sim.watches(field.watch).unwatch(id);
			}
			return;
		}
		let _ = self.mix_watches.port.unwatch(id);
		for slot in self.mix_watches.cells.remove(&id).unwrap_or_default() {
			if let Some(n) = self.mix_watches.watched.get_mut(&slot) {
				*n -= 1;
				if *n == 0 {
					self.mix_watches.watched.remove(&slot);
				}
			}
		}
	}

	/// Evaluates main-mixture watches and hands every pending gas wake to
	/// `out` (the reactor).
	pub fn take_wakes(&mut self, out: &mut Vec<Wake>) {
		self.mix_watches.evaluate(&mut self.wakes);
		out.append(&mut self.wakes);
	}

	// --- Ticks ------------------------------------------------------------

	/// Applies the heat world's energy and refreshes its probes.
	pub fn exchange_heat(&mut self) {
		let pending = std::mem::take(
			&mut *self
				.exchange
				.pending
				.lock()
				.unwrap_or_else(std::sync::PoisonError::into_inner),
		);
		for (gas, e) in pending {
			let r = match gas {
				vg_heat::GasRef::Turf(c) => Some(MixRef::Turf(c)),
				vg_heat::GasRef::Mixture(id) => MixRef::from_id(id),
			};
			if let Some(r) = r {
				let mut d = [0.0; Q];
				d[N] = e;
				self.add_amounts(r, &d, 0.0);
			}
		}
		let mut ids: Vec<u32> = std::mem::take(
			&mut *self
				.exchange
				.requests
				.lock()
				.unwrap_or_else(std::sync::PoisonError::into_inner),
		);
		{
			let probes = self
				.exchange
				.probes
				.lock()
				.unwrap_or_else(std::sync::PoisonError::into_inner);
			ids.extend(probes.keys().copied());
		}
		ids.sort_unstable();
		ids.dedup();
		let mut fresh = HashMap::with_capacity(ids.len());
		for id in ids {
			let Some(r) = MixRef::from_id(id) else {
				continue;
			};
			if matches!(r, MixRef::Turf(_)) {
				continue;
			}
			if let Some(m) = self.load(r) {
				fresh.insert(
					id,
					vg_heat::GasProbe {
						temperature: m.get_temperature(),
						capacity: m.heat_capacity(),
						reservoir: m.is_immutable(),
					},
				);
			}
		}
		*self
			.exchange
			.probes
			.lock()
			.unwrap_or_else(std::sync::PoisonError::into_inner) = fresh;
	}

	/// One SSair tick: pin the newest view, reconcile takes, collect events
	/// and wakes, apply heat, start the next frame. Returns DM's events as
	/// flat `kind, cell, value, extra` records.
	pub fn tick(&mut self, dispatch: bool) -> Vec<f32> {
		let start = std::time::Instant::now();
		self.stats.ticks += 1;
		let mut flat = Vec::new();
		if self.field.is_none() {
			return flat;
		}
		self.exchange_heat();
		let field = self.field.as_mut().expect("checked");
		field.sim.begin_tick();
		let out = field.sim.drain(field.key.cells);
		{
			let views = (
				Arc::clone(field.sim.port_ref(field.key.cells).pinned()),
				Arc::clone(field.sim.port_ref(field.key.geometry).pinned()),
			);
			*self
				.exchange
				.views
				.lock()
				.unwrap_or_else(std::sync::PoisonError::into_inner) = Some(views);
		}
		let takes: Vec<(PendingTake, [f32; Q])> = out
			.takes()
			.iter()
			.filter_map(|t| field.takes.remove(&t.seq).map(|p| (p, t.value.amounts())))
			.collect();
		for w in out.wakes() {
			self.wakes.push(Wake {
				source: w.source + TURF_BASE,
				..*w
			});
		}
		for e in out.events() {
			match e.kind {
				EventKind::ReactionCheck => self.stats.reactions += 1,
				EventKind::VisualChange => self.stats.visuals += 1,
				EventKind::PressureJump => self.stats.pressure += 1,
				_ => {}
			}
			#[allow(clippy::cast_precision_loss)]
			flat.extend([
				f32::from(e.kind as u8),
				e.key as f32,
				e.value,
				e.extra as f32,
			]);
		}
		self.stats.events += out.events().len() as u64;
		if dispatch {
			// A settled station costs nothing: no frame while nothing is awake
			// or queued (a command, a mask, a watch or heat wakes it again).
			if field.idle() {
				field.idle_skips += 1;
			} else if field.sim.dispatch_frame() {
				field.frames += 1;
			}
		}
		for (take, exact) in takes {
			let mut d = [0.0; Q];
			for i in 0..Q {
				d[i] = exact[i] - take.seen[i];
			}
			if d.iter().any(|v| *v != 0.0) {
				self.add_amounts(take.dest, &d, 0.0);
			}
			self.stats.takes_reconciled += 1;
		}
		self.stats.last_tick_us = start.elapsed().as_secs_f64() * 1e6;
		flat
	}

	/// Runs `n` frames to completion, one after another, and returns the
	/// events they produced (the test hook: deterministic, no wall clock).
	pub fn run_frames(&mut self, n: u32) -> Vec<f32> {
		let mut flat = Vec::new();
		for _ in 0..n {
			if let Some(f) = self.field.as_mut() {
				f.sim.wait_for_frame();
			}
			flat.extend(self.tick(true));
			if let Some(f) = self.field.as_mut() {
				f.sim.wait_for_frame();
			}
		}
		flat.extend(self.tick(false));
		flat
	}

	/// What flowed into space and planet reservoirs so far.
	#[must_use]
	pub fn field_ledger(&self) -> Vec<f64> {
		self.field
			.as_ref()
			.map_or_else(|| vec![0.0; Q], Field::ledger)
	}

	/// Totals of every conserved quantity DM and the worker hold: main
	/// mixtures, pipes, turf cells (pinned view; call after `run_frames`)
	/// and the field's reservoir ledger. For conservation tests.
	#[must_use]
	pub fn totals(&self) -> [f64; Q] {
		let mut out = self.mains.totals();
		for (o, v) in out.iter_mut().zip(self.pipes.totals()) {
			*o += v;
		}
		if let Some(field) = &self.field {
			let cells = field.sim.port_ref(field.key.cells).pinned();
			let geom = field.sim.port_ref(field.key.geometry).pinned();
			let t = FieldState::<TurfGas>::totals(cells.store(), geom.store());
			for (o, v) in out.iter_mut().zip(t) {
				*o += v;
			}
		}
		out
	}
}
