/datum/base
	var/datum/cell
	var/datum/second

CAPABILITIES(/datum/base)
	owns_one(nameof(cell), /datum)
	owns_one(nameof(second), /datum)

/datum/base/child
	var/datum/own_var

CAPABILITIES(/datum/base/child)
	owns_one(nameof(own_var), /datum)

/datum/base/child/proc/fill(datum/thing)
	rel_set(src, nameof(cell), thing)
	rel_set(src, nameof(own_var), thing)
	rel_set(src, nameof(second), thing)
