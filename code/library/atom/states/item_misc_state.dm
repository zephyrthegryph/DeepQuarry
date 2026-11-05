// item_misc: lazy state of /obj/item (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, item_misc, field), write with STATE_SET(A, item_misc, field, value), end it with item_misc_clear(A).

/datum/item_misc_state
	parent_type = /datum/lazy_state
	/// base_vars wave 3
	var/cleaving = FALSE
	var/clothing_channel_colors
	var/d_mult_old = 1
	var/digest_stage
	var/item_tf_spawn_allowed = FALSE
	var/tether_path
	var/trash_eatable = TRUE
	var/worn_layer
	/// / TRUE while the item is held up to zoom (a scope, binoculars): set and cleared by the item_zoom remote view.
	var/zoom = FALSE
