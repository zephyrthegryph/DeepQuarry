// omen: lazy owned state of /mob/living (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, omen, field), write with omen_of(M).set_field(value), end it with omen_clear(M).

/datum/omen_state
	/// / Base damage from negative events (sparse slot omen_damage, default 1). Cursed take 25% of this damage.
	var/omen_damage = 1
	/// / If we want to do more evil events, such as spontaneous combustion (sparse slot omen_evil, default TRUE).
	var/omen_evil = TRUE
	var/omen_incidents = INFINITY
	var/omen_luck = 1
	var/omen_safe_disposals = FALSE
	var/omen_vorish = TRUE

/mob/living
	var/datum/omen_state/omen
