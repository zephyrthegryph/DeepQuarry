// The cover capability (doc/rewrite/dx_conventions.md §2): a hatch or front plate that opens by
// hand or with a tool. State: CAP_COVER_OPEN. Other entries declare `behind = COVER` to be reachable
// only while it is open (cap_gate_reason()). Layer: "cover_open". Accessor: cover_is_open().
//
//	. += cover(open_tool = TOOL_CROWBAR, locked_by = LOCK)
//	. += cover(open_tool = BY_HAND)

/datum/capability/cover
	/// TOOL_* needed to open and close it, or BY_HAND.
	var/open_tool
	var/delay = 0

/// A cover. open_tool: TOOL_* or BY_HAND (null can't be passed: DM would substitute the default). locked_by = LOCK refuses while locked; behind gates
/// the cover itself behind something else.
/proc/cover(open_tool = TOOL_CROWBAR, locked_by = NONE, behind = NONE, delay = 0, log)
	var/datum/capability/cover/C = new
	C.open_tool = open_tool
	C.locked_by = locked_by
	C.behind = behind
	C.delay = delay
	C.log = log
	return C

/datum/capability/cover/interactions(atom/holder)
	var/datum/capability/entry/wrapper
	if(open_tool && open_tool != BY_HAND)
		wrapper = tool("Open cover", open_tool, TYPE_PROC_REF(/atom, cap_cover_toggle), delay = delay, behind = behind, locked_by = locked_by, log = log, priority = 10, name_proc = TYPE_PROC_REF(/atom, cap_cover_name))
	else
		wrapper = hand("Open cover", TYPE_PROC_REF(/atom, cap_cover_toggle), behind = behind, locked_by = locked_by, works_broken = TRUE, works_unpowered = TRUE, log = log, name_proc = TYPE_PROC_REF(/atom, cap_cover_name))
	return list(own_entry(wrapper, id = "cover:[open_tool]"))

/datum/capability/cover/examine(atom/holder, mob/user)
	if(cover_is_open(holder))
		return list("Its cover is open.")
	return null

/datum/capability/cover/draw(atom/holder, datum/look/look)
	look.overlay("cover_open", when = cover_is_open(holder))

/datum/capability/cover/ui_data(atom/holder, mob/user, list/data)
	data["cover_open"] = cover_is_open(holder)

/atom/proc/cap_cover_name(mob/user)
	return cover_is_open(src) ? "Close cover" : "Open cover"

/atom/proc/cap_cover_toggle(mob/user, obj/item/held)
	var/opening = !cover_is_open(src)
	cap_set(src, CAP_COVER_OPEN, opening)
	act_message(user, src, self = "You [opening ? "open" : "close"] the cover of %T%.", others = "%U% [opening ? "opens" : "closes"] the cover of %T%.")
	return TRUE
