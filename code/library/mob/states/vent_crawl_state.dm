// vent_crawl: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, vent_crawl, field), write with vent_crawl_of(M).set_field(value), end it with vent_crawl_clear(M).

/datum/vent_crawl_state
	var/is_ventcrawling = FALSE
	var/ventcrawl_layer = 3

/mob/living
	var/datum/vent_crawl_state/vent_crawl
