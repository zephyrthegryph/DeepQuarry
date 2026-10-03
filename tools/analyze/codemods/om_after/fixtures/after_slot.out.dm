/datum/thing/proc/slots(mob/user)
	after(src, 5 SECONDS, PROC_REF(tick), key = "tick_timer")
	after(user, 2 SECONDS, PROC_REF(tick), key = "color", with = list(user))
	after(src, 1, PROC_REF(tick), key = "multi", with = list(user, 7))
	after(null, 9, GLOBAL_PROC_REF(free_tick), key = "global", with = list(src))
	after(src,
		3, // the delay
		PROC_REF(tick), key = "split")
	after(src, 4, PROC_REF(tick), key = "k[id]")
