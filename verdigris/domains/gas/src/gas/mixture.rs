//! A `/datum/gas_mixture`'s gas: every gas's moles, a temperature, a volume.
//! The mixture maths DM's gas procs run (merge, remove, share, compare).

use super::constants::{
	GAS_MIN_MOLES, MINIMUM_HEAT_CAPACITY, MINIMUM_MOLES_DELTA_TO_MOVE,
	MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND, R_IDEAL_GAS_EQUATION, TCMB,
};
use super::GasIDX;
use crate::cell::{N, SPECIFIC_HEATS};

/// A gas mixture.
#[derive(Clone, Debug, PartialEq)]
pub struct Mixture {
	temperature: f32,
	pub volume: f32,
	min_heat_capacity: f32,
	moles: [f32; N],
	immutable: bool,
}

impl Default for Mixture {
	fn default() -> Self {
		Self::new()
	}
}

impl Mixture {
	/// An empty mixture (2.7 K, 2500 L).
	#[must_use]
	pub const fn new() -> Self {
		Self {
			temperature: 2.7,
			volume: 2500.0,
			min_heat_capacity: 0.0,
			moles: [0.0; N],
			immutable: false,
		}
	}

	/// An empty mixture of `vol` litres.
	#[must_use]
	pub const fn from_vol(vol: f32) -> Self {
		let mut ret = Self::new();
		ret.volume = vol;
		ret
	}

	/// A mixture from a full mole vector.
	#[must_use]
	pub fn from_parts(moles: &[f32; N], temperature: f32, volume: f32, immutable: bool) -> Self {
		let temperature = if temperature.is_normal() {
			temperature
		} else {
			TCMB
		};
		Self {
			temperature,
			volume,
			min_heat_capacity: 0.0,
			moles: *moles,
			immutable,
		}
	}

	/// Every gas's moles, by gas index.
	#[must_use]
	pub const fn moles_array(&self) -> [f32; N] {
		self.moles
	}

	/// Whether two mixtures hold exactly the same gas in the same state.
	#[must_use]
	pub fn same_state(&self, other: &Self) -> bool {
		self == other
	}

	#[must_use]
	pub const fn min_heat_capacity(&self) -> f32 {
		self.min_heat_capacity
	}

	#[must_use]
	pub const fn get_temperature(&self) -> f32 {
		self.temperature
	}

	/// Sets the temperature, unless immutable (or not a normal number).
	pub fn set_temperature(&mut self, temp: f32) {
		if !self.immutable && temp.is_normal() {
			self.temperature = temp;
		}
	}

	pub fn set_min_heat_capacity(&mut self, amt: f32) {
		self.min_heat_capacity = amt;
	}

	/// Calls `f` with every gas index and its moles.
	///
	/// # Errors
	/// Whatever `f` returns.
	pub fn for_each_gas(
		&self,
		mut f: impl FnMut(GasIDX, f32) -> eyre::Result<()>,
	) -> eyre::Result<()> {
		self.moles
			.iter()
			.enumerate()
			.try_for_each(|(i, &g)| f(i, g))
	}

	#[must_use]
	pub fn get_moles(&self, idx: GasIDX) -> f32 {
		self.moles.get(idx).copied().unwrap_or(0.0)
	}

	pub fn mark_immutable(&mut self) {
		self.immutable = true;
	}

	#[must_use]
	pub const fn is_immutable(&self) -> bool {
		self.immutable
	}

	/// Zeroes every gas below [`GAS_MIN_MOLES`].
	fn garbage_collect(&mut self) {
		self.moles
			.iter_mut()
			.filter(|m| **m <= GAS_MIN_MOLES)
			.for_each(|m| *m = 0.0);
	}

	pub fn set_moles(&mut self, idx: GasIDX, amt: f32) {
		if !self.immutable && idx < N {
			self.moles[idx] = amt;
		}
	}

	pub fn adjust_moles(&mut self, idx: GasIDX, amt: f32) {
		self.adjust_multi(&[(idx, amt)]);
	}

