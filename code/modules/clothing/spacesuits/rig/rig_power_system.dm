/*
 * /datum/rig_power_system
 *
 * Owns all power-related and thermal state for a hardsuit rig.
 * The rig holds one instance of this datum and delegates cooling processing
 * and offline-state bookkeeping here.
 *
 * Public API used by the rig and its modules:
 *   - run_cooling(H)        — one process tick of thermal management
 *   - process_offline_state() — manages offline transitions; returns TRUE when offline
 *
 * The rig's power vars (cell, electrified, slowdown, canremove, installed_modules)
 * are still on /obj/item/rig directly so that the existing module API and TGUI
 * remain unmodified.
 */

/datum/rig_power_system
	/// The rig this datum belongs to.  Nulled on Destroy().
	var/obj/item/rig/holder

	// ---- Cooling system ----
	/// Whether the active cooling system is running.
	var/cooling_on = 0
	/// Maximum degrees Kelvin the cooling unit can remove per second.
	var/max_cooling = 15
	/// Power consumed per second (cell charge units) at max_cooling.
	var/charge_consumption = 2
	/// Target body temperature when cooling is active (Kelvin).
	var/thermostat = T20C

	// ---- Offline state machine ----
	/// 0 = online, 1 = offline-pending-deactivation, 2 = offline-stable.
	var/offline = 1
	/// Slowdown applied to the wearer when the suit is offline/unpowered.
	var/offline_slowdown = 1.5
	/// Vision restriction when offline. 0 = none, 1 = welder vision, 2 = blind.
	var/offline_vision_restriction = 1

/datum/rig_power_system/New(obj/item/rig/new_holder)
	holder = new_holder

/datum/rig_power_system/Destroy()
	holder = null
	return ..()

/*
 * proc/get_environment_temperature()
 *
 * Returns the ambient temperature at the rig's location for cooling calculations.
 * Returns 0 for space, and accounts for mecha interiors and cryo cells.
 */
/datum/rig_power_system/proc/get_environment_temperature()
	if(ishuman(holder.loc))
		var/mob/living/carbon/human/H = holder.loc
		if(istype(H.loc, /obj/mecha))
			var/obj/mecha/M = H.loc
			return M.return_temperature()
		if(istype(H.loc, /obj/machinery/atmospherics/unary/cryo_cell))
			var/obj/machinery/atmospherics/unary/cryo_cell/cryo = H.loc
			return cryo.air_contents.temperature

	var/turf/T = get_turf(holder)
	if(!T)
		return 0
	if(istype(T, /turf/space))
		return 0

	var/datum/gas_mixture/environment = T.return_air()
	if(!environment)
		return 0

	return environment.temperature

/*
 * proc/run_cooling(mob/living/carbon/human/H)
 *
 * Performs one process tick of active cooling.  Reduces H.bodytemperature
 * toward thermostat and drains the cell.  Turns cooling off on cell exhaustion.
 * Called from /obj/item/rig/process().
 */
/datum/rig_power_system/proc/run_cooling(mob/living/carbon/human/H)
	if(!cooling_on || !holder.cell)
		return
	if(!H)
		return
	if(!holder.attached_to_user(H))
		return
	if(!holder.suit_is_deployed())
		return

	var/turf/T = get_turf(holder)
	if(!T)
		return

	var/datum/gas_mixture/environment = T.return_air()
	if(!environment)
		return

	var/efficiency = 1 - H.get_pressure_weakness(environment.return_pressure())
	var/env_temp = get_environment_temperature()
	var/thermal_protection = H.get_heat_protection(env_temp)

	var/temp_adj
	if(thermal_protection < 0.99)
		temp_adj = min(H.bodytemperature - max(thermostat, env_temp), max_cooling)
	else
		temp_adj = min(H.bodytemperature - thermostat, max_cooling)

	if(temp_adj < 0.5)
		return

	var/charge_usage = (temp_adj / max_cooling) * charge_consumption
	H.bodytemperature -= temp_adj * efficiency
	holder.cell.use(charge_usage)

	if(holder.cell.charge <= 0)
		holder.turn_cooling_off(H, 1)

/*
 * proc/process_offline_state()
 *
 * Manages the rig's online/offline transition each process tick.
 * Returns TRUE if the rig is currently offline (callers should skip
 * module processing when this returns TRUE).
 *
 * Offline state machine:
 *   offline == 0 — powered and running
 *   offline == 1 — just lost power; deactivate modules, apply slowdown, notify wearer
 *   offline == 2 — offline-stable; no further action until power returns
 */
/datum/rig_power_system/proc/process_offline_state()
	var/mob/living/carbon/human/W = holder.wearer

	if(!holder.cell || holder.cell.charge <= 0)
		if(holder.electrified > 0)
			holder.electrified = 0
		if(!offline)
			if(istype(W))
				if(!holder.canremove)
					if(offline_slowdown < 1.5)
						to_chat(W, span_danger("Your suit beeps stridently, and suddenly goes dead."))
					else
						to_chat(W, span_danger("Your suit beeps stridently, and suddenly you're wearing a leaden mass of metal and plastic composites instead of a powered suit."))
					playsound(holder, 'sound/machines/rig/rigdown.ogg', 60, FALSE)
				if(offline_vision_restriction == 1)
					to_chat(W, span_danger("The suit optics flicker and die, leaving you with restricted vision."))
				else if(offline_vision_restriction == 2)
					to_chat(W, span_danger("The suit optics drop out completely, drowning you in darkness."))
		if(!offline)
			offline = 1
	else if(offline)
		offline = 0
		if(istype(W) && !W.wearing_rig)
			W.wearing_rig = holder
		if(!istype(holder, /obj/item/rig/protean))
			holder.slowdown = initial(holder.slowdown)

	if(offline)
		if(offline == 1)
			for(var/obj/item/rig_module/module in holder.installed_modules)
				module.deactivate()
			offline = 2
			holder.slowdown = offline_slowdown
		return TRUE

	return FALSE
