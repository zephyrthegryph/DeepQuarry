// The maintenance panel (doc/rewrite/final_api.html, section 11 "The library": panel()).
//
// A panel a tool opens and closes. State key PANEL_OPEN; op panel.open (toggles it, a screwdriver by default); look layer and examine line.
// It declares the space it closes, space(SPACE_PANEL, door = CAP_PANEL) (`space` = null: none), so the wires behind it (wires(), at
// SPACE_PANEL) are reachable only while it is open. What holds it shut is a latch of that space (maintenance_hatch()'s
// panel_needs_cover_closed: latch(SPACE_PANEL, COVER_OPEN, ...)); its open op needs req_door_free(CAP_PANEL).

MSG_DEF(panel/opened, "You open the maintenance panel of %T%.", "%U% opens the maintenance panel of %T%.")
MSG_DEF(panel/shut, "You close the maintenance panel of %T%.", "%U% closes the maintenance panel of %T%.")
MSG_DEF_SELF(panel/closed, "The maintenance panel is closed.")
MSG_DEF_SELF(panel/open_examine, "The maintenance panel is open.")

CAPABILITY_TYPE(panel, CAP_PANEL, /datum/capability/lib/panel, key = NONE, tool = TOOL_SCREWDRIVER, space = SPACE_PANEL)
cap_keys(CAP_PANEL, OPEN = MSG(panel/closed))

/datum/capability/lib/panel

/datum/capability/lib/panel/entries()
	return list(
		space ? global.space(space, door = CAP_PANEL) : null,
		op("open", tool(tool), needs(req_door_free(CAP_PANEL)), toggles(PANEL_OPEN), says(CAP_PROC(toggled_message))),
		look_layer(LOOK_PANEL_OPEN, when = PANEL_OPEN),
		examine_line(MSG(panel/open_examine), when = PANEL_OPEN))

/datum/capability/lib/panel/door_open(datum/holder)
	return panel_open(holder, null)

GLOBAL_LIST_INIT(panel_door_keys, list(PANEL_OPEN))

/datum/capability/lib/panel/door_keys(datum/holder)
	return GLOB.panel_door_keys

/datum/capability/lib/panel/door_closed_reason()
	return /datum/msg/panel/closed

/datum/capability/lib/panel/door_close_first_reason()
	return /datum/msg/hatch/close_panel

/// What panel.open just did: opened or closed.
/datum/capability/lib/panel/proc/toggled_message(datum/act/A)
	return panel_open(A.holder) ? /datum/msg/panel/opened : /datum/msg/panel/shut
