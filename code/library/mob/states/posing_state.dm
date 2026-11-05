// posing: lazy owned state of /mob/living/carbon (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, posing, field), write with posing_of(M).set_field(value), end it with posing_clear(M).

/datum/posing_state
	var/pose
	/// /mob/living/carbon
	var/pose_move = FALSE

/mob/living/carbon
	var/datum/posing_state/posing
