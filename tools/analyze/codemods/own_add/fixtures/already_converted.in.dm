/datum/holder/proc/fill(datum/thing)
	rel_add(src, nameof(parts), thing)
	var/datum/got = rel_add(src, nameof(parts), thing)
	return got
