/datum/holder
	var/datum/cell

CAPABILITIES(/datum/holder)
	owns_one(nameof(cell), /datum)

/datum/holder/proc/fill(datum/thing)
	rel_set(src, nameof(cell), thing)
	var/datum/got = rel_set(src, nameof(cell), thing)
	return got
