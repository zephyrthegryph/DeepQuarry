// dream_seq: lazy owned state of /mob/living/carbon (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, dream_seq, field), write with STATE_SET(M, dream_seq, field, value), end it with dream_seq_clear(M).

/datum/dream_seq_state
	var/datum/dream/current_dream
	var/dream_wait = 0
	var/list/dream_fragments

/mob/living/carbon
	var/datum/dream_seq_state/dream_seq
