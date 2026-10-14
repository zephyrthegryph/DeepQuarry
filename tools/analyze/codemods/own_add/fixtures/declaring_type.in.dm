/datum/base
	var/list/datum/parts
	var/list/datum/second_parts

/datum/base/child
	var/list/datum/own_parts

/datum/base/child/proc/fill(datum/thing)
	own_add(src, nameof(parts), thing)
	own_add(src, nameof(own_parts), thing)
	own_add(src, nameof(second_parts), thing)
