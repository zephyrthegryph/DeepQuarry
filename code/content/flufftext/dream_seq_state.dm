// dream_seq: lazy owned state of /mob/living/carbon (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, dream_seq, field), write with dream_seq_of(M).set_field(value), end it with dream_seq_clear(M).

/datum/dream_seq_state
	var/datum/dream/current_dream
	var/dream_wait = 0

/mob/living/carbon
	var/datum/dream_seq_state/dream_seq
