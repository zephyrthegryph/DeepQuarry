// gut_disability: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, gut_disability, field), write with gut_disability_of(M).set_field(value), end it with gut_disability_clear(M).

/datum/gut_disability_state
	var/disability_death_time = FALSE
	var/disability_gut_pressure = 0

/mob/living
	var/datum/gut_disability_state/gut_disability
