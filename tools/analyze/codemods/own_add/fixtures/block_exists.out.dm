/datum/blocked
	var/list/datum/parts
	var/list/datum/other_parts

CAPABILITIES(/datum/blocked)
	owns_many(nameof(other_parts), /datum)
	owns_many(nameof(parts), /datum)

/datum/blocked/proc/fill(datum/thing)
	rel_add(src, nameof(parts), thing)
	rel_add(src, nameof(other_parts), thing)
