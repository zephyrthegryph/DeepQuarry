// What wakes a mob's sleeping Life steps when its surroundings or its body change (doc/rewrite/life_on_om.md §5).
//
// The air watch: breathing and environment sleep in steady air. Rust holds one band watch per mob on the air of the turf
// it stands on (COND_BANDS, verdigris/ffi/src/sched.rs world_watch_bands): the partial pressures of the gases its lungs
// react to, the temperature and the pressure, each cut at the levels this mob's code acts on (its species' limits, the
// BREATH_* levels). Rust evaluates it only when the turf's gas changed, and reports only a crossing; the mob hears it as
// air_changed_here(): MOB_KEY_AIR, the breath and the environment exchange are due again. A change that crosses no level
// changes nothing these steps would do, so it wakes nothing. The watch follows the mob: the steps that read the air
// re-arm it when they run (they run after every move: MOB_KEY_LOC), and the key below skips the re-arm when nothing moved.
//
// The body heat watch: body temperature lives in Rust (heat_mobs.dm) and drifts with the room through the body's
// couplings. A band watch on the body (heat_watch_band()) at the levels the body's steps act on (the comfort band around
// the set point, discomfort, harm, the medical metric thresholds) publishes MOB_KEY_BODY_HEAT on a crossing.

/datum/body
	/// The Rust band watch on the air of the turf its mob stands on (/mob/living/proc/air_watch_arm()).
	var/tmp/datum/native_watch/world/air_watch
	/// What `air_watch` was armed for (the mixture and the levels), so an unchanged watch is not re-armed.
	var/tmp/air_watch_key
	/// The Rust band watch on its mob's body temperature (/mob/living/proc/body_heat_watch_arm()).
	var/tmp/datum/native_watch/heat/body_heat_watch
	/// The levels `body_heat_watch` was armed with.
	var/tmp/body_heat_watch_key

/// The air on this mob's turf crossed a level that matters to it (its air watch), or this mob was told the air changed.
/// The steps that read the air (MOB_KEY_AIR) are due again.
/mob/living/proc/air_changed_here()
	PUBLISH_CHANGE(src, MOB_KEY_AIR)

/// The gas channels and levels this mob's Life steps act on: list("[CH_GAS_*]" = list(levels, ...)), or null for no
/// air watch. Levels need not be sorted or unique (air_watch_arm() normalises them).
/mob/living/proc/air_watch_levels()
	return null

/// What air_watch_levels() depends on besides the species and type (a body temperature it is relative to, ...): a change
/// of this text re-arms the watch.
/mob/living/proc/air_watch_levels_key()
	return ""

/// Points this mob's air watch at the air it stands in now. Cheap when nothing changed: the steps that read the air call
/// it every time they run.
/mob/living/proc/air_watch_arm()
	var/turf/T = src.loc
	var/datum/gas_mixture/air = isturf(T) ? T.return_air() : null
	var/id = (air && !istype(air, /datum/gas_mixture/immutable)) ? air.arena_id() : null
	if(isnull(id))
		air_watch_clear() // off a turf (a container wakes the steps that read its air itself: they stay awake there) or in still air
		return
	var/datum/body/B = src.body
	if(!B)
		return
	var/key = "[id]|[air_watch_levels_key()]"
	if(key == B.air_watch_key && B.air_watch)
		return
	air_watch_clear()
	B.air_watch_key = key
	var/list/levels = air_watch_levels()
	if(!length(levels))
		return
	var/list/chs = list()
	var/list/cuts = list()
	var/list/starts = list()
	for(var/ch_text in levels)
		var/ch = text2num(ch_text)
		var/list/normal = air_watch_normalise(levels[ch_text], air_watch_spacing(ch))
		if(!length(normal))
			continue
		chs += ch
		cuts += list(normal)
		starts += air_watch_band_of(air_watch_reading(air, ch), normal)
	if(!length(chs))
		return
	rel_set(B, nameof(B.air_watch), world_watch_when(src, COND_BANDS(WORLD_GAS_HANDLE(air), chs, cuts, starts, -1), PROC_REF(air_watch_heard), LANE_URGENT))

/mob/living/proc/air_watch_clear()
	var/datum/body/B = src.body
	if(!B)
		return
	B.air_watch_key = null
	if(B.air_watch)
		own_clear(B, nameof(B.air_watch), OWN_DELETE)

/// Rust: the air this mob stands in crossed one of its levels.
/mob/living/proc/air_watch_heard(datum/native_watch/world/W, reason, source, source_kind)
	if(QDELETED(src) || W != src.body?.air_watch)
		return
	air_changed_here()

/// The band of `value` among ascending `levels`: how many are at or under it (Rust's band index).
/proc/air_watch_band_of(value, list/levels)
	. = 0
	for(var/level in levels)
		if(level > value)
			return
		.++

