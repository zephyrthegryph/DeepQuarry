// tf_xform: lazy state of /atom (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, tf_xform, field), write with STATE_SET(A, tf_xform, field, value), end it with tf_xform_clear(A).

/datum/tf_xform_state
	parent_type = /datum/lazy_state
	var/tf_offset_x
	var/tf_offset_y
	var/tf_rotation
	var/tf_scale_x
	var/tf_scale_y
