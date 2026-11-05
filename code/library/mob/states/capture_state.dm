// capture: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, capture, field), write with capture_of(M).set_field(value), end it with capture_clear(M).

/datum/capture_state
	/// /mob/living
	var/capture_caught = FALSE
	/// / If TRUE (the default), the mob is capturable. Otherwise it isn't.
	var/capture_crystal = TRUE

/mob/living
	var/datum/capture_state/capture
