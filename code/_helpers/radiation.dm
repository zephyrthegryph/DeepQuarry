/// Whether or not it's possible for this atom to be irradiated
#define CAN_IRRADIATE(atom) (ismob(##atom))

/// Calculates the max chance for a radiation_pulse via a radioactive reagent
#define CALCULATE_RAD_MAX_CHANCE(rad_power) (20 + (15 * (rad_power - 1)))

/// Sends out a pulse of radiation, eminating from the source.
/// Radiation is performed by collecting all radiatables within the max range (0 means source only, 1 means adjacent, etc),
/// then makes their way towards them. A number, starting at 1, is multiplied
/// by the insulation amounts of whatever is in the way (for example, walls lowering it down).
/// If this number hits equal or below the threshold, then the target can no longer be irradiated.
/// If the number is above the threshold, then the chance is the chance that the target will be irradiated.
/// As a consumer, this means that max_range going up usually means you want to lower the threshold too,
/// as well as the other way around.
/// If max_range is high, but threshold is too high, then it usually won't reach the source at the max range in time.
/// If max_range is low, but threshold is too low, then it basically guarantees everyone nearby, even if there's walls
/// and such in the way, can be irradiated.
/// You can also pass in a minimum exposure time. If this is set, then this radiation pulse
/// will not irradiate the source unless they have been around *any* radioactive source for that
/// period of time.
/// The chance to get irradiated diminishes over range, and from objects that block radiation.
/// Assuming there is nothing in the way, the chance will determine what the chance is to get irradiated from half of max_range.
/// Example: If chance is equal to 30%, and max_range is equal to 8,
/// then the chance for a thing to get irradiated is 30% if they are 4 turfs away from the pulse source.
/// Also, strength is how much radiation the target will get if they fail their RNG check / linger for too long.
/proc/radiation_pulse(
	atom/source,
	max_range,
	threshold,
	chance = DEFAULT_RADIATION_CHANCE,
	minimum_exposure_time = 0,
	strength = 100
)
	if(!SSradiation.is_enabled())
		return

	var/datum/radiation_pulse_information/pulse_information = new
	rel_set(pulse_information, nameof(/datum/contract_damage_report::source_ref), source)
	pulse_information.max_range = max_range
	pulse_information.threshold = threshold
	pulse_information.chance = chance
	pulse_information.minimum_exposure_time = minimum_exposure_time
	pulse_information.strength = strength
	// Targets (living mobs and the collector, geiger and radiovoltaic registries)
	// are collected and traced in one Rust call when the pulse first processes.
	SSradiation.queue_pulse(pulse_information)

	return TRUE

/datum/radiation_pulse_information
	/// The pulse source: a relation view (named source_ref for radiation_service.dm, which reads it).
	var/atom/source_ref
	var/max_range
	var/threshold
	var/chance
	var/minimum_exposure_time
	var/strength
	/// Targets on the source's z-level, set when the pulse is traced.
	var/list/targets
	/// Path transmission to each of `targets` (-1 = out of range); null until traced.
	var/list/transmissions
	/// Index into `targets` of the next one to apply.
	var/next_target = 1

/// How many targets this pulse still has to visit.
/datum/radiation_pulse_information/proc/remaining_targets()
	return max(length(targets) - next_target + 1, 0)

/// Sets rad_insulation and marks the shielding layer dirty if the value changed. The registered setter of
/// rad_insulation (admin var edits and tracked_lint go through it); the batch flush to Rust stays in the radiation
/// world service (flush_shielding), one FFI call for every dirty turf.
SETTER(/atom, rad_insulation)
/atom/proc/set_rad_insulation(new_insulation)
	if(rad_insulation == new_insulation)
		return
	rad_insulation = new_insulation
	RAD_SHIELDING_CHANGED(isturf(src) ? src : loc)

/// Radiation transmission of `material_id` (a MAT_* name) at `thickness_mm`,
/// or `fallback` when the material is unknown.
/proc/material_rad_insulation(material_id, thickness_mm, fallback = RAD_NO_INSULATION)
	var/datum/material/M = material_id ? get_material_by_name(material_id) : null
	return M ? M.radiation_transmission(thickness_mm) : fallback

/// Declared shielding: an atom whose `rad_shield_material` is set derives its
/// insulation from that material at `rad_shield_thickness_mm`.
/atom/proc/apply_rad_shield_material()
	if(rad_shield_material)
		set_rad_insulation(material_rad_insulation(rad_shield_material, rad_shield_thickness_mm, rad_insulation))

/turf/simulated/Initialize(mapload)
	. = ..()
	if(rad_insulation != RAD_NO_INSULATION)
		RAD_SHIELDING_CHANGED(src)

#define MEDIUM_RADIATION_THRESHOLD_RANGE 0.5
#define EXTREME_RADIATION_CHANCE 30

/// Gets the perceived "danger" of radiation pulse, given the threshold to the target.
/// Returns a RADIATION_DANGER_* define, see [code/__DEFINES/radiation.dm]
/proc/get_perceived_radiation_danger(datum/radiation_pulse_information/pulse_information, insulation_to_target)
	if (insulation_to_target > pulse_information.threshold)
		// We could get irradiated! The only thing stopping us now is chance, so scale based on that.
		if (pulse_information.chance >= EXTREME_RADIATION_CHANCE)
			return PERCEIVED_RADIATION_DANGER_EXTREME
		else
			return PERCEIVED_RADIATION_DANGER_HIGH
	else
		// We're out of the threshold from being irradiated, but by how much?
		if (insulation_to_target / pulse_information.threshold <= MEDIUM_RADIATION_THRESHOLD_RANGE)
			return PERCEIVED_RADIATION_DANGER_MEDIUM
		else
			return PERCEIVED_RADIATION_DANGER_LOW

/// A common proc used to emit /datum/definition_event/atom_propagate_rad_pulse on adjacent atoms
/// Only used for uranium (false/tram)walls to spread their radiation pulses
/atom/proc/propagate_radiation_pulse()
	for(var/atom/atom in orange(1,src))
		PUBLISH_LEGACY(atom, /datum/notice/atom_propagate_rad_pulse, src)

#undef MEDIUM_RADIATION_THRESHOLD_RANGE
#undef EXTREME_RADIATION_CHANCE
