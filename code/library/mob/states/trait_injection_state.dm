// trait_injection: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, trait_injection, field), write with STATE_SET(M, trait_injection, field, value), end it with trait_injection_clear(M).

/datum/trait_injection_state
	var/trait_injection_amount = 5
	var/trait_injection_selected
	var/trait_injection_verb = "bite"
	var/list/trait_injection_reagents

/mob/living
	var/datum/trait_injection_state/trait_injection
