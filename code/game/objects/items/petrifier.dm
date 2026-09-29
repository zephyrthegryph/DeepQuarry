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
	rel_set(src, nameof(linked), to_link)

DECLARE_INTERACTIONS(/obj/item/petrifier, INTERACT_USE(null, PROC_REF(interaction_self), REQ_TARGET_STATE(/obj/item/petrifier/proc/can_fire)))

/// Requirement: TRUE, or why the device does nothing.
/obj/item/petrifier/proc/can_fire(mob/user, atom/target, obj/item/held)
	if(!isturf(user.loc) && get_ultimate_mob(user) != target_ref())
		return "the device beeps but does nothing"
	return TRUE

/// Old attack_self.
/obj/item/petrifier/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if (linked()?.petrify(user, src))
		visible_message(span_notice("A ray of purple light streams out of \the [src], aimed directly at [target_ref()]. Everywhere the light touches on them quickly [adjective] into [material]."))
		to_chat(user, span_warning("The device fizzles and crumbles into dust."))
		consume(src, user)
	return TRUE

/// Relation view: target (reads null once it is gone).
/obj/item/petrifier/proc/target_ref() as /mob/living/carbon/human
	return target

/// Relation view: linked (reads null once it is gone).
/obj/item/petrifier/proc/linked() as /obj/machinery/petrification
	return linked
