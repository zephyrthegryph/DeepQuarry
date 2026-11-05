// passtable: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, passtable, field), write with passtable_of(M).set_field(value), end it with passtable_clear(M).

/datum/passtable_state
	var/passtable_crawl_checked = FALSE
	var/passtable_reset

/mob/living
	var/datum/passtable_state/passtable
