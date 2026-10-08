// The cover capability (doc/rewrite/dx_conventions.md §2): a hatch or front plate that opens by
// hand or with a tool. State: CAP_COVER_OPEN, and CAP_COVER_REMOVED once a removable cover is pried
// off (the APC's "cover removed": it stays open and can't be closed). Other entries declare
// `needs = req_set(COVER)` to be reachable only while it is open (cap_gate_reason()). Look: LOOK_COVER_OPEN.
// Accessors: cover_is_open(), legacy_cover_removed().
//
//	. += cap_cover(open_tool = TOOL_CROWBAR, needs = req_clear(LOCK))
//	. += cap_cover(open_tool = BY_HAND)
//	. += cap_cover(removable = TRUE, needs = PROC_REF(coverlock_ok), else_say = "the cover is locked")

/datum/capability/cover
	layer_name = LOOK_COVER_OPEN
	/// TOOL_* needed to open and close it, or BY_HAND.
	var/open_tool
	var/delay = 0
	/// A crowbar on harm intent pries it off (CAP_COVER_REMOVED).
	var/removable = FALSE

/// A cover. open_tool: TOOL_* or BY_HAND (null can't be passed: DM would substitute the default).
/// removable: a crowbar on harm intent removes it. Gating as every library constructor.
/proc/cap_cover(open_tool = TOOL_CROWBAR, delay = 0, removable = FALSE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/cover/C = new
	C.open_tool = open_tool
	C.delay = delay
	C.removable = removable
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/// Ops: "open_cover" (the tool's click, OP_PRIORITY_PART; or an empty hand's, BY_HAND), and with `removable`
/// "remove_cover" (a crowbar in harm: the hostile ACT_ATTACK, above the opening).
/datum/capability/cover/interactions(atom/holder)
	. = list()
	var/present = GLOBAL_PROC_REF(cap_cover_present)
	if(open_tool && open_tool != BY_HAND)
		. += adopt_entry(lib_op("Open cover", GLOBAL_PROC_REF(cap_cover_toggle), OP_SHAPE_TOOL, using = open_tool, key = "open_cover", delay = delay, needs = present, priority = OP_PRIORITY_PART, name_proc = GLOBAL_PROC_REF(cap_cover_name)), id = "cover:[open_tool]")
	else
		// A removed cover is not what an empty hand means: the touch falls through.
		. += adopt_entry(lib_op("Open cover", GLOBAL_PROC_REF(cap_cover_toggle), OP_SHAPE_HAND, key = "open_cover", offered = req_proc(present), works_broken = TRUE, works_unpowered = TRUE, name_proc = GLOBAL_PROC_REF(cap_cover_name)), id = "cover:[open_tool]")
	if(removable)
		. += adopt_entry(lib_op("Remove cover", GLOBAL_PROC_REF(cap_cover_remove), OP_SHAPE_TOOL, using = TOOL_CROWBAR, key = "remove_cover", action = ACT_ATTACK, delay = delay, needs = present, priority = OP_PRIORITY_PART * 2, stance = I_HURT), id = "cover:remove")

GLOBAL_LIST_INIT(cap_examine_cover_removed, list("Its cover has been removed."))
GLOBAL_LIST_INIT(cap_examine_cover_open, list("Its cover is open."))

/datum/capability/cover/examine(atom/holder, mob/user)
	if(legacy_cover_removed(holder))
		return GLOB.cap_examine_cover_removed
	if(cover_is_open(holder))
		return GLOB.cap_examine_cover_open
	return null

/datum/capability/cover/draw(atom/holder, datum/look/look)
	// A removed cover isn't drawn open: the holder draws its coverless sprite (the APC).
	draw_layer(look, when = cover_is_open(holder) && !legacy_cover_removed(holder))

/datum/capability/cover/legacy_ui_data(atom/holder, mob/user, list/data)
	data["open"] = cover_is_open(holder)
	data["removed"] = legacy_cover_removed(holder)

/proc/legacy_cover_removed(atom/A)
	return !!(capability_bits(A) & CAP_COVER_REMOVED)

/proc/cap_cover_name(atom/holder, mob/user)
	return cover_is_open(holder) ? "Close cover" : "Open cover"

/// needs: the cover is still there.
/proc/cap_cover_present(mob/user, atom/holder, obj/item/held)
	return legacy_cover_removed(holder) ? "the cover has been removed" : TRUE

/proc/cap_cover_toggle(atom/holder, mob/user, obj/item/held)
	var/opening = !cover_is_open(holder)
	cap_set(holder, CAP_COVER_OPEN, opening)
	act_message(user, holder, self = "You [opening ? "open" : "close"] the cover of %T%.", others = "%U% [opening ? "opens" : "closes"] the cover of %T%.")
	return TRUE

/proc/cap_cover_remove(atom/holder, mob/user, obj/item/held)
	cap_set(holder, CAP_COVER_OPEN | CAP_COVER_REMOVED, TRUE)
	act_message(user, holder, self = span_warning("You pry the cover off %T%."), others = span_warning("%U% pries the cover off %T%."), item = held)
	return TRUE
