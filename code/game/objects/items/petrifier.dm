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

CAPABILITIES(/obj/item/petrifier)
	op("fire", in_hand(), wait(0), needs(req(PROC_REF(can_fire), because = MSG(petrifier/beeps))), then(PROC_REF(fired)))
	param(nameof(linked), pos = 1)

MSG_DEF_SELF(petrifier/beeps, "The device beeps but does nothing.")

/// Requirement: the device does nothing from inside something unless the one it aims at is the one holding it.
/obj/item/petrifier/proc/can_fire(datum/act/op/A)
	var/mob/user = A.actor
	// ALLOW(reads): where the user stands is read when the device is used, never from a cached menu
	return (isturf(user.loc) || get_ultimate_mob(user) == target_ref()) ? null : MSG(petrifier/beeps)

/// The use in the hand.
/obj/item/petrifier/proc/fired(datum/act/op/A)
	var/mob/user = A.actor
	if (linked()?.petrify(user, src))
		visible_message(span_notice("A ray of purple light streams out of \the [src], aimed directly at [target_ref()]. Everywhere the light touches on them quickly [adjective] into [material]."))
		to_chat(user, span_warning("The device fizzles and crumbles into dust."))
		consume(src, user)
	return OP_OK

/// Relation view: target (reads null once it is gone).
/obj/item/petrifier/proc/target_ref() as /mob/living/carbon/human
	return target // ALLOW(reads): the one it aims at is read when the device is used, never from a cached menu

/// Relation view: linked (reads null once it is gone).
/obj/item/petrifier/proc/linked() as /obj/machinery/petrification
	return linked
