// What wakes a mob's sleeping Life steps when its surroundings or its body change (doc/rewrite/archive/life_sequence_origin.md §5).
//
// The air watch: breathing and environment sleep in steady air. The mob senses the air of the turf
// it stands on (sense_gas(), code/domains/verdigris/sense.dm): the partial pressures of the gases its lungs
// react to, the temperature and the pressure, each cut at the levels this mob's code acts on (its species' limits, the
// BREATH_* levels). Rust shares one threshold set per cell and channel among every mob and machine that senses it, and reports only a
// band change; the mob hears it as air_changed_here(): MOB_KEY_AIR, the breath and the environment exchange are due again. A change that crosses no level
// changes nothing these steps would do, so it wakes nothing. The watch follows the mob: the steps that read the air
// re-arm it when they run (they run after every move: MOB_KEY_LOC), and the key below skips the re-arm when nothing moved.
// A human's environment exchange averages the temperature of the air around it (its plume), so its watch also holds a
// band on each atmos-adjacent turf's temperature (one watch, a cell per channel). Inside a container the watch is on the
// air the container gives the mob (air_watch_source()): a closet passes its turf's air through, a sealed pod its own; a
// container whose air is made up per breath (a belly) or picked at random (a mech cabin) has none, and the steps that
// read the air stay awake there.
//
// The body heat watch: body temperature lives in Rust (heat_mobs.dm) and drifts with the room through the body's
// couplings. A sensing of the body (sense_heat()) at the levels the body's steps act on (the comfort band around
// the set point, discomfort, harm, the medical metric thresholds) publishes MOB_KEY_BODY_HEAT on a crossing.

/datum/body
	/// The sensings of the air of the turf its mob stands on and the turfs around it, one per channel and mixture (/mob/living/proc/air_watch_arm()).
	var/tmp/list/datum/sense_sub/air_subs
	/// What `air_subs` were armed for (the mixture and the levels), so unchanged sensings are not made again.
	var/tmp/air_watch_key
	/// The watch's own-air bands as armed: list(list(ch, levels, band), ...). A move compares the new air against them
	/// (/mob/living/proc/air_check_moved()): a band that differs is a crossing the watch never sees (it watches the old air).
	var/tmp/list/air_watch_own
	/// The sensing of its mob's body temperature (/mob/living/proc/body_heat_watch_arm()).
	var/tmp/datum/sense_sub/heat/body_heat_watch
	/// The levels `body_heat_watch` was armed with.
	var/tmp/body_heat_watch_key

/// What blocks air on this turf changed (a door opened or closed, a window broke, a wall went up): Rust rebuilt its adjacency, so the air the mobs
/// on this turf and on the turfs around it breathe, stand in and average (their plume) is another set of mixtures than the one their watch is
/// armed on. They re-arm now. Their Life steps do not have to run for it to hold: a sleeping human's steps are asleep because nothing they read
/// moved, and this is a change of what they read that no band crossing reports (code/domains/atmos/environmental/LINDA_system.dm).
/turf/proc/air_structure_changed()
	for(var/turf/T as anything in RANGE_TURFS(1, src))
		for(var/mob/living/L as anything in contents_of(T, /mob/living))
			L.air_watch_structure_changed()

/// This mob's air watch is stale if the mixtures it covers are not the ones it would be armed on now: re-arms it, and when it changed wakes the steps
/// that read the air (their conclusions rest on the old set). A mob with no watch has nothing stale.
/mob/living/proc/air_watch_structure_changed()
	var/datum/body/B = src.body
	if(QDELETED(src) || !B || !(length(B.air_subs) || B.air_watch_key))
		return
	var/before = B.air_watch_key
	air_watch_arm()
	if(B.air_watch_key != before)
		air_changed_here()

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
	var/datum/gas_mixture/air = src.loc?.air_watch_source(src)
	var/id = air?.arena_id()
	if(isnull(id))
		air_watch_clear() // no air to watch here (made up per breath, or still air): the steps that read the air stay awake (air_watched())
		return
	var/datum/body/B = src.body
	if(!B)
		return
	var/list/around = air_watch_around()
	var/list/around_ids = list()
	for(var/datum/gas_mixture/other as anything in around)
		around_ids += other.arena_id()
	var/key = "[id]|[jointext(around_ids, ",")]|[air_watch_levels_key()]"
	if(key == B.air_watch_key && length(B.air_subs))
		return
	air_watch_clear()
	B.air_watch_key = key
	var/list/levels = air_watch_levels()
	if(!length(levels))
		return
	var/list/own = list()
	for(var/ch_text in levels)
		var/ch = text2num(ch_text)
		var/list/normal = air_watch_normalise(levels[ch_text], air_watch_spacing(ch))
		if(!length(normal))
			continue
		rel_add(B, nameof(B.air_subs), sense_gas(src, PROC_REF(air_watch_heard), air, ch, normal))
		own += list(list(ch, normal, air_watch_band_of(air_watch_reading(air, ch), normal)))
	// The plume: each neighbour's temperature at the levels of this mob's own air temperature. While every one of them is
	// inside a band, so is their mean (what the environment exchange reads); a mean that leaves it moves one of them out.
	var/list/temperature_levels = levels["[CH_GAS_TEMPERATURE]"]
	if(length(around) && length(temperature_levels))
		var/list/normal_t = air_watch_normalise(temperature_levels, air_watch_spacing(CH_GAS_TEMPERATURE))
		for(var/datum/gas_mixture/other as anything in around)
			rel_add(B, nameof(B.air_subs), sense_gas(src, PROC_REF(air_watch_heard), other, CH_GAS_TEMPERATURE, normal_t))
	if(!length(B.air_subs))
		return
	B.air_watch_own = own

