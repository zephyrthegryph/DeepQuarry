/obj/machinery/shield_diffuser
	name = "shield diffuser"
	desc = "A small underfloor device specifically designed to disrupt energy barriers."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "fdiffuser_on"
	circuit = /obj/item/circuitboard/shield_diffuser
	use_power = USE_POWER_ACTIVE
	idle_power_usage = 25		// Previously 100.
	active_power_usage = 500	// Previously 2000
	anchored = TRUE
	density = FALSE
	level = 1
	maintenance_flags = MACHINE_MAINT_STANDARD
	var/alarm = 0
	var/enabled = 1

/obj/machinery/shield_diffuser/Initialize(mapload)
	. = ..()
	default_apply_parts()

	var/turf/T = get_turf(src)
	hide(!T.is_plating())

//If underfloor, hide the cable^H^H diffuser
/obj/machinery/shield_diffuser/hide(i)
	if(istype(loc, /turf))
		invisibility = i ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE
	update_icon()

/obj/machinery/shield_diffuser/hides_under_flooring()
	return 1

/obj/machinery/shield_diffuser/process()
	if(alarm)
		alarm--
		if(!alarm)
			update_icon()
		else
			return

	if(!enabled)
		return PROCESS_KILL
	for(var/direction in GLOB.cardinal)
		var/turf/simulated/shielded_tile = get_step(get_turf(src), direction)
		for(var/obj/effect/shield/S in shielded_tile)
			S.diffuse(5)
		// Legacy shield support
		for(var/obj/effect/energy_field/S in shielded_tile)
			qdel(S)
	return PROCESS_KILL

/obj/machinery/shield_diffuser/update_icon()
	if(alarm)
		icon_state = "fdiffuser_emergency"
		return
	if((stat & (NOPOWER | BROKEN)) || !enabled)
		icon_state = "fdiffuser_off"
	else
		icon_state = "fdiffuser_on"

/obj/machinery/shield_diffuser/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/shield_diffuser_toggle,
		/datum/interaction/machine_item/part_replacement,
	)
	..()

/// Old attack_hand: silence the alarm, or toggle the diffuser.
/datum/interaction/machine_hand/shield_diffuser_toggle
	id = "shield_diffuser_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/shield_diffuser/proc/interaction_toggle

/obj/machinery/shield_diffuser/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(alarm)
		to_chat(user, "You press an override button on \the [src], re-enabling it.")
		alarm = 0
		update_icon()
		return TRUE
	enabled = !enabled
	START_MACHINE_PROCESSING(src)
	update_use_power(enabled ? USE_POWER_ACTIVE : USE_POWER_IDLE)
	update_icon()
	to_chat(user, "You turn \the [src] [enabled ? "on" : "off"].")
	return TRUE

/obj/machinery/shield_diffuser/proc/meteor_alarm(duration)
	if(!duration)
		return
	alarm = round(max(alarm, duration))
	START_MACHINE_PROCESSING(src)
	update_icon()

/// Shield segments call this when they regenerate or appear, so stable
/// diffusers do not need to scan their four neighboring turfs forever.
/proc/nearby_active_shield_diffuser(atom/target)
	var/turf/center = get_turf(target)
	if(!center)
		return FALSE
	for(var/direction in GLOB.cardinal)
		var/turf/neighbor = get_step(center, direction)
		for(var/obj/machinery/shield_diffuser/D in neighbor)
			if(D.enabled && !D.alarm && !(D.stat & (NOPOWER | BROKEN)))
				return TRUE
	return FALSE

/obj/machinery/shield_diffuser/examine(mob/user)
	. = ..()
	. += "It is [enabled ? "enabled" : "disabled"]."
	if(alarm)
		. += "A red LED labeled \"Proximity Alarm\" is blinking on the control panel."
