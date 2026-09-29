// The breakable capability (doc/rewrite/dx_conventions.md §2). State: CAP_BROKEN, set when the
// holder breaks (atom_break() of the obj_integrity system) and cleared when it is fixed
// (atom_fix()) or repaired with repair_tool. Every other entry refuses while broken unless it is
// works_broken (cap_gate_reason()). Layer: "broken". Accessor: is_broken().
//
//	. += cap_breakable(repair_tool = TOOL_WELDER, repair_delay = 3 SECONDS)

/datum/capability/breakable
	layer_name = "broken"
	var/repair_tool
	var/repair_delay

/// Breaks with the holder; `repair_tool` over `repair_delay` repairs it. repair_tool = NONE: no repair
/// entry (null can't be passed: DM would substitute the default).
/proc/cap_breakable(repair_tool = TOOL_WELDER, repair_delay = 3 SECONDS, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, layer = "broken")
	var/datum/capability/breakable/C = new
	C.repair_tool = repair_tool
	C.repair_delay = repair_delay
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/breakable/interactions(atom/holder)
	if(!repair_tool)
		return null
	return list(adopt_entry(cap_tool("Repair", repair_tool, TYPE_PROC_REF(/atom, cap_breakable_repair), delay = repair_delay, needs = TYPE_PROC_REF(/atom, cap_breakable_is_broken), else_say = "it isn't broken", works_broken = TRUE, works_unpowered = TRUE, priority = 10), id = "breakable:[repair_tool]"))

/datum/capability/breakable/examine(atom/holder, mob/user)
	if(is_broken(holder))
		return list("It is broken.")
	return null

/datum/capability/breakable/draw(atom/holder, datum/look/look)
	draw_layer(look, when = is_broken(holder))

/datum/capability/breakable/ui_data(atom/holder, mob/user, list/data)
	data["broken"] = is_broken(holder)

/// atom_break() / atom_fix() report here: a breakable holder mirrors it into CAP_BROKEN.
/atom/proc/caps_set_broken(broken)
	if(cap_of(src, /datum/capability/breakable))
		cap_set(src, CAP_BROKEN, broken)

/atom/proc/cap_breakable_is_broken(mob/user, obj/item/held)
	return is_broken(src)

/atom/proc/cap_breakable_repair(mob/user, obj/item/held)
	if(uses_integrity && get_integrity() < max_integrity)
		repair_damage(max_integrity - get_integrity()) // back above the failure point: atom_fix() runs
	cap_set(src, CAP_BROKEN, FALSE)
	act_message(user, src, self = "You repair %T%.", others = "%U% repairs %T%.")
	return TRUE