/// The air around this mob that its steps read besides its own (mixtures with an arena id), or an empty list.
/mob/living/proc/air_watch_around()
	return list()

/// Whether the air this mob's steps read is watched: FALSE in a container whose air can't be watched (made up per breath,
/// picked at random), where the steps that read the air stay awake.
/mob/living/proc/air_watched()
	return src.loc && !isnull(src.loc.air_watch_source(src)?.arena_id())

// ---------------------------------------------------------------- where the air comes from

/// The mixture a living mob inside this atom breathes and stands in, kept (so a watch on it stays valid), or null when there
/// is none to watch: made up per breath, picked at random, or a container that hasn't said (the default).
/atom/proc/air_watch_source(mob/living/L)
	RETURN_TYPE(/datum/gas_mixture)
	return null

/turf/air_watch_source(mob/living/L)
	var/datum/gas_mixture/air = return_air()
	return (air && !istype(air, /datum/gas_mixture/immutable)) ? air : null

/// A mob carried inside another (a holder in its hands) breathes its carrier's air.
/mob/living/air_watch_source(mob/living/L)
	return loc?.air_watch_source(L)

/// Closets, lockers and body bags pass their turf's air through (return_air() and return_air_for_internal_lifeform()).
/obj/structure/closet/air_watch_source(mob/living/L)
	return loc?.air_watch_source(L)

/// A grave makes up a breath of underground air every time.
/obj/structure/closet/grave/air_watch_source(mob/living/L)
	return null

/// A freezer crate hands out a chilled copy of the air.
/obj/structure/closet/crate/freezer/air_watch_source(mob/living/L)
	return null

/// A stasis bag with a tank breathes the tank, which can be swapped.
/obj/structure/closet/body_bag/cryobag/air_watch_source(mob/living/L)
	return tank ? null : ..()

/// A carried small mob breathes its carrier's air.
/obj/item/holder/air_watch_source(mob/living/L)
	return loc?.air_watch_source(L)

/obj/structure/drop_pod/air_watch_source(mob/living/L)
	return air

/obj/structure/transit_tube_pod/air_watch_source(mob/living/L)
	return air_contents

/mob/living/proc/air_watch_clear()
	var/datum/body/B = src.body
	if(!B)
		return
	B.air_watch_key = null
	B.air_watch_own = null
	rel_clear(B, nameof(B.air_subs))

/// Rust: the air this mob stands in (or a neighbour's temperature) moved to another band of its levels.
/mob/living/proc/air_watch_heard(band, was)
	if(QDELETED(src) || !length(src.body?.air_subs))
		return
	air_changed_here()
	air_watch_own_refresh()
	air_hazard_now("its air crossed a level")

// ---------------------------------------------------------------- at once

/// The air this mob stands in crossed a level its steps act on (its air watch, delivered on the urgent lane the frame
/// after the gas changed), or it moved into air in another band (air_check_moved()), or its body temperature crossed a
/// level (the body heat watch): the steps that read the air run now instead of on the next Life frame (up to
/// LIFE_CYCLE away), so the first alert and the first damage tick come at once. Damage pacing stays on the Life
/// cycle: this is one extra run at the change. One per tick: several crossings in the same tick run them once.
/mob/living/proc/air_hazard_now(reason, breath = TRUE)
	if(QDELETED(src) || !src.loc || src.transforming)
		return
	if(src.clock_rate_bio < 1)
		return // in stasis the scheduled frames pace these steps (when = "!in_stasis")
	var/now = TIME_NOW(CLOCK_OWN, src)
	var/environment = STATE_GET(src, breath_hazard, air_hazard_at) != now
	breath = breath && STATE_GET(src, breath_hazard, air_hazard_breath_at) != now
	if(!environment && !breath)
		return
	STATE_SET(src, breath_hazard, air_hazard_at, now)
	if(breath)
		STATE_SET(src, breath_hazard, air_hazard_breath_at, now)
	log_game("AIR_HAZARD_NOW: [src] ([src.type]) runs its air steps at once ([breath ? "breath, " : ""][environment ? "environment" : ""]): [reason]")
	air_hazard_steps(reason, breath, environment)

/// The steps air_hazard_now() runs: the environment exchange (temperature, pressure, a simple mob's gas limits), unless
/// it already ran this tick. A breather's breath is its own (a body heat crossing earlier in the tick takes none).
/mob/living/proc/air_hazard_steps(reason, breath, environment)
	if(environment)
		run_step_now(src, PROC_REF(life_environment), /datum/sequence/life)

