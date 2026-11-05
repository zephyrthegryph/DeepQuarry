// carbon_misc: lazy owned state of /mob/living/carbon (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, carbon_misc, field), write with carbon_misc_of(M).set_field(value), end it with carbon_misc_clear(M).

/datum/carbon_misc_state
	var/breath_cycle = 0
	var/germs_rolled_at
	/// /mob/living/carbon
	var/last_taste_text = ""
	var/synth_reag_processing = TRUE

/mob/living/carbon
	var/datum/carbon_misc_state/carbon_misc
