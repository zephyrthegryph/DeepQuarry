// item_material: lazy state of /obj/item (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, item_material, field), write with STATE_SET(A, item_material, field, value), end it with item_material_clear(A).

/datum/item_material_state
	parent_type = /datum/lazy_state
	var/mat_luminescence = 0
	var/mat_radioactivity = 0
	var/mat_toxicity = 0
