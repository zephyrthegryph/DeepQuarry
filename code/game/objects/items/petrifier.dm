/obj/item/petrifier
	name = "odd button"
	desc = "A metal device with a single, purple button on it, and a tiny interface."
	icon = 'icons/obj/machines/petrification.dmi'
	icon_state = "petrifier"

	var/target_handle
	var/identifier = "statue"
	var/material = "stone"
	var/adjective = "hardens"
	var/tint = "#FFFFFF"
	var/discard_clothes = TRUE
	var/able_to_unpetrify = TRUE
	var/linked_handle

/obj/item/petrifier/Initialize(mapload, to_link)
	. = ..()
	linked_handle = om_handle(to_link)

DECLARE_INTERACTIONS(/obj/item/petrifier, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/petrifier/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if (!isturf(user.loc) && get_ultimate_mob(user) != target_ref())
		to_chat(user, span_warning("The device beeps but does nothing."))
		return TRUE
	if (linked()?.petrify(user, src))
		visible_message(span_notice("A ray of purple light streams out of \the [src], aimed directly at [target_ref()]. Everywhere the light touches on them quickly [adjective] into [material]."))
		to_chat(user, span_warning("The device fizzles and crumbles into dust."))
		consume(src, user)
	return TRUE

/// LC-refs: target -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/petrifier/proc/target_ref() as /mob/living/carbon/human
	return om_resolve(target_handle)

/// LC-refs: linked -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/petrifier/proc/linked() as /obj/machinery/petrification
	return om_resolve(linked_handle)
