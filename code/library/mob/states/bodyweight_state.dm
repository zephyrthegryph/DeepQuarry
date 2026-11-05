// bodyweight: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, bodyweight, field), write with STATE_SET(M, bodyweight, field, value), end it with bodyweight_clear(M).

/datum/bodyweight_state
	/// Body weight in pounds for the weightgain system; reads as DEFAULT_MOB_WEIGHT when unset (sparse_get_or / sparse_set_or).
	var/weight = DEFAULT_MOB_WEIGHT
	var/weight_gain = 1
	var/weight_loss = 0.5

/mob/living
	var/datum/bodyweight_state/bodyweight
