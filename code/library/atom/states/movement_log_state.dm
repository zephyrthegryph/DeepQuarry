// movement_log: lazy state of /atom/movable (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, movement_log, field), write with STATE_SET(A, movement_log, field, value), end it with movement_log_clear(A).

/datum/movement_log_state
	parent_type = /datum/lazy_state
	var/last_high_pressure_movement_air_cycle = 0
	/// Direction of the last step (the old /atom/movable last_move), written by Move()/doMove(); a stopped mover holds nothing.
	var/last_move = 0
	var/moved_recently = 0
