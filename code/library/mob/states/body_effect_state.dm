// body_effect: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, body_effect, field), write with body_effect_of(M).set_field(value), end it with body_effect_clear(M).

/datum/body_effect_state
	var/body_effect_serial = 0

/mob/living
	var/datum/body_effect_state/body_effect
