// spont_belly: lazy owned state of /mob (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, spont_belly, field), write with STATE_SET(M, spont_belly, field, value), end it with spont_belly_clear(M).

/datum/spont_belly_state
	var/spont_belly_front
	var/spont_belly_left
	var/spont_belly_rear
	var/spont_belly_right

/mob
	var/datum/spont_belly_state/spont_belly
