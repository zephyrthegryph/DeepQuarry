/obj/item/shield_diffuser/get_mechanics_info(list/additional_information)
	return ..(list("This device disrupts shields on directly adjacent tiles (in a + shaped pattern), like the floor mounted variant. It runs on an internal battery that can be recharged in a regular recharger.") + additional_information)

/obj/item/shield_diffuser
	name = "portable shield diffuser"
	desc = "A small handheld device designed to disrupt energy barriers."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "hdiffuser_off"
	var/obj/item/cell/device/cell

/obj/item/shield_diffuser/var/enabled = FALSE
TRACKED(/obj/item/shield_diffuser, enabled)
CAPABILITIES(/obj/item/shield_diffuser)
	owns_one(nameof(cell), starts = /obj/item/cell/device)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	every(2 SECONDS, then(PROC_REF(shield_diffuser_step)), when = nameof(enabled))


/obj/item/shield_diffuser/get_cell()
	return cell

/obj/item/shield_diffuser/proc/shield_diffuser_step(datum/act/timer/A)
	for(var/direction in GLOB.cardinal)
		var/turf/simulated/shielded_tile = get_step(get_turf(src), direction)
		for(var/obj/effect/shield/S in turf_contents_of_type(shielded_tile, /obj/effect/shield))
			// 10kJ per pulse, but gap in the shield lasts for longer than regular diffusers.
			if(istype(S) && !S.diffused_for && !S.disabled_for && cell.checked_use(10 KILOWATTS * CELLRATE))
				S.diffuse(20)
		// Legacy shield support
		for(var/obj/effect/energy_field/S in turf_contents_of_type(shielded_tile, /obj/effect/energy_field))
			if(istype(S) && cell.checked_use(10 KILOWATTS * CELLRATE))
				spent(S)

/// The look (the draw sweep: from its template).
/obj/item/shield_diffuser/draw(datum/look/look)
	..()
	look.state("hdiffuser_[enabled ? "on" : "off"]")

/// Old attack_self.
/obj/item/shield_diffuser/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	set_enabled(!enabled)
	to_chat(user, "You turn \the [src] [enabled ? "on" : "off"].")
	return TRUE

/obj/item/shield_diffuser/examine(mob/user)
	. = ..()
	. += "The charge meter reads [cell ? cell.percent() : 0]%"
	. += "It is [enabled ? "enabled" : "disabled"]."
