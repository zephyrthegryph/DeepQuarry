// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

// Simple mob Life: the living core, then these TAIL stages in the old order:
//	vitals (health display), then [alive] (the old `if(stat >= DEAD) return FALSE`) statuses,
//	supernatural, special, guts, healing, then the type_post variants.

/// Health display. Death is decided by the body (evaluate_status -> death()).
/mob/living/simple_mob/proc/life_simple_vitals(datum/seq_frame/life/F)
	src.update_health_display()

/// Event-driven: health and stat changes wake it.

/// Passive healing while fed.
/mob/living/simple_mob/proc/life_simple_healing(datum/seq_frame/life/F)
	src.do_healing()

/// Heals only while hurt and fed.
/mob/living/simple_mob/proc/life_simple_healing_due()
	return src.nutrition >= 150 && src.is_injured()

/mob/living/simple_mob/life_type_post_due()
	return FALSE

/// Refreshes the health HUD, nutrition alert and injury slowdown. Death itself
/// is handled by the body plan (total load >= endurance -> death()).
/mob/living/simple_mob/proc/update_health_display()
	get_injury_level()
	//Update our hud if we have one
	if(healths)
		healths.icon_state = vitality_health_band(src)

	//Updates the nutrition while we're here
	switch(nutrition)
		if(250 to INFINITY)
			clear_alert("nutrition")
		if(150 to 250)
			throw_alert("nutrition", /atom/movable/screen/alert/hungry)
		if(-INFINITY to 150)
			throw_alert("nutrition", /atom/movable/screen/alert/starving)

// ADD START - I made this for catslugs but tbh it's probably cool to give to everything.
//Gives all simplemobs passive healing as long as they can find food.
//Slow enough that it should affect combat basically not at all

/mob/living/simple_mob/proc/do_healing()
	if(nutrition < 150)
		return
	if(!is_injured())
		return
	if(heal_countdown > 0)
		heal_countdown --
		return
	if(resting)
		natural_mend(10)
		adjust_nutrition(-(50))
		heal_countdown = 5
		return
	natural_mend(1)
	adjust_nutrition(-(5))
	heal_countdown = 5

/// Natural regeneration: physical injury first, then burns. Mechanical mobs
/// (synthetic biology) self-repair plating then wiring instead.
/mob/living/simple_mob/proc/natural_mend(amount)
	if(biology & BIOLOGY_ORGANIC)
		if(!mend(TREAT_TISSUE_REPAIR, amount))
			mend(TREAT_BURN_CARE, amount)
	else
		if(!mend(TREAT_PLATING_REPAIR, amount))
			mend(TREAT_WIRING_REPAIR, amount)
// ADD END

/// Per-type behaviour (the old handle_special() overrides). Variants mirror the mob path.
/mob/living/simple_mob/proc/life_special(datum/seq_frame/life/F)
	return

/mob/living/simple_mob/proc/life_special_due()
	return FALSE

/// Idle while the air is survivable and the body has nothing for it to treat. Air that
/// changes in place (a breach) is caught by a slow timer: atmos has no per-mob signal yet.
/mob/living/simple_mob/life_environment_due()
	if(src.is_incorporeal() || !src.loc)
		return FALSE
	if(LAZYLEN(src.body?.afflictions))
		return TRUE
	if(src.body_temperature() < src.minbodytemp || src.body_temperature() > src.maxbodytemp)
		return TRUE
	var/datum/gas_mixture/environment = isbelly(src.loc) ? src.loc.return_air_for_internal_lifeform(src) : src.loc.return_air()
	return environment && !src.environment_is_safe(environment)

/mob/living/simple_mob/life_environment_rewake()
	return 15 SECONDS

/// TRUE when exchange() would change nothing: temperature within the mob's range and every
/// gas inside its bounds. Read-only; shared by the sleep rule and the hibernation audit.
/mob/living/simple_mob/proc/environment_is_safe(datum/gas_mixture/environment)
	if(abs(environment.return_temperature() - body_temperature()) > temperature_range)
		return FALSE
	var/o2 = LINDA_GAS_AMT(environment, GAS_O2)
	if((min_oxy && o2 < min_oxy) || (max_oxy && o2 > max_oxy))
		return FALSE
	var/phoron = LINDA_GAS_AMT(environment, GAS_PHORON)
	if((min_tox && phoron < min_tox) || (max_tox && phoron > max_tox))
		return FALSE
	var/n2 = LINDA_GAS_AMT(environment, GAS_N2)
	if((min_n2 && n2 < min_n2) || (max_n2 && n2 > max_n2))
		return FALSE
	var/co2 = LINDA_GAS_AMT(environment, GAS_CO2)
	if((min_co2 && co2 < min_co2) || (max_co2 && co2 > max_co2))
		return FALSE
	var/ch4 = LINDA_GAS_AMT(environment, GAS_CH4)
	if((min_ch4 && ch4 < min_ch4) || (max_ch4 && ch4 > max_ch4))
		return FALSE
	return TRUE

