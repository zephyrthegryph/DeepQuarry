//! Turf gas on the R6 field framework (`simulation.md` §1, §4).
//!
//! This module is pure (no `byondapi`): the cell value, the commands DM
//! sends, the flux law, the local reaction check and the channels. The DLL
//! side (`world.rs`) owns the [`Sim`](vg_core::sim::Sim) the field runs in.
//!
//! # The cell
//! A [`GasCell`] holds the conserved quantities, the moles of every gas and
//! the thermal energy (J), plus values `refresh` caches for channels and
//! DM reads: total moles, temperature and pressure. The cell's volume is the
//! geometry capacity. Space and planet atmospheres are reservoir cells
//! (geometry flag): the flux never changes them, and what flows in is
//! booked in the field's ledger.
//!
//! # The flux
//! Two of core's generic exchange kernels (`vg_core::field::kernel`),
//! summed, each getting half the edge's donor share:
//! - **bulk flow** (`kernel::pressure_flow`, the aperture kernel): moles
//!   move from the high-pressure side at rate `G (pa/na + pb/nb)` toward
//!   pressure equality, carrying the upwind side's composition and energy
//!   per mole;
//! - **diffusion** (`kernel::diffusion`): each gas (and the energy
//!   density) relaxes toward equal concentration at rate `K (1/Va + 1/Vb)`.
//!
//! Overshoot safety is the field framework's job, not this module's: it
//! picks a sub-step from [`TurfGas::stiffness`] so that `dt * faces *
//! stiffness <= 1` (the monotone bound of an explicit scheme), the same
//! generic guarantee every `FieldKind` gets. Each kernel also never takes
//! more than half the donor's `share` (the framework's positivity bound),
//! so all edges together never overdraw a cell even before sub-stepping.

use vg_core::field::kernel::{self, Amounts, Operand};
use vg_core::field::{FieldKind, Side};
use vg_core::owner::{Applied, Domain};

use crate::gas::constants::{
	CELL_VOLUME, GAS_MIN_MOLES, MINIMUM_HEAT_CAPACITY, R_IDEAL_GAS_EQUATION, TCMB,
};
use crate::gas::ids::GAS_COUNT;

/// Gases per cell.
pub const N: usize = GAS_COUNT;
/// Conserved quantities per cell: every gas, then energy.
pub const Q: usize = N + 1;

/// Specific heat of each gas (J/(mol K)), by gas ID. Gas IDs are fixed at
/// compile time (`ids.rs`), so their heat capacities are too; the gas
/// registry checks DM's `specific_heat` against this table at boot.
pub const SPECIFIC_HEATS: [f32; N] = [
	20.0,   // oxygen
	20.0,   // nitrogen
	30.0,   // carbon dioxide
	200.0,  // plasma
	40.0,   // water vapor
	2000.0, // hypernoblium
	40.0,   // nitrous oxide
	10.0,   // nitrium
	10.0,   // tritium
	20.0,   // bz
	80.0,   // pluoxium
	20.0,   // miasma
	600.0,  // freon
	15.0,   // hydrogen
	10.0,   // healium
	30.0,   // proto nitrate
	350.0,  // zauker
	175.0,  // halon
	15.0,   // helium
	1.0,    // antinoblium
	34.0,   // methane
	30.0,   // volatile fuel
];

/// Bulk-flow conductance, mol/(s kPa) per unit `p/n`: the pair's pressure
/// difference relaxes at `G (pa/na + pb/nb)` per second (about `2G` for two
/// standard cells, `G` against vacuum).
pub const BULK_CONDUCTANCE: f32 = 4.0;
/// Diffusion conductance, L/s: two standard cells relax their
/// concentration difference at `DIFFUSION_RATE` per second.
pub const DIFFUSION_RATE: f32 = 1.15;
const DIFFUSION_CONDUCTANCE: f32 = DIFFUSION_RATE * CELL_VOLUME / 2.0;

/// An edge sleeps below this difference in any gas, per standard cell (mol).
pub const SETTLED_MOLES: f32 = 0.05;
/// ... and below this temperature difference (K), unless a side is nearly empty.
pub const SETTLED_KELVIN: f32 = 0.5;
/// Revision bands (as machines' dirty observations: 0.5 kPa, 0.5 K; and
/// 0.05 mol in total).
pub const REVISION_KPA: f32 = 0.5;
pub const REVISION_KELVIN: f32 = 0.5;
pub const REVISION_MOLES: f32 = 0.05;
/// Pressure differences below this (kPa) do not add bulk flow to the
/// stiffness (they still flow).
const STIFF_PRESSURE: f32 = 1.0;