/// The watch crossed a level in place: the own bands a move compares against follow the air they watch.
/mob/living/proc/air_watch_own_refresh()
	var/list/own = src.body?.air_watch_own
	var/datum/gas_mixture/air = own && src.loc?.air_watch_source(src)
	if(!air)
		return
	for(var/list/entry as anything in own)
		entry[3] = air_watch_band_of(air_watch_reading(air, entry[1]), entry[2])

/// A move: the air here against the bands the watch was armed with on the air it left. Any band that differs runs the
/// air steps at once (air_hazard_now()). A mob with no watch (no levels, or none to watch where it was) has nothing to
/// compare: its air steps are awake and run on its next frame.
/mob/living/proc/air_check_moved()
	var/list/own = src.body?.air_watch_own
	if(!own || !src.loc || isbelly(src.loc))
		return
	var/datum/gas_mixture/air = src.loc.air_watch_source(src) || src.loc.return_air()
	for(var/list/entry as anything in own)
		var/band = air ? air_watch_band_of(air_watch_reading(air, entry[1]), entry[2]) : 0
		if(band != entry[3])
			air_hazard_now("moved into air in another band")
			return

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
		// Read off the mixture itself, not Rust's level cache: a move compares air no gas frame has stepped yet.
		if(CH_GAS_PRESSURE)
			return air.return_pressure()
		if(CH_GAS_TEMPERATURE)
			return air.return_temperature()
		if(CH_GAS_MOLES)
			return air.total_moles()
		if(CH_GAS_OXYGEN)
			return air.get_moles(/datum/gas/oxygen)
		if(CH_GAS_PLASMA)
			return air.get_moles(/datum/gas/plasma)
		if(CH_GAS_CARBON_DIOXIDE)
			return air.get_moles(/datum/gas/carbon_dioxide)
		if(CH_GAS_O2_CO2_KPA)
			return air_watch_reading(air, CH_GAS_O2_KPA) + air_watch_reading(air, CH_GAS_CO2_KPA)
		if(CH_GAS_NITROGEN)
			return air.get_moles(/datum/gas/nitrogen)
		if(CH_GAS_METHANE)
			return air.get_moles(/datum/gas/methane)
	return gas_reading(air, ch)

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
		var/datum/breath_profile/profile = src.breath_profile()
		if(profile && !profile.uses_lungs)
			// The skin lives on oxygen and CO2 together (skin_exchange()): one band on their sum, and CO2's own levels for
			// the photosynthesis share and the plant's CO2 alert.
			if(S.minimum_breath_pressure > 0)
				air_watch_add(., CH_GAS_O2_CO2_KPA, list(S.minimum_breath_pressure))
				air_watch_add(., CH_GAS_CO2_KPA, list(S.minimum_breath_pressure * 0.25, S.minimum_breath_pressure * 0.5, S.minimum_breath_pressure * 0.75, S.minimum_breath_pressure))
			air_watch_add(., CH_GAS_CO2_KPA, list(BREATH_EXHALED_MAX * 0.7))
		else if(S.minimum_breath_pressure > 0)
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

/// The atmos-adjacent turfs' air the plume temperature averages (life_environment_plume_temperature()).
/mob/living/carbon/human/air_watch_around()
	. = list()
	var/turf/T = src.loc
	if(!isturf(T))
		return
	for(var/turf/N as anything in vg_atmos_adjacent_turfs(T))
		if(N.z != T.z || !N.heat_has_air())
			continue
		var/datum/gas_mixture/air = N.return_air()
		if(air && !istype(air, /datum/gas_mixture/immutable) && !isnull(air.arena_id()))
			. += air

/mob/living/carbon/human/air_watch_levels_key()
	return "[src.species?.type]|[src.breathes()]|[air_watch_body_reference()]"

/mob/living/carbon/air_changed_here()
	var/datum/physiology/P = src.body?.physiology
	if(P)
		P.air_stale = TRUE
	..()

/mob/living/carbon/human/air_changed_here()
	STATE_SET(src, human_misc, environment_steady, FALSE)
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
	rel_set(B, nameof(B.body_heat_watch), sense_heat(src, PROC_REF(body_heat_heard), src, levels, keep_body = FALSE))
	body_heat_changed() // new levels: the steps that read the band are due again (a registration says nothing until the band moves)

/// Rust: the body temperature crossed one of this mob's levels.
/mob/living/proc/body_heat_heard(band, was)
	if(QDELETED(src))
		return
	body_heat_changed()
	air_hazard_now("its body temperature crossed a level", breath = FALSE)

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
	STATE_SET(src, human_misc, environment_steady, FALSE)
	src.body?.invalidate(BODY_DIRTY_METRICS) // the medical metric triggers read the body temperature
	..()

/// A simple mob is harmed outside its body temperature range.
/mob/living/simple_mob/body_heat_levels()
	return list(src.minbodytemp, src.maxbodytemp)
