//! Turf binds: the world grid, turf registration and air-block masks, the
//! adjacency reads DM asks for, and the SSair tick.
//!
//! Turf adjacency comes from the air-block masks DM publishes (M1a): each is
//! the turf's `blocked` geometry in the gas field, one `GeomCmd` per change.
//! Readers see their own writes at once through the overlay, so there are
//! no topology barriers or transactions: a shuttle move or an explosion is
//! a run of commands the next frame applies in order.

use byondapi::prelude::*;
use eyre::{bail, Result};
use vg_core::field::{FieldKind, Side};
use vg_core::grid::Face;
use vg_core::sim::Mode;

use crate::cell::{GasCell, TurfGas};
use crate::gas::constants::CELL_VOLUME;
use crate::world::{cell_of_mixture, with_world, Field, GasWorld, MixRef, OBSERVATION_STRIDE};

/// Every face a mask can block (`NORTH|SOUTH|EAST|WEST|UP|DOWN`).
/// @dm-define AIR_BLOCK_ALL
pub const AIR_BLOCK_ALL: u8 = 63;

/// Mask argument meaning "keep the mask Rust already has for this turf".
/// @dm-define AIR_BLOCK_KEEP
pub const AIR_BLOCK_KEEP: i32 = -1;

/// Registration flag DM passes for a simulated turf.
/// @dm-define SIMULATION_ANY
pub const DM_SIMULATION_ANY: u8 = 3;

/// Numbers per event returned by `gas_tick`: kind, turf, value, other turf.
/// @dm-define GAS_EVENT_STRIDE
pub const GAS_EVENT_STRIDE: u32 = 4;
/// A turf's gas may react (`air.react(turf)`).
/// @dm-define GAS_EVENT_REACT
pub const GAS_EVENT_REACT: u32 = 2;
/// A turf's visible gas changed (`set_visuals()`).
/// @dm-define GAS_EVENT_VISUAL
pub const GAS_EVENT_VISUAL: u32 = 3;
/// Spacewind: `turf.consider_pressure_difference(other, value)`.
/// @dm-define GAS_EVENT_PRESSURE
pub const GAS_EVENT_PRESSURE: u32 = 1;

const _: () = {
	assert!(GAS_EVENT_REACT == vg_core::outbox::EventKind::ReactionReady as u32);
	assert!(GAS_EVENT_VISUAL == vg_core::outbox::EventKind::VisualChange as u32);
	assert!(GAS_EVENT_PRESSURE == vg_core::outbox::EventKind::PressureJump as u32);
	assert!(OBSERVATION_STRIDE == crate::GAS_OBSERVATION_STRIDE);
};

fn mask_from_value(mask: &ByondValue) -> Option<u8> {
	mask.get_number()
		.ok()
		.filter(|&m| m >= 0.0)
		.map(|m| (m as u8) & AIR_BLOCK_ALL)
}

fn turf_value(cell: u32) -> ByondValue {
	ByondValue::new_ref(ValueType::Turf, cell)
}

fn list_of(values: Vec<ByondValue>) -> Result<ByondValue> {
	let list = ByondValue::new_list()?;
	list.write_list(&values)?;
	Ok(list)
}

fn floats(values: &[f32]) -> Result<ByondValue> {
	list_of(values.iter().map(|&v| ByondValue::from(v)).collect())
}

// --- World grid -------------------------------------------------------------

/// Overlay (commands, views, overlay) unless `DQ_GAS_FALLBACK` asks for the
/// main-thread fallback (`rust_core.md` §3.11); see the M1b notes in
/// `verdigris/README.md` for the measurement that chose overlay.
fn gas_mode() -> Mode {
	match std::env::var("DQ_GAS_FALLBACK") {
		Ok(v) if !v.is_empty() && v != "0" => Mode::Fallback {
			budget_cells: v.parse().unwrap_or(4096),
		},
		_ => Mode::Overlay,
	}
}

