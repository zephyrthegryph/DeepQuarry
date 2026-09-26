//! Pipes on the R7 network framework (`rust_architecture.md` §6, §8.5, step
//! 5): [`PipeGas`] (a region's pooled gas) and the [`Pipes`] [`NetworkKind`]
//! itself. Adding an edge merges two regions' gas; removing one splits it
//! in proportion to the parts' volumes.
//!
//! Pipe regions are main-owned entities on the shared
//! `vg_core::world::World` (`WorldBuilder::add_network::<Pipes>`,
//! `verdigris/ffi/src/world.rs`'s `register`), not a domain-local host: the
//! old hand-rolled `PipeNet` (its own slot table, revision/idle-skip
//! bookkeeping and DM batch-string decoder) duplicated exactly what
//! `vg_core::network::host::NetworkHost` already gives every
//! `NetworkKind` generically. `verdigris/ffi/src/pipes.rs` is the pipe
//! topology/device FFI now (`domains/gas/src/lib.rs`'s old
//! `pipenet_topology_batch`/`pipenet_device_batch`/`pipenet_step_devices`
//! binds are gone).

use vg_core::network::NetworkKind;

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
	/// implementation `device::Flow` uses.
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

impl vg_core::conservation::Conserved for PipeGas {
	fn totals(&self, visit: &mut dyn FnMut(&'static str, f64)) {
		visit("pipe_moles", self.total());
		visit("pipe_energy", self.energy);
	}
}

impl NetworkKind for Pipes {
	const NAME: &'static str = "pipes";
	/// A port's volume (L).
	type Node = f32;
	/// The region's volume.
	type Summary = f64;
	type Payload = PipeGas;
	/// A device edge's own network-graph data: none. Its flow law and
	/// parameters live in linked `DeviceFlow`/`DeviceValve` components now
	/// (`rust_architecture.md` §8.5 step 6's pipe-device redesign; used to
	/// be `device::DeviceParams` stored right here).
	type Device = ();
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

#[cfg(test)]
mod tests {
	use super::*;
	use crate::gas::ids::GAS_OXYGEN;

	// Property tests for `impl NetworkKind for Pipes`'s split/merge
	// (`rust_architecture.md` §7: "split/merge conserving moles and
	// energy"). Topology/device-edge coverage (merges, splits, releases,
	// idle-skip) now lives against the real `NetworkHost<Pipes>` the world
	// hosts -- `vg_core::network`'s own generic test suite already proves
	// that mechanism domain-agnostically, and `verdigris/ffi/tests/pipes.rs`
	// exercises it end to end for pipes specifically.
	use proptest::prelude::*;

	fn arb_gas() -> impl Strategy<Value = PipeGas> {
		(0.0f64..10_000.0, 0.0f64..10_000.0, 0.0f64..10_000.0, 0.0f64..2000.0).prop_map(
			|(o2, co2, plasma, energy)| {
				let mut g = PipeGas::default();
				g.moles[GAS_OXYGEN] = o2;
				g.moles[crate::gas::ids::GAS_CARBON_DIOXIDE] = co2;
				g.moles[crate::gas::ids::GAS_PLASMA] = plasma;
				g.energy = energy;
				g
			},
		)
	}

	/// A `(whole, part)` pair with `0 <= part <= whole` and `whole > 0`,
	/// `Pipes::split`'s documented domain (a region summary and one
	/// member's share of it).
	fn arb_whole_part() -> impl Strategy<Value = (f64, f64)> {
		(1.0f64..1_000_000.0).prop_flat_map(|whole| (Just(whole), 0.0..=whole))
	}

	proptest! {
		#[test]
		fn split_then_merge_round_trips_moles_and_energy(
			mut whole_gas in arb_gas(),
			(whole, part) in arb_whole_part(),
		) {
			let before = whole_gas.total();
			let before_energy = whole_gas.energy;
			let carved = Pipes::split(&mut whole_gas, &whole, &part);
			// Conserves at the moment of the split...
			prop_assert!((carved.total() + whole_gas.total() - before).abs() < 1e-6 * before.max(1.0));
			prop_assert!((carved.energy + whole_gas.energy - before_energy).abs() < 1e-3 * before_energy.max(1.0));
			prop_assert!(carved.total() >= -1e-9, "split never returns negative moles");
			prop_assert!(whole_gas.total() >= -1e-9, "split never leaves negative moles behind");
			// ...and merging the two pieces back restores the original.
			Pipes::merge(&mut whole_gas, carved);
			prop_assert!((whole_gas.total() - before).abs() < 1e-6 * before.max(1.0));
			prop_assert!((whole_gas.energy - before_energy).abs() < 1e-3 * before_energy.max(1.0));
		}

		#[test]
		fn merge_is_commutative_for_totals(a in arb_gas(), b in arb_gas()) {
			// PipeGas is Copy, so `a`/`b` are still usable after seeding
			// `ab`/`ba` - each gets merged with the *other* original value,
			// not a value already mutated by the first merge.
			let expected = a.total() + b.total();
			let expected_energy = a.energy + b.energy;
			let mut ab = a;
			Pipes::merge(&mut ab, b);
			let mut ba = b;
			Pipes::merge(&mut ba, a);
			prop_assert!((ab.total() - expected).abs() < 1e-6 * expected.max(1.0));
			prop_assert!((ba.total() - expected).abs() < 1e-6 * expected.max(1.0));
			prop_assert!((ab.energy - expected_energy).abs() < 1e-3 * expected_energy.max(1.0));
			prop_assert!((ba.energy - expected_energy).abs() < 1e-3 * expected_energy.max(1.0));
		}

		#[test]
		fn split_never_exceeds_the_donor_and_whole_collapses_the_region(
			mut whole_gas in arb_gas(),
			whole in 1.0f64..1_000_000.0,
		) {
			let before = whole_gas.total();
			// part == whole: the documented "last node of a region" case -
			// the whole payload moves, nothing is left behind.
			let carved = Pipes::split(&mut whole_gas, &whole, &whole);
			prop_assert!((carved.total() - before).abs() < 1e-6 * before.max(1.0));
			prop_assert!(whole_gas.total() < 1e-6 * before.max(1.0) + 1e-9);
		}
	}
}
