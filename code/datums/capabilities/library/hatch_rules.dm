// cap_hatch_rules(cover_locked_while): refuses the cover's entries (both ways) while a holder proc says
// the cover holds, with that proc's reason. maintenance_hatch()'s own cover lock only refuses opening,
// with a generic reason; a holder whose cover also can't CLOSE in some state (the APC with its board
// unsecured) adds this with the same proc.

/datum/capability/hatch_rules
	layer_name = CAP_NO_LAYER
	/// Holder proc (mob/user, obj/item/held): null/FALSE while the cover may move, TRUE or a reason.
	var/cover_locked_while

/proc/cap_hatch_rules(cover_locked_while)
	var/datum/capability/hatch_rules/C = new
	C.cover_locked_while = cover_locked_while
	return C

/datum/capability/hatch_rules/gate(atom/holder, mob/user, datum/interaction/entry)
	var/datum/interaction/capability/E = entry
	if(!istype(E) || !istype(E.cap, /datum/capability/cover))
		return null
	var/holds = call(holder, cover_locked_while)(user, null)
	if(!holds)
		return null
	return istext(holds) ? holds : "the cover is locked"
