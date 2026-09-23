// Robot Life: a fixed sequence of small systems (doc/mob_life_architecture.md §5.2).
//   Status  - incapacitation counters wear off.
//   Power   - one ledger draw of the cached demand; brownout on shortfall; heat debt.
//   Body    - afflictions, consciousness and death, ticked exactly once.
//   HUD/Senses - client readouts. Camera, radio and lights change on events,
//             not here (update_senses(), set_lights()).
// Countdowns (killswitch, weapon lock) are timers (robot.dm).

/mob/living/silicon/robot/Life()
	set invisibility = INVISIBILITY_NONE

	if(transforming)
		return

	used_power_this_tick = 0
	handle_modifiers()
	handle_statuses()
	handle_sensory_recovery()
	handle_instability()

	if(stat != DEAD)
		process_power()

	// Vitals, part breakage, consciousness and death: the machine plan decides.
	body?.life_tick()

	if(client)
		handle_regular_hud_updates()
		handle_vision()
		update_items()
	if(stat != DEAD)
		process_queued_alarms()
	update_canmove()

/// Temporary blindness, deafness and blur wear off.
/mob/living/silicon/robot/proc/handle_sensory_recovery()
	var/senses_changed = FALSE
	if(eye_blind)
		AdjustBlinded(-1)
		senses_changed = !eye_blind
	if(ear_deaf > 0)
		ear_deaf--
	if(ear_damage < 25)
		ear_damage = max(ear_damage - 0.05, 0)
	if(ear_deaf <= 0)
		deaf_loop.stop()
	if(sdisabilities & DEAF)
		ear_deaf = 1
	if(eye_blurry > 0)
		eye_blurry = max(0, eye_blurry - 1)
	if(senses_changed)
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
		return
	heat_debt += (1 - circulation) * ROBOT_HEAT_DEBT_SHED * 2
	if(heat_debt < ROBOT_HEAT_DEBT_RUNAWAY || body?.has_affliction(/datum/affliction/synthetic/thermal_runaway))
		return
	if(body?.afflict(/datum/affliction/synthetic/thermal_runaway))
		log_runtime("ROBOT_HEAT: [key_name(src)] entered thermal runaway (heat debt [round(heat_debt)], circulation [round(circulation, 0.01)]).")
		to_chat(src, span_danger("Warning: core temperature exceeding safe limits."))

// --- Senses and HUD ------------------------------------------------------------------------------

/mob/living/silicon/robot/handle_vision()
	var/fullbright = FALSE
	var/seemeson = FALSE
	var/seejanhud = sight_mode & BORGJAN

	var/area/A = get_area(src)
	if(A?.flag_check(AREA_NO_SPOILERS))
		disable_spoiler_vision()

	if (stat == DEAD || (XRAY in mutations) || (sight_mode & BORGXRAY))
		sight |= SEE_TURFS
		sight |= SEE_MOBS
		sight |= SEE_OBJS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_MINIMUM
	else if ((sight_mode & BORGMESON) && (sight_mode & BORGTHERM))
		sight |= SEE_TURFS
		sight |= SEE_MOBS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
	else if (sight_mode & BORGMESON)
		sight |= SEE_TURFS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
		seemeson = TRUE
	else if (sight_mode & BORGMATERIAL)
		sight |= SEE_OBJS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
	else if (sight_mode & BORGTHERM)
		sight |= SEE_MOBS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_LEVEL_TWO
		fullbright = TRUE
	else if (sight_mode & BORGANOMALOUS)
		see_in_dark = 8
		see_invisible = INVISIBILITY_SHADEKIN
		fullbright = TRUE
	else if (!seedarkness)
		sight &= ~SEE_MOBS
		sight &= ~SEE_TURFS
		sight &= ~SEE_OBJS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_NOLIGHTING
	else if (stat != DEAD)
		sight &= ~SEE_MOBS
		sight &= ~SEE_TURFS
		sight &= ~SEE_OBJS
		see_in_dark = 8 			 // see_in_dark means you can FAINTLY see in the dark, humans have a range of 3 or so, tajaran have it at 8
		see_invisible = SEE_INVISIBLE_LIVING // This is normal vision (25), setting it lower for normal vision means you don't "see" things like darkness since darkness
											// has a "invisible" value of 15

	if(plane_holder)
		plane_holder.set_vis(VIS_FULLBRIGHT,fullbright)
		plane_holder.set_vis(VIS_MESONS,seemeson)
		plane_holder.set_vis(VIS_JANHUD,seejanhud)

	// Call parent to handle signals
	..()

/mob/living/silicon/robot/handle_regular_hud_updates()
	. = ..()
	if(!.)
		return

	if (syndicate)
		for(var/datum/mind/tra in GLOB.traitors.current_antagonists)
			if(tra.current)
				// TODO: Update to new antagonist system.
				var/I = image('icons/mob/mob.dmi', loc = tra.current, icon_state = "traitor")
				client.images += I
		disconnect_from_ai()
		if(mind)
			// TODO: Update to new antagonist system.
			if(!mind.special_role)
				mind.special_role = "traitor"
				GLOB.traitors.current_antagonists |= mind

	update_cell()

	var/turf/T = get_turf(src)
	var/datum/gas_mixture/environment = T.return_air()
	if(environment)
		switch(environment.return_temperature()) //310.055 optimal body temp
			if(400 to INFINITY)
				throw_alert("temp", /atom/movable/screen/alert/hot/robot, HOT_ALERT_SEVERITY_MODERATE)
			if(360 to 400)
				throw_alert("temp", /atom/movable/screen/alert/hot/robot, HOT_ALERT_SEVERITY_LOW)
			if(260 to 360)
				clear_alert("temp")
			if(200 to 260)
				throw_alert("temp", /atom/movable/screen/alert/cold/robot, COLD_ALERT_SEVERITY_LOW)
			else
				throw_alert("temp", /atom/movable/screen/alert/cold/robot, COLD_ALERT_SEVERITY_MODERATE)

	// Blindness is raised by update_senses() when the camera or stat changes.
	if(stat != DEAD && !blinded)
		set_fullscreen(eye_blurry, "blurry", /atom/movable/screen/fullscreen/blurry)
		set_fullscreen(druggy, "high", /atom/movable/screen/fullscreen/high)

	if(emagged)
		throw_alert("hacked", /atom/movable/screen/alert/hacked)
	else
		clear_alert("hacked")

/mob/living/silicon/robot/handle_hud_icons_health()
	. = ..()
	if(!. || !healths)
		return

	if(stat == DEAD || (status_effects & FAKEDEATH))
		healths.icon_state = "health7"
		return

	// Same bands as the old 200..-200 health scale, read from vitality.
	var/v = vitality()
	if(v >= 1)
		healths.icon_state = "health0"
	else if(v >= 0.875)
		healths.icon_state = "health1"
	else if(v >= 0.75)
		healths.icon_state = "health2"
	else if(v >= 0.625)
		healths.icon_state = "health3"
	else if(v >= 0.5)
		healths.icon_state = "health4"
	else if(v > 0)
		healths.icon_state = "health5"
	else
		healths.icon_state = "health6"

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

/mob/living/silicon/robot/fire_act()
	if(is_incorporeal())
		return
	if(!on_fire) //Silicons don't gain stacks from hotspots, but hotspots can ignite them
		ignite_mob()

/mob/living/silicon/robot/update_fire()
	cut_overlay(image(icon = 'icons/mob/OnFire.dmi', icon_state = get_fire_icon_state()))
	if(on_fire)
		add_overlay(image(icon = 'icons/mob/OnFire.dmi', icon_state = get_fire_icon_state()))
