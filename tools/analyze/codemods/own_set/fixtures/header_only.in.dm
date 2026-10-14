/datum/header
	var/datum/cell

CAPABILITIES(/datum/header)

/datum/header/proc/fill(datum/thing)
	own_set(src, nameof(cell), thing)
