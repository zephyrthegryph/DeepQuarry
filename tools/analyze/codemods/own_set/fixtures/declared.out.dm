/datum/declared
	var/datum/cell

CAPABILITIES(/datum/declared)
	owns_one(nameof(cell), /datum)

/datum/declared/proc/fill(datum/thing)
	rel_set(src, nameof(cell), thing)
