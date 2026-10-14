#define SECONDS *10
#define PROC_REF(X) (#X)
#define GLOBAL_PROC_REF(X) (#X)
#define TYPE_PROC_REF(T, X) (#X)

/datum/thing
	var/id

/datum/thing/proc/tick(a, b)
	return

/proc/free_tick(a)
	return

/proc/om_after(datum/E, delay, proc_ref, ...)
	return 1

/proc/after(datum/owner, delay, handler, key = null, clock = 0, list/with = null)
	return 1

/proc/after_slot(datum/E, slot, delay, proc_ref, ...)
	return 1
