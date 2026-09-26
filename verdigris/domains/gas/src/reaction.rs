//! A reaction's requirements, pure (`rust_architecture.md` §8.5 step 6,
//! decision 1): reactions themselves stay in DM (`AGENTS.md`) and are
//! called back through a live `/datum/gas_reaction` reference, which is
//! inherently `byondapi` (`ffi/src/gas.rs`'s own reaction registry keeps
//! that reference and the actual call-back); this module keeps only the
//! plain data every reaction needs regardless of who holds the DM side --
//! the gate the turf field's `local` step reads (`gate.rs`), constructed by
//! [`Reaction::new`] instead of reading a `ByondValue` directly.

use crate::gas::{GasIDX, Mixture};
use float_ord::FloatOrd;

pub type ReactionPriority = FloatOrd<f32>;
pub type ReactionIdentifier = u64;

#[derive(Clone, Debug)]
pub struct Reaction {
	id: ReactionIdentifier,
	priority: ReactionPriority,
	min_temp_req: Option<f32>,
	max_temp_req: Option<f32>,
	min_ener_req: Option<f32>,
	min_fire_req: Option<f32>,
	min_gas_reqs: Vec<(GasIDX, f32)>,
}

impl Reaction {
	/// Builds a reaction's requirements from already-parsed values (the
	/// `ByondValue` reading -- `min_requirements`, `priority`, `id` --
	/// lives in `ffi/src/gas.rs`, the only place allowed to hold the live
	/// DM reaction reference this data was extracted from).
	#[must_use]
	#[allow(clippy::too_many_arguments)]
	pub fn new(
		id: ReactionIdentifier,
		priority: ReactionPriority,
		min_temp_req: Option<f32>,
		max_temp_req: Option<f32>,
		min_ener_req: Option<f32>,
		min_fire_req: Option<f32>,
		min_gas_reqs: Vec<(GasIDX, f32)>,
	) -> Self {
		Self {
			id,
			priority,
			min_temp_req,
			max_temp_req,
			min_ener_req,
			min_fire_req,
			min_gas_reqs,
		}
	}

	/// The requirements the turf field checks (`gate.rs`).
	#[must_use]
	pub fn requirement(&self) -> crate::gate::Requirement {
		crate::gate::Requirement {
			min_temp: self.min_temp_req,
			max_temp: self.max_temp_req,
			min_energy: self.min_ener_req,
			min_fire: self.min_fire_req,
			gases: self.min_gas_reqs.clone(),
		}
	}
	/// Gets the reaction's identifier.
	#[must_use]
	pub fn get_id(&self) -> ReactionIdentifier {
		self.id
	}
	/// Checks if the given gas mixture can react with this reaction.
	pub fn check_conditions(&self, mix: &Mixture) -> bool {
		self.min_temp_req
			.is_none_or(|temp_req| mix.get_temperature() >= temp_req)
			&& self
				.max_temp_req
				.is_none_or(|temp_req| mix.get_temperature() <= temp_req)
			&& self
				.min_gas_reqs
				.iter()
				.all(|&(k, v)| mix.get_moles(k) >= v)
			&& self
				.min_ener_req
				.is_none_or(|ener_req| mix.thermal_energy() >= ener_req)
			&& self.min_fire_req.is_none_or(|fire_req| {
				let (oxi, fuel) = mix.get_burnability();
				oxi.min(fuel) >= fire_req
			})
	}
	/// Returns the priority of the reaction.
	#[must_use]
	pub fn get_priority(&self) -> ReactionPriority {
		self.priority
	}
}
