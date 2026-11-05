// dq_vitals: lazy owned state of /mob/living/carbon/human (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, dq_vitals, field), write with STATE_SET(M, dq_vitals, field, value), end it with dq_vitals_clear(M).

/datum/dq_vitals_state
	var/dq_last_bodytemperature
	var/dq_last_neural_load
	var/dq_last_radiation

/mob/living/carbon/human
	var/datum/dq_vitals_state/dq_vitals