/// Creates the gas field for the map (or grows it). A grid that keeps its
/// x and y keeps every turf's cell index, so its cells are copied over.
fn configure(w: &mut GasWorld, max_x: u32, max_y: u32, max_z: u32) -> Result<()> {
	if let Some(field) = &w.field {
		let d = field.dims;
		if d.max_x() == max_x && d.max_y() == max_y && max_z <= d.max_z() {
			return Ok(());
		}
	}
	let mut field = Field::new(max_x, max_y, max_z, gas_mode(), &w.exchange)?;
	if let Some(mut old) = w.field.take() {
		if old.dims.max_x() == max_x && old.dims.max_y() == max_y {
			old.sim.settle();
			old.copy_into(&mut field);
		}
	}
	w.mode = field.mode;
	w.field = Some(field);
	Ok(())
}

/// Args: (maxx, maxy, maxz). Sizes the gas field (and the heat field) for
/// the map. Called at world start and when the map grows.
#[auxmacros::bind("/proc/auxmos_configure_world")]
fn configure_world(max_x: ByondValue, max_y: ByondValue, max_z: ByondValue) -> Result<ByondValue> {
	let max_x = max_x.get_number()?.max(1.0) as u32;
	let max_y = max_y.get_number()?.max(1.0) as u32;
	let max_z = max_z.get_number()?.max(1.0) as u32;
	with_world(|w| configure(w, max_x, max_y, max_z))?;
	vg_ffi::reactor::register_domain(vg_ffi::reactor::DOMAIN_GAS, Box::new(GasDomain));
	#[cfg(feature = "heat")]
	crate::heat::configure_heat(max_x, max_y, max_z)?;
	Ok(ByondValue::null())
}

/// Args: (links). One entry per z-level: the `UP`/`DOWN` bits of the levels
/// air may cross into. Vertical faces open only between linked levels.
#[auxmacros::bind("/datum/controller/subsystem/air/proc/auxmos_set_z_links")]
fn set_z_links(links: ByondValue) -> Result<ByondValue> {
	// get_list_values, not iter(): iter() indexes the list by each item.
	let links = links
		.get_list_values()?
		.iter()
		.map(|value| value.get_number().unwrap_or(0.0) as u8)
		.collect::<Vec<_>>();
	with_world(|w| {
		if let Some(field) = w.field.as_mut() {
			field.set_z_links(links);
		}
	});
	Ok(ByondValue::null())
}

/// Gas as a reactor domain: `REACT_ON` / `REACT_WHEN` on gas handles (turf
/// gas by its turf's air handle, or a main-owned mixture). One kind of
/// handle per condition.
struct GasDomain;

impl vg_ffi::reactor::ExternalDomain for GasDomain {
	fn channels(&self) -> Vec<vg_core::channel::ChannelInfo> {
		vg_core::channel::channel_infos::<TurfGas>()
	}

	fn watch(
		&mut self,
		sub: u32,
		lane: vg_core::outbox::Lane,
		cond: &vg_core::watch::Cond,
	) -> Result<(u8, vg_core::outbox::WatchId)> {
		with_world(|w| w.watch(sub, lane, cond))
	}

	fn unwatch(&mut self, port: u8, id: vg_core::outbox::WatchId) {
		with_world(|w| w.unwatch(port, id));
	}

	fn take_wakes(&mut self, out: &mut Vec<vg_core::outbox::Wake>) {
		with_world(|w| w.take_wakes(out));
	}
}

// --- Registration -------------------------------------------------------------

fn is_set(value: Result<f32, byondapi::Error>) -> bool {
	value.is_ok_and(|n| n != 0.0)
}