	/// Adds `(gas, moles)` pairs (a removal zeroes what drops below
	/// [`GAS_MIN_MOLES`]).
	pub fn adjust_multi(&mut self, adjustments: &[(usize, f32)]) {
		if self.immutable {
			return;
		}
		let mut collect = false;
		for &(idx, amt) in adjustments.iter().filter(|(i, a)| *i < N && a.is_normal()) {
			self.moles[idx] += amt;
			collect |= amt <= 0.0;
		}
		if collect {
			self.garbage_collect();
		}
	}

	/// J/K (never below the minimum heat capacity DM set).
	#[must_use]
	pub fn heat_capacity(&self) -> f32 {
		crate::cell::heat_capacity(&self.moles).max(self.min_heat_capacity)
	}

	/// Heat capacity of one gas in this mix.
	#[must_use]
	pub fn partial_heat_capacity(&self, idx: GasIDX) -> f32 {
		self.moles
			.get(idx)
			.filter(|amt| amt.is_normal())
			.map_or(0.0, |amt| amt * SPECIFIC_HEATS[idx])
	}

	#[must_use]
	pub fn total_moles(&self) -> f32 {
		self.moles.iter().sum()
	}

	/// kPa.
	#[must_use]
	pub fn return_pressure(&self) -> f32 {
		self.total_moles() * R_IDEAL_GAS_EQUATION * self.temperature / self.volume
	}

	/// J.
	#[must_use]
	pub fn thermal_energy(&self) -> f32 {
		self.heat_capacity() * self.temperature
	}

	/// Adds `giver`'s gas and heat (the giver is unchanged).
	pub fn merge(&mut self, giver: &Self) {
		if self.immutable {
			return;
		}
		let (ours, theirs) = (self.heat_capacity(), giver.heat_capacity());
		self.moles
			.iter_mut()
			.zip(giver.moles)
			.for_each(|(a, b)| *a += b);
		if ours + theirs > MINIMUM_HEAT_CAPACITY {
			self.set_temperature(
				(ours * self.temperature + theirs * giver.temperature) / (ours + theirs),
			);
		}
	}

	/// Moves fraction `r` of the listed gases (with their heat) into `into`.
	pub fn transfer_gases_to(&mut self, r: f32, gases: &[GasIDX], into: &mut Self) {
		let ratio = r.clamp(0.0, 1.0);
		let initial_energy = into.thermal_energy();
		let mut heat = 0.0;
		for &i in gases.iter().filter(|&&i| i < N) {
			let delta = self.moles[i] * ratio;
			heat += delta * self.temperature * SPECIFIC_HEATS[i];
			self.moles[i] -= delta;
			into.adjust_moles(i, delta);
		}
		into.set_temperature((initial_energy + heat) / into.heat_capacity());
	}

	/// Moves fraction `ratio` of this mixture into `into` (which it replaces;
	/// an immutable source keeps its gas).
	pub fn remove_ratio_into(&mut self, ratio: f32, into: &mut Self) {
		if ratio <= 0.0 {
			return;
		}
		let ratio = ratio.min(1.0);
		into.copy_from_mutable(self);
		into.multiply(ratio);
		self.multiply(1.0 - ratio);
	}

	/// As [`Mixture::remove_ratio_into`], by moles.
	pub fn remove_into(&mut self, amount: f32, into: &mut Self) {
		self.remove_ratio_into(amount / self.total_moles(), into);
	}

	#[must_use]
	pub fn remove_ratio(&mut self, ratio: f32) -> Self {
		let mut removed = Self::from_vol(self.volume);
		self.remove_ratio_into(ratio, &mut removed);
		removed
	}

	#[must_use]
	pub fn remove(&mut self, amount: f32) -> Self {
		self.remove_ratio(amount / self.total_moles())
	}

	/// Copies `sample`'s gas and temperature, unless immutable.
	pub fn copy_from_mutable(&mut self, sample: &Self) {
		if !self.immutable {
			self.moles = sample.moles;
			self.temperature = sample.temperature;
		}
	}

