/datum/thing/proc/schedule(mob/user)
	after(src, 5 SECONDS, PROC_REF(tick))
	after(src, 2, PROC_REF(tick), with = list(user))
	after(src, 3, PROC_REF(tick), key = "slot", with = list(user, 1))
	var/id = after(null, 1, GLOBAL_PROC_REF(free_tick), with = list(src))
	return id
