/obj/thing/confetti
	name = "confetti"

CAPABILITIES(/obj/thing/confetti)
	op("pick", hand(), label("Pick up"), then(PROC_REF(interaction_pick)))

/// Old attack_hand: slowly pick the confetti up.
/obj/thing/confetti/proc/interaction_pick(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You start to pick up [src]."))
	task_timed(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(pick_done), done_args = list(user))
	return TRUE

/obj/thing/confetti/proc/pick_done(mob/user)
	to_chat(user, "Done.")
	qdel(src)

/obj/thing/other
	name = "other"

CAPABILITIES(/obj/thing/other)
	op("use", item(/obj/item), then(PROC_REF(interaction_use)))

/obj/thing/other/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(!A.held)
		return OP_PASS
	task_timed(user, 30, target = src, receiver = src, on_done = PROC_REF(use_done), done_args = list(user))
	return OP_PASS

/obj/thing/other/proc/use_done(mob/user)
	qdel(src)
