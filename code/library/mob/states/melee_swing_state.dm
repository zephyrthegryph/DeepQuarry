// melee_swing: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, melee_swing, field), write with STATE_SET(M, melee_swing, field, value), end it with melee_swing_clear(M).

/datum/melee_swing_state
	var/is_swinging = FALSE
	var/melee_swing_resolving = FALSE
	var/melee_swing_serial = 0

/mob/living
	var/datum/melee_swing_state/melee_swing
