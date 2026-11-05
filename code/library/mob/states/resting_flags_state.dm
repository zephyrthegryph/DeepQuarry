// resting_flags: lazy owned state of /mob (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, resting_flags, field), write with resting_flags_of(M).set_field(value), end it with resting_flags_clear(M).

/datum/resting_flags_state
	var/dizzy_was_resting
	var/jittery_was_resting
	var/lying_prev = 0

/mob
	var/datum/resting_flags_state/resting_flags
