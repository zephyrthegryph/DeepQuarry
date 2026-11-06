// cloak: lazy state of /atom/movable (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, cloak, field), write with STATE_SET(A, cloak, field, value), end it with cloak_clear(A).

/datum/cloak_state
	parent_type = /datum/lazy_state
	var/image/cloak_selfimage
	var/cloaked = FALSE
