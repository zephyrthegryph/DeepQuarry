/obj/item/petrifier
	name = "odd button"
	desc = "A metal device with a single, purple button on it, and a tiny interface."
	icon = 'icons/obj/machines/petrification.dmi'
	icon_state = "petrifier"

	var/mob/living/carbon/human/target
	var/identifier = "statue"
	var/material = "stone"
	var/adjective = "hardens"
	var/tint = "#FFFFFF"
	var/discard_clothes = TRUE
	var/able_to_unpetrify = TRUE
	var/obj/machinery/petrification/linked

/obj/item/petrifier/Initialize(mapload, to_link)
	. = ..()
	linked = to_link

DECLARE_INTERACTIONS(/obj/item/petrifier, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/petrifier/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if (!isturf(user.loc) && get_ultimate_mob(user) != target)
		to_chat(user, span_warning("The device beeps but does nothing."))
		return TRUE
	if (linked?.petrify(user, src))
		visible_message(span_notice("A ray of purple light streams out of \the [src], aimed directly at [target]. Everywhere the light touches on them quickly [adjective] into [material]."))
		to_chat(user, span_warning("The device fizzles and crumbles into dust."))
		consume(src, user)
	return TRUE
