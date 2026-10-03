/datum/holder/proc/fill(datum/thing)
	rel_set(src, nameof(cell), thing)
	var/datum/got = rel_set(src, nameof(cell), thing)
	return got
