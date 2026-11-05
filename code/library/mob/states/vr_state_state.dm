// vr_state: lazy owned state of /mob (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, vr_state, field), write with STATE_SET(M, vr_state, field, value), end it with vr_state_clear(M).

/datum/vr_state_state
	var/died_in_vr = FALSE

/mob
	var/datum/vr_state_state/vr_state
