// attacker: lazy owned state of /mob (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, attacker, field), write with STATE_SET(M, attacker, field, value), end it with attacker_clear(M).

/datum/attacker_state
	var/lastattacker_key = ""
	var/lastattacker_name = ""

/mob
	var/datum/attacker_state/attacker
