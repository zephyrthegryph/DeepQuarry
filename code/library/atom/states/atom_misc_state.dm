// atom_misc: lazy state of /atom (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, atom_misc, field), write with STATE_SET(A, atom_misc, field, value), end it with atom_misc_clear(A).

/datum/atom_misc_state
	parent_type = /datum/lazy_state
	/// / Per-instance catalogue scan delay, or unset for the per-type default.
	var/catalogue_delay
	var/examine_icon_snapshot
	/// / Bitflags of lighting-related atom properties (LIGHT_ATTACHED, ...): a sparse slot, since almost no atom has any. Read with STATE_PEEK(A, atom_misc, light_flags).
	var/light_flags = NONE
	/// base_vars wave 3
	var/map_json_data
