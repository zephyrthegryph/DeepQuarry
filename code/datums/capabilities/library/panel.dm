// The maintenance panel capability (doc/rewrite/dx_conventions.md §2). State: CAP_PANEL_OPEN.
// Other entries declare `needs = req_set(PANEL)`. Look: LOOK_PANEL_OPEN. Accessor: panel_is_open().
//
//	. += cap_panel(tool = TOOL_SCREWDRIVER, needs = req_set(COVER))

/datum/capability/panel
	layer_name = LOOK_PANEL_OPEN
	var/tool_quality
	var/delay = 0

/// A maintenance panel toggled with `tool`; behind = COVER puts it behind a cover.
/proc/cap_panel(tool = TOOL_SCREWDRIVER, delay = 0, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/panel/C = new
	C.tool_quality = tool
	C.delay = delay
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/// One op, "open_maintenance_panel": the tool's click (OP_PRIORITY_PART) opens or closes it.
/datum/capability/panel/interactions(atom/holder)
	return list(adopt_entry(lib_op("Open maintenance panel", TYPE_PROC_REF(/atom, cap_panel_toggle), OP_SHAPE_TOOL, using = tool_quality, key = "open_maintenance_panel", delay = delay, priority = OP_PRIORITY_PART, name_proc = GLOBAL_PROC_REF(cap_panel_name)), id = "panel:[tool_quality]"))

/datum/capability/panel/examine(atom/holder, mob/user)
	if(panel_is_open(holder))
		return list("The maintenance panel is open.")
	return null

/datum/capability/panel/draw(atom/holder, datum/look/look)
	draw_layer(look, when = panel_is_open(holder))

/datum/capability/panel/ui_data(atom/holder, mob/user, list/data)
	data["open"] = panel_is_open(holder)

/proc/cap_panel_name(atom/holder, mob/user)
	return panel_is_open(holder) ? "Close maintenance panel" : "Open maintenance panel"

/atom/proc/cap_panel_toggle(mob/user, obj/item/held)
	var/opening = !panel_is_open(src)
	cap_set(src, CAP_PANEL_OPEN, opening)
	act_message(user, src, self = "You [opening ? "open" : "close"] the maintenance panel of %T%.", others = "%U% [opening ? "opens" : "closes"] the maintenance panel of %T%.")
	return TRUE
