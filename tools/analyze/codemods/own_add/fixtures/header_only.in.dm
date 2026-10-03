/datum/header
	var/list/datum/parts

CAPABILITIES(/datum/header)

/datum/header/proc/fill(datum/thing)
	own_add(src, nameof(parts), thing)
