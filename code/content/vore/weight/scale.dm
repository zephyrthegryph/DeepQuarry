/obj/machinery/scale
	name = "scale"
	icon = 'icons/obj/machines/fitness_machines_vr.dmi'
	icon_state = "scale"
	desc = "A scale used to measure ones weight relative to their size and species."
	anchored = TRUE // Set to 0 when we can construct or dismantle these.
	use_power = USE_POWER_OFF

CAPABILITIES(/obj/machinery/scale)
	configure(uses_power(idle = 0, active = 0))
	op("scale_weigh_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Weigh"), then(PROC_REF(scale_weigh_hand)))

/// Old attack_hand: read out the weight of whoever stands on it.
/obj/machinery/scale/proc/scale_weigh_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user.loc != loc)
		to_chat(user, span_notice("You need to be standing on top of the scale for it to work!"))
		return OP_OK
	if(STATE_GET(user, bodyweight, weight)) //Just in case.
		var/kilograms = round(text2num(STATE_GET(user, bodyweight, weight)),4) / 2.20463
		act_message(src, user, others = span_notice("%U% displays a reading of [STATE_GET(user, bodyweight, weight)]lb / [kilograms]kg when %T% stands on it."))
	return OP_OK
