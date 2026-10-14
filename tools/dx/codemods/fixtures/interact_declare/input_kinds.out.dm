CAPABILITIES(/obj/machinery/gap_cell)
	op("drag", item(/mob/living), gesture(GESTURE_DRAG), label("Put inside"), then(PROC_REF(interaction_drag)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), label("Flip the switch"), then(PROC_REF(interaction_alt)))
	op("tk", tk(), label("Interaction tk"), then(PROC_REF(interaction_tk)))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/obj/machinery/gap_cell/proc/interaction_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/target = A.held
	if(!ismob(target) || user.lying)
		return OP_DECLINE
	put_mob(target, user)
	return TRUE

/obj/machinery/gap_cell/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if(!powered)
		return OP_DECLINE
	flip(user)
	return TRUE

/obj/machinery/gap_cell/proc/interaction_tk(datum/act/op/A)
	var/mob/user = A.actor
	if(!powered)
		return OP_DECLINE
	nudge(user)
	return TRUE

/obj/machinery/gap_cell/proc/interaction_self(datum/act/op/A)
	if(!powered)
		return OP_DECLINE
	return TRUE
