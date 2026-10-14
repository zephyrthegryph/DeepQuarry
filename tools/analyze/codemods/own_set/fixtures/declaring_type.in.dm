/datum/base
	var/datum/cell
	var/datum/second

/datum/base/child
	var/datum/own_var

/datum/base/child/proc/fill(datum/thing)
	own_set(src, nameof(cell), thing)
	own_set(src, nameof(own_var), thing)
	own_set(src, nameof(second), thing)
