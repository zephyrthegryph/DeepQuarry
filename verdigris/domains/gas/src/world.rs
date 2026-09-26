//! The gas world: every gas the DLL holds, by owner (`rust_core.md` §3.1).
//!
//! - **Main-owned mixtures** ([`Mains`]): tanks, lungs, canisters, device
//!   buffers and scratch mixtures. DM reads and writes them synchronously,
//!   with no staleness.
//! - **Turf gas**: the cells of the [`TurfGas`] field on the shared
//!   `vg_core::world::World`, reached through [`TurfAccess`]. DM reads the
//!   pinned view plus its own writes (the overlay); DM writes are
//!   [`GasCmd`]s with absolute amounts.
//! - **Pipe gas**: region payloads of the pipe network on the shared World,
//!   reached through [`PipeAccess`].
//!
//! A `/datum/gas_mixture` holds one number, its handle ([`MixRef`]), in
//! `_extools_pointer_gasmixture`. Every DM gas proc goes through
//! [`with_mix`](crate::gas::with_mix) / [`with_mix_mut`](crate::gas::with_mix_mut),
//! which dispatch on the owner, so DM's gas API (`return_air`, `remove`,
//! `merge`, `get_moles`, ...) is unchanged.

use std::cell::RefCell;
use std::collections::HashMap;

use byondapi::prelude::*;
use eyre::{bail, eyre, Result};
use vg_core::cow::{ChunkLayout, CowStore};
use vg_core::field::Geom;
use vg_core::outbox::{Lane, Outbox, Wake, WatchId};
use vg_core::watch::{Cond, WatchPort, WatchState};

use crate::cell::{flags, heat_capacity, GasCell, GasCmd, N, Q};
use crate::gas::constants::{CELL_VOLUME, TCMB};
use crate::gas::Mixture;
use crate::pipes::PipeGas;

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
//
// The slab itself lives in `verdigris/ffi/src/gas.rs` (`MainsStore`): main-
// owned mixtures are FFI state, the same as the reaction table and the
// pipe region slot compaction this file's `PipeAccess` already bridges.
// `GasWorld` reaches it through the installed [`MainsAccess`] below --
// [`Mains`] is a stateless facade over that bridge, kept so `GasWorld`'s own
// field (`mains: Mains`) and every existing call site (`w.mains.alloc(...)`,
// `.get(...)`, `.free(...)`, `.live()`, `.capacity()`) keep their shape.

/// What `GasWorld` needs from the DLL's main-owned mixture slab. Installed
/// once by the FFI crate at DLL init (`crate::gas::install_mains_access`);
/// domain-crate tests install their own in-memory double instead
/// (`tests.rs`'s `world()`).
pub trait MainsAccess {
	/// Allocates a slot for `mix`. `None`: every main handle is in use.
	fn alloc(&self, mix: Mixture) -> Option<u32>;
	/// Frees a live slot. A no-op if it's already free.
	fn free(&self, i: u32);
	/// The slot's mixture, or `None` if it isn't live.
	fn get(&self, i: u32) -> Option<Mixture>;
	/// Replaces a live slot's mixture and bumps its revision. A no-op if
	/// the slot isn't live.
	fn set(&self, i: u32, mix: Mixture);
	fn revision(&self, i: u32) -> u32;
	fn live(&self) -> usize;
	fn capacity(&self) -> usize;
	/// Total gas (moles + energy) over every live slot, for conservation
	/// checks.
	fn totals(&self) -> [f64; Q];
}

thread_local! {
	static MAINS_ACCESS: RefCell<Option<Box<dyn MainsAccess>>> = const { RefCell::new(None) };
}

/// Installs the main-owned-mixture bridge (`verdigris_init`/DLL load, or a
/// domain-crate test's own setup).
pub fn install_mains_access(access: Box<dyn MainsAccess>) {
	MAINS_ACCESS.with_borrow_mut(|p| *p = Some(access));
}

fn with_mains_access<T>(f: impl FnOnce(&dyn MainsAccess) -> T) -> Option<T> {
	MAINS_ACCESS.with_borrow(|p| p.as_deref().map(f))
}

/// Facade over the installed [`MainsAccess`] bridge -- see the section docs
/// above.
#[derive(Default, Clone, Copy)]
pub struct Mains;

