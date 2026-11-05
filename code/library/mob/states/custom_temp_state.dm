// custom_temp: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, custom_temp, field), write with STATE_SET(M, custom_temp, field, value), end it with custom_temp_clear(M).

/datum/custom_temp_state
	var/list/custom_cold
	var/list/custom_heat

/mob/living
	var/datum/custom_temp_state/custom_temp