/// Cell flags.
pub mod flags {
	/// Space and immutable air: commands never change it.
	pub const IMMUTABLE: u8 = 1;
	/// The last `local` step found a reaction whose requirements hold.
	pub const REACT: u8 = 2;
	/// DM changed the cell since the last frame (its visuals must be
	/// refreshed even if the frame's start and end look alike).
	pub const TOUCHED: u8 = 4;
}

/// One turf's gas.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GasCell {
	/// Moles of each gas, by gas ID.
	pub moles: [f32; N],
	/// Thermal energy, J (`heat capacity * temperature`).
	pub energy: f32,
	/// Cached by `refresh` (and kept when the cell empties).
	pub temperature: f32,
	/// Cached by `refresh`, kPa.
	pub pressure: f32,
	/// Cached by `refresh`.
	pub total: f32,
	/// DM's `revision()`: bumped when pressure, temperature or total moles
	/// leave the band around their values at the last bump (the same bands
	/// as machines' dirty observations), never on settling drift.
	pub revision: u32,
	/// Pressure, temperature and total moles at the last revision bump.
	pub rev_at: [f32; 3],
	/// [`flags`].
	pub flags: u8,
	/// Planet atmosphere id (0: none). Planet cells are reservoirs that DM
	/// may disturb; the gas world relaxes them back to their atmosphere.
	pub planet: u8,
	/// Visible-gas signature (a changed signature is a `VisualChange`).
	pub vis: u16,
}

impl Default for GasCell {
	fn default() -> Self {
		Self {
			moles: [0.0; N],
			energy: 0.0,
			temperature: TCMB,
			pressure: 0.0,
			total: 0.0,
			revision: 0,
			rev_at: [0.0; 3],
			flags: 0,
			planet: 0,
			vis: 0,
		}
	}
}

/// Heat capacity of a mole vector, J/K.
#[must_use]
pub fn heat_capacity(moles: &[f32; N]) -> f32 {
	moles
		.iter()
		.zip(SPECIFIC_HEATS)
		.fold(0.0, |acc, (&n, c)| c.mul_add(n, acc))
}

/// Temperature from energy, keeping `fallback` when there is no gas.
#[must_use]
pub fn temperature_of(moles: &[f32; N], energy: f32, fallback: f32) -> f32 {
	let c = heat_capacity(moles);
	if c > MINIMUM_HEAT_CAPACITY {
		(energy / c).max(TCMB)
	} else {
		fallback
	}
}

impl GasCell {
	/// A cell holding `moles` at `temperature`.
	#[must_use]
	pub fn new(moles: [f32; N], temperature: f32) -> Self {
		let mut cell = Self {
			moles,
			energy: heat_capacity(&moles) * temperature,
			temperature,
			..Self::default()
		};
		cell.refresh_in(CELL_VOLUME);
		cell
	}

	#[must_use]
	pub fn total_moles(&self) -> f32 {
		self.moles.iter().sum()
	}

	#[must_use]
	pub fn heat_capacity(&self) -> f32 {
		heat_capacity(&self.moles)
	}

	/// The live temperature (not the cached one).
	#[must_use]
	pub fn temperature_now(&self) -> f32 {
		temperature_of(&self.moles, self.energy, self.temperature)
	}

	/// The live pressure in `volume` litres.
	#[must_use]
	pub fn pressure_in(&self, volume: f32) -> f32 {
		if volume <= 0.0 {
			return 0.0;
		}
		self.total_moles() * R_IDEAL_GAS_EQUATION * self.temperature_now() / volume
	}

	#[must_use]
	pub fn is_immutable(&self) -> bool {
		self.flags & flags::IMMUTABLE != 0
	}

	/// Recomputes the cached values for `volume`, bumping the revision if
	/// they moved.
	pub fn refresh_in(&mut self, volume: f32) {
		let total = self.total_moles();
		let temperature = self.temperature_now();
		let pressure = if volume > 0.0 {
			total * R_IDEAL_GAS_EQUATION * temperature / volume
		} else {
			0.0
		};
		self.band_check(Some(pressure), temperature, total);
		self.total = total;
		self.temperature = temperature;
		self.pressure = pressure;
		self.vis = vis_signature(&self.moles);
	}

