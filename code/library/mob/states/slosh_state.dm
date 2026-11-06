// slosh: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, slosh, field), write with STATE_SET(M, slosh, field, value), end it with slosh_clear(M).

/datum/slosh_state
	var/slosh_chance = 0
	var/slosh_steps = 0
	var/slosh_volume = 0

/mob/living
	var/datum/slosh_state/slosh
