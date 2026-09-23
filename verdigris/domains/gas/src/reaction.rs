use crate::gas::{gas_path, total_num_gases, GasIDX, Mixture};
use byondapi::prelude::*;
use eyre::{Context, Result};
use float_ord::FloatOrd;
use hashbrown::HashMap;
use rustc_hash::FxBuildHasher;
use std::{
	cell::RefCell,
	hash::{Hash, Hasher},
};

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

thread_local! {
	/// The DM `/datum/gas_reaction` for each reaction id. Reactions run in DM.
	static REACTION_VALUES: RefCell<HashMap<ReactionIdentifier, ByondValue, FxBuildHasher>> = Default::default();
}

/// Runs a reaction given a `ReactionIdentifier`. Returns the result of the reaction, error or success.
/// # Errors
/// If the reaction itself has a runtime.
pub fn react_by_id(
	id: ReactionIdentifier,
	src: ByondValue,
	holder: ByondValue,
) -> Result<ByondValue> {
	REACTION_VALUES.with_borrow(|r| {
		r.get(&id).map_or_else(
			|| Err(eyre::eyre!("Reaction with invalid id")),
			|reaction| {
				reaction
					.call_id(byond_string!("react"), &[src, holder])
					.wrap_err("calling byond side react in react_by_id")
			},
		)
	})
}

impl Reaction {
	/// Takes a `/datum/gas_reaction` and makes a byond reaction out of it.
	pub fn from_byond_reaction(reaction: ByondValue) -> Result<Self> {
		let priority = FloatOrd(
			reaction
				.read_number_id(byond_string!("priority"))
				.map_err(|_| eyre::eyre!("Reaction priority must be a number!"))?,
		);
		let string_id = reaction
			.read_string_id(byond_string!("id"))
			.map_err(|_| eyre::eyre!("Reaction id must be a string!"))?;

		let id = {
			let mut state = rustc_hash::FxHasher::default();
			string_id.as_bytes().hash(&mut state);
			state.finish()
		};

		let our_reaction = {
			if let Some(min_reqs) = reaction
				.read_var_id(byond_string!("min_requirements"))
				.map_or(None, |value| value.is_list().then_some(value))
			{
				let mut min_gas_reqs: Vec<(GasIDX, f32)> = Vec::new();
				for i in 0..total_num_gases() {
					let Some(path) = gas_path(i) else {
						continue;
					};
					if let Ok(req_amount) =
						min_reqs.read_list_index(path).and_then(|v| v.get_number())
					{
						min_gas_reqs.push((i, req_amount));
					}
				}
				let min_temp_req = min_reqs
					.read_list_index("TEMP")
					.ok()
					.and_then(|item| item.get_number().ok());
				let max_temp_req = min_reqs
					.read_list_index("MAX_TEMP")
					.ok()
					.and_then(|item| item.get_number().ok());
				let min_ener_req = min_reqs
					.read_list_index("ENER")
					.ok()
					.and_then(|item| item.get_number().ok());
				let min_fire_req = min_reqs
					.read_list_index("FIRE_REAGENTS")
					.ok()
					.and_then(|item| item.get_number().ok());
				Ok(Reaction {
					id,
					priority,
					min_temp_req,
					max_temp_req,
					min_ener_req,
					min_fire_req,
					min_gas_reqs,
				})
			} else {
				Err(eyre::eyre!(format!(
					"Reaction {string_id} doesn't have a gas requirements list!"
				)))
			}
		}?;

		REACTION_VALUES.with_borrow_mut(|reaction_map| -> Result<()> {
			reaction_map.insert(our_reaction.id, reaction);
			Ok(())
		})?;
		Ok(our_reaction)
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
	/// Calls the reaction with the given arguments.
	/// # Errors
	/// If the reaction itself has a runtime error, this will propagate it up.
	pub fn react(&self, src: ByondValue, holder: ByondValue) -> Result<ByondValue> {
		react_by_id(self.id, src, holder)
	}
}