	/// A mutable copy, whether or not this one is immutable.
	#[must_use]
	pub fn copy_to_mutable(&self) -> Self {
		Self {
			immutable: false,
			..self.clone()
		}
	}

	/// Whether the temperatures differ enough to matter (with enough gas).
	#[must_use]
	pub fn temperature_compare(&self, sample: &Self) -> bool {
		(self.temperature - sample.temperature).abs() > MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND
			&& self.total_moles() > MINIMUM_MOLES_DELTA_TO_MOVE
	}

	/// The largest per-gas mole difference.
	#[must_use]
	pub fn compare(&self, sample: &Self) -> f32 {
		self.moles
			.iter()
			.zip(sample.moles)
			.fold(0.0, |acc, (a, b)| acc.max((a - b).abs()))
	}

	/// Whether any gas differs by at least `amt`.
	#[must_use]
	pub fn compare_with(&self, sample: &Self, amt: f32) -> bool {
		self.compare(sample) >= amt
	}

	pub fn clear(&mut self) {
		if !self.immutable {
			self.moles = [0.0; N];
		}
	}

	pub fn multiply(&mut self, multiplier: f32) {
		if !self.immutable {
			self.moles.iter_mut().for_each(|amt| *amt *= multiplier);
			self.garbage_collect();
		}
	}

	/// Adds `num` moles of every gas.
	pub fn add(&mut self, num: f32) {
		if !self.immutable {
			self.moles.iter_mut().for_each(|amt| *amt += num);
			self.garbage_collect();
		}
	}

	/// The ids of every reaction this mixture can run, highest priority first.
	#[must_use]
	pub fn all_reactable(&self) -> Vec<u64> {
		crate::gate::with(|g| g.all_ready(&self.moles, self.thermal_energy(), self.temperature))
	}

	/// `(oxidation power, fuel amount)` at the mixture's temperature.
	#[must_use]
	pub fn get_burnability(&self) -> (f32, f32) {
		crate::gate::with(|g| g.burnability(&self.moles, self.temperature))
	}

	#[must_use]
	pub fn get_oxidation_power(&self) -> f32 {
		self.get_burnability().0
	}

	#[must_use]
	pub fn get_fuel_amount(&self) -> f32 {
		self.get_burnability().1
	}

	/// Adds `heat` joules.
	pub fn adjust_heat(&mut self, heat: f32) {
		let cap = self.heat_capacity();
		self.set_temperature((cap * self.temperature + heat) / cap);
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn merge_mixes_heat_and_remove_ratio_splits() {
		let mut into = Mixture::new();
		into.set_moles(0, 82.0);
		into.set_moles(1, 22.0);
		into.set_temperature(293.15);
		let mut source = Mixture::new();
		source.set_moles(2, 100.0);
		source.set_temperature(313.15);
		into.merge(&source);
		assert_eq!(into.get_moles(2), 100.0);
		assert_eq!(source.get_moles(2), 100.0, "merge leaves the giver alone");
		// (82 + 22) * 20 * 293.15 + 100 * 30 * 313.15 over 2,080 + 3,000 J/K.
		assert!(
			(into.get_temperature() - 304.961).abs() < 0.01,
			"{}",
			into.get_temperature()
		);

		let mut removed = Mixture::new();
		removed.set_moles(0, 22.0);
		removed.set_moles(1, 82.0);
		let new = removed.remove_ratio(0.5);
		assert!(removed.compare(&new) < MINIMUM_MOLES_DELTA_TO_MOVE);
		assert_eq!((removed.get_moles(0), removed.get_moles(1)), (11.0, 41.0));
		removed.mark_immutable();
		let new_two = removed.remove_ratio(0.5);
		assert!(removed.compare(&new_two) >= MINIMUM_MOLES_DELTA_TO_MOVE);
		assert_eq!((removed.get_moles(0), new_two.get_moles(0)), (11.0, 5.5));
	}
}
