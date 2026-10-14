/obj/thing/confetti
	name = "confetti"

MSG_DEF_SELF(confetti/pick_begins, span_notice("You start to pick up %T%."))

CAPABILITIES(/obj/thing/confetti)
	op("pick", hand(), label("Pick up"), begins(MSG(confetti/pick_begins)), wait(6 SECONDS), then(PROC_REF(pick_done)))

/obj/thing/confetti/proc/pick_done(datum/act/op/A)
	var/mob/user = A.actor
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
