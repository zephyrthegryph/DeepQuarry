// P2-S7 / P2-D8: how a body breathes, asked in one place.
//
// `mob.breath_profile()` (the body decides) returns a flyweight /datum/breath_profile, or null for
// a body that doesn't breathe at all (no lungs, a does_not_breathe grant, mNobreath, ...).
// `mob.breathes()` is the yes/no question. Emotes, vitals, smoke, the physiology and the
// breathing life stage all ask these instead of reading does_not_breathe / O_LUNGS themselves.
//
// The profile also owns HOW a breath is taken: lungs (the breathing step's life_breathing_lung_breath()) or
// the skin (alraunes: CO2 in, oxygen out, no masks), which used to be a 200-line copy of the
// breath code in the species' environment_effects().

/// The shared instance of a breath profile type.
/proc/breath_profile_instance(profile_type)
	var/static/list/instances = list()
	var/datum/breath_profile/P = instances[profile_type]
	if(!P)
		P = new profile_type
		instances[profile_type] = P
	return P

/datum/breath_profile
	var/name = "lungs"
	/// Breathes through lungs. FALSE: through the skin (no lung organ; masks don't filter).
	var/uses_lungs = TRUE

/// Take one breath for `self`, driven by its breathing Life step.
/datum/breath_profile/proc/take_breath(mob/living/carbon/self)
	self.life_breathing_lung_breath()

// --- Asking --------------------------------------------------------------------------------

/// This body's breath profile, or null if it doesn't breathe.
/datum/body/proc/breath_profile()
	var/mob/living/carbon/C = owner
	if(istype(C))
		if(C.does_not_breathe || C.has_mutation(mNobreath) || !C.should_have_organ(O_LUNGS))
			return null
		return breath_profile_instance(/datum/breath_profile)
	// Simple mobs and silicons: organic bodies breathe (their environment stage reads the air).
	return (biology_of(null) & BIOLOGY_ORGANIC) ? breath_profile_instance(/datum/breath_profile) : null

/// Humanoids: the species may breathe some other way (breath_profile_type); otherwise lungs.
/datum/body/humanoid/breath_profile()
	var/mob/living/carbon/human/H = owner
	if(!H.species || H.does_not_breathe || H.has_mutation(mNobreath))
		return null
	if(H.species.breath_profile_type)
		return breath_profile_instance(H.species.breath_profile_type)
	return H.should_have_organ(O_LUNGS) ? breath_profile_instance(/datum/breath_profile) : null

/// Does this mob breathe at all?
/mob/living/proc/breathes()
	return !!breath_profile()

/// How this mob breathes (a /datum/breath_profile), or null.
/mob/living/proc/breath_profile()
	RETURN_TYPE(/datum/breath_profile)
	return body?.breath_profile()

/// The one writer of does_not_breathe (changeling self-respiration, the nobreathe trait,
/// xenochimera): the physiology re-reads whether the body breathes.
/mob/living/carbon/proc/set_does_not_breathe(value)
	value = !!value
	if(does_not_breathe == value)
		return
	does_not_breathe = value
	body?.invalidate(BODY_DIRTY_PHYSIOLOGY)

// --- Shared breath chemistry (lungs and skin) ---------------------------------------------

/// Poison gas (the species' poison_type) in the breath: toxin in the blood and an alert.
/mob/living/carbon/human/proc/breathe_poison(datum/gas_mixture/breath, poison_type, breath_moles, breath_pressure)
	var/safe_toxins_min = 0.05
	var/safe_toxins_max = 0.2
	var/poison = LINDA_GAS_AMT(breath, poison_type)
	var/toxins_pp = (poison / breath_moles) * breath_pressure
	if(toxins_pp > safe_toxins_min)
		var/phoron_pp = (LINDA_GAS_AMT(breath, GAS_PHORON) / breath_moles) * breath_pressure
		if(phoron_pp > 0.05 && prob(3))
			to_chat(src, span_warning("Something burns as you breathe."))
	if(toxins_pp > safe_toxins_max)
		var/ratio = (poison / safe_toxins_max) * 10
		if(reagents)
			reagents.add_reagent(REAGENT_ID_TOXIN, CLAMP(ratio, MIN_TOXIN_DAMAGE, MAX_TOXIN_DAMAGE))
			breath.adjust_gas(poison_type, -poison / 6, update = 0) //update after
		throw_alert("tox_in_air", /atom/movable/screen/alert/tox_in_air)
	else
		clear_alert("tox_in_air")

