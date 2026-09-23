//! The heat domain in the DLL (M4): the binds DM calls and the gas adapter.
//!
//! This replaces `superconduct.rs`. The physics lives in `vg-heat` (host
//! tested); this module owns the one [`HeatWorld`] (a main-thread value, kept
//! in a thread local because BYOND calls every bind on its one thread), and
//! implements [`GasExchange`] over the turf gas arena so the heat frame's
//! coupling tasks can move energy into and out of gas.
//!
//! DM pushes each turf's thermal values (`vg_heat_set_turf`, or the bulk
//! form at round start) instead of Rust reading turf vars, reads turf and
//! body temperatures, adds heat, creates and releases heat bodies, and
//! registers temperature watches. SSair drives the frames with
//! `vg_heat_tick(seconds)` and drains wakes and crossings afterwards.

use super::*;
use crate::gas::constants::TCMB as GAS_TCMB;
use std::cell::RefCell;
use std::sync::Arc;
use vg_core::outbox::Lane;
use vg_core::watch::Cmp;
use vg_heat::body::{BodyCmd, Coupling, Phase, Target};
use vg_heat::consts as hc;
use vg_heat::world::{CellKind, CellSpec, HeatConfig, WatchCond, WatchTarget};
use vg_heat::{Body, GasExchange, GasProbe, GasRef, HeatWorld};

thread_local! {
	static HEAT: RefCell<Option<HeatWorld>> = const { RefCell::new(None) };
}

/// Gas mixtures whose temperature moved (fed from `mark_dirty_if_changed`),
/// turned into turf cells for the solid ↔ gas coupling.
static GAS_TEMPERATURE_CHANGED: Mutex<Vec<usize>> = const_mutex(Vec::new());

/// Called by the gas arena when a mixture's temperature moves past its dirty
/// threshold (was `superconduct::mark_heat_dirty`).
pub(crate) fn gas_temperature_changed(mix: usize) {
	GAS_TEMPERATURE_CHANGED.lock().push(mix);
}

fn with_heat<T>(f: impl FnOnce(&mut HeatWorld) -> T) -> Option<T> {
	HEAT.with_borrow_mut(|h| h.as_mut().map(f))
}

/// The heat domain's view of the gas arena. Never blocks a frame thread on
/// a busy gas: every lock is a `try`, and a miss retries next frame.
struct ArenaGas;

impl ArenaGas {
	/// The mixture id of a gas reference.
	fn mix_of(gas: GasRef) -> Option<usize> {
		match gas {
			GasRef::Mixture(id) => Some(id as usize),
			GasRef::Turf(cell) => {
				let arena = TURF_GASES.try_read()?;
				let arena = arena.as_ref()?;
				let node = arena.get_id(cell)?;
				let turf = arena.get(node)?;
				turf.enabled().then_some(turf.mix)
			}
		}
	}

	fn probe_mixture(gas: &Mixture) -> GasProbe {
		GasProbe {
			temperature: gas.get_temperature(),
			capacity: gas.heat_capacity(),
			reservoir: gas.is_immutable(),
		}
	}
}

impl GasExchange for ArenaGas {
	fn probe(&self, gas: GasRef) -> Option<GasProbe> {
		let mix = Self::mix_of(gas)?;
		GasArena::with_all_mixtures(|all| {
			let entry = all.get(mix)?.try_read()?;
			Some(Self::probe_mixture(&entry))
		})
	}

