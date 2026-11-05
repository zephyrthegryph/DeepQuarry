// autofire: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, autofire, field), write with STATE_SET(M, autofire, field, value), end it with autofire_clear(M).

/datum/autofire_state
	var/autofire_delay = 0
	var/autofire_params

/mob/living
	var/datum/autofire_state/autofire
