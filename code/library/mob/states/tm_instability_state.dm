// tm_instability: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, tm_instability, field), write with STATE_SET(M, tm_instability, field, value), end it with tm_instability_clear(M).

/datum/tm_instability_state
	var/last_instability = 0
	/// / Most recent world.time that something bad happened due to instability: the lazy state field last_instability_event.
	var/last_instability_event = 0

/mob/living
	var/datum/tm_instability_state/tm_instability
