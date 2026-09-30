// The maintenance panel capability (doc/rewrite/dx_conventions.md §2). State: CAP_PANEL_OPEN.
// Other entries declare `behind = PANEL`. Layer: LOOK_PANEL_OPEN. Accessor: panel_is_open().
//
//	. += cap_panel(tool = TOOL_SCREWDRIVER, behind = COVER)

/datum/capability/panel
	layer_name = LOOK_PANEL_OPEN
	var/tool_quality
	var/delay = 0

/// A maintenance panel toggled with `tool`; behind = COVER puts it behind a cover.
/proc/cap_panel(tool = TOOL_SCREWDRIVER, delay = 0, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, layer = LOOK_PANEL_OPEN)
	var/datum/capability/panel/C = new
	C.tool_quality = tool
	C.delay = delay
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/panel/interactions(atom/holder)
	return list(adopt_entry(cap_tool("Open maintenance panel", tool_quality, TYPE_PROC_REF(/atom, cap_panel_toggle), delay = delay, priority = 10, name_proc = TYPE_PROC_REF(/atom, cap_panel_name)), id = "panel:[tool_quality]"))

/datum/capability/panel/examine(atom/holder, mob/user)
	if(panel_is_open(holder))
		return list("The maintenance panel is open.")
	return null

/datum/capability/panel/draw(atom/holder, datum/look/look)
	draw_layer(look, when = panel_is_open(holder))

/datum/capability/panel/ui_data(atom/holder, mob/user, list/data)
	data["open"] = panel_is_open(holder)

/atom/proc/cap_panel_name(mob/user)
	return panel_is_open(src) ? "Close maintenance panel" : "Open maintenance panel"

/atom/proc/cap_panel_toggle(mob/user, obj/item/held)
	var/opening = !panel_is_open(src)
	cap_set(src, CAP_PANEL_OPEN, opening)
	act_message(user, src, self = "You [opening ? "open" : "close"] the maintenance panel of %T%.", others = "%U% [opening ? "opens" : "closes"] the maintenance panel of %T%.")
	return TRUE