/// Nitrous oxide in the breath: giggles, then paralysis, then sleep.
/mob/living/carbon/human/proc/breathe_sleeping_gas(datum/gas_mixture/breath, breath_moles, breath_pressure)
	var/n2o = LINDA_GAS_AMT(breath, GAS_N2O)
	if(!n2o)
		return
	var/SA_para_min = 1
	var/SA_sleep_min = 5
	var/SA_pp = (n2o / breath_moles) * breath_pressure
	// Enough to make us paralysed for a bit
	if(SA_pp > SA_para_min)
		// 3 gives them one second to wake up and run away a bit!
		status_at_least(STAT_PARALYZED, 3)
		status_at_least(STAT_SLEEPING, 1)
		// Enough to make us sleep as well
		if(SA_pp > SA_sleep_min)
			status_at_least(STAT_SLEEPING, 5)
	// There is sleeping gas in their lungs, but only a little, so give them a bit of a warning
	else if(SA_pp > 0.15)
		if(prob(20))
			emote(pick("giggle", "laugh"))
	breath.adjust_gas(GAS_N2O, -n2o / 6, update = 0) //update after

/// Wearing a sealed suit and helmet (internals take priority for skin breathing and the sun
/// barely reaches the skin).
/mob/living/carbon/human/proc/is_fully_sealed()
	var/obj/item/suit = get_equipped_item(SLOT_ID_SUIT)
	var/obj/item/helmet = get_equipped_item(SLOT_ID_HEAD)
	if(!suit || !helmet || !species)
		return FALSE
	return suit.min_pressure_protection < species.hazard_low_pressure && helmet.min_pressure_protection < species.hazard_low_pressure

// --- Skin breathing (alraunes) ------------------------------------------------------------

/mob/living
	/// 0..1: how much of the photosynthesis gas (CO2) the last skin breath carried. Boosts the
	/// photosynthesis trait's gains (/datum/trait_state/photosynth boosted_* vars).
	var/tmp/photosynthesis_boost = 0

/// Breathes through the skin: takes CO2 in, gives oxygen out, either gas keeps the tissue
/// alive. No lungs, so no smoke masks, no lung rupture and no breath sounds.
/datum/breath_profile/skin
	name = "skin"
	uses_lungs = FALSE
	/// The gas the skin takes in.
	var/intake_gas = GAS_CO2

/datum/breath_profile/skin/take_breath(mob/living/carbon/self)
	var/mob/living/carbon/human/H = self
	if(!istype(H) || !H.species)
		return
	var/datum/gas_mixture/breath = skin_breath_source(H)
	skin_exchange(H, breath)
	H.life_breathing_exhale(breath)

/// Where the skin's air comes from: internals under a sealed suit or in thin air, else the room.
/datum/breath_profile/skin/proc/skin_breath_source(mob/living/carbon/human/H)
	var/datum/gas_mixture/breath
	if(H.is_fully_sealed())
		breath = H.get_breath_from_internal()
	else
		// P2-F9: no loc (nullspace, being moved) means no air, not a runtime.
		var/datum/gas_mixture/environment = H.loc?.return_air()
		if((environment ? environment.return_pressure() : 0) < H.species.hazard_low_pressure)
			breath = H.get_breath_from_internal()
	if(!breath && H.loc)
		// Gas masks give the skin no benefit.
		var/datum/gas_mixture/room = H.loc.return_air_for_internal_lifeform(H)
		if(room)
			breath = room.remove_volume(BREATH_VOLUME)
			H.life_breathing_inhale_smoke(room)
	return breath

