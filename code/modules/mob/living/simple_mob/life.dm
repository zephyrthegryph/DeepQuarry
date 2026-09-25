// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

// Simple mob Life: the living core, then these TAIL stages in the old order:
//	vitals (health display), then [alive] (the old `if(stat >= DEAD) return FALSE`) statuses,
//	supernatural, special, guts, healing, then the type_post variants.

/// Health display. Death is decided by the body (evaluate_status -> death()).
/datum/om/stage/life/simple_vitals
	order = LIFE_PHASE_TAIL + 100
	name = "simple vitals"
	wake_on = CHANGE_MOB_HEALTH
	of = /mob/living/simple_mob
	woken_by = "injure, mend, body invalidate (health); set_stat"

/datum/om/stage/life/simple_vitals/perform(mob/living/simple_mob/self, datum/om/frame/life/ctx)
	self.update_health_display()

/// Event-driven: health and stat changes wake it.
/datum/om/stage/life/simple_vitals/idle(mob/living/simple_mob/self)
	return TRUE

/// Passive healing while fed.
/datum/om/stage/life/simple_healing
	order = LIFE_PHASE_TAIL + 150
	name = "simple healing"
	wake_on = CHANGE_MOB_HEALTH
	run_if = FACT("alive")
	of = /mob/living/simple_mob
	woken_by = "injure; feeding"

/datum/om/stage/life/simple_healing/perform(mob/living/simple_mob/self, datum/om/frame/life/ctx)
	self.do_healing()

/// Heals only while hurt and fed.
/datum/om/stage/life/simple_healing/idle(mob/living/simple_mob/self)
	return self.nutrition < 150 || !self.is_injured()

/datum/om/stage/life/type_post/simple_mob
	of = /mob/living/simple_mob


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

/datum/om/stage/life/special
	order = LIFE_PHASE_TAIL + 130
	name = "special"
	wake_on = 0
	run_if = FACT("alive")
	of = /mob/living/simple_mob

/// Per-type behaviour (the old handle_special() overrides). Variants mirror the mob path.
/datum/om/stage/life/special/perform(mob/living/simple_mob/self, datum/om/frame/life/ctx)
	return

/datum/om/stage/life/special/idle(mob/living/simple_mob/self)
	return type == /datum/om/stage/life/special

/datum/om/stage/life/environment/simple_mob
	of = /mob/living/simple_mob
	woken_by = "Moved; injure; its own timer for air changing in place"

/// Idle while the air is survivable and the body has nothing for it to treat. Air that
/// changes in place (a breach) is caught by a slow timer: atmos has no per-mob signal yet.
/datum/om/stage/life/environment/simple_mob/idle(mob/living/simple_mob/self)
	if(type != /datum/om/stage/life/environment/simple_mob)
		return FALSE
	if(self.is_incorporeal() || !self.loc)
		return TRUE
	if(LAZYLEN(self.body?.afflictions))
		return FALSE
	if(self.bodytemperature < self.minbodytemp || self.bodytemperature > self.maxbodytemp)
		return FALSE
	var/datum/gas_mixture/environment = isbelly(self.loc) ? self.loc.return_air_for_internal_lifeform(self) : self.loc.return_air()
	return !environment || self.environment_is_safe(environment)

/datum/om/stage/life/environment/simple_mob/rewake_delay(mob/living/simple_mob/self)
	return 15 SECONDS

