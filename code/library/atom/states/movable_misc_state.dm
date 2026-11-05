// movable_misc: lazy state of /atom/movable (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, movable_misc, field), write with STATE_SET(A, movable_misc, field, value), end it with movable_misc_clear(A).

/datum/movable_misc_state
	parent_type = /datum/lazy_state
	var/affecting_dynamic_lumi = 0
	/// Toggle for autotransfer mechanics (default TRUE; the slot is set only when FALSE).
	var/autotransferable = TRUE
	/// The per-instance state is sparse slots (code/engine/declare/sparse_slots.dm): nothing on /atom/movable until a slot is set.
	var/belly_cycles = 0
	/// base_vars wave 3
	var/blocks_light = FALSE
	var/icon_rotation = DEFAULT_ICON_ROTATION
	var/listening_recursive = NON_LISTENING_ATOM
	var/move_resist = MOVE_RESIST_DEFAULT
