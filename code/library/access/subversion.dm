// The subversion reset (doc/rewrite/final_api.html, section 11 "The library": subversion_reset(parts...)).
//
// What undoes an emag or a hack: a tool (a multitool at the open hatch) used on a holder that is subverted, with the type's parts for the wait and
// the place. One op, subversion_reset.use, offered only while the holder is subverted (is_subverted(): emagged, or taken over another way). Its work is
// the holder's own: reset_subversion(A) (a type overrides it; the default clears the emag), and `says` tells the user it worked.
//
//   subversion_reset(list(tool(TOOL_MULTITOOL), at(SPACE_HATCH)))

MSG_DEF(subversion/reset, "You reset %T%.", "%U% resets %T%.")

CAPABILITY_TYPE(subversion_reset, CAP_SUBVERSION_RESET, /datum/capability/lib/subversion_reset, key = NONE, parts = null, done = null)

/datum/capability/lib/subversion_reset

/datum/capability/lib/subversion_reset/entries()
	return list(op("use", parts, label("Reset"), when(TYPE_PROC_REF(/atom, subversion_to_reset)), \
		then(TYPE_PROC_REF(/atom, reset_subversion)), says(done || MSG(subversion/reset)), logs(LOG_GAME)))

/// The holder is subverted now.
/atom/proc/subversion_to_reset(datum/act/A)
	return is_subverted()

/// What a reset does to the holder: the default clears the emag (a type that is taken over another way overrides it and calls ..()).
/atom/proc/reset_subversion(datum/act/op/A)
	cap_key_set(src, EMAG_EMAGGED, FALSE, null)
	return OP_OK