	fn exchange(&self, gas: GasRef, f: &mut dyn FnMut(GasProbe) -> f32) -> Option<f32> {
		// Topology changes take TASKS for writing; hold it shared so a turf's
		// mixture cannot be swapped under the exchange (as superconduct did).
		let _topology = TASKS.try_read()?;
		let mix = Self::mix_of(gas)?;
		let _single_writer = GasArena::try_begin_solver_transaction()?;
		GasArena::with_all_mixtures(|all| {
			let mut entry = all.get(mix)?.try_write()?;
			let probe = Self::probe_mixture(&entry);
			let e = f(probe);
			if e == 0.0 || !e.is_finite() {
				return Some(0.0);
			}
			if probe.reservoir {
				// Immutable space/planet air: the energy leaves the books.
				return Some(e);
			}
			let capacity = probe.capacity;
			if capacity <= 0.0 {
				return Some(0.0);
			}
			let before = GasArena::change_signature(&entry);
			let t = (probe.temperature + e / capacity).max(GAS_TCMB);
			entry.set_temperature(t);
			let applied = (entry.get_temperature() - probe.temperature) * capacity;
			let after = GasArena::change_signature(&entry);
			let changed = GasArena::signature_changed(&before, &after);
			drop(entry);
			if GasArena::mark_dirty_if_changed(mix, before, after) {
				GasArena::bump_revision(mix);
			} else if changed {
				GasArena::bump_revision_only(mix);
			}
			Some(applied)
		})
	}

	fn take_changed(&self, out: &mut Vec<u32>) {
		let mixes = std::mem::take(&mut *GAS_TEMPERATURE_CHANGED.lock());
		if mixes.is_empty() {
			return;
		}
		let Some(map) = MIX_TO_TURF.try_read() else {
			// Busy: put them back for the next frame.
			GAS_TEMPERATURE_CHANGED.lock().extend(mixes);
			return;
		};
		if let Some(map) = map.as_ref() {
			out.extend(mixes.iter().filter_map(|m| map.get(m).map(|h| h.id)));
		}
	}
}

/// Headroom for z-levels created at run time (expeditions): the grid is
/// sized once, and cells past it are ignored.
fn z_capacity(max_z: u32) -> u32 {
	max_z.saturating_mul(2).max(256).max(max_z + 1)
}

/// Creates or grows the heat world (called by `auxmos_configure_world`).
pub(super) fn configure_heat(max_x: u32, max_y: u32, max_z: u32) -> Result<()> {
	HEAT.with_borrow_mut(|h| {
		if let Some(world) = h.as_ref() {
			let d = world.dims();
			if d.max_x() == max_x && d.max_y() == max_y && max_z <= d.max_z() {
				return Ok(());
			}
		}
		let Some(dims) = GridDims::new(max_x.max(1), max_y.max(1), z_capacity(max_z)) else {
			eyre::bail!("heat grid {max_x}x{max_y}x{max_z} does not fit a u32 index");
		};
		let world = HeatWorld::new(HeatConfig::new(dims), Arc::new(ArenaGas))
			.map_err(|e| eyre::eyre!("heat sim failed to build: {e:?}"))?;
		*h = Some(world);
		Ok(())
	})
}

/// Drops the heat world (world boot, before `auxmos_configure_world`), so a
/// rebooted world starts with no stale cells or bodies.
#[auxmacros::bind("/proc/heat_reset")]
fn heat_reset() -> Result<ByondValue> {
	HEAT.with_borrow_mut(|h| *h = None);
	GAS_TEMPERATURE_CHANGED.lock().clear();
	Ok(ByondValue::null())
}

// ------------------------------------------------------------------ turfs

/// `HEAT_CELL_*` kinds DM sends.
/// @dm-define HEAT_CELL_SOLID
pub const HEAT_CELL_SOLID: i32 = 0;
/// @dm-define HEAT_CELL_SPACE
pub const HEAT_CELL_SPACE: i32 = 1;
/// @dm-define HEAT_CELL_PLANET
pub const HEAT_CELL_PLANET: i32 = 2;

fn cell_spec(
	kind: f32,
	capacity: f32,
	conductivity: f32,
	emissivity: f32,
	temperature: f32,
	air: bool,
) -> CellSpec {
	let kind = match kind as i32 {
		HEAT_CELL_SPACE => CellKind::Space,
		HEAT_CELL_PLANET => CellKind::Planet,
		HEAT_CELL_SOLID => CellKind::Solid,
		// Unknown kinds are ordinary solids.
		_ => CellKind::Solid,
	};
	let mut spec = CellSpec {
		kind,
		capacity,
		conductivity,
		emissivity,
		temperature,
		air,
	};
	if kind == CellKind::Space {
		spec.capacity = spec.capacity.max(hc::HEAT_CAPACITY_VACUUM);
		spec.temperature = hc::TCMB;
	}
	spec
}

