/datum/holder/proc/fill(datum/thing, mob/user)
	own_add(src, nameof(parts), thing, user = user)
	own_add(src, nameof(parts), thing, into = 1)
	own_add(src, nameof(parts), thing, null, 1)
	own_add(src, nameof(parts))
	var/ref = GLOBAL_PROC_REF(own_add)
	#define LATER(x) own_add(src, nameof(parts), x)
	// the plain form beside them still converts
	own_add(src, nameof(parts), thing)
