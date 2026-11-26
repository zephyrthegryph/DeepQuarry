// footfall: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, footfall, field), write with STATE_SET(M, footfall, field, value), end it with footfall_clear(M).

/datum/footfall_state
	var/footstep_vary = FALSE

/mob/living
	var/datum/footfall_state/footfall