impl Mains {
	/// Allocates a slot.
	///
	/// # Errors
	/// If every main handle is in use, or nothing installed [`MainsAccess`]
	/// yet.
	pub fn alloc(&mut self, mix: Mixture) -> Result<u32> {
		with_mains_access(|a| a.alloc(mix))
			.flatten()
			.ok_or_else(|| eyre!("out of main gas mixture handles ({PIPE_BASE}), or no mains access installed"))
	}

	pub fn free(&mut self, i: u32) {
		with_mains_access(|a| a.free(i));
	}

	#[must_use]
	pub fn get(&self, i: u32) -> Option<Mixture> {
		with_mains_access(|a| a.get(i)).flatten()
	}

	pub fn set(&mut self, i: u32, mix: Mixture) {
		with_mains_access(|a| a.set(i, mix));
	}

	#[must_use]
	pub fn revision(&self, i: u32) -> u32 {
		with_mains_access(|a| a.revision(i)).unwrap_or(0)
	}

	#[must_use]
	pub fn live(&self) -> usize {
		with_mains_access(|a| a.live()).unwrap_or(0)
	}

	#[must_use]
	pub fn capacity(&self) -> usize {
		with_mains_access(|a| a.capacity()).unwrap_or(0)
	}

	#[must_use]
	pub fn totals(&self) -> [f64; Q] {
		with_mains_access(|a| a.totals()).unwrap_or([0.0; Q])
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


// --- Turf gas ------------------------------------------------------------------

/// Turf gas lives in the [`crate::cell::TurfGas`] field on the shared
/// `vg_core::world::World`, which this crate cannot reach (`vg-gas` has no
/// dependency on `vg-ffi`); `MixRef::Turf`'s accessors reach it through
/// this bridge, installed once by the FFI crate, like [`PipeAccess`].
pub trait TurfAccess {
	/// The cell's gas and its geometry, as DM sees them now.
	fn read(&self, cell: u32) -> Option<(GasCell, Geom)>;
	/// Submits a command to the cell.
	fn submit(&self, cell: u32, cmd: GasCmd);
}

thread_local! {
	static TURF_ACCESS: RefCell<Option<Box<dyn TurfAccess>>> = const { RefCell::new(None) };
}

/// Installs the turf-access bridge (`verdigris_init`/DLL load).
pub fn install_turf_access(access: Box<dyn TurfAccess>) {
	TURF_ACCESS.with_borrow_mut(|p| *p = Some(access));
}

fn turf_read(cell: u32) -> Option<(GasCell, Geom)> {
	TURF_ACCESS.with_borrow(|p| p.as_deref().and_then(|a| a.read(cell)))
}

fn turf_submit(cell: u32, cmd: GasCmd) {
	TURF_ACCESS.with_borrow(|p| {
		if let Some(a) = p.as_deref() {
			a.submit(cell, cmd);
		}
	});
}

// --- The gas world -------------------------------------------------------------

/// Every gas the DLL holds, as DM's gas procs see it.
pub struct GasWorld {
	pub mains: Mains,
	dirty: Dirty,
	mix_watches: MixWatches,
}

impl Default for GasWorld {
	fn default() -> Self {
		Self {
			mains: Mains,
			dirty: Dirty::default(),
			mix_watches: MixWatches::new(),
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

/// Pipe regions live on the shared `vg_core::world::World`
/// (`rust_architecture.md` §6, §8.5, step 5: `verdigris/ffi/src/pipes.rs`'s
/// `NetworkHost<Pipes>`), which this crate cannot reach directly (`vg-gas`
/// has no dependency on `vg-ffi`). `MixRef::Pipe`'s generic accessors
/// (`load`/`store`/`revision`, so every existing `/datum/gas_mixture` proc
/// -- `return_temperature`, `merge`, `adjust_gas`, ... -- keeps working on
/// a pipe-bound mixture unchanged) reach it through this trait instead,
/// installed once by the FFI crate at DLL init -- the same shape
/// [`Exchange`]/[`HeatGas`] already bridge gas data *out* to the heat
/// world; this bridges pipe data *in*.
pub trait PipeAccess {
	/// The region's gas and volume (L), by its DM-facing slot.
	fn probe(&self, slot: u32) -> Option<(PipeGas, f64)>;
	/// Replaces the region's gas.
	fn apply(&self, slot: u32, gas: &PipeGas);
	/// The region's revision (bumped on every write, including this one).
	fn revision(&self, slot: u32) -> u32;
}

thread_local! {
	static PIPE_ACCESS: RefCell<Option<Box<dyn PipeAccess>>> = const { RefCell::new(None) };
}

/// Installs the pipe-access bridge (`verdigris_init`/DLL load).
pub fn install_pipe_access(access: Box<dyn PipeAccess>) {
	PIPE_ACCESS.with_borrow_mut(|p| *p = Some(access));
}

fn with_pipe_access<T>(f: impl FnOnce(&dyn PipeAccess) -> T) -> Option<T> {
	PIPE_ACCESS.with_borrow(|p| p.as_deref().map(f))
}

pub fn mixture_of_pipe(gas: &PipeGas, volume: f64) -> Mixture {
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
			MixRef::Main(i) => self.mains.get(i),
			MixRef::Pipe(s) => {
				let (gas, volume) = with_pipe_access(|p| p.probe(s))??;
				Some(mixture_of_pipe(&gas, volume))
			}
			MixRef::Turf(c) => {
				let (cell, geom) = turf_read(c)?;
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
				self.mains.set(i, after.clone());
				self.touched(r, after);
			}
			MixRef::Pipe(s) => {
				let (b, a) = (before.moles_array(), after.moles_array());
				let de = energy_of(after) - energy_of(before);
				let t = after.get_temperature();
				if let Some((mut gas, _)) = with_pipe_access(|p| p.probe(s)).flatten() {
					for i in 0..N {
						if a[i] != b[i] {
							gas.moles[i] = (gas.moles[i] + f64::from(a[i] - b[i])).max(0.0);
						}
					}
					gas.energy = (gas.energy + de).max(0.0);
					gas.temperature = t;
					with_pipe_access(|p| p.apply(s, &gas));
				}
				self.touched(r, after);
			}
			MixRef::Turf(c) => {
				let Some((cell, _)) = turf_read(c) else {
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
				turf_submit(c, GasCmd::Delta(d));
				self.touched(r, after);
			}
		}
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
			MixRef::Pipe(s) => with_pipe_access(|p| p.revision(s)).unwrap_or(0),
			MixRef::Turf(c) => turf_read(c).map_or(0, |(cell, _)| cell.revision()),
		}
	}

	/// Adds amounts to a mixture (reconciliations, released pipe gas,
	/// heat). Negative amounts clamp at zero.
	pub fn add_amounts(&mut self, r: MixRef, amounts: &[f32; Q], temperature_hint: f32) {
		match r {
			MixRef::Turf(c) => turf_submit(c, GasCmd::Delta(*amounts)),
			MixRef::Pipe(s) => {
				if let Some((mut gas, _)) = with_pipe_access(|p| p.probe(s)).flatten() {
					for (moles, &amount) in gas.moles.iter_mut().zip(amounts.iter()).take(N) {
						*moles = (*moles + f64::from(amount)).max(0.0);
					}
					gas.energy = (gas.energy + f64::from(amounts[N])).max(0.0);
					if gas.total() > 0.0 && temperature_hint > 0.0 && gas.energy == 0.0 {
						gas.temperature = temperature_hint;
					}
					with_pipe_access(|p| p.apply(s, &gas));
				}
			}
			MixRef::Main(i) => {
				let Some(before) = self.mains.get(i) else {
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

	// --- Reactor watches on main-owned mixtures --------------------------------

	/// Registers a watch on main-owned mixture handles.
	///
	/// # Errors
	/// If a handle is not a main-owned mixture, or the condition is rejected.
	pub fn watch(&mut self, sub: u32, lane: Lane, cond: &Cond) -> Result<WatchId> {
		let mut ids = Vec::new();
		cond_cells(cond, &mut ids);
		if !ids.iter().all(|&id| matches!(MixRef::from_id(id), Some(MixRef::Main(_)))) {
			bail!("a main-mixture watch takes main-owned mixture handles only");
		}
		let id = self.mix_watches.port.watch(sub, lane, cond).map_err(|e| eyre!("{e:?}"))?;
		for &slot in &ids {
			*self.mix_watches.watched.entry(slot).or_default() += 1;
			if let Some(m) = self.mains.get(slot) {
				self.mix_watches.store.set(slot, GasProbeCell::of(&m));
			}
		}
		self.mix_watches.cells.insert(id, ids);
		Ok(id)
	}

	pub fn unwatch(&mut self, id: WatchId) {
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
		self.mix_watches.evaluate(out);
	}

}