/// Registers or updates one turf's solid heat cell: its kind
/// (`HEAT_CELL_*`), heat capacity (J/K), `thermal_conductivity`,
/// emissivity, temperature (used only for a new cell) and whether it has
/// air. A capacity of 0 removes it.
#[auxmacros::bind("/turf/proc/heat_set_turf")]
fn heat_set_turf(
	turf: ByondValue,
	kind: ByondValue,
	capacity: ByondValue,
	conductivity: ByondValue,
	emissivity: ByondValue,
	temperature: ByondValue,
	air: ByondValue,
) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	let spec = cell_spec(
		kind.get_number()?,
		capacity.get_number()?,
		conductivity.get_number()?,
		emissivity.get_number()?,
		temperature.get_number()?,
		air.is_true(),
	);
	Ok(with_heat(|w| w.set_cell(cell, spec))
		.unwrap_or(false)
		.into())
}

/// Bulk form of `heat_set_turf`: a flat list of `[turf, kind, capacity,
/// conductivity, emissivity, temperature, air]` records, one FFI call.
#[auxmacros::bind("/proc/heat_set_turfs_bulk")]
fn heat_set_turfs_bulk(records: ByondValue) -> Result<ByondValue> {
	let values = records.get_list_values()?;
	let mut set = 0u32;
	with_heat(|w| -> Result<()> {
		for r in values.chunks_exact(7) {
			let Ok(cell) = r[0].get_ref() else {
				continue;
			};
			let spec = cell_spec(
				r[1].get_number()?,
				r[2].get_number()?,
				r[3].get_number()?,
				r[4].get_number()?,
				r[5].get_number()?,
				r[6].is_true(),
			);
			if w.set_cell(cell, spec) {
				set += 1;
			}
		}
		Ok(())
	})
	.transpose()?;
	Ok((set as f32).into())
}

/// Removes a turf from the heat field.
#[auxmacros::bind("/turf/proc/heat_clear_turf")]
fn heat_clear_turf(turf: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	with_heat(|w| w.clear_cell(cell));
	Ok(ByondValue::null())
}

/// The turf's solid temperature (K), or null if the turf is not in the
/// heat field (DM then uses its `temperature` var).
#[auxmacros::bind("/turf/proc/heat_turf_temperature")]
fn heat_turf_temperature(turf: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	Ok(with_heat(|w| w.cell_temperature(cell))
		.flatten()
		.filter(|t| t.is_finite())
		.map_or_else(ByondValue::null, ByondValue::from))
}

/// Adds heat (J) to the turf's solid. Returns 1 if the turf took it.
#[auxmacros::bind("/turf/proc/heat_add_turf")]
fn heat_add_turf(turf: ByondValue, joules: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	let joules = joules.get_number()?;
	Ok(with_heat(|w| w.add_cell_heat(cell, joules))
		.unwrap_or(false)
		.into())
}

/// Sets the turf's solid temperature (DM authority). Returns 1 on success.
#[auxmacros::bind("/turf/proc/heat_set_turf_temperature")]
fn heat_set_turf_temperature(turf: ByondValue, temperature: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	let t = temperature.get_number()?;
	Ok(with_heat(|w| w.set_cell_temperature(cell, t))
		.unwrap_or(false)
		.into())
}

/// `list(heat capacity, conductivity, emissivity)` of a turf's cell, or null.
#[auxmacros::bind("/turf/proc/heat_turf_properties")]
fn heat_turf_properties(turf: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	let Some((c, k, e)) = with_heat(|w| w.cell_properties(cell)).flatten() else {
		return Ok(ByondValue::null());
	};
	let list = ByondValue::new_list()?;
	list.write_list(&[c.into(), k.into(), e.into()])?;
	Ok(list)
}