/// Gas exchange through the skin. Reports breath quality to the physiology and the CO2 share
/// to the photosynthesis trait.
/datum/breath_profile/skin/proc/skin_exchange(mob/living/carbon/human/H, datum/gas_mixture/breath)
	var/breath_total = breath ? xgm_total_moles(breath) : 0
	if(!breath_total)
		H.failed_last_breath = 1
		H.photosynthesis_boost = 0
		H.body?.set_breath_quality(0)
		H.throw_alert("pressure", /atom/movable/screen/alert/lowpressure)
		return
	H.clear_alert("pressure")

	var/datum/species/S = H.species
	var/safe_exhaled_max = 10
	var/min_pressure = S.minimum_breath_pressure
	var/breath_pressure = (breath_total * R_IDEAL_GAS_EQUATION * breath.return_temperature()) / BREATH_VOLUME
	var/inhaling = LINDA_GAS_AMT(breath, intake_gas)
	var/exhaling = LINDA_GAS_AMT(breath, S.exhale_type)
	var/inhale_pp = (inhaling / breath_total) * breath_pressure
	var/exhaled_pp = (exhaling / breath_total) * breath_pressure

	// Either the intake gas or the exhale gas (oxygen) keeps the tissue alive.
	var/quality = 1
	var/failed = FALSE
	if((inhale_pp + exhaled_pp) < min_pressure)
		if(prob(20))
			H.emote("gasp")
		quality = min_pressure > 0 ? clamp((inhale_pp + exhaled_pp) / min_pressure, 0, 1) : 0
		failed = TRUE
		H.throw_alert("oxy", /atom/movable/screen/alert/not_enough_co2)
	else
		H.clear_alert("oxy")

	var/used = inhaling / 6
	breath.adjust_gas(intake_gas, -used, update = 0) //update afterwards
	breath.adjust_gas_temp(S.exhale_type, used, H.body_temperature(), update = 0) //update afterwards

	// Plenty of CO2 would be too much exhaled gas for a human; plants like it, and the alert tells them it's there.
	if(inhale_pp > safe_exhaled_max * 0.7)
		H.throw_alert("co2", /atom/movable/screen/alert/too_much_co2/plant)
	else
		H.clear_alert("co2")
	H.photosynthesis_boost = (inhaling && min_pressure > 0) ? clamp(inhale_pp, 0, min_pressure) / min_pressure : 0

	H.breathe_poison(breath, S.poison_type, breath_total, breath_pressure)
	H.breathe_sleeping_gas(breath, breath_total, breath_pressure)

	H.failed_last_breath = failed ? 1 : 0
	H.body?.set_breath_quality(quality)
	skin_temperature(H, breath, breath_total)

/// Hot or cold air on the skin: burns or frostbite on a random part, and a little body heat exchange.
/datum/breath_profile/skin/proc/skin_temperature(mob/living/carbon/human/H, datum/gas_mixture/breath, breath_total)
	var/datum/species/S = H.species
	var/breath_temperature = breath.return_temperature()
	if((breath_temperature < S.breath_cold_level_1 || breath_temperature > S.breath_heat_level_1) && !(H.has_mutation(COLD_RESISTANCE)))
		var/static/list/skin_parts = list(BP_L_FOOT, BP_R_FOOT, BP_L_LEG, BP_R_LEG, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_TORSO, BP_GROIN, BP_HEAD)
		var/bodypart = pick(skin_parts)
		if(breath_temperature >= S.breath_heat_level_1)
			if(prob(20))
				to_chat(H, span_danger("You feel yourself smouldering in the heat!"))
			if(breath_temperature < S.breath_heat_level_2)
				H.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_1, bodypart)
			else if(breath_temperature < S.breath_heat_level_3)
				H.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_2, bodypart)
			else
				H.injure(INJURY_BURN, HEAT_GAS_DAMAGE_LEVEL_3, bodypart)
		else
			if(prob(20))
				to_chat(H, span_danger("You feel icicles forming on your skin!"))
			if(breath_temperature > S.breath_cold_level_2)
				H.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_1, bodypart)
			else if(breath_temperature > S.breath_cold_level_3)
				H.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_2, bodypart)
			else
				H.injure(INJURY_FROSTBITE, COLD_GAS_DAMAGE_LEVEL_3, bodypart)

		// Air on the skin also heats or cools the body a bit.
		var/temp_adj = breath_temperature - H.body_temperature()
		if(temp_adj < 0)
			temp_adj /= (BODYTEMP_COLD_DIVISOR * 5)	//don't raise temperature as much as if we were directly exposed
		else
			temp_adj /= (BODYTEMP_HEAT_DIVISOR * 5)	//don't raise temperature as much as if we were directly exposed
		temp_adj *= breath_total / (MOLES_CELLSTANDARD * BREATH_PERCENTAGE)
		H.adjust_bodytemperature(clamp(temp_adj, BODYTEMP_COOLING_MAX, BODYTEMP_HEATING_MAX))
	else if(breath_temperature >= S.heat_discomfort_level)
		S.get_environment_discomfort(H, "heat")
	else if(breath_temperature <= S.cold_discomfort_level)
		S.get_environment_discomfort(H, "cold")
