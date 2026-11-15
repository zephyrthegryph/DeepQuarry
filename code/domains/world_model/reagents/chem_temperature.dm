// Reaction temperature (the table of every recipe's band: code/content/reagents/reactions/reaction_temperatures.dm).
//
// A holder has the temperature of the thing that holds it (get_temperature(): a beaker's heat body, else the room's). A chemistry recipe has a working range
// and a narrower ideal band inside it, in kelvin:
//
//   * inside the ideal band the recipe makes clean product;
//   * inside the range but off the band it still goes, but makes contaminants and loses product, both scaled by how far off the band it is (0 at the band's
//     edge, 1 at the edge of the range): too cold leaves organic residue, too hot leaves a reactive impurity and burns off some of the product;
//   * outside the range it does not react at all.
//
// A catalyst in the container (a material with catalytic activity, code/content/reagents/purification/catalyst.dm) widens the band and the range on both
// sides by its activity. Only holders in a loose container are gated (a beaker, a bottle, a pill): a mob's blood, a machine's buffer, a grenade or a slime
// extract react as they always did. Every refusal and every off-ideal step is written to the world log under GLOB.chem_trace.

/// Is this holder's chemistry gated by temperature: does it sit in a loose reagent container?
/datum/reagents/proc/temperature_gated()
	return istype(my_atom, /obj/item/reagent_containers)

/// The temperature the contents react at, K.
/datum/reagents/proc/reaction_temperature()
	return get_temperature()

/// The catalytic activity (0..100) of what sits in the container: a catalyst widens every recipe's ideal band (reaction_temperature_state()).
/datum/reagents/proc/catalyst_activity()
	var/obj/item/reagent_containers/glass/vessel = my_atom
	if(!istype(vessel))
		return 0
	return vessel.catalyst_activity()

/// How the holder's temperature stands against `X`'s band: list(REACTION_TEMP_STATE_*, deviation 0..1), or null when the rule is not gated here (another regime,
/// an ungated holder, or a recipe with no band).
/datum/reagents/proc/reaction_temperature_state(datum/xform/X)
	if(X.regime != REGIME_INSTANT || !ispath(X.rule_type, /transformation/chem) || !temperature_gated())
		return null
	var/list/band = reaction_temperature_profile(X.rule_type)
	if(!band)
		return null
	var/widen = catalyst_activity() * CATALYST_BAND_PER_POINT
	var/low = band[1] - widen
	var/ideal_low = band[2] - widen
	var/ideal_high = band[3] + widen
	var/high = band[4] + widen
	var/temperature = reaction_temperature()
	if(temperature < low || temperature > high)
		return list(REACTION_TEMP_STATE_OUT, 1)
	if(temperature < ideal_low)
		return list(REACTION_TEMP_STATE_COLD, (ideal_low - temperature) / max(ideal_low - low, 0.01))
	if(temperature > ideal_high)
		return list(REACTION_TEMP_STATE_HOT, (temperature - ideal_high) / max(high - ideal_high, 0.01))
	return list(REACTION_TEMP_STATE_IDEAL, 0)

/// Does the holder's temperature let `X` react at all (it is inside the working range, or the rule is not gated)?
/datum/reagents/proc/reaction_temperature_ok(datum/xform/X)
	var/list/state = reaction_temperature_state(X)
	if(!state || state[1] != REACTION_TEMP_STATE_OUT)
		return TRUE
	if(GLOB.chem_trace)
		log_world("CHEM: reaction [X.rule_type] refused in [my_atom]: [round(reaction_temperature() - T0C, 0.1)] C is outside its working range")
	return FALSE

/// A step of `X` made `produced` units: off the ideal band it also makes contaminants and (hot) loses some of the product.
/datum/reagents/proc/apply_temperature_effects(datum/xform/X, produced)
	var/list/state = reaction_temperature_state(X)
	if(!state || state[1] == REACTION_TEMP_STATE_IDEAL || state[1] == REACTION_TEMP_STATE_OUT || produced <= 0)
		return
	var/deviation = state[2]
	if(state[1] == REACTION_TEMP_STATE_COLD)
		var/residue = produced * deviation * REACTION_COLD_RESIDUE_RATE
		add_reagent(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE, residue, safety = 1)
		if(GLOB.chem_trace)
			log_world("CHEM: [X.rule_type] ran cold ([round(reaction_temperature() - T0C, 0.1)] C) in [my_atom]: [round(residue, 0.001)]u organic residue with [round(produced, 0.001)]u of product")
		return
	var/lost = produced * deviation * REACTION_HOT_LOSS_SHARE
	if(X.result && lost > 0)
		remove_reagent(X.result, lost, safety = 1)
	var/impurity = produced * deviation * REACTION_HOT_IMPURITY_RATE
	add_reagent(REAGENT_ID_CONTAMINANT_REACTIVE, impurity, safety = 1)
	if(GLOB.chem_trace)
		log_world("CHEM: [X.rule_type] ran hot ([round(reaction_temperature() - T0C, 0.1)] C) in [my_atom]: [round(impurity, 0.001)]u reactive impurity, [round(lost, 0.001)]u of product lost")