// ----------------------------------------------------------------- bodies

/// Coupling target kinds DM sends.
/// @dm-define HEAT_TARGET_NONE
pub const HEAT_TARGET_NONE: i32 = 0;
/// A turf's solid cell (target: the turf).
/// @dm-define HEAT_TARGET_SOLID
pub const HEAT_TARGET_SOLID: i32 = 1;
/// A turf's air (target: the turf).
/// @dm-define HEAT_TARGET_TURF_AIR
pub const HEAT_TARGET_TURF_AIR: i32 = 2;
/// A gas mixture (target: its arena id).
/// @dm-define HEAT_TARGET_MIXTURE
pub const HEAT_TARGET_MIXTURE: i32 = 3;
/// Another body (target: its handle).
/// @dm-define HEAT_TARGET_BODY
pub const HEAT_TARGET_BODY: i32 = 4;

fn target(kind: &ByondValue, target: &ByondValue) -> Result<Target> {
	Ok(match kind.get_number()? as i32 {
		HEAT_TARGET_SOLID => Target::Solid(target.get_ref()?),
		HEAT_TARGET_TURF_AIR => Target::Gas(GasRef::Turf(target.get_ref()?)),
		HEAT_TARGET_MIXTURE => Target::Gas(GasRef::Mixture(target.get_number()? as u32)),
		HEAT_TARGET_BODY => Target::Body(target.get_number()? as u32 & (hc::MAX_BODIES - 1)),
		HEAT_TARGET_NONE => Target::None,
		other => eyre::bail!("bad heat target kind {other}"),
	})
}

fn handle(h: &ByondValue) -> Option<u32> {
	h.get_number().ok().filter(|n| *n >= 0.0).map(|n| n as u32)
}

/// Creates a heat body: capacity (J/K), temperature (K), one coupling
/// (`HEAT_TARGET_*`, target, conductance W/K), and whether DM keeps it
/// (no release at equilibrium). Returns the handle, or null when full.
#[auxmacros::bind("/proc/heat_body_create")]
fn heat_body_create(
	capacity: ByondValue,
	temperature: ByondValue,
	target_kind: ByondValue,
	target_ref: ByondValue,
	conductance: ByondValue,
	keep: ByondValue,
) -> Result<ByondValue> {
	let mut body = Body::new(capacity.get_number()?, temperature.get_number()?).with_coupling(
		0,
		Coupling::new(
			target(&target_kind, &target_ref)?,
			conductance.get_number()?,
		),
	);
	if keep.is_true() {
		body = body.kept();
	}
	Ok(with_heat(|w| w.create_body(body))
		.flatten()
		.map_or_else(ByondValue::null, |h| (h as f32).into()))
}

/// A body's temperature (K), or null if the handle is dead (the body was
/// released: the atom is back at its surroundings' temperature).
#[auxmacros::bind("/proc/heat_body_temperature")]
fn heat_body_temperature(h: ByondValue) -> Result<ByondValue> {
	let Some(h) = handle(&h) else {
		return Ok(ByondValue::null());
	};
	Ok(with_heat(|w| w.body_temperature(h))
		.flatten()
		.map_or_else(ByondValue::null, ByondValue::from))
}

fn body_cmd(h: &ByondValue, cmd: BodyCmd) -> ByondValue {
	let Some(h) = handle(h) else {
		return false.into();
	};
	with_heat(|w| w.body_command(h, cmd))
		.unwrap_or(false)
		.into()
}

/// Adds heat (J) to a body. Returns 0 if the handle is dead.
#[auxmacros::bind("/proc/heat_body_add")]
fn heat_body_add(h: ByondValue, joules: ByondValue) -> Result<ByondValue> {
	Ok(body_cmd(&h, BodyCmd::AddHeat(joules.get_number()?)))
}

