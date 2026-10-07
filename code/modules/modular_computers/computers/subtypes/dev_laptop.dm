/obj/item/modular_computer/laptop
	anchored = TRUE
	name = "laptop computer"
	desc = "A portable computer."
	hardware_flag = PROGRAM_LAPTOP
	icon_state_unpowered = "laptop-open"
	icon = 'icons/obj/modular_laptop.dmi'
	icon_state = "laptop-open"
	icon_state_screensaver = "standby"
	base_idle_power_usage = 25
	base_active_power_usage = 200
	max_hardware_size = 2
	light_strength = 3
	max_integrity = 200
	integrity_failure = 0.5 // Stops working below 100 integrity.
	w_class = ITEMSIZE_NORMAL
	var/icon_state_closed = "laptop-closed"

CAPABILITIES(/obj/item/modular_computer/laptop)
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Alternate use"), then(PROC_REF(interaction_alt)))

/// Requirement: laptops open only on a stable surface (a table, unless already open), so open laptops aren't carried in hand
/// and tablets keep their mobility advantage.
/obj/item/modular_computer/laptop/proc/can_fold(mob/user, atom/target, obj/item/held)
	if(!istype(loc, /turf))
		return "it has to be on a stable surface first"
	if(anchored || (locate(/obj/structure/table) in contents_of(loc)))
		return TRUE
	return "you will need a better supporting surface before opening it"

/// Old click_alt.

/obj/item/modular_computer/laptop/proc/interaction_alt(datum/act/op/A)
	var/refusal = can_fold(A.actor, src, A.held)
	if(refusal != TRUE)
		if(istext(refusal))
			to_chat(A.actor, span_warning(refusal))
		return OP_DECLINE
	var/mob/living/carbon/user = A.actor
	// We need to be close to it to open it
	if((!in_range(src, user)) || user.stat || user.restrained())
		return TRUE
	set_anchored(!anchored)
	screen_on = anchored
	update_icon()
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/item/modular_computer/laptop, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/modular_computer/laptop/appearance_overlays()
	. = list()
	if(anchored)
		. += ..()
	else
		set_light(0)		// No glow from closed laptops
		icon_state = icon_state_closed

/obj/item/modular_computer/laptop/preset
	anchored = FALSE
	screen_on = FALSE
