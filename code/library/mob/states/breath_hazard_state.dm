// breath_hazard: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, breath_hazard, field), write with STATE_SET(M, breath_hazard, field, value), end it with breath_hazard_clear(M).

/datum/breath_hazard_state
	var/air_hazard_at = -1
	var/air_hazard_breath_at = -1
	var/failed_last_breath = 0

/mob/living
	var/datum/breath_hazard_state/breath_hazard
