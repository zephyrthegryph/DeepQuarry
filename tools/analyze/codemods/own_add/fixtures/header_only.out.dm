/datum/header
	var/list/datum/parts

CAPABILITIES(/datum/header)
	owns_many(nameof(parts), /datum)

/datum/header/proc/fill(datum/thing)
	rel_add(src, nameof(parts), thing)