/// Sets coupling 0 or 1 of a body.
#[auxmacros::bind("/proc/heat_body_couple")]
fn heat_body_couple(
	h: ByondValue,
	slot: ByondValue,
	target_kind: ByondValue,
	target_ref: ByondValue,
	conductance: ByondValue,
) -> Result<ByondValue> {
	let c = Coupling::new(
		target(&target_kind, &target_ref)?,
		conductance.get_number()?,
	);
	Ok(body_cmd(
		&h,
		BodyCmd::Couple(slot.get_number()?.clamp(0.0, 1.0) as u8, c),
	))
}

/// Sets a body's sustained source (W; negative is a sink).
#[auxmacros::bind("/proc/heat_body_power")]
fn heat_body_power(h: ByondValue, watts: ByondValue) -> Result<ByondValue> {
	Ok(body_cmd(&h, BodyCmd::Power(watts.get_number()?)))
}

/// Changes a body's heat capacity, keeping its temperature.
#[auxmacros::bind("/proc/heat_body_capacity")]
fn heat_body_capacity(h: ByondValue, capacity: ByondValue) -> Result<ByondValue> {
	Ok(body_cmd(&h, BodyCmd::Capacity(capacity.get_number()?)))
}

/// Sets a body's phase plateau: latent heat (J) at a phase temperature (K).
#[auxmacros::bind("/proc/heat_body_phase")]
fn heat_body_phase(
	h: ByondValue,
	temperature: ByondValue,
	latent: ByondValue,
) -> Result<ByondValue> {
	Ok(body_cmd(
		&h,
		BodyCmd::Phase(Phase {
			temperature: temperature.get_number()?,
			latent: latent.get_number()?,
		}),
	))
}

/// Sets a body's temperature (DM authority).
#[auxmacros::bind("/proc/heat_body_set_temperature")]
fn heat_body_set_temperature(h: ByondValue, temperature: ByondValue) -> Result<ByondValue> {
	Ok(body_cmd(
		&h,
		BodyCmd::SetTemperature(temperature.get_number()?),
	))
}

/// Keeps a body (never released at equilibrium) or lets it go.
#[auxmacros::bind("/proc/heat_body_keep")]
fn heat_body_keep(h: ByondValue, keep: ByondValue) -> Result<ByondValue> {
	Ok(body_cmd(&h, BodyCmd::Keep(keep.is_true())))
}

/// Releases a body: its excess heat goes to its environment and the handle
/// dies at once.
#[auxmacros::bind("/proc/heat_body_release")]
fn heat_body_release(h: ByondValue) -> Result<ByondValue> {
	if let Some(h) = handle(&h) {
		with_heat(|w| w.release_body(h));
	}
	Ok(ByondValue::null())
}

/// Energy (J) that left the body through coupling 0 in its last settle or
/// step (positive: out of the body). For thermoelectric conversion.
#[auxmacros::bind("/proc/heat_body_flow")]
fn heat_body_flow(h: ByondValue) -> Result<ByondValue> {
	let Some(h) = handle(&h) else {
		return Ok(0.0f32.into());
	};
	Ok(with_heat(|w| w.body(h).map(|b| b.flow))
		.flatten()
		.unwrap_or(0.0)
		.into())
}

// ---------------------------------------------------------------- watches

/// Watch kinds.
/// @dm-define HEAT_WATCH_ABOVE
pub const HEAT_WATCH_ABOVE: i32 = 0;
/// @dm-define HEAT_WATCH_BELOW
pub const HEAT_WATCH_BELOW: i32 = 1;
/// @dm-define HEAT_WATCH_BAND
pub const HEAT_WATCH_BAND: i32 = 2;
/// @dm-define HEAT_WATCH_SET
pub const HEAT_WATCH_SET: i32 = 3;

