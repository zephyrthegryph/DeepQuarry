/datum/holder/proc/fill(datum/thing, mob/user)
	own_set(src, nameof(cell), thing, user = user)
	own_set(src, nameof(cell), thing, into = 1)
	own_set(src, nameof(cell), thing, null, 1)
	own_set(src, nameof(cell))
	var/ref = GLOBAL_PROC_REF(own_set)
	#define LATER(x) own_set(src, nameof(cell), x)
	// the plain form beside them still converts
	rel_set(src, nameof(cell), thing)
