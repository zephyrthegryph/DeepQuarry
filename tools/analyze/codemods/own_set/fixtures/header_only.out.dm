/datum/header
	var/datum/cell

CAPABILITIES(/datum/header)
	owns_one(nameof(cell), /datum)

/datum/header/proc/fill(datum/thing)
	rel_set(src, nameof(cell), thing)