/// Registers a temperature watch on a turf's solid (`on_body` false: the
/// target is the turf) or a body (the target is its handle). `kind` is
/// `HEAT_WATCH_*`; `level` is the limit for above/below (and `both` fires on
/// leaving too) or a list of levels for a band. Lane: 0 urgent, 1 normal,
/// 2 background. Returns the watch handle; a bad watch is a runtime.
#[auxmacros::bind("/proc/heat_watch")]
fn heat_watch(
	on_body: ByondValue,
	target_ref: ByondValue,
	subscriber: ByondValue,
	lane: ByondValue,
	kind: ByondValue,
	level: ByondValue,
	both: ByondValue,
) -> Result<ByondValue> {
	let target = if on_body.is_true() {
		WatchTarget::Body(handle(&target_ref).ok_or_else(|| eyre::eyre!("bad body handle"))?)
	} else {
		WatchTarget::Cell(target_ref.get_ref()?)
	};
	let both = both.is_true();
	let cond = match kind.get_number()? as i32 {
		HEAT_WATCH_ABOVE => WatchCond::Above {
			limit: level.get_number()?,
			both,
		},
		HEAT_WATCH_BELOW => WatchCond::Below {
			limit: level.get_number()?,
			both,
		},
		HEAT_WATCH_BAND => WatchCond::Band(
			level
				.get_list_values()?
				.iter()
				.map(|v| v.get_number())
				.collect::<Result<Vec<_>, _>>()?,
		),
		HEAT_WATCH_SET => WatchCond::Set,
		other => eyre::bail!("bad heat watch kind {other}"),
	};
	let lane = Lane::from_id(lane.get_number()? as u8).unwrap_or(Lane::Normal);
	let subscriber = subscriber.get_number()? as u32;
	let id = with_heat(|w| w.watch(target, subscriber, lane, &cond))
		.ok_or_else(|| eyre::eyre!("heat domain is not configured"))?
		.map_err(|e| eyre::eyre!("bad heat watch: {e}"))?;
	Ok((id as f32).into())
}

/// Adds (or replaces) a `HEAT_WATCH_SET` entry: payload, generation,
/// `HEAT_WATCH_ABOVE`/`BELOW`, limit (K), and whether leaving fires too.
#[auxmacros::bind("/proc/heat_watch_set_add")]
fn heat_watch_set_add(
	watch: ByondValue,
	payload: ByondValue,
	generation: ByondValue,
	cmp: ByondValue,
	limit: ByondValue,
	both: ByondValue,
) -> Result<ByondValue> {
	let cmp = if cmp.get_number()? as i32 == HEAT_WATCH_BELOW {
		Cmp::Below
	} else {
		Cmp::Above
	};
	with_heat(|w| {
		w.set_add(
			watch.get_number()? as u32,
			payload.get_number()? as u32,
			generation.get_number()? as u32,
			cmp,
			limit.get_number()?,
			both.is_true(),
		)
		.map_err(|e| eyre::eyre!("{e}"))
	})
	.transpose()?;
	Ok(ByondValue::null())
}

/// Removes a `HEAT_WATCH_SET` entry.
#[auxmacros::bind("/proc/heat_watch_set_remove")]
fn heat_watch_set_remove(watch: ByondValue, payload: ByondValue) -> Result<ByondValue> {
	let (watch, payload) = (watch.get_number()? as u32, payload.get_number()? as u32);
	with_heat(|w| w.set_remove(watch, payload).ok());
	Ok(ByondValue::null())
}

/// Removes a watch (a stale handle is ignored).
#[auxmacros::bind("/proc/heat_unwatch")]
fn heat_unwatch(watch: ByondValue) -> Result<ByondValue> {
	let watch = watch.get_number()? as u32;
	with_heat(|w| w.unwatch(watch).ok());
	Ok(ByondValue::null())
}

// ------------------------------------------------------------------- tick

/// One heat tick: collect the finished frame, then dispatch the next when
/// `seconds` of game time make one due. Never waits. Returns the number of
/// wakes plus crossings waiting for `vg_heat_take_wakes()`.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/heat_tick")]
fn heat_tick(seconds: ByondValue) -> Result<ByondValue> {
	let seconds = seconds.get_number()?;
	Ok(with_heat(|w| {
		w.tick(seconds);
		w.pending_notices() as f32
	})
	.unwrap_or(0.0)
	.into())
}

