// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/mob/living/simple_mob/Life()
	..()

	// Death is decided by the body (evaluate_status -> death()); we only refresh displays here.
	update_health_display()
	if(stat >= DEAD)
		return FALSE

	handle_sleeping()
	handle_stunned()
	handle_weakened()
	handle_paralysed()
	handle_supernatural()

	handle_special()

	handle_guts()
	do_healing()

	return TRUE


/// Refreshes the health HUD, nutrition alert and injury slowdown. Death itself
/// is handled by the body plan (total load >= endurance -> death()).
/mob/living/simple_mob/proc/update_health_display()
	get_injury_level()
	//Update our hud if we have one
	if(healths)
		if(stat != DEAD)
			var/heal_per = vitality() * 100
			switch(heal_per)
				if(100 to INFINITY)
					healths.icon_state = "health0"
				if(80 to 100)
					healths.icon_state = "health1"
				if(60 to 80)
					healths.icon_state = "health2"
				if(40 to 60)
					healths.icon_state = "health3"
				if(20 to 40)
					healths.icon_state = "health4"
				if(0 to 20)
					healths.icon_state = "health5"
				else
					healths.icon_state = "health6"
		else
			healths.icon_state = "health7"

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
		nutrition -= 50
		heal_countdown = 5
		return
	natural_mend(1)
	nutrition -= 5
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

// Override for special bullshit.
/mob/living/simple_mob/proc/handle_special()
	return

// Handle interacting with and taking damage from atmos
/mob/living/simple_mob/handle_environment(datum/gas_mixture/environment)

	if(in_stasis)
		return 1 // return early to skip atmos checks
	if(is_incorporeal())
		return 1

	var/env_temperature = environment.return_temperature()
	if( abs(env_temperature - bodytemperature) > temperature_range )
		bodytemperature += ((env_temperature - bodytemperature) / 5)

	// Accumulate (|=) failures across gas blocks so an earlier failing gas
	// isn't masked by a later passing one.
	var/atmos_unsuitable = 0
	if(min_oxy && LINDA_GAS_AMT(environment, GAS_O2) < min_oxy)
		atmos_unsuitable |= 1
		throw_alert("oxy", /atom/movable/screen/alert/not_enough_oxy)
	else if(max_oxy && LINDA_GAS_AMT(environment, GAS_O2) > max_oxy)
		atmos_unsuitable |= 1
		throw_alert("oxy", /atom/movable/screen/alert/too_much_oxy)
	else
		clear_alert("oxy")

	if(min_tox && LINDA_GAS_AMT(environment, GAS_PHORON) < min_tox)
		atmos_unsuitable |= 2
		throw_alert("tox_in_air", /atom/movable/screen/alert/not_enough_tox)
	else if(max_tox && LINDA_GAS_AMT(environment, GAS_PHORON) > max_tox)
		atmos_unsuitable |= 2
		throw_alert("tox_in_air", /atom/movable/screen/alert/tox_in_air)
	else
		clear_alert("tox_in_air")

	if(min_n2 && LINDA_GAS_AMT(environment, GAS_N2) < min_n2)
		atmos_unsuitable |= 1
		throw_alert("n2o", /atom/movable/screen/alert/not_enough_nitro)
	else if(max_n2 && LINDA_GAS_AMT(environment, GAS_N2) > max_n2)
		atmos_unsuitable |= 1
		throw_alert("n2o", /atom/movable/screen/alert/too_much_nitro)
	else
		clear_alert("n2o")

	if(min_co2 && LINDA_GAS_AMT(environment, GAS_CO2) < min_co2)
		atmos_unsuitable |= 1
		throw_alert("co2", /atom/movable/screen/alert/not_enough_co2)
	else if(max_co2 && LINDA_GAS_AMT(environment, GAS_CO2) > max_co2)
		atmos_unsuitable |= 1
		throw_alert("co2", /atom/movable/screen/alert/too_much_co2)
	else
		clear_alert("co2")

	if(min_ch4 && LINDA_GAS_AMT(environment, GAS_CH4) < min_ch4)
		atmos_unsuitable |= 2
		throw_alert("methane_in_air", /atom/movable/screen/alert/not_enough_methane)
	else if(max_ch4 && LINDA_GAS_AMT(environment, GAS_CH4) > max_ch4)
		atmos_unsuitable |= 2
		throw_alert("methane_in_air", /atom/movable/screen/alert/methane_in_air)
	else
		clear_alert("methane_in_air")

	//Atmos effect
	if(bodytemperature < minbodytemp)
		injure(INJURY_FROSTBITE, cold_damage_per_tick, source = loc)
		throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MAX)
	else if(bodytemperature > maxbodytemp)
		injure(INJURY_BURN, heat_damage_per_tick, source = loc)
		throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
	else
		clear_alert("temp")

	if(atmos_unsuitable)
		injure(INJURY_ASPHYXIA, unsuitable_atoms_damage, source = loc)
	else
		mend(TREAT_OXYGENATION, unsuitable_atoms_damage)

/mob/living/simple_mob/proc/handle_guts()
	for(var/obj/item/organ/OR in internal_organs)
		OR.process()

	for(var/obj/item/organ/OR in organs)
		OR.process()

/mob/living/simple_mob/proc/handle_supernatural()
	if(purge)
		purge -= 1

/mob/living/simple_mob/
	var/update_icon_timer

/mob/living/simple_mob/death(gibbed, deathmessage = "dies!")
	update_icon()
	release_vore_contents()
	density = FALSE //We don't block even if we did before

	if(has_eye_glow)
		remove_eyes()

	if(loot_list.len) //Drop any loot
		for(var/path in loot_list)
			if(prob(loot_list[path]))
				new path(get_turf(src))

	update_icon_timer = addtimer(CALLBACK(src, PROC_REF(callback_update_icon)), 0.3 SECONDS, TIMER_STOPPABLE)

	ghostjoin = 0
	GLOB.active_ghost_pods -= src
	ghostjoin_icon()
	return ..(gibbed,deathmessage)

/mob/living/simple_mob/proc/callback_update_icon()
	update_icon()

/mob/living/simple_mob/Destroy()
	deltimer(update_icon_timer)
	update_icon_timer = null
	. = ..()