/// Registers (flag >= 0) or removes (flag < 0) a turf's gas.
///
/// A turf's own `air` datum moves into its field cell (the datum's handle
/// becomes the cell's). Space's shared immutable vacuum stays a main-owned
/// mixture; its cells are reservoirs. Planet turfs are reservoirs that
/// relax back to their atmosphere when DM disturbs them.
fn register_turf(w: &mut GasWorld, src: ByondValue, flag: i32, mask: Option<u8>) -> Result<()> {
	let cell = src.get_ref()?;
	let Some(field) = w.field.as_mut() else {
		return Ok(());
	};
	if !field.contains(cell) {
		return Ok(());
	}
	if flag < 0 || is_set(src.read_number_id(byond_string!("blocks_air"))) {
		field.unregister(cell);
		return Ok(());
	}
	let Ok(mut air) = src.read_var_id(byond_string!("air")) else {
		return Ok(());
	};
	if air.is_null() {
		field.unregister(cell);
		return Ok(());
	}
	let r = MixRef::of(&air)?;
	if r == MixRef::Turf(cell) {
		// Already this turf's cell: the mask and the planet flag can change.
		let planet = is_set(src.read_number_id(byond_string!("planetary_atmos")));
		let (value, _) = field.read(cell).unwrap_or_default();
		if planet != (value.planet > 0) {
			let mut value = value;
			value.planet = if planet {
				let key = src
					.read_string_id(byond_string!("initial_gas_mix"))
					.unwrap_or_default();
				field.planet_id(&key, value)
			} else {
				0
			};
			field.register(cell, value, CELL_VOLUME, planet, mask);
		} else if field.is_registered(cell) {
			field.set_mask(cell, mask);
		} else {
			let (value, geom) = field.read(cell).unwrap_or_default();
			let reservoir = geom.reservoir;
			field.register(cell, value, CELL_VOLUME, reservoir, mask);
		}
		return Ok(());
	}
	let Some(mix) = w.load(r) else {
		bail!("turf air has no gas mixture ({r:?})");
	};
	let field = w.field.as_mut().expect("checked above");
	let immutable =
		mix.is_immutable() || is_set(src.read_number_id(byond_string!("immutable_atmos")));
	let mut value = cell_of_mixture(&mix);
	if immutable {
		value.flags |= crate::cell::flags::IMMUTABLE;
		field.register(cell, value, mix.volume, true, mask);
		// Shared vacuum: the datum stays main-owned.
		return Ok(());
	}
	let planet = is_set(src.read_number_id(byond_string!("planetary_atmos")));
	if planet {
		let key = src
			.read_string_id(byond_string!("initial_gas_mix"))
			.unwrap_or_default();
		value.planet = field.planet_id(&key, value);
	}
	field.register(cell, value, mix.volume, planet, mask);
	if let MixRef::Main(slot) = r {
		w.mains.free(slot);
	}
	MixRef::Turf(cell).store(&mut air)?;
	Ok(())
}

/// Args: (flag, mask). Registers (flag >= 0) or removes (flag < 0) this
/// turf's gas and publishes its air-block mask (`AIR_BLOCK_KEEP` keeps the
/// current one). Reads blocks_air, air, immutable_atmos, planetary_atmos and
/// initial_gas_mix.
#[auxmacros::bind("/turf/proc/update_air_ref")]
fn hook_register_turf(src: ByondValue, flag: ByondValue, mask: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let mask = mask_from_value(&mask);
	with_world(|w| register_turf(w, src, flag, mask))?;
	Ok(ByondValue::null())
}

/// Bulk registration for round start and map loads. Args: (turfs, flag),
/// where `turfs` is an assoc list of turf -> air-block mask.
#[auxmacros::bind("/proc/_auxmos_register_turfs_bulk")]
fn hook_register_turfs_bulk(list: ByondValue, flag: ByondValue) -> Result<ByondValue> {
	let flag = flag.get_number()? as i32;
	let turfs = list.iter()?.collect::<Vec<_>>();
	with_world(|w| -> Result<()> {
		for (turf, mask) in &turfs {
			register_turf(w, *turf, flag, mask_from_value(mask))?;
		}
		Ok(())
	})?;
	Ok(ByondValue::null())
}

/// This turf's gas revision (bumped whenever its gas changes).
#[auxmacros::bind("/turf/proc/air_revision")]
fn hook_air_revision(src: ByondValue) -> Result<ByondValue> {
	let cell = src.get_ref()?;
	#[allow(clippy::cast_precision_loss)]
	Ok(with_world(|w| (w.revision(MixRef::Turf(cell)) & 0x00FF_FFFF) as f32).into())
}

// --- Adjacency reads ----------------------------------------------------------

fn with_field<T>(default: T, f: impl FnOnce(&Field) -> T) -> T {
	with_world(|w| w.field.as_ref().map_or(default, f))
}

fn open_neighbors(field: &Field, cell: u32) -> Vec<u32> {
	Face::ALL
		.into_iter()
		.filter_map(|f| field.open(cell, f))
		.collect()
}

/// Returns: the turfs this turf shares air with (face neighbours only).
#[auxmacros::bind("/proc/atmos_adjacent_turfs")]
fn atmos_adjacent_turfs(turf: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	let cells = with_field(Vec::new(), |f| open_neighbors(f, cell));
	list_of(cells.into_iter().map(turf_value).collect())
}