/// Takes the wakes and `ThresholdSet` crossings collected so far, as one flat
/// list: `[count of wakes]`, then `[subscriber, watch, reason, source]` per
/// wake, then `[watch, payload, entered, generation]` per crossing.
#[auxmacros::bind("/proc/heat_take_wakes")]
fn heat_take_wakes() -> Result<ByondValue> {
	let mut flat = Vec::new();
	with_heat(|w| {
		let mut wakes = Vec::new();
		w.take_wakes(&mut wakes);
		flat.push((wakes.len() / 4) as f32);
		flat.extend(wakes);
		for (watch, payload, entered, generation) in w.drain_crossings() {
			flat.extend_from_slice(&[
				watch as f32,
				payload as f32,
				if entered { 1.0 } else { 0.0 },
				generation as f32,
			]);
		}
	});
	let list = ByondValue::new_list()?;
	let values: Vec<ByondValue> = flat.into_iter().map(ByondValue::from).collect();
	list.write_list(&values)?;
	Ok(list)
}

/// Runs `frames` heat frames to completion, blocking. Unit tests only.
#[auxmacros::bind("/proc/heat_debug_run_frames")]
fn heat_debug_run_frames(frames: ByondValue) -> Result<ByondValue> {
	let n = frames.get_number()?.clamp(0.0, 10_000.0) as u32;
	with_heat(|w| {
		w.settle();
		w.run_frames(n);
	});
	Ok(ByondValue::null())
}

/// `list(TCMB, T0C, T20C, space sky temperature, Stefan–Boltzmann constant,
/// default emissivity, seconds per heat frame, normal body temperature, human
/// heat capacity, ignition temperature, vacuum heat capacity)`. DM gets these
/// as generated defines; the unit tests compare the two (H1).
#[auxmacros::bind("/proc/heat_constants")]
fn heat_constants() -> Result<ByondValue> {
	let list = ByondValue::new_list()?;
	list.write_list(&[
		hc::TCMB.into(),
		hc::T0C.into(),
		hc::T20C.into(),
		hc::SPACE_SKY_TEMPERATURE.into(),
		(hc::STEFAN_BOLTZMANN as f32).into(),
		hc::DEFAULT_EMISSIVITY.into(),
		hc::HEAT_DT.into(),
		hc::BODYTEMP_NORMAL.into(),
		hc::HUMAN_HEAT_CAPACITY.into(),
		hc::IGNITION_TEMPERATURE.into(),
		hc::HEAT_CAPACITY_VACUUM.into(),
	])?;
	Ok(list)
}

/// `(frames dispatched, live bodies, last frame µs)` for diagnostics.
pub(crate) fn heat_diagnostics() -> (usize, usize, u64) {
	with_heat(|w| {
		let (dispatched, _completed, micros, bodies) = w.diagnostics();
		(dispatched as usize, bodies, micros)
	})
	.unwrap_or((0, 0, 0))
}

#[cfg(test)]
mod constant_tests {
	use super::hc;
	use crate::gas::constants as gc;

	/// The gas crate keeps its own copies of the shared temperatures; they must
	/// equal the heat constants DM's defines are generated from (B12).
	#[test]
	fn gas_constants_match_heat_constants() {
		assert_eq!(gc::TCMB, hc::TCMB);
		assert_eq!(gc::T0C, hc::T0C);
		assert_eq!(gc::T20C, hc::T20C);
		assert!((gc::FIRE_MINIMUM_TEMPERATURE_TO_EXIST - hc::IGNITION_TEMPERATURE).abs() < 1e-4);
		assert!((gc::PLASMA_MINIMUM_BURN_TEMPERATURE - hc::IGNITION_TEMPERATURE).abs() < 1e-4);
	}
}
