// Robot Life: the robot life set, a fixed sequence of small systems (doc/mob_life_architecture.md §5.2).
//   Cycle   - transform halt and power counter reset, then modifiers.
//   Status  - incapacitation counters wear off; senses recover; instability decays.
//   Power   - one ledger draw of the cached demand; brownout on shortfall; heat debt.
//   Body    - afflictions, consciousness and death, ticked exactly once.
//   HUD/Senses - client readouts. Camera, radio and lights change on events,
//             not here (update_senses(), set_lights()).
// Countdowns (killswitch, weapon lock) are timers (robot.dm).

/mob/living/silicon/robot
	life_set = LIFE_SET_ROBOT

/// `if(transforming) return` and the per-cycle power counter reset.
/datum/life_system/robot_cycle
	name = "robot cycle"
	bit = LIFE_SYS_MACHINE
	phase = LIFE_PHASE_INPUT
	order = 0
	life_sets = LIFE_SET_ROBOT
	mob_type = /mob/living/silicon/robot

/datum/life_system/robot_cycle/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	if(self.transforming)
		return LIFE_HALT
	self.used_power_this_tick = 0

/datum/life_system/modifiers/silicon/robot
	mob_type = /mob/living/silicon/robot
	order = 10
	segment = NONE

/datum/life_system/statuses/silicon/robot
	mob_type = /mob/living/silicon/robot
	phase = LIFE_PHASE_INPUT
	order = 20
	segment = NONE

/datum/life_system/instability/silicon/robot
	mob_type = /mob/living/silicon/robot
	order = 40

/// One ledger draw of the cached demand; brownout on shortfall; heat debt.
/datum/life_system/robot_power
	name = "robot power"
	bit = LIFE_SYS_MACHINE
	phase = LIFE_PHASE_BODY
	order = 10
	life_sets = LIFE_SET_ROBOT
	mob_type = /mob/living/silicon/robot

/datum/life_system/robot_power/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	if(self.stat != DEAD)
		self.process_power()

/// Vitals, part breakage, consciousness and death: the machine plan decides.
/datum/life_system/robot_body
	name = "robot body"
	bit = LIFE_SYS_BODY
	phase = LIFE_PHASE_BODY
	order = 20
	life_sets = LIFE_SET_ROBOT
	mob_type = /mob/living/silicon/robot

/datum/life_system/robot_body/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	self.body?.life_tick()

/// Client readouts: HUD, vision and module items. Camera, radio and lights change on events.
/datum/life_system/robot_interface
	name = "robot interface"
	bit = LIFE_SYS_HUD
	phase = LIFE_PHASE_OUTPUT
	order = 10
	life_sets = LIFE_SET_ROBOT
	mob_type = /mob/living/silicon/robot

/datum/life_system/robot_interface/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	if(self.client)
		self.refresh_hud()
		self.refresh_vision()
		self.update_items()

/// Queued alarms reach the robot.
/datum/life_system/robot_alarms
	name = "robot alarms"
	bit = LIFE_SYS_MACHINE
	phase = LIFE_PHASE_OUTPUT
	order = 20
	life_sets = LIFE_SET_ROBOT
	mob_type = /mob/living/silicon/robot

/datum/life_system/robot_alarms/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	if(self.stat != DEAD)
		self.process_queued_alarms()

/datum/life_system/canmove/silicon/robot
	mob_type = /mob/living/silicon/robot
	order = 30
	segment = NONE

/// Temporary blindness, deafness and blur wear off.
/datum/life_system/robot_senses
	name = "robot senses"
	bit = LIFE_SYS_SENSES
	phase = LIFE_PHASE_INPUT
	order = 30
	life_sets = LIFE_SET_ROBOT
	mob_type = /mob/living/silicon/robot

/// Temporary blindness, deafness and blur wear off.
/datum/life_system/robot_senses/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	var/senses_changed = FALSE
	if(self.eye_blind)
		self.AdjustBlinded(-1)
		senses_changed = !self.eye_blind
	if(self.ear_deaf > 0)
		self.ear_deaf--
	if(self.ear_damage < 25)
		self.ear_damage = max(self.ear_damage - 0.05, 0)
	if(self.ear_deaf <= 0)
		self.deaf_loop.stop()
	if(self.sdisabilities & DEAF)
		self.ear_deaf = 1
	if(self.eye_blurry > 0)
		self.eye_blurry = max(0, self.eye_blurry - 1)
	if(senses_changed)
		self.update_senses()

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

/datum/life_system/vision/silicon/robot
	mob_type = /mob/living/silicon/robot