/// Batched form of `atmos_adjacent_turfs`: a list of lists, one per turf.
#[auxmacros::bind("/proc/atmos_adjacent_turfs_bulk")]
fn atmos_adjacent_turfs_bulk(turfs: ByondValue) -> Result<ByondValue> {
	let cells = turfs
		.get_list_values()?
		.iter()
		.map(ByondValue::get_ref)
		.collect::<Result<Vec<_>, _>>()?;
	let lists = with_field(Vec::new(), |f| {
		cells.iter().map(|&c| open_neighbors(f, c)).collect()
	});
	let mut out = Vec::with_capacity(cells.len());
	for i in 0..cells.len() {
		let cells = lists.get(i).cloned().unwrap_or_default();
		out.push(list_of(cells.into_iter().map(turf_value).collect())?);
	}
	list_of(out)
}

/// Returns: the direction bits (NORTH..DOWN) across which this turf shares air.
#[auxmacros::bind("/proc/atmos_open_dirs")]
fn atmos_open_dirs(turf: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	Ok(f32::from(with_field(0, |f| f.open_dirs(cell))).into())
}

/// Diagnostic: list(registered, mask, z-level links, zero-based z).
#[auxmacros::bind("/proc/atmos_cell_info")]
fn atmos_cell_info(turf: ByondValue) -> Result<ByondValue> {
	let cell = turf.get_ref()?;
	floats(&with_field(
		[0.0, f32::from(AIR_BLOCK_ALL), 0.0, 0.0],
		|f| f.info(cell),
	))
}

/// Returns: whether two turfs are face neighbours that share air.
#[auxmacros::bind("/proc/atmos_turfs_share")]
fn atmos_turfs_share(first: ByondValue, second: ByondValue) -> Result<ByondValue> {
	let (a, b) = (first.get_ref()?, second.get_ref()?);
	Ok(with_field(false, |f| f.shares(a, b)).into())
}

/// Diagnostic invariant for shuttle and atmos tests: the turf's air datum
/// names its field cell (or the shared vacuum), and the cell's geometry is
/// what the turf's mask says.
#[auxmacros::bind("/proc/_auxmos_topology_matches")]
fn topology_matches(src: ByondValue) -> Result<ByondValue> {
	let cell = src.get_ref()?;
	let air = src.read_var_id(byond_string!("air"))?;
	let r = MixRef::of(&air).ok();
	Ok(with_world(|w| {
		let Some(field) = w.field.as_ref() else {
			return false;
		};
		let Some((value, geom)) = field.read(cell) else {
			return false;
		};
		let bound = r == Some(MixRef::Turf(cell)) || value.is_immutable();
		bound && geom.is_node() && field.is_registered(cell)
	})
	.into())
}

/// Diagnostic: whether the turf's gas is still moving (some open edge is
/// not settled).
#[auxmacros::bind("/turf/proc/auxmos_is_atmos_active")]
fn turf_active_hook(src: ByondValue) -> Result<ByondValue> {
	let cell = src.get_ref()?;
	Ok(with_field(false, |f| {
		let Some((a, ga)) = f.read(cell) else {
			return false;
		};
		if !ga.is_node() || ga.reservoir {
			return false;
		}
		Face::ALL.into_iter().any(|face| {
			let Some(nb) = f.open(cell, face) else {
				return false;
			};
			let Some((b, gb)) = f.read(nb) else {
				return false;
			};
			// Holding air next to vacuum is not settled until it is gone.
			!TurfGas::settled(side(&a, ga), side(&b, gb))
		})
	})
	.into())
}

// --- The tick -----------------------------------------------------------------

fn side(cell: &GasCell, g: vg_core::field::Geom) -> Side<'_, GasCell> {
	Side {
		cell,
		capacity: g.capacity,
		inv_capacity: g.inv_capacity(),
		reservoir: g.reservoir,
		share: 1.0 / 6.0,
	}
}

