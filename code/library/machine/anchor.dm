// The anchor capability (doc/rewrite/final_api.html, section 11 "The library": anchor(tool =)).
//
// A machine that can be bolted to the floor and unbolted again. Op anchor.toggle: a wrench (by default) flips the holder's anchored flag through its
// setter, so everything that reads `anchored` (a look, a charge loop, a requirement) follows. It is instant (wait(0)): the legacy machines it
// replaces never made the player wait for a wrench, and a machine that wants a delay says so with extend("anchor.toggle", wait(t)).
//
//   anchor()                                   a wrench anchors and unanchors it
//   anchor(empty = nameof(charging))           ...but not while the named holder var holds something (a charger with a cell in it)

MSG_DEF(anchor/attached, "You attach %T% to the ground.", "%U% attaches %T% to the ground.")
MSG_DEF(anchor/detached, "You detach %T% from the ground.", "%U% detaches %T% from the ground.")
MSG_DEF_SELF(anchor/occupied, "Remove what is in it first.")

CAPABILITY_TYPE(anchor, CAP_ANCHOR, /datum/capability/lib/anchor, key = NONE, tool = TOOL_WRENCH, empty = null)

/datum/capability/lib/anchor

/datum/capability/lib/anchor/entries()
	if(empty)
		return list(op("toggle", tool(tool), wait(0), needs(req_empty(empty, because = MSG(anchor/occupied))), toggles(nameof(/atom/movable::anchored)), says(CAP_PROC(toggled_message))))
	return list(op("toggle", tool(tool), wait(0), toggles(nameof(/atom/movable::anchored)), says(CAP_PROC(toggled_message))))

/// What anchor.toggle just did: attached or detached.
/datum/capability/lib/anchor/proc/toggled_message(datum/act/A)
	var/atom/movable/holder = A.holder
	return holder.anchored ? /datum/msg/anchor/attached : /datum/msg/anchor/detached
