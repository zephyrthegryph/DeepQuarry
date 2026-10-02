// The maintenance panel (doc/rewrite/final_api.html, section 11 "The library": panel()).
//
// A panel a tool opens and closes. State key PANEL_OPEN; op panel.open (toggles it, a screwdriver by default); look layer and examine line.
// The wires behind it (wires()) and the service bay are reachable only while it is open. What must be true to move it (a closed cover, an
// unlocked machine) is an extend("panel.open", needs(...)) of the type or of maintenance_hatch().

MSG_DEF(panel/opened, "You open the maintenance panel of %T%.", "%U% opens the maintenance panel of %T%.")
MSG_DEF(panel/shut, "You close the maintenance panel of %T%.", "%U% closes the maintenance panel of %T%.")
MSG_DEF_SELF(panel/closed, "The maintenance panel is closed.")
MSG_DEF_SELF(panel/open_examine, "The maintenance panel is open.")

CAPABILITY_TYPE(panel, CAP_PANEL, /datum/capability/lib/panel, key = NONE, tool = TOOL_SCREWDRIVER)
cap_keys(CAP_PANEL, OPEN = MSG(panel/closed))

/datum/capability/lib/panel

/datum/capability/lib/panel/entries()
	return list(
		op("open", tool(tool), toggles(PANEL_OPEN), says(CAP_PROC(toggled_message))),
		look_layer(LOOK_PANEL_OPEN, when = PANEL_OPEN),
		examine_line(MSG(panel/open_examine), when = PANEL_OPEN))

/// What panel.open just did: opened or closed.
/datum/capability/lib/panel/proc/toggled_message(datum/act/A)
	return panel_open(A.holder) ? /datum/msg/panel/opened : /datum/msg/panel/shut
