// swarm: lazy state of /atom/movable (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, swarm, field), write with STATE_SET(A, swarm, field, value), end it with swarm_clear(A).

/datum/swarm_state
	parent_type = /datum/lazy_state
	/// /atom/movable
	var/is_swarming = FALSE
	var/swarm_offset_x = 0
	var/swarm_offset_y = 0
