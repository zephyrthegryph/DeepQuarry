/datum/declared
	var/list/datum/parts

CAPABILITIES(/datum/declared)
	owns_many(nameof(parts), /datum)

/datum/declared/proc/fill(datum/thing)
	rel_add(src, nameof(parts), thing)
