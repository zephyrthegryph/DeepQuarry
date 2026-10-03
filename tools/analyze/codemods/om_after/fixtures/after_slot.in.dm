/datum/thing/proc/slots(mob/user)
	after_slot(src, "tick_timer", 5 SECONDS, PROC_REF(tick))
	after_slot(user, "color", 2 SECONDS, PROC_REF(tick), user)
	after_slot(src, "multi", 1, PROC_REF(tick), user, 7)
	after_slot(null, "global", 9, GLOBAL_PROC_REF(free_tick), src)
	after_slot(src,
		"split", 3, // the delay
		PROC_REF(tick))
	after_slot(src, "k[id]", 4, PROC_REF(tick))
