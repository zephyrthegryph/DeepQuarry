// The anchor capability (doc/rewrite/final_api.html, section 11 "The library": anchor(tool =)).
//
// A machine that can be bolted to the floor and unbolted again. Op anchor.toggle: a wrench (by default) flips the holder's anchored flag through its
// setter, so everything that reads `anchored` (a look, a charge loop, a requirement) follows. It is instant (wait(0)): the legacy machines it
// replaces never made the player wait for a wrench, and a machine that wants a delay says so with extend("anchor.toggle", wait(t)).
//
//   anchor()                                   a wrench anchors and unanchors it
//   anchor(empty = nameof(charging))           ...but not while the named holder var holds something (a charger with a cell in it)
//   anchor(sfx = SFX_ITEMS_RATCHET)            ...with the ratchet sound (`volume` is play_sfx()'s volume factor, 1 by default)
//   anchor(attached = MSG(x), detached = MSG(y))   ...saying its own messages for the two outcomes
//   anchor(delay = 2 SECONDS)                  ...taking that long; a refusal of its own is extend("anchor.toggle", needs(...))

MSG_DEF(anchor/attached, "You attach %T% to the ground.", "%U% attaches %T% to the ground.")
MSG_DEF(anchor/detached, "You detach %T% from the ground.", "%U% detaches %T% from the ground.")
MSG_DEF_SELF(anchor/occupied, "Remove what is in it first.")

// Messages for a wrench on a fixture, for `attached` and `detached`: said to the wrencher alone (_self) or to onlookers as well.
MSG_DEF(anchor/wrenched, "You wrench %T%.", "%U% wrenches %T%.")
MSG_DEF(anchor/unwrenched, "You unwrench %T%.", "%U% unwrenches %T%.")
MSG_DEF_SELF(anchor/wrenched_self, "You wrench %T%.")
MSG_DEF_SELF(anchor/unwrenched_self, "You unwrench %T%.")
MSG_DEF_SELF(anchor/secured_self, "You secure %T%.")
MSG_DEF_SELF(anchor/unsecured_self, "You unsecure %T%.")

CAPABILITY_TYPE(anchor, CAP_ANCHOR, /datum/capability/lib/anchor, key = NONE, tool = TOOL_WRENCH, empty = null, sfx = null, volume = 1, delay = 0, attached = null, detached = null)

/datum/capability/lib/anchor

/datum/capability/lib/anchor/entries()
	return list(op("toggle", tool(tool), wait(delay), \
		empty ? needs(req_empty(empty, because = MSG(anchor/occupied))) : null, \
		toggles(nameof(/atom/movable::anchored)), says(CAP_PROC(toggled_message)), \
		sfx ? plays(sfx, volume = volume) : null))

/// What anchor.toggle just did: attached or detached.
/datum/capability/lib/anchor/proc/toggled_message(datum/act/A)
	var/atom/movable/holder = A.holder
	if(holder.anchored)
		return attached || /datum/msg/anchor/attached
	return detached || /datum/msg/anchor/detached
