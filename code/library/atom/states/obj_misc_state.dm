// obj_misc: lazy state of /obj (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, obj_misc, field), write with STATE_SET(A, obj_misc, field, value), end it with obj_misc_clear(A).

/datum/obj_misc_state
	parent_type = /datum/lazy_state
	/// /obj
	var/being_shocked = FALSE
	var/debris_amount = 1
	var/micro_accepted_scale = 0.5
	/// / Behaviour flags of an object (sparse slot obj_flags, default CAN_BE_HIT).
	var/obj_flags = CAN_BE_HIT
