/datum/blocked
	var/list/datum/parts
	var/list/datum/other_parts

CAPABILITIES(/datum/blocked)
	owns_many(nameof(other_parts), /datum)

/datum/blocked/proc/fill(datum/thing)
	own_add(src, nameof(parts), thing)
	own_add(src, nameof(other_parts), thing)