/// The reading of `air` on gas channel `ch`, as Rust computes it (cell.rs gas_ch).
/proc/air_watch_reading(datum/gas_mixture/air, ch)
	var/static/list/kpa_gases = list("[CH_GAS_O2_KPA]" = /datum/gas/oxygen, "[CH_GAS_N2_KPA]" = /datum/gas/nitrogen, "[CH_GAS_CO2_KPA]" = /datum/gas/carbon_dioxide, 		"[CH_GAS_PLASMA_KPA]" = /datum/gas/plasma, "[CH_GAS_N2O_KPA]" = /datum/gas/nitrous_oxide, "[CH_GAS_CH4_KPA]" = /datum/gas/methane, "[CH_GAS_FUEL_KPA]" = /datum/gas/volatile_fuel)
	var/gas = kpa_gases["[ch]"]
	if(gas)
		var/total = air.total_moles()
		return total > 0 ? air.get_moles(gas) / total * air.return_pressure() : 0
	switch(ch)
		if(CH_GAS_NITROGEN)
			return air.get_moles(/datum/gas/nitrogen)
		if(CH_GAS_METHANE)
			return air.get_moles(/datum/gas/methane)
	return gas_level_read(air, ch)

/// The least distance between two levels of channel `ch`: a band is wider than the channel's hysteresis (Rust checks it).
/proc/air_watch_spacing(ch)
	switch(ch)
		if(CH_GAS_PRESSURE, CH_GAS_TEMPERATURE)
			return 0.6
		if(CH_GAS_MOLES, CH_GAS_OXYGEN, CH_GAS_PLASMA, CH_GAS_CARBON_DIOXIDE, CH_GAS_NITROGEN, CH_GAS_METHANE)
			return 0.12
	return 0.025

/// `levels` sorted, positive, and at least `spacing` apart (a level too close to the one below it is dropped).
/proc/air_watch_normalise(list/levels, spacing)
	var/list/sorted = list()
	for(var/level in levels)
		if(isnum(level) && level > 0 && level < INFINITY)
			sorted += level
	sortTim(sorted, GLOBAL_PROC_REF(cmp_numeric_asc))
	. = list()
	var/last = -INFINITY
	for(var/level in sorted)
		if(level - last >= spacing)
			. += level
			last = level

/// Adds `values` to channel `ch`'s levels in the assoc `levels`.
/proc/air_watch_add(list/levels, ch, list/values)
	var/key = "[ch]"
	if(!levels[key])
		levels[key] = list()
	var/list/L = levels[key]
	L += values

/// The partial-pressure channel of breath gas `gas` (a GAS_* id), or null when no channel follows it.
/proc/air_watch_gas_channel(gas)
	var/static/list/channels = list(
		GAS_O2 = CH_GAS_O2_KPA,
		GAS_N2 = CH_GAS_N2_KPA,
		GAS_CO2 = CH_GAS_CO2_KPA,
		GAS_PHORON = CH_GAS_PLASMA_KPA,
		GAS_N2O = CH_GAS_N2O_KPA,
		GAS_CH4 = CH_GAS_CH4_KPA,
		GAS_VOLATILE_FUEL = CH_GAS_FUEL_KPA,
	)
	return gas ? channels[gas] : null

// ---------------------------------------------------------------- humans

/// A human's levels: what its breath exchange acts on (if it breathes) and what its environment exchange acts on.
/mob/living/carbon/human/air_watch_levels()
	var/datum/species/S = src.species
	if(!S)
		return null
	. = list()
	if(src.breathes())
		var/breath_type = S.breath_type || GAS_O2
		if(S.minimum_breath_pressure > 0)
			air_watch_add(., air_watch_gas_channel(breath_type), list(S.minimum_breath_pressure))
		if(S.exhale_type)
			air_watch_add(., air_watch_gas_channel(S.exhale_type), list(BREATH_EXHALED_MAX * 0.6, BREATH_EXHALED_MAX * 0.7, BREATH_EXHALED_MAX))
		air_watch_add(., air_watch_gas_channel(S.poison_type || GAS_PHORON), list(BREATH_TOXINS_MIN, BREATH_TOXINS_MAX))
		air_watch_add(., CH_GAS_PLASMA_KPA, list(BREATH_TOXINS_MIN))
		air_watch_add(., CH_GAS_N2O_KPA, list(BREATH_N2O_GIGGLE, BREATH_N2O_PARALYSE, BREATH_N2O_SLEEP))
		if(breath_type != GAS_CH4)
			air_watch_add(., CH_GAS_CH4_KPA, list(BREATH_TOXINS_MIN, BREATH_TOXINS_MAX))
		// Breath temperature: harm and discomfort.
		air_watch_add(., CH_GAS_TEMPERATURE, list(S.breath_cold_level_3, S.breath_cold_level_2, S.breath_cold_level_1, S.cold_discomfort_level, \
			S.heat_discomfort_level, S.breath_heat_level_1, S.breath_heat_level_2, S.breath_heat_level_3))
	// The environment exchange idles while the air is within 20 K of the body and the pressure inside the warning band.
	var/body = air_watch_body_reference()
	air_watch_add(., CH_GAS_TEMPERATURE, list(body - 20, body + 20))
	air_watch_add(., CH_GAS_PRESSURE, list(S.hazard_low_pressure, S.warning_low_pressure, S.warning_high_pressure, S.hazard_high_pressure))

