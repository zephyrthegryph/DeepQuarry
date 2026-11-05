// item_clean: lazy state of /obj/item (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, item_clean, field), write with STATE_SET(A, item_clean, field, value), end it with item_clean_clear(A).

/datum/item_clean_state
	parent_type = /datum/lazy_state
	/// /obj/item
	var/cleandesc
	var/cleanname
	var/oldname
