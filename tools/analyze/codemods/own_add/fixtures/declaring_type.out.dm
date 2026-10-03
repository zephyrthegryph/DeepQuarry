/datum/base
	var/list/datum/parts
	var/list/datum/second_parts

CAPABILITIES(/datum/base)
	owns_many(nameof(parts), /datum)
	owns_many(nameof(second_parts), /datum)

/datum/base/child
	var/list/datum/own_parts

CAPABILITIES(/datum/base/child)
	owns_many(nameof(own_parts), /datum)

/datum/base/child/proc/fill(datum/thing)
	rel_add(src, nameof(parts), thing)
	rel_add(src, nameof(own_parts), thing)
	rel_add(src, nameof(second_parts), thing)