fn events_list(flat: &[f32]) -> Result<ByondValue> {
	let mut out = Vec::with_capacity(flat.len());
	for e in flat.chunks_exact(4) {
		out.push(ByondValue::from(e[0]));
		out.push(turf_value(e[1] as u32));
		out.push(ByondValue::from(e[2]));
		out.push(if e[0] as u32 == GAS_EVENT_PRESSURE {
			turf_value(e[3] as u32)
		} else {
			ByondValue::null()
		});
	}
	list_of(out)
}

/// One SSair tick: pin the newest turf gas, collect its events and watch
/// wakes, apply heat, start the next frame. Never waits. Returns the events
/// as `GAS_EVENT_STRIDE` values each: `GAS_EVENT_*`, turf, value, other turf.
#[auxmacros::bind("/proc/gas_tick")]
fn gas_tick() -> Result<ByondValue> {
	let flat = with_world(|w| w.tick(true));
	events_list(&flat)
}

/// Test hook: runs `frames` gas frames to completion, one after another,
/// deterministically (no wall clock), and returns their events like
/// `gas_tick`.
#[auxmacros::bind("/proc/gas_run_frames")]
fn gas_run_frames(frames: ByondValue) -> Result<ByondValue> {
	let n = frames.get_number()?.clamp(0.0, 100_000.0) as u32;
	let flat = with_world(|w| w.run_frames(n));
	events_list(&flat)
}

/// `list(frames, commands, events, reactions, visuals, pressure, takes
/// reconciled, last tick µs, last frame µs, command backlog, overlay entries,
/// view age, frames skipped, removal shortfall (mol), fallback pieces applied,
/// fallback pieces rejected, mode, idle frames skipped, active chunks last
/// step)`.
#[auxmacros::bind("/proc/gas_stats")]
fn gas_stats() -> Result<ByondValue> {
	let v = with_world(|w| {
		let s = w.stats;
		let (frames, m, shortfall, fb, idle_skips, awake_chunks) =
			w.field.as_ref().map_or(
				(0, vg_core::sim::SimMetrics::default(), 0.0, None, 0, 0),
				|f| {
					(
						f.frames,
						f.sim.metrics().clone(),
						f.sim.port_ref(f.key.cells).pinned().shortfall_total(),
						f.sim.port_ref(f.key.cells).fallback_stats(),
						f.idle_skips,
						f.awake_chunks(),
					)
				},
			);
		#[allow(clippy::cast_precision_loss)]
		[
			frames as f32,
			s.commands as f32,
			s.events as f32,
			s.reactions as f32,
			s.visuals as f32,
			s.pressure as f32,
			s.takes_reconciled as f32,
			s.last_tick_us as f32,
			m.last_frame.as_secs_f32() * 1e6,
			m.command_backlog as f32,
			m.overlay_entries as f32,
			m.view_age_ticks as f32,
			m.dispatches_skipped as f32,
			shortfall as f32,
			fb.map_or(0.0, |f| f.applied_pieces as f32),
			fb.map_or(0.0, |f| f.rejected_pieces as f32),
			if matches!(w.mode, Mode::Overlay) {
				0.0
			} else {
				1.0
			},
			idle_skips as f32,
			awake_chunks as f32,
		]
	});
	floats(&v)
}

/// Conservation totals for tests: `list(moles, energy)` summed over every
/// main-owned mixture, pipe region and turf cell (pinned), plus what flowed
/// into reservoirs.
#[auxmacros::bind("/proc/gas_totals")]
fn gas_totals() -> Result<ByondValue> {
	let (moles, energy) = with_world(|w| {
		let t = w.totals();
		let ledger = w.field_ledger();
		let moles: f64 =
			t[..crate::cell::N].iter().sum::<f64>() + ledger[..crate::cell::N].iter().sum::<f64>();
		(moles, t[crate::cell::N] + ledger[crate::cell::N])
	});
	#[allow(clippy::cast_possible_truncation)]
	floats(&[moles as f32, energy as f32])
}

/// Diagnostics for SSair's stat panel: `list(main mixtures live, main slots,
/// pipe regions, pipe ports, registered turf cells, field frames)`.
pub(crate) fn diagnostics() -> [usize; 6] {
	with_world(|w| {
		[
			w.mains.live(),
			w.mains.capacity(),
			w.pipes.net.region_count(),
			w.pipes.port_count(),
			w.field.as_ref().map_or(0, Field::registered),
			w.field.as_ref().map_or(0, |f| f.frames as usize),
		]
	})
}
