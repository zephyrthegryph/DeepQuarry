// airborne: lazy state of /atom/movable (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, airborne, field), write with STATE_SET(A, airborne, field, value), end it with airborne_clear(A).

/datum/airborne_state
	parent_type = /datum/lazy_state
	var/hovering
	var/parachute = FALSE
	var/parachuting
	var/softfall