/// TRUE when exchange() would change nothing: temperature within the mob's range and every
/// gas inside its bounds. Read-only; shared by the sleep rule and the hibernation audit.
/mob/living/simple_mob/proc/environment_is_safe(datum/gas_mixture/environment)
	if(abs(environment.return_temperature() - bodytemperature) > temperature_range)
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
/datum/om/stage/life/environment/simple_mob/exchange(mob/living/simple_mob/self, datum/gas_mixture/environment)

	if(self.inStasisNow())
		return 1 // return early to skip atmos checks
	if(self.is_incorporeal())
		return 1

	var/env_temperature = environment.return_temperature()
	if( abs(env_temperature - self.bodytemperature) > self.temperature_range )
		self.bodytemperature += ((env_temperature - self.bodytemperature) / 5)

	// Accumulate (|=) failures across gas blocks so an earlier failing gas
	// isn't masked by a later passing one.
	var/atmos_unsuitable = 0
	if(self.min_oxy && LINDA_GAS_AMT(environment, GAS_O2) < self.min_oxy)
		atmos_unsuitable |= 1
		self.throw_alert("oxy", /atom/movable/screen/alert/not_enough_oxy)
	else if(self.max_oxy && LINDA_GAS_AMT(environment, GAS_O2) > self.max_oxy)
		atmos_unsuitable |= 1
		self.throw_alert("oxy", /atom/movable/screen/alert/too_much_oxy)
	else
		self.clear_alert("oxy")

	if(self.min_tox && LINDA_GAS_AMT(environment, GAS_PHORON) < self.min_tox)
		atmos_unsuitable |= 2
		self.throw_alert("tox_in_air", /atom/movable/screen/alert/not_enough_tox)
	else if(self.max_tox && LINDA_GAS_AMT(environment, GAS_PHORON) > self.max_tox)
		atmos_unsuitable |= 2
		self.throw_alert("tox_in_air", /atom/movable/screen/alert/tox_in_air)
	else
		self.clear_alert("tox_in_air")

	if(self.min_n2 && LINDA_GAS_AMT(environment, GAS_N2) < self.min_n2)
		atmos_unsuitable |= 1
		self.throw_alert("n2o", /atom/movable/screen/alert/not_enough_nitro)
	else if(self.max_n2 && LINDA_GAS_AMT(environment, GAS_N2) > self.max_n2)
		atmos_unsuitable |= 1
		self.throw_alert("n2o", /atom/movable/screen/alert/too_much_nitro)
	else
		self.clear_alert("n2o")

	if(self.min_co2 && LINDA_GAS_AMT(environment, GAS_CO2) < self.min_co2)
		atmos_unsuitable |= 1
		self.throw_alert("co2", /atom/movable/screen/alert/not_enough_co2)
	else if(self.max_co2 && LINDA_GAS_AMT(environment, GAS_CO2) > self.max_co2)
		atmos_unsuitable |= 1
		self.throw_alert("co2", /atom/movable/screen/alert/too_much_co2)
	else
		self.clear_alert("co2")

	if(self.min_ch4 && LINDA_GAS_AMT(environment, GAS_CH4) < self.min_ch4)
		atmos_unsuitable |= 2
		self.throw_alert("methane_in_air", /atom/movable/screen/alert/not_enough_methane)
	else if(self.max_ch4 && LINDA_GAS_AMT(environment, GAS_CH4) > self.max_ch4)
		atmos_unsuitable |= 2
		self.throw_alert("methane_in_air", /atom/movable/screen/alert/methane_in_air)
	else
		self.clear_alert("methane_in_air")

	//Atmos effect
	if(self.bodytemperature < self.minbodytemp)
		self.injure(INJURY_FROSTBITE, self.cold_damage_per_tick, source = self.loc)
		self.throw_alert("temp", /atom/movable/screen/alert/cold, COLD_ALERT_SEVERITY_MAX)
	else if(self.bodytemperature > self.maxbodytemp)
		self.injure(INJURY_BURN, self.heat_damage_per_tick, source = self.loc)
		self.throw_alert("temp", /atom/movable/screen/alert/hot, HOT_ALERT_SEVERITY_MAX)
	else
		self.clear_alert("temp")

	if(atmos_unsuitable)
		self.add_oxygen_debt(self.unsuitable_atoms_damage, self.loc)
	else
		self.mend(TREAT_OXYGENATION, self.unsuitable_atoms_damage)

/datum/om/stage/life/guts
	order = LIFE_PHASE_TAIL + 140
	name = "guts"
	wake_on = 0
	run_if = FACT("alive")
	of = /mob/living/simple_mob

/// Organ processing.
/datum/om/stage/life/guts/perform(mob/living/simple_mob/self, datum/om/frame/life/ctx)
	for(var/obj/item/organ/OR in self.internal_organs)
		OR.process()

	for(var/obj/item/organ/OR in self.organs)
		OR.process()

/// Only mobs carrying real organ objects process them (most list organ paths for butchery).
/datum/om/stage/life/guts/idle(mob/living/simple_mob/self)
	return !(LAZYLEN(self.internal_organs) && (locate(/obj/item/organ) in self.internal_organs)) && !(LAZYLEN(self.organs) && (locate(/obj/item/organ) in self.organs))

/datum/om/stage/life/supernatural
	order = LIFE_PHASE_TAIL + 120
	name = "supernatural"
	wake_on = CHANGE_MOB_STATUS
	run_if = FACT("alive")
	of = /mob/living/simple_mob

/// Holy purge wears off.
/datum/om/stage/life/supernatural/perform(mob/living/simple_mob/self, datum/om/frame/life/ctx)
	if(self.purge)
		self.purge -= 1

/datum/om/stage/life/supernatural/idle(mob/living/simple_mob/self)
	return !self.purge

/mob/living/simple_mob/
	var/update_icon_timer

/mob/living/simple_mob/death(gibbed, deathmessage = "dies!")
	update_icon()
	release_vore_contents()
	density = FALSE //We don't block even if we did before

	if(has_eye_glow)
		remove_eyes()

	if(LAZYLEN(loot_list)) //Drop any loot
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
