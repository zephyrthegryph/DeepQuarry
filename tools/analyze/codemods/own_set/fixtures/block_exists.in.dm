/datum/blocked
	var/datum/cell
	var/datum/other

CAPABILITIES(/datum/blocked)
	owns_one(nameof(other), /datum)

/datum/blocked/proc/fill(datum/thing)
	own_set(src, nameof(cell), thing)
	own_set(src, nameof(other), thing)
