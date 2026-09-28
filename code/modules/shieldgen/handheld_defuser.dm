/obj/item/shield_diffuser
	name = "portable shield diffuser"
	desc = "A small handheld device designed to disrupt energy barriers."
	description_info = "This device disrupts shields on directly adjacent tiles (in a + shaped pattern), in a similar way the floor mounted variant does. It is, however, portable and run by an internal battery. Can be recharged with a regular recharger."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "hdiffuser_off"
	var/obj/item/cell/device/cell
	var/enabled = 0

/obj/item/shield_diffuser/Initialize(mapload)
	. = ..()
	cell = new(src)

DECLARE_REF(/obj/item/shield_diffuser, "cell", OWNED, null)

/obj/item/shield_diffuser/get_cell()
	return cell

/obj/item/shield_diffuser/periodic_step()
	if(!enabled)
		return PROCESS_KILL

	for(var/direction in GLOB.cardinal)
		var/turf/simulated/shielded_tile = get_step(get_turf(src), direction)
		for(var/obj/effect/shield/S in turf_contents_of_type(shielded_tile, /obj/effect/shield))
			// 10kJ per pulse, but gap in the shield lasts for longer than regular diffusers.
			if(istype(S) && !S.diffused_for && !S.disabled_for && cell.checked_use(10 KILOWATTS * CELLRATE))
				S.diffuse(20)
		// Legacy shield support
		for(var/obj/effect/energy_field/S in turf_contents_of_type(shielded_tile, /obj/effect/energy_field))
			if(istype(S) && cell.checked_use(10 KILOWATTS * CELLRATE))
				qdel(S)

/obj/item/shield_diffuser/update_icon()
	if(enabled)
		icon_state = "hdiffuser_on"
	else
		icon_state = "hdiffuser_off"

DECLARE_INTERACTIONS(/obj/item/shield_diffuser, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/shield_diffuser/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	enabled = !enabled
	update_icon()
	if(enabled)
		om_task_periodic(src, PERIODIC_SLOW)
	else
		om_task_periodic_stop(src)
	to_chat(user, "You turn \the [src] [enabled ? "on" : "off"].")
	return TRUE

/obj/item/shield_diffuser/examine(mob/user)
	. = ..()
	. += "The charge meter reads [cell ? cell.percent() : 0]%"
	. += "It is [enabled ? "enabled" : "disabled"]."
