// regen: lazy owned state of /mob/living/carbon/human (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, regen, field), write with STATE_SET(M, regen, field, value), end it with regen_clear(M).

/datum/regen_state
	/// /mob/living/carbon/human
	var/active_regen = FALSE
	var/active_regen_delay = 300

/mob/living/carbon/human
	var/datum/regen_state/regen
