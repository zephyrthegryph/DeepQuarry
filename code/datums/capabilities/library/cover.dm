// The cover capability (doc/rewrite/dx_conventions.md §2): a hatch or front plate that opens by
// hand or with a tool. State: CAP_COVER_OPEN, and CAP_COVER_REMOVED once a removable cover is pried
// off (the APC's "cover removed": it stays open and can't be closed). Other entries declare
// `behind = COVER` to be reachable only while it is open (cap_gate_reason()). Layer: "cover_open".
// Accessors: cover_is_open(), cover_removed().
//
//	. += cap_cover(open_tool = TOOL_CROWBAR, locked_by = LOCK)
//	. += cap_cover(open_tool = BY_HAND)
//	. += cap_cover(removable = TRUE, needs = PROC_REF(coverlock_ok), else_say = "the cover is locked")

/datum/capability/cover
	layer_name = "cover_open"
	/// TOOL_* needed to open and close it, or BY_HAND.
	var/open_tool
	var/delay = 0
	/// A crowbar on harm intent pries it off (CAP_COVER_REMOVED).
	var/removable = FALSE

/// A cover. open_tool: TOOL_* or BY_HAND (null can't be passed: DM would substitute the default).
/// removable: a crowbar on harm intent removes it. Gating as every library constructor.
/proc/cap_cover(open_tool = TOOL_CROWBAR, delay = 0, removable = FALSE, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, layer = "cover_open")
	var/datum/capability/cover/C = new
	C.open_tool = open_tool
	C.delay = delay
	C.removable = removable
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/cover/interactions(atom/holder)
	. = list()
	var/present = TYPE_PROC_REF(/atom, cap_cover_present)
	if(open_tool && open_tool != BY_HAND)
		. += adopt_entry(cap_tool("Open cover", open_tool, TYPE_PROC_REF(/atom, cap_cover_toggle), delay = delay, needs = present, priority = 10, name_proc = TYPE_PROC_REF(/atom, cap_cover_name)), id = "cover:[open_tool]")
	else
		. += adopt_entry(cap_hand("Open cover", TYPE_PROC_REF(/atom, cap_cover_toggle), needs = present, works_broken = TRUE, works_unpowered = TRUE, name_proc = TYPE_PROC_REF(/atom, cap_cover_name)), id = "cover:[open_tool]")
	if(removable)
		var/datum/interaction/capability/E = adopt_entry(cap_tool("Remove cover", TOOL_CROWBAR, TYPE_PROC_REF(/atom, cap_cover_remove), delay = delay, needs = present, priority = 20), id = "cover:remove")
		E.stance = I_HURT
		E.apply_stance_tags()
		. += E

/datum/capability/cover/examine(atom/holder, mob/user)
	if(cover_removed(holder))
		return list("Its cover has been removed.")
	if(cover_is_open(holder))
		return list("Its cover is open.")
	return null

/datum/capability/cover/draw(atom/holder, datum/look/look)
	// A removed cover isn't drawn open: the holder draws its coverless sprite (the APC).
	draw_layer(look, when = cover_is_open(holder) && !cover_removed(holder))

/datum/capability/cover/ui_data(atom/holder, mob/user, list/data)
	data["open"] = cover_is_open(holder)
	data["removed"] = cover_removed(holder)

/proc/cover_removed(atom/A)
	return !!(A.cap_state & CAP_COVER_REMOVED)

/atom/proc/cap_cover_name(mob/user)
	return cover_is_open(src) ? "Close cover" : "Open cover"

/// needs: the cover is still there.
/atom/proc/cap_cover_present(mob/user, obj/item/held)
	return cover_removed(src) ? "the cover has been removed" : TRUE

/atom/proc/cap_cover_toggle(mob/user, obj/item/held)
	var/opening = !cover_is_open(src)
	cap_set(src, CAP_COVER_OPEN, opening)
	act_message(user, src, self = "You [opening ? "open" : "close"] the cover of %T%.", others = "%U% [opening ? "opens" : "closes"] the cover of %T%.")
	return TRUE

/atom/proc/cap_cover_remove(mob/user, obj/item/held)
	cap_set(src, CAP_COVER_OPEN | CAP_COVER_REMOVED, TRUE)
	act_message(user, src, self = span_warning("You pry the cover off %T%."), others = span_warning("%U% pries the cover off %T%."), item = held)
	return TRUE