	/// Bumps the revision when a value left its band (`None`: pressure
	/// unknown here, as in `Domain::apply`, which has no volume).
	fn band_check(&mut self, pressure: Option<f32>, temperature: f32, total: f32) {
		let [p0, t0, n0] = self.rev_at;
		let moved = pressure.is_some_and(|p| (p - p0).abs() >= REVISION_KPA)
			|| (temperature - t0).abs() >= REVISION_KELVIN
			|| (total - n0).abs() >= REVISION_MOLES;
		if moved {
			self.revision = self.revision.wrapping_add(1);
			self.rev_at = [pressure.unwrap_or(p0), temperature, total];
		}
	}

	/// The amounts vector (every gas, then energy).
	#[must_use]
	pub fn amounts(&self) -> [f32; Q] {
		let mut out = [0.0; Q];
		out[..N].copy_from_slice(&self.moles);
		out[N] = self.energy;
		out
	}

	fn add_amounts(&mut self, amounts: &[f32; Q]) -> f32 {
		let mut shortfall = 0.0;
		for (m, &d) in self.moles.iter_mut().zip(amounts) {
			let v = *m + d;
			if v < 0.0 {
				shortfall -= v;
				*m = 0.0;
			} else {
				*m = if v < GAS_MIN_MOLES * 0.01 { 0.0 } else { v };
			}
		}
		self.energy = (self.energy + amounts[N]).max(0.0);
		shortfall
	}
}

/// Commands DM sends to a turf's gas. Absolute amounts computed on the main
/// thread (`rust_core.md` §3.2): DM keeps exactly what it computed.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum GasCmd {
	/// Adds (or, negative, removes) moles and energy. A removal that finds
	/// less than DM saw clamps at zero and reports the shortfall (§3.10).
	Delta([f32; Q]),
	/// Sets the planet atmosphere id (planet cells relax back to it).
	Planet(u8),
}

/// The turf gas field.
pub struct TurfGas;

impl Domain for TurfGas {
	type Value = GasCell;
	type Command = GasCmd;
	const NAME: &'static str = "gas";

	fn apply(value: &mut GasCell, cmd: &GasCmd) -> Applied {
		match cmd {
			GasCmd::Delta(d) => {
				if value.is_immutable() {
					return Applied::default();
				}
				let shortfall = value.add_amounts(d);
				let (t, n) = (value.temperature_now(), value.total_moles());
				value.band_check(None, t, n);
				value.flags |= flags::TOUCHED;
				Applied { shortfall }
			}
			GasCmd::Planet(p) => {
				value.planet = *p;
				Applied::default()
			}
		}
	}
}

/// Pressure's derivative in moles, `p / n` (0 for a reservoir or an empty
/// side: a reservoir's pressure never moves).
/// Pressure's derivative in moles, `p / n` (0 for a reservoir or an empty
/// side: a reservoir's pressure never moves). Used only for [`stiffness`]:
/// the flux itself is core's `kernel::pressure_flow`, which takes the raw
/// pressures.
fn dp_dn(side: &Side<'_, GasCell>, p: f32) -> f32 {
	let n = side.cell.total_moles();
	if side.reservoir || n <= GAS_MIN_MOLES {
		0.0
	} else {
		p / n
	}
}

/// A [`Side`]'s amounts as a core [`Operand`], with its share halved: two
/// kernels (bulk flow and diffusion) share one edge's donor-share budget.
fn operand<'a>(side: &Side<'_, GasCell>, amounts: &'a [f32; Q]) -> Operand<'a, Q> {
	Operand {
		amounts,
		capacity: side.capacity,
		inv_capacity: side.inv_capacity,
		share: side.share * 0.5,
	}
}

/// Equal up to a few `f32` ulps.
fn close(a: f32, b: f32) -> bool {
	(a - b).abs() <= 1e-6 * a.abs().max(b.abs())
}

impl FieldKind for TurfGas {
	const GEOMETRY_NAME: &'static str = "gas_geometry";
	const QUANTITIES: usize = Q;
	type Flux = Amounts<Q>;