/// Handle interacting with and taking damage from atmos.
/mob/living/simple_mob/life_environment_exchange(datum/gas_mixture/environment)
	if(src.is_incorporeal())
		return 1

	var/env_temperature = environment.return_temperature()
	if( abs(env_temperature - src.body_temperature()) > src.temperature_range )
		src.adjust_bodytemperature(((env_temperature - src.body_temperature()) / 5))

	// Accumulate (|=) failures across gas blocks so an earlier failing gas
	// isn't masked by a later passing one.
	var/atmos_unsuitable = 0
	if(src.min_oxy && LINDA_GAS_AMT(environment, GAS_O2) < src.min_oxy)
		atmos_unsuitable |= 1
		src.throw_alert("oxy", /atom/movable/screen/alert/not_enough_oxy)
	else if(src.max_oxy && LINDA_GAS_AMT(environment, GAS_O2) > src.max_oxy)
		atmos_unsuitable |= 1
		src.throw_alert("oxy", /atom/movable/screen/alert/too_much_oxy)
	else
		src.clear_alert("oxy")

	if(src.min_tox && LINDA_GAS_AMT(environment, GAS_PHORON) < src.min_tox)
		atmos_unsuitable |= 2
		src.throw_alert("tox_in_air", /atom/movable/screen/alert/not_enough_tox)
	else if(src.max_tox && LINDA_GAS_AMT(environment, GAS_PHORON) > src.max_tox)
		atmos_unsuitable |= 2
		src.throw_alert("tox_in_air", /atom/movable/screen/alert/tox_in_air)
	else
		src.clear_alert("tox_in_air")

	if(src.min_n2 && LINDA_GAS_AMT(environment, GAS_N2) < src.min_n2)
		atmos_unsuitable |= 1
		src.throw_alert("n2o", /atom/movable/screen/alert/not_enough_nitro)
	else if(src.max_n2 && LINDA_GAS_AMT(environment, GAS_N2) > src.max_n2)
		atmos_unsuitable |= 1
		src.throw_alert("n2o", /atom/movable/screen/alert/too_much_nitro)
	else
		src.clear_alert("n2o")

	if(src.min_co2 && LINDA_GAS_AMT(environment, GAS_CO2) < src.min_co2)
		atmos_unsuitable |= 1
		src.throw_alert("co2", /atom/movable/screen/alert/not_enough_co2)
	else if(src.max_co2 && LINDA_GAS_AMT(environment, GAS_CO2) > src.max_co2)
		atmos_unsuitable |= 1
		src.throw_alert("co2", /atom/movable/screen/alert/too_much_co2)
	else
		src.clear_alert("co2")

	if(src.min_ch4 && LINDA_GAS_AMT(environment, GAS_CH4) < src.min_ch4)
		atmos_unsuitable |= 2
		src.throw_alert("methane_in_air", /atom/movable/screen/alert/not_enough_methane)
	else if(src.max_ch4 && LINDA_GAS_AMT(environment, GAS_CH4) > src.max_ch4)
		atmos_unsuitable |= 2
		src.throw_alert("methane_in_air", /atom/movable/screen/alert/methane_in_air)
	else
		src.clear_alert("methane_in_air")

	//Atmos effect
	if(src.body_temperature() < src.minbodytemp)
		src.injure(INJURY_FROSTBITE, src.cold_damage_per_tick, source = src.loc, flags = INJURE_CONTINUOUS)
		src.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MAX)
	else if(src.body_temperature() > src.maxbodytemp)
		src.injure(INJURY_BURN, src.heat_damage_per_tick, source = src.loc, flags = INJURE_CONTINUOUS)
		src.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
	else
		src.clear_alert("temp")

	if(atmos_unsuitable)
		src.add_oxygen_debt(src.unsuitable_atoms_damage, src.loc)
	else
		src.mend(TREAT_OXYGENATION, src.unsuitable_atoms_damage)

/// Organ processing.
/mob/living/simple_mob/proc/life_guts(datum/seq_frame/life/F)
	for(var/obj/item/organ/OR in src.internal_organ_list())
		OR.periodic_step()

	for(var/obj/item/organ/OR in src.organs)
		OR.periodic_step()

/// Only mobs carrying real organ objects process them (most list organ paths for butchery).
/mob/living/simple_mob/proc/life_guts_due()
	return length(src.internal_organ_list()) || (LAZYLEN(src.organs) && (locate_in_list(src.organs, /obj/item/organ)))

/// Holy purge wears off.
/mob/living/simple_mob/proc/life_supernatural(datum/seq_frame/life/F)
	if(src.purge)
		src.set_purge(src.purge - (1))

/mob/living/simple_mob/proc/life_supernatural_due()
	return src.purge

/mob/living/simple_mob/

/mob/living/simple_mob
	death_message = "dies!"

/mob/living/simple_mob/on_death(gibbed)
	. = ..()
	release_vore_contents()
	set_density(FALSE) //We don't block even if we did before

	if(LAZYLEN(loot_list)) //Drop any loot
		for(var/path in loot_list)
			if(prob(loot_list[path]))
				new path(get_turf(src))

	set_ghostjoin(0)
	registry_leave(REGISTRY_GHOST_PODS, src)

/// Undo what on_death() cleared: a revived creature blocks again.
/mob/living/simple_mob/on_revived(reason, datum/source)
	. = ..()
	set_density(initial(density))