/// The body temperature the environment levels are relative to, rounded to a kelvin (a change of it re-arms the watch).
/mob/living/carbon/human/proc/air_watch_body_reference()
	return round(src.body_temperature(), 1)

/mob/living/carbon/human/air_watch_levels_key()
	return "[src.species?.type]|[src.breathes()]|[air_watch_body_reference()]"

/mob/living/carbon/air_changed_here()
	var/datum/physiology/P = src.body?.physiology
	if(P)
		P.air_stale = TRUE
	..()

/mob/living/carbon/human/air_changed_here()
	src.environment_steady = FALSE
	..()

// ---------------------------------------------------------------- simple mobs

/// A simple mob's limits are moles of gas and a temperature range around its body.
/mob/living/simple_mob/air_watch_levels()
	. = list()
	air_watch_add(., CH_GAS_OXYGEN, list(src.min_oxy, src.max_oxy))
	air_watch_add(., CH_GAS_PLASMA, list(src.min_tox, src.max_tox))
	air_watch_add(., CH_GAS_NITROGEN, list(src.min_n2, src.max_n2))
	air_watch_add(., CH_GAS_CARBON_DIOXIDE, list(src.min_co2, src.max_co2))
	air_watch_add(., CH_GAS_METHANE, list(src.min_ch4, src.max_ch4))
	if(src.temperature_range < INFINITY)
		var/body = round(src.body_temperature(), 1)
		air_watch_add(., CH_GAS_TEMPERATURE, list(body - src.temperature_range, body + src.temperature_range))

/mob/living/simple_mob/air_watch_levels_key()
	return "[src.min_oxy],[src.max_oxy],[src.min_tox],[src.max_tox],[src.min_n2],[src.max_n2],[src.min_co2],[src.max_co2],[src.min_ch4],[src.max_ch4],[src.temperature_range]|[round(src.body_temperature(), 1)]"

// ---------------------------------------------------------------- body heat

/// The body temperatures this mob's steps act on, or null for no body heat watch.
/mob/living/proc/body_heat_levels()
	return null

/// Points the body heat watch at the levels this body acts on now. Cheap when they did not change.
/mob/living/proc/body_heat_watch_arm()
	var/list/levels = body_heat_levels()
	if(length(levels))
		levels = air_watch_normalise(levels, 0.2)
	var/datum/body/B = src.body
	if(!B)
		return
	var/key = jointext(levels || list(), ",")
	if(key == B.body_heat_watch_key && (B.body_heat_watch || !length(levels)))
		return
	if(B.body_heat_watch)
		own_clear(B, nameof(B.body_heat_watch), OWN_DELETE)
	B.body_heat_watch_key = key
	if(!length(levels))
		return
	rel_set(B, nameof(B.body_heat_watch), heat_watch_band(src, src, levels, PROC_REF(body_heat_heard), keep_body = FALSE))

/// Rust: the body temperature crossed one of this mob's levels.
/mob/living/proc/body_heat_heard(datum/native_watch/heat/W, reason, source)
	if(QDELETED(src) || W != src.body?.body_heat_watch)
		return
	body_heat_changed()

/// The body temperature moved into another band: the steps that read it are due again.
/mob/living/proc/body_heat_changed()
	PUBLISH_CHANGE(src, MOB_KEY_BODY_HEAT)

/// The comfort band around the set point (thermoregulation), discomfort and harm (environment), and the medical metric
/// thresholds (hypothermia, heatstroke).
/mob/living/carbon/human/body_heat_levels()
	var/datum/species/S = src.species
	if(!S || isnull(S.body_temperature))
		return null
	var/setpoint = src.thermal_setpoint()
	var/normal = src.dq_normal_body_temperature()
	return list(S.cold_level_3, S.cold_level_2, S.cold_level_1, S.cold_discomfort_level, setpoint - 0.5, setpoint + 0.5, \
		S.heat_discomfort_level, S.heat_level_1, S.heat_level_2, S.heat_level_3, normal - DQ_COLD_EXPOSURE_KELVIN, normal + DQ_HEAT_EXPOSURE_KELVIN)

/mob/living/carbon/human/body_heat_changed()
	src.environment_steady = FALSE
	src.body?.invalidate(BODY_DIRTY_METRICS) // the medical metric triggers read the body temperature
	..()

/// A simple mob is harmed outside its body temperature range.
/mob/living/simple_mob/body_heat_levels()
	return list(src.minbodytemp, src.maxbodytemp)