	fn flux(a: Side<'_, GasCell>, b: Side<'_, GasCell>, dt: f32) -> Amounts<Q> {
		let (xa, xb) = (a.cell.amounts(), b.cell.amounts());
		let (op_a, op_b) = (operand(&a, &xa), operand(&b, &xb));
		let (pa, pb) = (a.cell.pressure_in(a.capacity), b.cell.pressure_in(b.capacity));
		let bulk = kernel::pressure_flow(op_a, pa, op_b, pb, N, BULK_CONDUCTANCE, dt);
		let diffusion = kernel::diffusion(op_a, op_b, DIFFUSION_CONDUCTANCE, dt);
		bulk + diffusion
	}

	fn apply_flux(cell: &mut GasCell, flux: Amounts<Q>) {
		cell.add_amounts(&flux.0);
	}

	fn settled(a: Side<'_, GasCell>, b: Side<'_, GasCell>) -> bool {
		let (sa, sb) = (CELL_VOLUME / a.capacity, CELL_VOLUME / b.capacity);
		let moles = a
			.cell
			.moles
			.iter()
			.zip(&b.cell.moles)
			.all(|(&x, &y)| (x * sa - y * sb).abs() < SETTLED_MOLES);
		if !moles {
			return false;
		}
		let (na, nb) = (a.cell.total_moles(), b.cell.total_moles());
		na < SETTLED_MOLES
			|| nb < SETTLED_MOLES
			|| (a.cell.temperature_now() - b.cell.temperature_now()).abs() < SETTLED_KELVIN
	}

	fn stiffness(a: Side<'_, GasCell>, b: Side<'_, GasCell>) -> f32 {
		let diff_rate = kernel::exchange_stiffness(DIFFUSION_CONDUCTANCE, a.inv_capacity, b.inv_capacity);
		let (pa, pb) = (a.cell.pressure_in(a.capacity), b.cell.pressure_in(b.capacity));
		if (pa - pb).abs() > STIFF_PRESSURE {
			diff_rate + kernel::pressure_stiffness(BULK_CONDUCTANCE, dp_dn(&a, pa), dp_dn(&b, pb))
		} else {
			diff_rate
		}
	}

	fn local(cell: &mut GasCell, _capacity: f32, _dt: f32) -> bool {
		let react = crate::gate::can_react(cell);
		if react {
			cell.flags |= flags::REACT;
		} else {
			cell.flags &= !flags::REACT;
		}
		false
	}

	fn quiet(before: &GasCell, after: &GasCell) -> bool {
		close(before.energy, after.energy)
			&& before
				.moles
				.iter()
				.zip(&after.moles)
				.all(|(&x, &y)| close(x, y))
	}

	fn refresh(cell: &mut GasCell, capacity: f32) {
		cell.refresh_in(capacity);
	}

	fn totals(cell: &GasCell, out: &mut [f64]) {
		for (o, v) in out.iter_mut().zip(cell.amounts()) {
			*o += f64::from(v);
		}
	}

	fn flux_totals(flux: &Amounts<Q>, out: &mut [f64]) {
		flux.add_to(out);
	}
}

vg_core::channels! { pub mod gas_ch for TurfGas {
	PRESSURE: Scalar<Kpa> hysteresis 0.5 => |c, o| o[0] = c.pressure,
	TEMPERATURE: Scalar<Kelvin> hysteresis 0.5 => |c, o| o[0] = c.temperature,
	MOLES: Scalar<Moles> hysteresis 0.1 => |c, o| o[0] = c.total,
	OXYGEN: Scalar<Moles> hysteresis 0.05 => |c, o| o[0] = c.moles[crate::gas::ids::GAS_OXYGEN],
	PLASMA: Scalar<Moles> hysteresis 0.05 => |c, o| o[0] = c.moles[crate::gas::ids::GAS_PLASMA],
	CARBON_DIOXIDE: Scalar<Moles> hysteresis 0.05 => |c, o| o[0] = c.moles[crate::gas::ids::GAS_CARBON_DIOXIDE],
}}

/// Visible-gas signature: which gases are visible and at which step. The
/// thresholds are registry data (`gate.rs`); a zero signature is "nothing
/// visible".
#[must_use]
pub fn vis_signature(moles: &[f32; N]) -> u16 {
	crate::gate::vis_signature(moles)
}

