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

/// Proximity alarm countdown in steps (meteor_alarm()); while it runs the diffuser is silenced.
OM_FIELD(/obj/machinery/shield_diffuser, alarm, 0, CHANGE_MACHINE_SETTINGS)
OM_FIELD(/obj/machinery/shield_diffuser, enabled, TRUE, CHANGE_MACHINE_SETTINGS)
/// It has a step to take: an alarm to count down, or a diffuse pass while enabled.
OM_DERIVE_FIELD(/obj/machinery/shield_diffuser, diffuser_has_work, list("enabled", "alarm"))
/obj/machinery/shield_diffuser/proc/diffuser_has_work()
	return enabled || alarm
// ALLOW(init/INSTANCE_STATE): takes its built parts and hides under the floor tile it is placed on
/obj/machinery/shield_diffuser/Initialize(mapload)
	. = ..()
	default_apply_parts()

	var/turf/T = get_turf(src)
	hide(!T.is_plating())

//If underfloor, hide the cable^H^H diffuser
/obj/machinery/shield_diffuser/hide(i)
	if(istype(loc, /turf))
		invisibility = i ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE

/obj/machinery/shield_diffuser/hides_under_flooring()
	return 1

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/shield_diffuser)
	started_work(step = PROC_REF(work_step), starts = TRUE, gate = PROC_REF(diffuser_has_work), wakes_on = list(nameof(enabled), nameof(alarm)))
	op("toggle", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(interaction_toggle)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))

/obj/machinery/shield_diffuser/proc/work_step(datum/act/timer/A)
	if(alarm)
		set_alarm(alarm - 1)
		if(!alarm)
			update_icon()
		else
			return

	if(!enabled)
		return
	for(var/direction in GLOB.cardinal)
		var/turf/simulated/shielded_tile = get_step(get_turf(src), direction)
		for(var/obj/effect/shield/S in turf_contents_of_type(shielded_tile, /obj/effect/shield))
			S.diffuse(5)
		// Legacy shield support
		for(var/obj/effect/energy_field/S in turf_contents_of_type(shielded_tile, /obj/effect/energy_field))
			spent(S)
	return PROCESS_KILL

/// Appearance reader: working and switched on.
/obj/machinery/shield_diffuser/proc/appearance_diffusing()
	return operable() && enabled

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/shield_diffuser/draw(datum/look/look)
	..()
	look.state("fdiffuser_[appearance_diffusing() ? "on" : "off"]")
	if(appearance_alarmed() == 1)
		look.state("fdiffuser_emergency")

/// Appearance reader: alarm raised (as 1/0).
/obj/machinery/shield_diffuser/proc/appearance_alarmed()
	return alarm ? 1 : 0

/obj/machinery/shield_diffuser/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if(alarm)
		to_chat(user, "You press an override button on \the [src], re-enabling it.")
		set_alarm(0)
		return TRUE
	set_enabled(!enabled)
	set_use_power(enabled ? USE_POWER_ACTIVE : USE_POWER_IDLE)
	to_chat(user, "You turn \the [src] [enabled ? "on" : "off"].")
	return TRUE

/obj/machinery/shield_diffuser/proc/meteor_alarm(duration)
	if(!duration)
		return
	set_alarm(round(max(alarm, duration)))

/// Shield segments call this when they regenerate or appear, so stable
/// diffusers do not need to scan their four neighboring turfs forever.
/proc/nearby_active_shield_diffuser(atom/target)
	var/turf/center = get_turf(target)
	if(!center)
		return FALSE
	for(var/direction in GLOB.cardinal)
		var/turf/neighbor = get_step(center, direction)
		for(var/obj/machinery/shield_diffuser/D in turf_contents_of_type(neighbor, /obj/machinery/shield_diffuser))
			if(D.enabled && !D.alarm && D.operable())
				return TRUE
	return FALSE

/obj/machinery/shield_diffuser/examine(mob/user)
	. = ..()
	. += "It is [enabled ? "enabled" : "disabled"]."
	if(alarm)
		. += "A red LED labeled \"Proximity Alarm\" is blinking on the control panel."