/datum/life_system/vision/silicon/robot/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	var/fullbright = FALSE
	var/seemeson = FALSE
	var/seejanhud = self.sight_mode & BORGJAN

	var/area/A = get_area(self)
	if(A?.flag_check(AREA_NO_SPOILERS))
		self.disable_spoiler_vision()

	if (self.stat == DEAD || (XRAY in self.mutations) || (self.sight_mode & BORGXRAY))
		self.sight |= SEE_TURFS
		self.sight |= SEE_MOBS
		self.sight |= SEE_OBJS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_MINIMUM
	else if ((self.sight_mode & BORGMESON) && (self.sight_mode & BORGTHERM))
		self.sight |= SEE_TURFS
		self.sight |= SEE_MOBS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
	else if (self.sight_mode & BORGMESON)
		self.sight |= SEE_TURFS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
		seemeson = TRUE
	else if (self.sight_mode & BORGMATERIAL)
		self.sight |= SEE_OBJS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_MINIMUM
		fullbright = TRUE
	else if (self.sight_mode & BORGTHERM)
		self.sight |= SEE_MOBS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_LEVEL_TWO
		fullbright = TRUE
	else if (self.sight_mode & BORGANOMALOUS)
		self.see_in_dark = 8
		self.see_invisible = INVISIBILITY_SHADEKIN
		fullbright = TRUE
	else if (!self.seedarkness)
		self.sight &= ~SEE_MOBS
		self.sight &= ~SEE_TURFS
		self.sight &= ~SEE_OBJS
		self.see_in_dark = 8
		self.see_invisible = SEE_INVISIBLE_NOLIGHTING
	else if (self.stat != DEAD)
		self.sight &= ~SEE_MOBS
		self.sight &= ~SEE_TURFS
		self.sight &= ~SEE_OBJS
		self.see_in_dark = 8 			 // see_in_dark means you can FAINTLY see in the dark, humans have a range of 3 or so, tajaran have it at 8
		self.see_invisible = SEE_INVISIBLE_LIVING // This is normal vision (25), setting it lower for normal vision means you don't "see" things like darkness since darkness
											// has a "invisible" value of 15

	if(self.plane_holder)
		self.plane_holder.set_vis(VIS_FULLBRIGHT,fullbright)
		self.plane_holder.set_vis(VIS_MESONS,seemeson)
		self.plane_holder.set_vis(VIS_JANHUD,seejanhud)

	// Call parent to handle signals
	..()

/datum/life_system/hud/silicon/robot
	mob_type = /mob/living/silicon/robot

/datum/life_system/hud/silicon/robot/tick(mob/living/silicon/robot/self, datum/life_context/ctx)
	. = ..()
	if(!.)
		return

	if (self.syndicate)
		for(var/datum/mind/tra in GLOB.traitors.current_antagonists)
			if(tra.current)
				// TODO: Update to new antagonist system.
				var/I = image('icons/mob/mob.dmi', loc = tra.current, icon_state = "traitor")
				self.client.images += I
		self.disconnect_from_ai()
		if(self.mind)
			// TODO: Update to new antagonist system.
			if(!self.mind.special_role)
				self.mind.special_role = "traitor"
				LAZYOR(GLOB.traitors.current_antagonists, self.mind)

	self.update_cell()

	var/turf/T = get_turf(self)
	var/datum/gas_mixture/environment = T.return_air()
	if(environment)
		switch(environment.return_temperature()) //310.055 optimal body temp
			if(400 to INFINITY)
				self.throw_alert("temp", /atom/movable/screen/alert/hot/robot, HOT_ALERT_SEVERITY_MODERATE)
			if(360 to 400)
				self.throw_alert("temp", /atom/movable/screen/alert/hot/robot, HOT_ALERT_SEVERITY_LOW)
			if(260 to 360)
				self.clear_alert("temp")
			if(200 to 260)
				self.throw_alert("temp", /atom/movable/screen/alert/cold/robot, COLD_ALERT_SEVERITY_LOW)
			else
				self.throw_alert("temp", /atom/movable/screen/alert/cold/robot, COLD_ALERT_SEVERITY_MODERATE)

	// Blindness is raised by update_senses() when the camera or stat changes.
	if(self.stat != DEAD && !self.blinded)
		self.set_fullscreen(self.eye_blurry, "blurry", /atom/movable/screen/fullscreen/blurry)
		self.set_fullscreen(self.druggy, "high", /atom/movable/screen/fullscreen/high)

	if(self.emagged)
		self.throw_alert("hacked", /atom/movable/screen/alert/hacked)
	else
		self.clear_alert("hacked")

/datum/life_system/hud/silicon/robot/health_icons(mob/living/silicon/robot/self)
	. = ..()
	if(!. || !self.healths)
		return

	if(self.stat == DEAD || (self.status_effects & FAKEDEATH))
		self.healths.icon_state = "health7"
		return

	// Same bands as the old 200..-200 health scale, read from vitality.
	var/v = self.vitality()
	if(v >= 1)
		self.healths.icon_state = "health0"
	else if(v >= 0.875)
		self.healths.icon_state = "health1"
	else if(v >= 0.75)
		self.healths.icon_state = "health2"
	else if(v >= 0.625)
		self.healths.icon_state = "health3"
	else if(v >= 0.5)
		self.healths.icon_state = "health4"
	else if(v > 0)
		self.healths.icon_state = "health5"
	else
		self.healths.icon_state = "health6"

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