/// A pair of cells for kernel tests and benches: `(cell, volume, reservoir)`.
#[cfg(test)]
pub(crate) fn side<'a>(cell: &'a GasCell, volume: f32, reservoir: bool) -> Side<'a, GasCell> {
	Side {
		cell,
		capacity: volume,
		inv_capacity: if reservoir { 0.0 } else { 1.0 / volume },
		reservoir,
		share: if reservoir { f32::INFINITY } else { 1.0 / 6.0 },
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::gas::ids::{GAS_NITROGEN, GAS_OXYGEN, GAS_PLASMA};

	fn air(scale: f32, t: f32) -> GasCell {
		let mut m = [0.0; N];
		m[GAS_OXYGEN] = 21.8 * scale;
		m[GAS_NITROGEN] = 82.1 * scale;
		GasCell::new(m, t)
	}

	fn sum(f: &Amounts<Q>, g: &Amounts<Q>) -> f32 {
		f.0.iter().zip(g.0).map(|(a, b)| (a + b).abs()).sum()
	}

	#[test]
	fn flux_is_antisymmetric() {
		let (x, y) = (air(1.0, 293.0), air(0.3, 350.0));
		for dt in [0.05, 0.5, 5.0] {
			let f = TurfGas::flux(side(&x, 2500.0, false), side(&y, 2500.0, false), dt);
			let g = TurfGas::flux(side(&y, 2500.0, false), side(&x, 2500.0, false), dt);
			assert!(sum(&f, &g) < 1e-3, "{f:?} {g:?}");
		}
	}

	#[test]
	fn flux_never_overshoots_pressure_equality() {
		let (x, y) = (air(3.0, 293.0), air(0.0, 293.0));
		for dt in [0.1, 1.0, 100.0] {
			let f = TurfGas::flux(side(&x, 2500.0, false), side(&y, 2500.0, false), dt);
			let (mut a, mut b) = (x, y);
			TurfGas::apply_flux(&mut a, -f);
			TurfGas::apply_flux(&mut b, f);
			assert!(
				a.pressure_in(2500.0) >= b.pressure_in(2500.0) - 1e-2,
				"dt {dt}"
			);
			assert!(a.moles.iter().all(|&m| m >= 0.0));
		}
	}

	#[test]
	fn vacuum_drains_exponentially() {
		let x = air(1.0, 293.0);
		let space = GasCell::default();
		let f = TurfGas::flux(side(&x, 2500.0, false), side(&space, 2500.0, true), 0.5);
		let moved: f32 = f.0[..N].iter().sum();
		// At most half the donor's share per kernel pair, and a real amount.
		assert!(
			moved > 0.0 && moved <= x.total_moles() / 6.0 + 1e-3,
			"{moved}"
		);
		// Nothing flows out of vacuum.
		let back = TurfGas::flux(side(&space, 2500.0, true), side(&x, 2500.0, false), 0.5);
		assert!(back.0[..N].iter().all(|v| *v <= 0.0));
	}

	#[test]
	fn diffusion_mixes_composition_at_equal_pressure() {
		let mut m = [0.0; N];
		m[GAS_PLASMA] = 103.9;
		let (x, y) = (GasCell::new(m, 293.0), air(1.0, 293.0));
		let f = TurfGas::flux(side(&x, 2500.0, false), side(&y, 2500.0, false), 0.5);
		assert!(f.0[GAS_PLASMA] > 0.0 && f.0[GAS_OXYGEN] < 0.0);
		assert!(!TurfGas::settled(
			side(&x, 2500.0, false),
			side(&y, 2500.0, false)
		));
		assert!(TurfGas::settled(
			side(&y, 2500.0, false),
			side(&y, 2500.0, false)
		));
	}

	#[test]
	fn delta_clamps_and_reports_the_shortfall() {
		let mut c = air(1.0, 293.0);
		let mut d = [0.0; Q];
		d[GAS_OXYGEN] = -30.0;
		let applied = TurfGas::apply(&mut c, &GasCmd::Delta(d));
		assert_eq!(c.moles[GAS_OXYGEN], 0.0);
		assert!((applied.shortfall - 8.2).abs() < 1e-3);
		let mut space = GasCell::default();
		space.flags |= flags::IMMUTABLE;
		d[GAS_OXYGEN] = 5.0;
		TurfGas::apply(&mut space, &GasCmd::Delta(d));
		assert_eq!(space.total_moles(), 0.0);
	}
}
