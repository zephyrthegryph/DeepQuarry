// Capability presets (doc/rewrite/dx_conventions.md §2): plain procs returning the capability lists
// most machines share. A type adds them to its capabilities() and appends its own:
//
//	/obj/machinery/power/apc/capabilities()
//		. = ..()
//		. += cap_wall_machine(board = /obj/item/module/power_control, wires = /datum/wires/apc)
//		. += cap_slot(nameof(cell), /obj/item/cell, behind = COVER)
//
// A preset is only a list: `without()` / `replace()` edit what it contributed like any other entry.
// Names follow the constructor rule (cap_<noun>), so no holder proc (`computer()`) can shadow them.

/**
 * What every buildable machine has: a maintenance panel, deconstruction to its board behind the panel,
 * breakage with welder repair, and the dark/unpowered state. `wires` adds the wiring behind the panel.
 */
/proc/cap_machine_basics(board, wires, panel_tool = TOOL_SCREWDRIVER, repair_tool = TOOL_WELDER)
	. = list(
		cap_panel(tool = panel_tool),
		cap_breakable(repair_tool = repair_tool),
		cap_power(),
	)
	if(wires)
		. += cap_wires(wires, behind = PANEL)
	if(board)
		. += cap_deconstruct(board, behind = PANEL)

/// A floor machine: the basics, plus a wrench to anchor and unanchor it (behind nothing).
/proc/cap_floor_machine(board, wires, panel_tool = TOOL_SCREWDRIVER, repair_tool = TOOL_WELDER, anchor_delay = 2 SECONDS)
	. = cap_machine_basics(board = board, wires = wires, panel_tool = panel_tool, repair_tool = repair_tool)
	. += cap_anchor(delay = anchor_delay)

/// A wall-mounted machine: the basics, never unanchored (it hangs on the wall), and its board comes
/// out with the panel open.
/proc/cap_wall_machine(board, wires, panel_tool = TOOL_SCREWDRIVER, repair_tool = TOOL_WELDER)
	return cap_machine_basics(board = board, wires = wires, panel_tool = panel_tool, repair_tool = repair_tool)

/// A computer console: breakage (the screen cracks; no welder repair), power, and the screwdriver
/// that takes it apart into a computer frame with its board.
/proc/cap_computer(board)
	. = list(
		cap_breakable(repair_tool = NONE),
		cap_power(),
	)
	if(board)
		. += cap_deconstruct(board, behind = NONE)
