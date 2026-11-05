// vore_fx: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, vore_fx, field), write with vore_fx_of(M).set_field(value), end it with vore_fx_clear(M).

/datum/vore_fx_state
	/// /mob/living
	var/absorbing_prey = 0
	var/appendage_alt_setting = FALSE
	var/digestion_in_progress = FALSE
	var/drain_finalized = 0
	var/eggs = 0
	var/flight_vore = FALSE
	var/liquidbelly_visuals = TRUE
	var/prey_controlled = FALSE
	var/stuffing_feeder = FALSE
	/// / Set while a vomit is on its way (between the first wave of nausea and puke_recovered()).
	var/vomiting
	var/vore_egg_type = "egg"

/mob/living
	var/datum/vore_fx_state/vore_fx
