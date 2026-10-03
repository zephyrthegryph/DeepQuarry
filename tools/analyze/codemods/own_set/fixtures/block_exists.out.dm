/datum/blocked
	var/datum/cell
	var/datum/other

CAPABILITIES(/datum/blocked)
	owns_one(nameof(other), /datum)
	owns_one(nameof(cell), /datum)

/datum/blocked/proc/fill(datum/thing)
	rel_set(src, nameof(cell), thing)
	rel_set(src, nameof(other), thing)
