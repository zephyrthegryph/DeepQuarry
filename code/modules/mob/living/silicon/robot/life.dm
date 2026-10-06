// Robot Life: the robot life set, a fixed sequence of small systems (doc/mob_life_architecture.md §5.2).
//   Cycle   - transform halt and power counter reset, then modifiers.
//   Status  - incapacitation counters wear off; senses recover; instability decays.
//   Power   - one ledger draw of the cached demand; brownout on shortfall; heat debt.
//   Body    - afflictions, consciousness and death, ticked exactly once.
//   HUD/Senses - client readouts. Camera, radio and lights change on events,
//             not here (update_senses(), set_lights()).
// Countdowns (killswitch, weapon lock) are timers (robot.dm).

/mob/living/silicon/robot
	fire_reaction = FIRE_REACTION_IGNITE
	life_set = LIFE_SET_ROBOT

/// `if(transforming) return` and the per-cycle power counter reset.
/mob/living/silicon/robot/proc/life_robot_cycle(datum/seq_frame/life/F)
	if(src.transforming)
		return F.abort()
	src.used_power_this_tick = 0

/// One ledger draw of the cached demand; brownout on shortfall; heat debt.
/mob/living/silicon/robot/proc/life_robot_power(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.process_power()

/// Vitals, part breakage, consciousness and death: the machine plan decides.
/mob/living/silicon/robot/proc/life_robot_body(datum/seq_frame/life/F)
	src.body?.life_tick()

/// Queued alarms reach the robot.
/mob/living/silicon/robot/proc/life_robot_alarms(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.process_queued_alarms()


/// Ear damage heals; a deafness disability keeps deafness up. Temporary blindness, deafness and
/// blur are timed statuses that end on their own (update_senses() follows blindness ending).
/mob/living/silicon/robot/proc/life_robot_senses(datum/seq_frame/life/F)
	if(src.ear_damage < 25)
		src.set_ear_damage(max(src.ear_damage - 0.05, 0))
	if(src.sdisabilities & DEAF)
		src.status_at_least(EFFECT_DEAFENED, 1)

/mob/living/silicon/robot/proc/life_robot_senses_due()
	return (src.sdisabilities & DEAF) || !(src.ear_damage <= 0 || src.ear_damage >= 25)

/// Blindness ending: the robot's sensors come back.
/mob/living/silicon/robot/status_sight_returned()
	update_senses()

// --- Power system ------------------------------------------------------------------------------

/// Spend the cached demand through the ledger. A shortfall is a brownout.
/mob/living/silicon/robot/proc/process_power()
	if(cell && nutrition >= ROBOT_NUTRITION_BURN && cell.charge < cell.maxcharge)
		adjust_nutrition(-ROBOT_NUTRITION_BURN)
		add_power(ROBOT_NUTRITION_JOULES, src)
	var/delivered = power_bus_ok() && draw_power(power_demand, src)
	update_power_state(delivered)
	process_heat()

/// Machine physiology: a cooling loop that can't circulate builds heat debt;
/// enough debt tips it into thermal runaway.
/mob/living/silicon/robot/proc/process_heat()
	var/datum/robot_component/cooling/loop = get_component(ROBOT_SLOT_COOLING)
	if(!istype(loop))
		return
	var/circulation = loop.circulation()
	if(circulation >= ROBOT_CIRCULATION_OK)
		if(heat_debt > 0)
			heat_debt = max(0, heat_debt - ROBOT_HEAT_DEBT_SHED)
		// A working loop is the chassis' coolant: it brings a runaway back down. Without this a
		// borg (no reagent holder, so no coolant reagent) stayed in runaway until an admin healed it.
		if(body?.has_affliction(/datum/affliction/synthetic/thermal_runaway) && mend(TREAT_COOLANT, ROBOT_RUNAWAY_LOOP_COOLING))
			if(!body.has_affliction(/datum/affliction/synthetic/thermal_runaway))
				log_runtime("ROBOT_HEAT: [key_name(src)] recovered from thermal runaway (circulation [round(circulation, 0.01)]).")
		return
	heat_debt += (1 - circulation) * ROBOT_HEAT_DEBT_SHED * 2
	if(heat_debt < ROBOT_HEAT_DEBT_RUNAWAY || body?.has_affliction(/datum/affliction/synthetic/thermal_runaway))
		return
	if(body?.afflict(/datum/affliction/synthetic/thermal_runaway))
		log_runtime("ROBOT_HEAT: [key_name(src)] entered thermal runaway (heat debt [round(heat_debt)], circulation [round(circulation, 0.01)]).")
		to_chat(src, span_danger("Warning: core temperature exceeding safe limits."))

// --- Senses and HUD ------------------------------------------------------------------------------


/mob/living/silicon/robot/life_vision()
	var/fullbright = FALSE
	var/seemeson = FALSE
	var/seejanhud = src.sight_mode & BORGJAN

	var/area/A = get_area(src)
	if(A?.flag_check(AREA_NO_SPOILERS))
		src.disable_spoiler_vision()

	if (src.stat == DEAD || (src.has_mutation(XRAY)) || (src.sight_mode & BORGXRAY))
		src.sight |= SEE_TURFS
		src.sight |= SEE_MOBS
		src.sight |= SEE_OBJS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_MINIMUM
	else if ((src.sight_mode & BORGMESON) && (src.sight_mode & BORGTHERM))
		src.sight |= SEE_TURFS
		src.sight |= SEE_MOBS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
	else if (src.sight_mode & BORGMESON)
		src.sight |= SEE_TURFS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
		seemeson = TRUE
	else if (src.sight_mode & BORGMATERIAL)
		src.sight |= SEE_OBJS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
	else if (src.sight_mode & BORGTHERM)
		src.sight |= SEE_MOBS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_LEVEL_TWO
		fullbright = TRUE
	else if (src.sight_mode & BORGANOMALOUS)
		src.see_in_dark = 8
		src.see_invisible = INVISIBILITY_SHADEKIN
		fullbright = TRUE
	else if (!src.seedarkness)
		src.sight &= ~SEE_MOBS
		src.sight &= ~SEE_TURFS
		src.sight &= ~SEE_OBJS
		src.see_in_dark = 8
		src.see_invisible = SEE_INVISIBLE_NOLIGHTING
	else if (src.stat != DEAD)
		src.sight &= ~SEE_MOBS
		src.sight &= ~SEE_TURFS
		src.sight &= ~SEE_OBJS
		src.see_in_dark = 8 			 // see_in_dark means you can FAINTLY see in the dark, humans have a range of 3 or so, tajaran have it at 8
		src.see_invisible = SEE_INVISIBLE_LIVING // This is normal vision (25), setting it lower for normal vision means you don't "see" things like darkness since darkness
											// has a "invisible" value of 15

	if(src.plane_holder)
		src.plane_holder.set_vis(VIS_FULLBRIGHT,fullbright)
		src.plane_holder.set_vis(VIS_MESONS,seemeson)
		src.plane_holder.set_vis(VIS_JANHUD,seejanhud)

	// Call parent to handle signals
	..()


/mob/living/silicon/robot/life_hud()
	. = ..()
	if(!.)
		return

	src.update_cell()

	var/turf/T = get_turf(src)
	var/datum/gas_mixture/environment = T?.return_air()
	if(environment)
		switch(environment.return_temperature())
			if(400 to INFINITY)
				src.throw_alert("temp", /atom/movable/screen/alert/hot/robot, HOT_ALERT_SEVERITY_MODERATE)
			if(360 to 400)
				src.throw_alert("temp", /atom/movable/screen/alert/hot/robot, HOT_ALERT_SEVERITY_LOW)
			if(260 to 360)
				src.clear_alert("temp")
			if(200 to 260)
				src.throw_alert("temp", /atom/movable/screen/alert/cold/robot, COLD_ALERT_SEVERITY_LOW)
			else
				src.throw_alert("temp", /atom/movable/screen/alert/cold/robot, COLD_ALERT_SEVERITY_MODERATE)

	// Blindness is raised by update_senses() when the camera or stat changes.
	if(src.stat != DEAD && !src.blinded)
		src.set_fullscreen(src.status_units(EFFECT_BLURRY), "blurry", /atom/movable/screen/fullscreen/blurry)
		src.set_fullscreen(src.status_units(EFFECT_DRUGGED), "high", /atom/movable/screen/fullscreen/high)

	if(src.emagged)
		src.throw_alert("hacked", /atom/movable/screen/alert/hacked)
	else
		src.clear_alert("hacked")

/mob/living/silicon/robot/life_hud_health_icons()
	. = ..()
	if(!. || !src.healths)
		return

	src.healths.icon_state = vitality_health_band(src)

/mob/living/silicon/robot/proc/update_cell()
	if(cell)
		var/cellcharge = cell.charge/cell.maxcharge
		switch(cellcharge)
			if(0.75 to INFINITY)
				clear_alert("charge")
			if(0.5 to 0.75)
				throw_alert("charge", /atom/movable/screen/alert/lowcell, 1)
			if(0.25 to 0.5)
				throw_alert("charge", /atom/movable/screen/alert/lowcell, 2)
			if(0.01 to 0.25)
				throw_alert("charge", /atom/movable/screen/alert/lowcell, 3)
			else
				throw_alert("charge", /atom/movable/screen/alert/emptycell)
	else
		throw_alert("charge", /atom/movable/screen/alert/nocell)


/mob/living/silicon/robot/proc/update_items()
	if(client)
		client.screen -= contents
		for(var/obj/I in contents)
			if(I && !(istype(I,/obj/item/cell) || istype(I,/obj/item/radio)  || istype(I,/obj/machinery/camera) || istype(I,/obj/item/mmi)))
				client.screen += I
	for(var/slot in 1 to 3)
		var/obj/item/held = get_module_slot(slot)
		if(held)
			held.screen_loc = get_module_slot_screen_loc(slot)

/mob/living/silicon/robot/update_canmove()
	..() // Let's not reinvent the wheel.
	if(lockdown || !is_component_functioning(ROBOT_SLOT_ACTUATOR))
		canmove = FALSE
	return canmove

/mob/living/silicon/robot/update_fire()
	cut_overlay(image(icon = 'icons/mob/OnFire.dmi', icon_state = get_fire_icon_state()))
	if(on_fire)
		add_overlay(image(icon = 'icons/mob/OnFire.dmi', icon_state = get_fire_icon_state()))
